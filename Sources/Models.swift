import Foundation

enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case alarm, notification
    var id: String { rawValue }
    var title: String { self == .alarm ? "Будильник" : "Уведомление" }
    var icon: String { self == .alarm ? "alarm.fill" : "bell.fill" }
}

struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String = ""
    var text: String = ""
    var kind: ReminderKind = .alarm
    /// Для разового — полная дата; для повторяющегося используются только часы и минуты.
    var time: Date = Reminder.defaultTime()
    /// Дни недели по Calendar: 1 = Вс, 2 = Пн … 7 = Сб. Пусто = один раз.
    var repeatDays: Set<Int> = []
    var speak: Bool = true
    var enabled: Bool = true
    var soundRev: Int = 0

    static func defaultTime() -> Date {
        let d = Date().addingTimeInterval(3600)
        let cal = Calendar.current
        return cal.date(bySetting: .second, value: 0, of: d) ?? d
    }

    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { return text }
        return kind.title
    }

    var spokenText: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let x = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty && x.isEmpty { return kind == .alarm ? "Подъём! Пора вставать." : "Напоминание" }
        if t.isEmpty { return x }
        if x.isEmpty { return t }
        return "\(t). \(x)"
    }

    /// Ближайшие срабатывания, строго позже `after`.
    func occurrences(after: Date, limit: Int, cal: Calendar = .current) -> [Date] {
        guard enabled else { return [] }
        if repeatDays.isEmpty {
            return time > after ? [time] : []
        }
        let hm = cal.dateComponents([.hour, .minute], from: time)
        var result: [Date] = []
        var day = cal.startOfDay(for: after)
        for _ in 0..<16 {
            let wd = cal.component(.weekday, from: day)
            if repeatDays.contains(wd),
               let d = cal.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: day),
               d > after {
                result.append(d)
                if result.count >= limit { break }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    static let weekOrder = [2, 3, 4, 5, 6, 7, 1]
    static let shortDay: [Int: String] = [1: "Вс", 2: "Пн", 3: "Вт", 4: "Ср", 5: "Чт", 6: "Пт", 7: "Сб"]

    var repeatSummary: String {
        if repeatDays.isEmpty {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateFormat = "d MMM, EEEE"
            return "Один раз · " + f.string(from: time)
        }
        if repeatDays.count == 7 { return "Каждый день" }
        if repeatDays == [2, 3, 4, 5, 6] { return "По будням" }
        if repeatDays == [7, 1] { return "По выходным" }
        return Reminder.weekOrder.filter { repeatDays.contains($0) }.compactMap { Reminder.shortDay[$0] }.joined(separator: ", ")
    }

    /// Коротко и заглавными — для списка.
    var shortSummary: String {
        if repeatDays.isEmpty {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateFormat = "d MMM"
            return f.string(from: time).uppercased()
        }
        if repeatDays.count == 7 { return "ЕЖЕДНЕВНО" }
        if repeatDays == [2, 3, 4, 5, 6] { return "БУДНИ" }
        if repeatDays == [7, 1] { return "ВЫХОДНЫЕ" }
        if repeatDays.count == 6, let missing = (1...7).first(where: { !repeatDays.contains($0) }) {
            return "КРОМЕ " + (Reminder.shortDay[missing] ?? "").uppercased()
        }
        return Reminder.weekOrder.filter { repeatDays.contains($0) }
            .compactMap { Reminder.shortDay[$0]?.uppercased() }.joined(separator: " ")
    }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: time)
    }

    var isPastOnce: Bool { repeatDays.isEmpty && time < Date() }
}

@MainActor
final class ReminderStore: ObservableObject {
    static let shared = ReminderStore()

    @Published private(set) var items: [Reminder] = []
    private let key = "reminders.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Reminder].self, from: data) {
            items = list
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func item(_ id: UUID) -> Reminder? { items.first { $0.id == id } }

    func upsert(_ r: Reminder) {
        var r = r
        r.soundRev += 1
        if let i = items.firstIndex(where: { $0.id == r.id }) { items[i] = r } else { items.append(r) }
        save()
        Scheduler.reschedule()
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].enabled = on
        if on && items[i].isPastOnce {
            // разовый в прошлом — переносим на ближайшие сутки на то же время
            let cal = Calendar.current
            let hm = cal.dateComponents([.hour, .minute], from: items[i].time)
            var d = cal.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: Date()) ?? Date()
            if d <= Date() { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
            items[i].time = d
        }
        save()
        Scheduler.reschedule()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
        SoundMaker.removeSounds(for: id)
        Scheduler.reschedule()
    }
}
