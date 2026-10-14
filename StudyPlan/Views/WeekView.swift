import SwiftUI

/// 1週間の時間割（マスをタップして授業を選ぶ）
struct WeekView: View {
    @EnvironmentObject var store: Store
    @State var path: [UUID] = []
    @State var picking: SlotTarget?
    @State var importing: ImportSource?
    @State var editing: Course?
    @State var termOverride: Term?

    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                grid(now: Clock.fixed ?? context.date)
            }
            .navigationTitle("時間割")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    termMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { importing = .portal } label: { Label("エドポタから取り込む", systemImage: "square.and.arrow.down") }
                        Button { importing = .syllabus } label: { Label("Webシラバスで探す", systemImage: "magnifyingglass") }
                        Divider()
                        Button { editing = store.draft(day: nil, period: nil) } label: { Label("自分で入力", systemImage: "square.and.pencil") }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                CourseDetailView(courseID: id)
            }
            .sheet(item: $picking) { target in
                SlotPicker(target: target)
            }
            .sheet(item: $importing) { ImportView(source: $0) }
            .sheet(item: $editing) { course in
                CourseEditor(course: course, isNew: true)
            }
            .onAppear {
                // スクリーンショット用
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-pick") { picking = SlotTarget(day: .wed, period: 3) }
                if args.contains("-detail"), let first = store.data.courses.first(where: { $0.day == .tue && $0.period == 2 }) {
                    path = [first.id]
                }
            }
        }
    }

    private var shownTerm: Term { termOverride ?? store.term }

    private var termMenu: some View {
        Menu {
            Picker("学期", selection: Binding(get: { shownTerm }, set: { termOverride = $0 == store.term ? nil : $0 })) {
                Text("前期").tag(Term.first)
                Text("後期").tag(Term.second)
            }
        } label: {
            HStack(spacing: 3) {
                Text("\(AcademicYear.of(Clock.now))年度 \(shownTerm.label)")
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
        }
    }

    private func grid(now: Date) -> some View {
        let schedule = store.schedule
        let days = schedule.days
        let rows = schedule.rows
        let today = JST.weekday(now)
        let term = shownTerm
        let unscheduled = schedule.courses(term: term).filter { !$0.isScheduled }
        return GeometryReader { geo in
            let spacing: CGFloat = 4
            let headerHeight: CGFloat = 34
            let footer: CGFloat = unscheduled.isEmpty ? 0 : 56
            let available = geo.size.height - headerHeight - footer - 16
            let cellHeight = max(78, (available - spacing * CGFloat(rows - 1)) / CGFloat(rows))
            ScrollView {
                VStack(spacing: spacing) {
                    // 曜日の見出し
                    HStack(spacing: spacing) {
                        Color.clear.frame(width: 30, height: headerHeight)
                        ForEach(days) { d in
                            let isToday = d == today && term == schedule.term(on: now)
                            Text(d.short)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isToday ? Color.white : Color.secondary)
                                .frame(width: 28, height: 28)
                                .background(isToday ? Color.red : Color.clear, in: Circle())
                                .frame(maxWidth: .infinity)
                        }
                    }
                    HStack(alignment: .top, spacing: spacing) {
                        // 時限
                        VStack(spacing: spacing) {
                            ForEach(1...rows, id: \.self) { p in
                                PeriodLabel(period: schedule.period(p), number: p)
                                    .frame(width: 30, height: cellHeight)
                            }
                        }
                        ForEach(days) { d in
                            DayColumn(schedule: schedule, day: d, term: term, rows: rows, cellHeight: cellHeight,
                                      spacing: spacing, now: d == today ? now : nil, compact: false,
                                      onTapCourse: { path.append($0.id) },
                                      onTapEmpty: { p in picking = SlotTarget(day: d, period: p) })
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if !unscheduled.isEmpty {
                        UnscheduledStrip(courses: unscheduled) { path.append($0.id) }
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .background(Color(.systemBackground))
    }
}

struct SlotTarget: Identifiable, Hashable {
    let day: Weekday
    let period: Int
    var id: String { "\(day.rawValue)-\(period)" }
}

private struct PeriodLabel: View {
    let period: PeriodTime?
    let number: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold))
            if let period {
                Text(period.startText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(period.endText)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }
}

/// 時間外（集中講義・オンデマンドなど）の授業
private struct UnscheduledStrip: View {
    let courses: [Course]
    let open: (Course) -> Void
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("時間外")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(courses) { c in
                        let tint = CourseTint(base: c.color.color, scheme: scheme)
                        Button { open(c) } label: {
                            Text(c.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tint.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(tint.fill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
