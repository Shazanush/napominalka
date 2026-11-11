import SwiftUI
import AVFoundation

// MARK: - Главный экран

struct ContentView: View {
    @EnvironmentObject var store: ReminderStore
    @EnvironmentObject var alarm: AlarmController
    @State private var editing: Reminder?
    @State private var authorized = true

    private var alarms: [Reminder] { sorted(store.items.filter { $0.kind == .alarm }) }
    private var notes: [Reminder] { sorted(store.items.filter { $0.kind == .notification }) }

    private func sorted(_ list: [Reminder]) -> [Reminder] {
        list.sorted {
            let a = Calendar.current.dateComponents([.hour, .minute], from: $0.time)
            let b = Calendar.current.dateComponents([.hour, .minute], from: $1.time)
            return (a.hour ?? 0, a.minute ?? 0) < (b.hour ?? 0, b.minute ?? 0)
        }
    }

    private let insets = EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            List {
                header
                    .listRowInsets(insets)
                    .listRowBackground(Color.black)
                    .listRowSeparator(.hidden)

                if !authorized {
                    permissionBanner
                        .listRowInsets(insets)
                        .listRowBackground(Color.black)
                        .listRowSeparator(.hidden)
                }

                if store.items.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        DotMatrixText(text: "00:00", dot: 6, color: Theme.ash)
                        Text("ПОКА ПУСТО").font(.caption).tracking(3).foregroundStyle(Theme.ash)
                        Text("Нажми красную кнопку, чтобы добавить будильник или напоминание.")
                            .font(.subheadline).foregroundStyle(Theme.ashLight)
                    }
                    .padding(.vertical, 30)
                    .listRowInsets(insets)
                    .listRowBackground(Color.black)
                    .listRowSeparator(.hidden)
                }

                if !alarms.isEmpty {
                    sectionHeader("01 — БУДИЛЬНИКИ", alarms.count)
                    ForEach(alarms) { r in row(r) }
                        .onDelete { idx in idx.map { alarms[$0].id }.forEach { store.delete($0) } }
                }
                if !notes.isEmpty {
                    sectionHeader(alarms.isEmpty ? "01 — УВЕДОМЛЕНИЯ" : "02 — УВЕДОМЛЕНИЯ", notes.count)
                    ForEach(notes) { r in row(r) }
                        .onDelete { idx in idx.map { notes[$0].id }.forEach { store.delete($0) } }
                }

                Text("Будильник звонит каждые 30 секунд, до 10 минут, пока не отключишь через Face ID. Не ставь телефон на беззвучный режим. Нажми на точку слева, чтобы включить или выключить.")
                    .font(.caption2).foregroundStyle(Theme.ash)
                    .padding(.vertical, 24)
                    .listRowInsets(insets)
                    .listRowBackground(Color.black)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .tint(Theme.emeraldLight)
        .sheet(item: $editing) { r in
            EditView(original: r, isNew: store.item(r.id) == nil)
                .environmentObject(store)
        }
        .fullScreenCover(item: $alarm.active) { _ in
            AlarmView()
                .environmentObject(alarm)
                .environmentObject(store)
        }
        .task {
            _ = await Scheduler.requestPermission()
            authorized = await Scheduler.isAuthorized()
            alarm.checkActive()
            Scheduler.reschedule()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("НАПОМИНАЛКА")
                        .font(Theme.condensed(38))
                        .foregroundStyle(Theme.text)
                    Text("侍 · ПУТЬ ДИСЦИПЛИНЫ")
                        .font(.caption2).tracking(3).foregroundStyle(Theme.ash)
                }
                Spacer()
                Menu {
                    Button { editing = Reminder(kind: .alarm) } label: {
                        Label("Новый будильник", systemImage: "alarm")
                    }
                    Button { editing = Reminder(kind: .notification) } label: {
                        Label("Новое уведомление", systemImage: "bell")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Theme.blood))
                }
            }
            KatanaView()
                .frame(width: 170)
                .padding(.top, 18)
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private func sectionHeader(_ title: String, _ count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)")
        }
        .font(.caption2).tracking(2).foregroundStyle(Theme.ash)
        .padding(.top, 22).padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x333333)).frame(height: 0.5) }
        .listRowInsets(insets)
        .listRowBackground(Color.black)
        .listRowSeparator(.hidden)
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("● УВЕДОМЛЕНИЯ ВЫКЛЮЧЕНЫ").font(.caption).tracking(2).foregroundStyle(Theme.blood)
            Text("Без них будильник не зазвонит. Разреши уведомления в настройках.")
                .font(.subheadline).foregroundStyle(Theme.ashLight)
            Button("Открыть настройки") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline.bold())
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func row(_ r: Reminder) -> some View {
        let isAlarm = r.kind == .alarm
        HStack(spacing: 12) {
            Button {
                store.setEnabled(r.id, !r.enabled)
            } label: {
                Circle()
                    .fill(r.enabled ? (isAlarm ? Theme.blood : Theme.oceanLight) : Color.clear)
                    .overlay(Circle().stroke(r.enabled ? Color.clear : Theme.ash, lineWidth: 1))
                    .frame(width: 10, height: 10)
                    .frame(width: 30, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 7) {
                DotMatrixText(text: r.timeString, dot: 4.4, color: Theme.text)
                Text(r.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ashLight)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(r.enabled ? r.shortSummary : "ВЫКЛ")
                if r.speak && r.enabled {
                    Text("● ГОЛОС").foregroundStyle(Theme.emeraldLight)
                }
            }
            .font(.caption2).tracking(1).foregroundStyle(Theme.ash)
        }
        .padding(.vertical, 12)
        .opacity(r.enabled ? 1 : 0.45)
        .contentShape(Rectangle())
        .onTapGesture { editing = r }
        .listRowInsets(insets)
        .listRowBackground(Color.black)
        .listRowSeparatorTint(Theme.line)
    }
}

// MARK: - Редактирование

struct EditView: View {
    @EnvironmentObject var store: ReminderStore
    @Environment(\.dismiss) private var dismiss
    let original: Reminder
    let isNew: Bool
    @State private var r: Reminder
    @State private var speaker = AVSpeechSynthesizer()

    init(original: Reminder, isNew: Bool) {
        self.original = original
        self.isNew = isNew
        _r = State(initialValue: original)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Тип", selection: $r.kind) {
                        ForEach(ReminderKind.allCases) { k in Text(k.title).tag(k) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(r.kind == .alarm
                         ? "Звонит и повторяется, пока не отключишь через Face ID."
                         : "Просто приходит уведомление со звуком.")
                        .foregroundStyle(Theme.ash)
                }

                Section {
                    TextField("Название, например: Открыть магазин", text: $r.title)
                    TextField("Что прочитать вслух / подробности", text: $r.text, axis: .vertical)
                        .lineLimit(2...6)
                    Toggle("Читать текст голосом", isOn: $r.speak).tint(Theme.emerald)
                    if r.speak {
                        Button {
                            let u = AVSpeechUtterance(string: r.spokenText)
                            u.voice = AVSpeechSynthesisVoice(language: "ru-RU")
                            u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
                            try? AVAudioSession.sharedInstance().setCategory(.playback)
                            speaker.stopSpeaking(at: .immediate)
                            speaker.speak(u)
                        } label: {
                            Label("Прослушать", systemImage: "play.fill")
                                .foregroundStyle(Theme.emeraldLight)
                        }
                    }
                } header: { header("01 — ТЕКСТ") }
                .listRowBackground(Theme.field)

                Section {
                    HStack {
                        Spacer()
                        DotMatrixText(text: timeText, dot: 6)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    if r.repeatDays.isEmpty {
                        DatePicker("Дата и время", selection: $r.time, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    } else {
                        DatePicker("Время", selection: $r.time, displayedComponents: .hourAndMinute)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ПОВТОРЯТЬ").font(.caption2).tracking(2).foregroundStyle(Theme.ash)
                        HStack(spacing: 6) {
                            ForEach(Reminder.weekOrder, id: \.self) { d in
                                let on = r.repeatDays.contains(d)
                                Button {
                                    if on { r.repeatDays.remove(d) } else { r.repeatDays.insert(d) }
                                } label: {
                                    Text(Reminder.shortDay[d] ?? "")
                                        .font(.footnote.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background(on ? Theme.emerald : Color(hex: 0x1A1B1A))
                                        .foregroundStyle(on ? Theme.text : Theme.ash)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack {
                            Button("Каждый день") { r.repeatDays = Set(1...7) }
                            Spacer()
                            Button("Будни") { r.repeatDays = [2, 3, 4, 5, 6] }
                            Spacer()
                            Button("Один раз") { r.repeatDays = [] }
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.emeraldLight)
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                } header: { header("02 — ВРЕМЯ") }
                .listRowBackground(Theme.field)

                if !isNew {
                    Section {
                        Button("Удалить", role: .destructive) {
                            store.delete(r.id)
                            dismiss()
                        }
                        .foregroundStyle(Theme.blood)
                    }
                    .listRowBackground(Theme.field)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .tint(Theme.emeraldLight)
            .navigationTitle(isNew ? "Новое" : "Изменить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.foregroundStyle(Theme.ash)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.bold().foregroundStyle(Theme.blood)
                }
            }
        }
    }

    private var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: r.time)
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.caption2).tracking(2).foregroundStyle(Theme.ash).textCase(nil)
    }

    private func save() {
        var item = r
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.time)
        comps.second = 0
        var t = cal.date(from: comps) ?? item.time
        if item.repeatDays.isEmpty && t <= Date() {
            t = cal.date(byAdding: .day, value: 1, to: t) ?? t
        }
        item.time = t
        item.enabled = true
        store.upsert(item)
        dismiss()
    }
}

// MARK: - Экран звонящего будильника

struct AlarmView: View {
    @EnvironmentObject var alarm: AlarmController
    @EnvironmentObject var store: ReminderStore

    private let dial: CGFloat = 250

    var body: some View {
        let r = alarm.active.flatMap { store.item($0.reminderID) }
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("● БУДИЛЬНИК")
                    .font(.caption2).tracking(4).foregroundStyle(Theme.blood)
                    .padding(.top, 20)

                Spacer(minLength: 10)

                ZStack {
                    SunDial(size: dial)
                    KatanaView()
                        .frame(width: dial * 0.96)
                        .rotationEffect(.degrees(-28))
                    FallingDrops(points: [CGPoint(x: 0.55, y: 0.56), CGPoint(x: 0.72, y: 0.46)], distance: 46)
                }
                .frame(width: dial, height: dial)

                DotMatrixText(text: r?.timeString ?? "", dot: 8)
                    .padding(.top, 22)

                Text((r?.displayTitle ?? "Будильник").uppercased())
                    .font(.footnote).tracking(3)
                    .foregroundStyle(Theme.ash)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)

                if let t = r?.text, !t.isEmpty, t != r?.displayTitle {
                    Text(t)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ashLight)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }

                Spacer()

                if let e = alarm.errorText {
                    Text(e).font(.subheadline).foregroundStyle(.yellow)
                        .multilineTextAlignment(.center).padding(.bottom, 10)
                }

                Button {
                    Task { await alarm.dismissWithFaceID() }
                } label: {
                    Image(systemName: "faceid")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.text)
                        .frame(width: 84, height: 84)
                        .background(Circle().fill(Color.black))
                        .overlay(Circle().stroke(Theme.emeraldLight, lineWidth: 2))
                }
                .accessibilityLabel("Отключить через Face ID")

                Text("ОТКЛЮЧИТЬ · FACE ID")
                    .font(Theme.condensed(15)).tracking(3)
                    .foregroundStyle(Theme.ashLight)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
        .interactiveDismissDisabled(true)
    }
}
