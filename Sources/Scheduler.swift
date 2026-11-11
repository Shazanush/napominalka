import Foundation
import UserNotifications

/// Планирует уведомления. Будильник = цепочка уведомлений каждые 30 секунд
/// (звук до 29 сек), пока не отключишь через Face ID.
@MainActor
enum Scheduler {
    nonisolated static let chainCount = 20                 // 20 × 30 сек = 10 минут звона
    nonisolated static let chainInterval: TimeInterval = 30
    nonisolated static var chainWindow: TimeInterval { Double(chainCount) * chainInterval }
    static let maxPending = 60                 // iOS держит максимум 64 ожидающих уведомления

    private static var running: Task<Void, Never>?

    nonisolated static func occurrenceKey(_ id: UUID, _ occ: Date) -> String {
        "\(id.uuidString)|\(Int(occ.timeIntervalSince1970))"
    }

    nonisolated static func chainIDs(_ id: UUID, _ occ: Date) -> [String] {
        let key = occurrenceKey(id, occ)
        return (0..<chainCount).map { "\(key)#\($0)" }
    }

    // MARK: отключённые срабатывания

    nonisolated private static let dismissedKey = "dismissed.v1"

    nonisolated static func isDismissed(_ id: UUID, _ occ: Date) -> Bool {
        let set = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        return set.contains(occurrenceKey(id, occ))
    }

    nonisolated static func markDismissed(_ id: UUID, _ occ: Date) {
        var set = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        set.append(occurrenceKey(id, occ))
        let cutoff = Date().addingTimeInterval(-3 * 86400).timeIntervalSince1970
        set = set.filter { s in
            guard let e = s.split(separator: "|").last, let t = Double(e) else { return false }
            return t > cutoff
        }
        UserDefaults.standard.set(set, forKey: dismissedKey)
    }

    // MARK: разрешения

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    // MARK: планирование

    static func reschedule() {
        let prev = running
        running = Task {
            await prev?.value
            await doReschedule()
        }
    }

    private static func doReschedule() async {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        var planned: [(Date, UNNotificationRequest)] = []

        for r in ReminderStore.shared.items where r.enabled {
            let from = r.kind == .alarm ? now.addingTimeInterval(-chainWindow) : now
            let occs = r.occurrences(after: from, limit: 6)
            if occs.isEmpty { continue }
            let soundName = await SoundMaker.shared.ensureSound(for: r)

            for occ in occs where !isDismissed(r.id, occ) {
                if r.kind == .alarm {
                    for i in 0..<chainCount {
                        let fire = occ.addingTimeInterval(Double(i) * chainInterval)
                        if fire <= now.addingTimeInterval(1) { continue }
                        planned.append((fire, request(r, occ: occ, fire: fire, index: i, sound: soundName)))
                    }
                } else {
                    planned.append((occ, request(r, occ: occ, fire: occ, index: 0, sound: soundName)))
                }
            }
        }

        planned.sort { $0.0 < $1.0 }
        center.removeAllPendingNotificationRequests()
        for (_, req) in planned.prefix(maxPending) {
            try? await center.add(req)
        }
    }

    private static func request(_ r: Reminder, occ: Date, fire: Date, index: Int, sound: String?) -> UNNotificationRequest {
        let c = UNMutableNotificationContent()
        let key = occurrenceKey(r.id, occ)
        if r.kind == .alarm {
            c.title = "⏰ " + r.displayTitle
            let body = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
            c.body = (body.isEmpty || body == r.displayTitle ? "" : body + "\n") + "Открой приложение и отключи через Face ID"
        } else {
            c.title = "🔔 " + r.displayTitle
            let body = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if body != r.displayTitle { c.body = body }
        }
        if let s = sound {
            c.sound = UNNotificationSound(named: UNNotificationSoundName(s))
        } else {
            c.sound = .default
        }
        c.threadIdentifier = key
        c.userInfo = [
            "rid": r.id.uuidString,
            "occ": occ.timeIntervalSince1970,
            "kind": r.kind.rawValue
        ]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: "\(key)#\(index)", content: c, trigger: trigger)
    }
}
