import WidgetKit
import SwiftUI

@main
struct StudyPlanWidgets: WidgetBundle {
    var body: some Widget {
        NextClassWidget()
        TodayWidget()
        WeekWidget()
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
