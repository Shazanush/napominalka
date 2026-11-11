import SwiftUI
import UserNotifications

@main
struct NapominalkaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = ReminderStore.shared
    @StateObject private var alarm = AlarmController.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(alarm)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { p in
                    if p == .active {
                        alarm.checkActive()
                        Scheduler.reschedule()
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    private func handle(_ info: [AnyHashable: Any]) -> Bool {
        guard (info["kind"] as? String) == ReminderKind.alarm.rawValue,
              let s = info["rid"] as? String, let rid = UUID(uuidString: s),
              let t = info["occ"] as? Double else { return false }
        let occ = Date(timeIntervalSince1970: t)
        Task { @MainActor in AlarmController.shared.trigger(rid: rid, occ: occ) }
        return true
    }

    // Уведомление пришло, когда приложение открыто
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if handle(notification.request.content.userInfo) {
            completionHandler([])   // звонит сам экран будильника
        } else {
            completionHandler([.banner, .list, .sound])
        }
    }

    // Нажал на уведомление
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = handle(response.notification.request.content.userInfo)
        completionHandler()
    }
}
