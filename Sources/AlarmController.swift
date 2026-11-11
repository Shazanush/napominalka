import Foundation
import AVFoundation
import LocalAuthentication
import UserNotifications

/// Управляет звонящим будильником: громкий повтор, пока не пройдёшь Face ID.
@MainActor
final class AlarmController: ObservableObject {
    static let shared = AlarmController()

    struct Active: Identifiable, Equatable {
        let reminderID: UUID
        let occurrence: Date
        var id: String { Scheduler.occurrenceKey(reminderID, occurrence) }
    }

    @Published var active: Active?
    @Published var errorText: String?
    private var player: AVAudioPlayer?

    func trigger(rid: UUID, occ: Date) {
        guard let r = ReminderStore.shared.item(rid), r.kind == .alarm, r.enabled else { return }
        guard !Scheduler.isDismissed(rid, occ) else { return }
        guard Date().timeIntervalSince(occ) < Scheduler.chainWindow else { return }
        let a = Active(reminderID: rid, occurrence: occ)
        if active == a { return }
        active = a
        errorText = nil
        Task { await startSound(for: r) }
    }

    /// При открытии приложения: если будильник звонит и ещё не отключён — показать экран отключения.
    func checkActive() {
        if active != nil { return }
        let now = Date()
        for r in ReminderStore.shared.items where r.kind == .alarm && r.enabled {
            for occ in r.occurrences(after: now.addingTimeInterval(-Scheduler.chainWindow), limit: 2)
            where occ <= now && !Scheduler.isDismissed(r.id, occ) {
                trigger(rid: r.id, occ: occ)
                return
            }
        }
    }

    private func startSound(for r: Reminder) async {
        let session = AVAudioSession.sharedInstance()
        // .playback — звучит даже при беззвучном режиме, пока приложение открыто
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
        _ = await SoundMaker.shared.ensureSound(for: r)
        guard active?.reminderID == r.id else { return }
        let url = SoundMaker.url(for: r)
        if let p = try? AVAudioPlayer(contentsOf: url) {
            p.numberOfLoops = -1
            p.volume = 1
            p.play()
            player = p
        }
    }

    private func stopSound() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func dismissWithFaceID() async {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = ""   // без кнопки «Ввести пароль»
        var err: NSError?
        var policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics

        if !ctx.canEvaluatePolicy(policy, error: &err) {
            if err?.code == LAError.Code.biometryLockout.rawValue {
                // Face ID заблокирован после неудачных попыток — iOS разрешает только код-пароль
                policy = .deviceOwnerAuthentication
            } else {
                errorText = "Face ID недоступен: включи его в Настройках → Face ID и код-пароль."
                return
            }
        }

        do {
            let ok = try await ctx.evaluatePolicy(policy, localizedReason: "Отключить будильник")
            if ok { finish() }
        } catch {
            errorText = "Не получилось. Попробуй ещё раз."
        }
    }

    private func finish() {
        guard let a = active else { return }
        stopSound()
        Scheduler.markDismissed(a.reminderID, a.occurrence)

        let ids = Scheduler.chainIDs(a.reminderID, a.occurrence)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)

        if let r = ReminderStore.shared.item(a.reminderID), r.repeatDays.isEmpty {
            ReminderStore.shared.setEnabled(r.id, false)
        } else {
            Scheduler.reschedule()
        }
        active = nil
        errorText = nil
    }
}
