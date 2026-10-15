import SwiftUI
import WidgetKit

// アプリの見本画面とウィジェットで共通の表示

/// いまの状態（授業中・次の授業・なし）
struct ClassFocus {
    let item: ClassItem?
    let label: String
    let isNow: Bool

    init(schedule: Schedule, now: Date) {
        if let cur = schedule.current(at: now) {
            item = cur; label = "授業中"; isNow = true
        } else if let next = schedule.next(after: now) {
            item = next; isNow = false
            if JST.isSameDay(next.start, now) {
                label = "次の授業"
            } else if JST.isSameDay(next.start, JST.adding(days: 1, to: now)) {
                label = "明日"
            } else {
                label = (JST.weekday(next.start)?.long ?? "")
            }
        } else {
            item = nil; label = "授業なし"; isNow = false
        }
    }
}

// MARK: - 次の授業

struct NextClassWidgetView: View {
    let schedule: Schedule
    let now: Date
    let family: WidgetFamily
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let focus = ClassFocus(schedule: schedule, now: now)
        switch family {
        case .accessoryInline: inline(focus)
        case .accessoryRectangular: rectangular(focus)
        case .accessoryCircular: circular(focus)
        default: small(focus)
        }
    }

    @ViewBuilder
    private func small(_ focus: ClassFocus) -> some View {
        if let item = focus.item {
            let tint = CourseTint(base: item.course.color.color, scheme: scheme)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Circle().fill(tint.base).frame(width: 7, height: 7)
                    Text(focus.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint.text)
                    Spacer(minLength: 0)
                    Text(item.periodText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                if focus.isNow {
                    Text("あと" + Remaining.text(from: now, to: item.end))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                } else {
                    Text(JST.hm(item.start))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Text(item.course.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 1)
                if !item.course.room.isEmpty {
                    Text(item.course.room)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 1)
                }
                if focus.isNow {
                    ProgressView(value: item.progress(now))
                        .tint(tint.base)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyDayView(text: schedule.isEmpty ? "アプリで授業を\n登録してください" : "しばらく授業は\nありません")
        }
    }

    @ViewBuilder
    private func rectangular(_ focus: ClassFocus) -> some View {
        if let item = focus.item {
            VStack(alignment: .leading, spacing: 1) {
                Text(focus.isNow ? "授業中・あと\(Remaining.text(from: now, to: item.end))" : "\(focus.label)・\(JST.hm(item.start))")
                    .font(.caption.weight(.semibold))
                    .widgetAccentable()
                Text(item.course.name)
                    .font(.headline)
                    .lineLimit(1)
                Text([item.periodText, item.course.room].filter { !$0.isEmpty }.joined(separator: "・"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("時間割").font(.caption.weight(.semibold)).widgetAccentable()
                Text("授業はありません").font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func inline(_ focus: ClassFocus) -> some View {
        if let item = focus.item {
            if focus.isNow {
                Label("\(item.course.name) あと\(Remaining.text(from: now, to: item.end))", systemImage: "book.closed")
            } else {
                Label("\(JST.hm(item.start)) \(item.course.name) \(item.course.room)", systemImage: "book.closed")
            }
        } else {
            Label("授業なし", systemImage: "book.closed")
        }
    }

    @ViewBuilder
    private func circular(_ focus: ClassFocus) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            if let item = focus.item, let p = item.course.period {
                if focus.isNow {
                    Gauge(value: item.progress(now)) {
                        Text("\(p)限")
                    } currentValueLabel: {
                        Text("\(p)").font(.title3.weight(.semibold))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                } else {
                    VStack(spacing: -2) {
                        Text("\(p)限").font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text(JST.hm(item.start)).font(.system(size: 10, weight: .medium)).monospacedDigit()
                    }
                }
            } else {
                Image(systemName: "checkmark").font(.title3.weight(.semibold))
            }
        }
    }
}

// MARK: - 今日の授業

struct TodayWidgetView: View {
    let schedule: Schedule
    let now: Date
    let family: WidgetFamily
    @Environment(\.colorScheme) var scheme

    private var today: [ClassItem] { schedule.items(on: now) }

    /// 今日の残り。終わっていたら次の授業日
    private var shown: (title: String?, items: [ClassItem]) {
        let remaining = today.filter { !$0.isPast(now) }
        if !remaining.isEmpty {
            return (nil, family == .systemLarge ? today : remaining)
        }
        if let next = schedule.nextClassDay(after: now) {
            let isTomorrow = JST.isSameDay(next.date, JST.adding(days: 1, to: now))
            let title = isTomorrow ? "明日（\(JST.weekday(next.date)?.short ?? "")）" : "\(JST.month(next.date))/\(JST.day(next.date))（\(JST.weekday(next.date)?.short ?? "")）"
            return (title, next.items)
        }
        return (nil, [])
    }

    var body: some View {
        if family == .systemLarge { large } else { medium }
    }

    private var dateColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(JST.weekday(now)?.long ?? JST.format(now, "EEEE"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Soft.red)
            Text("\(JST.day(now))")
                .font(.system(size: 36, weight: .regular))
                .monospacedDigit()
            Spacer(minLength: 0)
            Text(todaySummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var todaySummary: String {
        let left = today.filter { !$0.isPast(now) }.count
        if today.isEmpty { return "授業なし" }
        if left == 0 { return "今日は終わり" }
        return "残り\(left)コマ"
    }

    private var medium: some View {
        let s = shown
        return HStack(alignment: .top, spacing: 12) {
            dateColumn.frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                if let title = s.title {
                    Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                if s.items.isEmpty {
                    Text(schedule.isEmpty ? "アプリで授業を登録してください" : "授業はありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(s.items.prefix(s.title == nil ? 3 : 2))) { item in
                        ClassRow(item: item, now: now, compact: true)
                    }
                    if s.items.count > (s.title == nil ? 3 : 2) {
                        Text("ほか\(s.items.count - (s.title == nil ? 3 : 2))コマ")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var large: some View {
        let s = shown
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(JST.format(now, "M月d日 EEEE"))
                    .font(.headline)
                Spacer()
                Text(schedule.term(on: now).label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if let title = s.title {
                Text(today.isEmpty ? "今日は授業がありません。\(title)の授業" : "今日の授業は終わりました。\(title)の授業")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if s.items.isEmpty {
                Spacer()
                EmptyDayView(text: schedule.isEmpty ? "アプリで授業を登録してください" : "授業はありません")
                Spacer()
            } else {
                ForEach(Array(s.items.prefix(6))) { item in
                    ClassRow(item: item, now: s.title == nil ? now : .distantPast, compact: false)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// 授業1件の行（色の帯・名前・時間と教室）
struct ClassRow: View {
    let item: ClassItem
    let now: Date
    let compact: Bool
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let tint = CourseTint(base: item.course.color.color, scheme: scheme)
        let isNow = item.isNow(now)
        let past = item.isPast(now)
        HStack(alignment: .center, spacing: compact ? 6 : 10) {
            if !compact {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(JST.hm(item.start)).font(.caption.weight(.semibold)).monospacedDigit()
                    Text(JST.hm(item.end)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                .frame(width: 40, alignment: .trailing)
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(tint.base)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.course.name)
                    .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isNow {
                Text("授業中")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint.text)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(tint.strong, in: Capsule())
            }
        }
        .padding(.vertical, compact ? 2 : 5)
        .padding(.horizontal, compact ? 4 : 6)
        .frame(maxHeight: compact ? 34 : 44)
        .background(isNow ? tint.fill : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(past ? 0.45 : 1)
    }

    private var detail: String {
        var parts: [String] = []
        if compact { parts.append(JST.hm(item.start)) } else { parts.append(item.periodText) }
        if !item.course.room.isEmpty { parts.append(item.course.room) }
        if !compact, !item.course.teacher.isEmpty { parts.append(item.course.teacher) }
        return parts.joined(separator: "・")
    }
}

// MARK: - 週の時間割

struct WeekWidgetView: View {
    let schedule: Schedule
    let now: Date
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let term = schedule.term(on: now)
        let days = schedule.days
        let rows = max(1, min(schedule.rows, 6))
        let today = JST.weekday(now)
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Text(term.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                ForEach(days) { d in
                    Text(d.short)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(d == today ? Color.white : Color.secondary)
                        .frame(width: 22, height: 22)
                        .background(d == today ? Soft.red : Color.clear, in: Circle())
                        .frame(maxWidth: .infinity)
                }
            }
            GeometryReader { geo in
                let spacing: CGFloat = 3
                let h = (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
                HStack(alignment: .top, spacing: spacing) {
                    VStack(spacing: spacing) {
                        ForEach(1...rows, id: \.self) { p in
                            Text("\(p)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: h)
                        }
                    }
                    ForEach(days) { d in
                        DayColumn(schedule: schedule, day: d, term: term, rows: rows, cellHeight: h, spacing: spacing,
                                  now: d == today ? now : nil, compact: true)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

/// 1日分の列（続いたコマはつなげて表示）
struct DayColumn: View {
    let schedule: Schedule
    let day: Weekday
    let term: Term
    let rows: Int
    let cellHeight: CGFloat
    let spacing: CGFloat
    /// 今日の列なら今の時刻（授業中のマスを強調）
    let now: Date?
    let compact: Bool
    var onTapCourse: ((Course) -> Void)? = nil
    var onTapEmpty: ((Int) -> Void)? = nil
    @Environment(\.colorScheme) var scheme

    private struct Block: Identifiable {
        let period: Int
        let length: Int
        let course: Course?
        var id: Int { period }
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var p = 1
        while p <= rows {
            if let c = schedule.course(day: day, period: p, term: term) {
                let end = min(rows, (c.lastPeriod ?? p))
                let len = max(1, end - p + 1)
                out.append(Block(period: p, length: len, course: c))
                p = max(p + 1, end + 1)
            } else {
                out.append(Block(period: p, length: 1, course: nil))
                p += 1
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(blocks) { block in
                let height = cellHeight * CGFloat(block.length) + spacing * CGFloat(block.length - 1)
                if let course = block.course {
                    CourseCell(course: course, compact: compact, highlighted: isNow(block))
                        .frame(height: height)
                        .contentShape(Rectangle())
                        .onTapGesture { onTapCourse?(course) }
                } else {
                    EmptyCell(compact: compact)
                        .frame(height: height)
                        .contentShape(Rectangle())
                        .onTapGesture { onTapEmpty?(block.period) }
                }
            }
        }
    }

    private func isNow(_ block: Block) -> Bool {
        guard let now, let first = schedule.period(block.period),
              let last = schedule.period(block.period + block.length - 1) else { return false }
        let m = JST.minutes(now)
        return term == schedule.term(on: now) && m >= first.start && m < last.end
    }
}

struct CourseCell: View {
    let course: Course
    let compact: Bool
    let highlighted: Bool
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let tint = CourseTint(base: course.color.color, scheme: scheme)
        VStack(alignment: .leading, spacing: 2) {
            Text(course.name)
                .font(compact ? .system(size: 10, weight: .semibold) : .system(size: 12, weight: .semibold))
                .foregroundStyle(tint.text)
                .lineLimit(compact ? 3 : 4)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !course.room.isEmpty {
                Text(course.room)
                    .font(.system(size: compact ? 8.5 : 10, weight: .medium))
                    .foregroundStyle(tint.text.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, compact ? 3 : 5)
        .padding(.vertical, compact ? 3 : 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.fill, in: RoundedRectangle(cornerRadius: compact ? 4 : 7, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: compact ? 4 : 7, bottomLeadingRadius: compact ? 4 : 7, style: .continuous)
                .fill(tint.base)
                .frame(width: compact ? 2.5 : 3.5)
        }
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: compact ? 4 : 7, style: .continuous)
                    .strokeBorder(tint.base, lineWidth: compact ? 1.5 : 2)
            }
        }
    }
}

struct EmptyCell: View {
    let compact: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: compact ? 4 : 7, style: .continuous)
            .fill(Color(.tertiarySystemFill).opacity(compact ? 0.5 : 0.6))
    }
}

struct EmptyDayView: View {
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WidgetMessageView: View {
    let text: String
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(text)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "calendar")
            }
        case .accessoryRectangular:
            Text(text).font(.caption).lineLimit(3)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
