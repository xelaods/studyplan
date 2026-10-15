import WidgetKit
import SwiftUI

@main
struct StudyPlanWidgets: WidgetBundle {
    var body: some Widget {
        NextClassWidget()
        TodayWidget()
        WeekWidget()
        CommuteWidget()
        BusWidget()
        AttendWidget()
    }
}

// MARK: - データ

enum LoadState {
    case ready(Schedule)
    case message(String)
}

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let state: LoadState
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: Sample.previewNow, state: .ready(Sample.snapshot().schedule))
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        let now = Date()
        if context.isPreview {
            completion(ScheduleEntry(date: Sample.previewNow, state: .ready(Sample.snapshot().schedule)))
            return
        }
        switch load() {
        case .message: completion(ScheduleEntry(date: Sample.previewNow, state: .ready(Sample.snapshot().schedule)))
        case let state: completion(ScheduleEntry(date: now, state: state))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let now = Date()
        let state = load()
        var entries = [ScheduleEntry(date: now, state: state)]
        var refresh = now.addingTimeInterval(60 * 60)
        if case .ready(let schedule) = state {
            // 授業の始まり・終わり・日付の変わり目で表示を切り替える。授業中は「あと◯分」のため5分ごと
            var times = Set(schedule.boundaries(from: now, hours: 24))
            if let cur = schedule.current(at: now) {
                var t = now.addingTimeInterval(300)
                while t < cur.end {
                    times.insert(t)
                    t = t.addingTimeInterval(300)
                }
            }
            for t in times.sorted().prefix(60) {
                entries.append(ScheduleEntry(date: t, state: state))
            }
            refresh = entries.last.map { $0.date.addingTimeInterval(60) } ?? refresh
            refresh = min(refresh, now.addingTimeInterval(12 * 3600))
        }
        completion(Timeline(entries: entries, policy: .after(max(refresh, now.addingTimeInterval(300)))))
    }

    private func load() -> LoadState {
        if let s = SharedStore.loadSnapshot() {
            return .ready(s.schedule)
        }
        if !SharedStore.isShared && !CalendarBridge.hasAccess {
            return .message("アプリの設定で「カレンダーへのアクセスを許可」すると表示されます")
        }
        return .message("アプリを開くと表示されます")
    }
}

extension View {
    func widgetBackground() -> some View {
        containerBackground(for: .widget) { Color("WidgetBackground") }
    }
}

struct EntryView<Content: View>: View {
    let entry: ScheduleEntry
    @ViewBuilder let content: (Schedule, Date, WidgetFamily) -> Content
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch entry.state {
        case .message(let text): WidgetMessageView(text: text, family: family)
        case .ready(let s): content(s, entry.date, family)
        }
    }
}

// MARK: - ウィジェット

struct NextClassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextClass", provider: ScheduleProvider()) { entry in
            EntryView(entry: entry) { s, now, family in
                NextClassWidgetView(schedule: s, now: now, family: family)
            }
            .widgetBackground()
            .widgetURL(URL(string: "studyplan://today"))
        }
        .configurationDisplayName("次の授業")
        .description("次の授業の時間と教室。授業中は残り時間を表示します。")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: ScheduleProvider()) { entry in
            EntryView(entry: entry) { s, now, family in
                TodayWidgetView(schedule: s, now: now, family: family)
            }
            .widgetBackground()
            .widgetURL(URL(string: "studyplan://today"))
        }
        .configurationDisplayName("今日の授業")
        .description("今日の授業の一覧。終わったら次の授業日を表示します。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Week", provider: ScheduleProvider()) { entry in
            EntryView(entry: entry) { s, now, _ in
                WeekWidgetView(schedule: s, now: now)
            }
            .widgetBackground()
            .widgetURL(URL(string: "studyplan://week"))
        }
        .configurationDisplayName("時間割")
        .description("1週間の時間割。今日の列と授業中のコマがわかります。")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - 通学（スクールバス × 電車）

struct CommuteEntry: TimelineEntry {
    let date: Date
    let plan: CommutePlan?
    let settings: CommuteSettings
}

struct CommuteProvider: TimelineProvider {
    func placeholder(in context: Context) -> CommuteEntry {
        CommuteEntry(date: Sample.previewNow, plan: Sample.commutePlan(), settings: CommuteSettings())
    }

    func getSnapshot(in context: Context, completion: @escaping (CommuteEntry) -> Void) {
        if context.isPreview || SharedStore.loadSnapshot() == nil {
            completion(CommuteEntry(date: Sample.previewNow, plan: Sample.commutePlan(), settings: CommuteSettings()))
            return
        }
        Task {
            let entry = await makeEntry(now: Date())
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CommuteEntry>) -> Void) {
        Task {
            let now = Date()
            let entry = await makeEntry(now: now)
            // 「あと◯分」を進めるため5分ごとの表示を作り、15分後に検索し直す
            var entries = [entry]
            for i in 1...3 {
                entries.append(CommuteEntry(date: now.addingTimeInterval(TimeInterval(i * 300)), plan: entry.plan, settings: entry.settings))
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }

    private func makeEntry(now: Date) async -> CommuteEntry {
        guard let snap = SharedStore.loadSnapshot() else {
            return CommuteEntry(date: now, plan: CommutePlan(title: "通学", dia: "", sections: [],
                                                             message: "アプリで授業を登録してください", generated: now, bus: nil),
                                settings: CommuteSettings())
        }
        let settings = snap.commute ?? CommuteSettings()
        let plan = await CommutePlanner.plan(schedule: snap.schedule, settings: settings, now: now)
        return CommuteEntry(date: now, plan: plan, settings: settings)
    }
}

struct CommuteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Commute", provider: CommuteProvider()) { entry in
            CommuteWidgetFamilyView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemGroupedBackground) }
                .widgetURL(URL(string: "studyplan://commute"))
        }
        .configurationDisplayName("通学")
        .description("スクールバスと電車の乗り継ぎ。時間割の1限に間に合う便と、帰りの便を表示します。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CommuteWidgetFamilyView: View {
    let entry: CommuteEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        CommuteWidgetView(plan: entry.plan, settings: entry.settings, now: entry.date, family: family)
    }
}

// MARK: - スクールバス（次の便）

struct BusEntry: TimelineEntry {
    let date: Date
    let day: BusDay?
    let message: String?
}

struct BusProvider: TimelineProvider {
    func placeholder(in context: Context) -> BusEntry {
        BusEntry(date: Sample.previewNow, day: Sample.commutePlan().bus, message: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BusEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task {
            let now = Date()
            let day = try? await BusSource.day(now)
            completion(BusEntry(date: now, day: day ?? Sample.commutePlan().bus, message: nil))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BusEntry>) -> Void) {
        Task {
            let now = Date()
            var day: BusDay?
            var message: String?
            do { day = try await BusSource.day(now) } catch { message = "通信できません" }
            // 「あと◯分」のため1分ごと（日付が変わったら取り直す）
            let start = JST.date(now, minutes: JST.minutes(now))
            let midnight = JST.adding(days: 1, to: JST.startOfDay(now))
            var entries: [BusEntry] = []
            for i in 0..<60 {
                let t = start.addingTimeInterval(TimeInterval(i * 60))
                if t >= midnight { break }
                entries.append(BusEntry(date: i == 0 ? now : t, day: day, message: message))
            }
            let next = min(start.addingTimeInterval(60 * 60), midnight.addingTimeInterval(60))
            completion(Timeline(entries: entries, policy: .after(message == nil ? next : now.addingTimeInterval(15 * 60))))
        }
    }
}

struct BusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Bus", provider: BusProvider()) { entry in
            BusWidgetFamilyView(entry: entry)
                .widgetBackground()
                .widgetURL(URL(string: "studyplan://commute"))
        }
        .configurationDisplayName("スクールバス")
        .description("おおたかの森駅 ⇄ 大学の次のスクールバスと、発車までの時間。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BusWidgetFamilyView: View {
    let entry: BusEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        BusWidgetView(day: entry.day, message: entry.message, now: entry.date, family: family)
    }
}
