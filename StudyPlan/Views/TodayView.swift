import SwiftUI

/// 今日の授業（リマインダーやカレンダーの一覧のような画面）
struct TodayView: View {
    @EnvironmentObject var store: Store
    @State var importing: ImportSource?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let now = Clock.fixed ?? context.date
                content(now: now)
            }
            .navigationTitle("今日")
            .navigationDestination(for: UUID.self) { id in
                CourseDetailView(courseID: id)
            }
            .sheet(item: $importing) { ImportView(source: $0) }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let schedule = store.schedule
        let items = schedule.items(on: now)
        let focus = ClassFocus(schedule: schedule, now: now)
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(JST.format(now, "M月d日 EEEE"))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(AcademicYear.of(now))年度 \(schedule.term(on: now).label)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }

            if schedule.isEmpty {
                Section {
                    OnboardingCard(importing: $importing)
                }
            } else if let item = focus.item {
                Section {
                    NavigationLink(value: item.course.id) {
                        FocusCard(item: item, label: focus.label, isNow: focus.isNow, now: now)
                    }
                }
            }

            if !schedule.isEmpty {
                Section {
                    if items.isEmpty {
                        Label(JST.weekday(now) == nil ? "日曜日です。ゆっくり休みましょう" : "今日は授業がありません", systemImage: "cup.and.saucer")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { item in
                            NavigationLink(value: item.course.id) {
                                TodayRow(item: item, now: now)
                            }
                        }
                    }
                } header: {
                    Text("今日の授業")
                } footer: {
                    if !items.isEmpty, let first = items.first, let last = items.last {
                        Text("\(items.count)コマ・\(JST.hm(first.start))〜\(JST.hm(last.end))")
                    }
                }

                if let next = schedule.nextClassDay(after: now) {
                    Section {
                        ForEach(next.items) { item in
                            NavigationLink(value: item.course.id) {
                                TodayRow(item: item, now: .distantPast)
                            }
                        }
                    } header: {
                        Text(nextHeader(next.date, now: now))
                    }
                }

                let unscheduled = schedule.courses(term: schedule.term(on: now)).filter { !$0.isScheduled }
                if !unscheduled.isEmpty {
                    Section("時間外の授業") {
                        ForEach(unscheduled) { c in
                            NavigationLink(value: c.id) {
                                CourseListRow(course: c)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func nextHeader(_ date: Date, now: Date) -> String {
        let wd = JST.weekday(date)?.short ?? ""
        if JST.isSameDay(date, JST.adding(days: 1, to: now)) { return "明日（\(wd)）" }
        return "\(JST.month(date))月\(JST.day(date))日（\(wd)）"
    }
}

/// 授業中・次の授業の大きめの表示
struct FocusCard: View {
    let item: ClassItem
    let label: String
    let isNow: Bool
    let now: Date
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let tint = CourseTint(base: item.course.color.color, scheme: scheme)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isNow ? "dot.radiowaves.left.and.right" : "clock")
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(isNow ? "あと\(Remaining.text(from: now, to: item.end))" : startText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(tint.text)

            Text(item.course.name)
                .font(.title2.weight(.bold))
                .lineLimit(2)

            HStack(spacing: 14) {
                Label(item.periodText + "  " + item.timeText, systemImage: "clock")
                if !item.course.room.isEmpty {
                    Label(item.course.room, systemImage: "mappin.and.ellipse")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .labelStyle(CompactLabelStyle())

            if isNow {
                ProgressView(value: item.progress(now))
                    .tint(tint.base)
            }
        }
        .padding(.vertical, 6)
    }

    private var startText: String {
        if JST.isSameDay(item.start, now) {
            return "\(JST.hm(item.start))から・あと\(Remaining.text(from: now, to: item.start))"
        }
        return "\(JST.hm(item.start))から"
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.caption)
            configuration.title
        }
    }
}

/// 今日の一覧の1行（左に時刻、色の帯）
struct TodayRow: View {
    let item: ClassItem
    let now: Date

    var body: some View {
        let past = item.isPast(now)
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(JST.hm(item.start)).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(JST.hm(item.end)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 44, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2)
                .fill(item.course.color.color)
                .frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.course.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text([item.periodText, item.course.room, item.course.teacher].filter { !$0.isEmpty }.joined(separator: "・"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.isNow(now) {
                Text("授業中")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(item.course.color.color, in: Capsule())
            }
        }
        .opacity(past ? 0.45 : 1)
        .padding(.vertical, 2)
    }
}

/// 授業がまだないとき
struct OnboardingCard: View {
    @Binding var importing: ImportSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(.blue)
            Text("時間割をつくりましょう")
                .font(.title3.weight(.bold))
            Text("エドポタにログインして時間割表を開くか、Webシラバスで検索すると、授業を読み取って選ぶだけで登録できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                importing = .portal
            } label: {
                Label("エドポタから取り込む", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button {
                importing = .syllabus
            } label: {
                Text("Webシラバスで探す（ログイン不要）")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.vertical, 8)
    }
}
