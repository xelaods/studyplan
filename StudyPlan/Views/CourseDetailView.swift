import SwiftUI

/// 授業の詳細（カレンダーの予定の詳細のような画面）
struct CourseDetailView: View {
    let courseID: UUID
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var editing = false
    @State var confirmDelete = false

    var body: some View {
        if let binding = store.binding(courseID) {
            content(binding)
        } else {
            ContentUnavailableView("授業がありません", systemImage: "book.closed")
        }
    }

    private func content(_ course: Binding<Course>) -> some View {
        let c = course.wrappedValue
        let schedule = store.schedule
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(c.color.color).frame(width: 12, height: 12)
                        Text("\(c.kindLabel)・\(c.term.label)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(c.name)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(timeText(c, schedule: schedule))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent {
                    Text(c.room.isEmpty ? "未設定" : c.room).foregroundStyle(c.room.isEmpty ? .tertiary : .secondary)
                } label: {
                    Label("教室", systemImage: "mappin.and.ellipse")
                }
                LabeledContent {
                    Text(c.teacher.isEmpty ? "未設定" : c.teacher).foregroundStyle(c.teacher.isEmpty ? .tertiary : .secondary)
                } label: {
                    Label("担当教員", systemImage: "person")
                }
                if !c.code.isEmpty {
                    LabeledContent {
                        Text(c.code).foregroundStyle(.secondary).textSelection(.enabled)
                    } label: {
                        Label("時間割コード", systemImage: "number")
                    }
                }
            }

            Section {
                Stepper(value: course.absences, in: 0...30) {
                    HStack {
                        Label("欠席", systemImage: "person.crop.circle.badge.xmark")
                        Spacer()
                        Text("\(c.absences)回")
                            .monospacedDigit()
                            .foregroundStyle(c.absences >= 4 ? Color.red : Color.secondary)
                    }
                }
                Stepper(value: course.lates, in: 0...30) {
                    HStack {
                        Label("遅刻", systemImage: "clock.badge.exclamationmark")
                        Spacer()
                        Text("\(c.lates)回").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("出欠のメモ")
            } footer: {
                Text("このアプリの中だけのメモです。エドヘンの出席記録とは連動しません。")
            }

            Section("メモ") {
                TextField("課題・持ち物・テストなど", text: course.memo, axis: .vertical)
                    .lineLimit(3...10)
            }

            Section {
                RequiredPicker(isRequired: Binding(get: { course.wrappedValue.isRequired }, set: { new in
                    store.setRequired(courseID, new)
                }))
            } header: {
                Text("区分")
            } footer: {
                Text("必修は赤、それ以外は青で表示します。同じ名前の授業はまとめて変わります。")
            }

            Section {
                Button("時間割から削除", role: .destructive) {
                    confirmDelete = true
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("編集") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            CourseEditor(course: c, isNew: false)
        }
        .confirmationDialog("「\(c.name)」を時間割から削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                dismiss()
                store.remove(courseID)
            }
        }
    }

    private func timeText(_ c: Course, schedule: Schedule) -> String {
        guard let day = c.day, let p = c.period else { return "時間外（集中講義・オンデマンドなど）" }
        let start = schedule.period(p)
        let end = schedule.period(p + c.length - 1)
        let range = (start.map(\.startText) ?? "") + "〜" + (end.map(\.endText) ?? "")
        return "\(day.long) \(c.length > 1 ? "\(p)〜\(p + c.length - 1)" : "\(p)")限・\(range)"
    }
}

/// 授業の入力・編集
struct CourseEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var course: Course
    let isNew: Bool
    var onSave: (() -> Void)? = nil

    init(course: Course, isNew: Bool, onSave: (() -> Void)? = nil) {
        _course = State(initialValue: course)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("授業名", text: $course.name)
                        .font(.body.weight(.medium))
                    TextField("教室", text: $course.room)
                    TextField("担当教員", text: $course.teacher)
                }

                Section {
                    Picker("曜日", selection: dayBinding) {
                        Text("時間外").tag(0)
                        ForEach(Weekday.allCases) { d in
                            Text(d.long).tag(d.rawValue)
                        }
                    }
                    if course.day != nil {
                        Picker("時限", selection: periodBinding) {
                            ForEach(1...PeriodTime.maxCount, id: \.self) { p in
                                if let t = store.schedule.period(p) {
                                    Text("\(p)限（\(t.rangeText)）").tag(p)
                                } else {
                                    Text("\(p)限").tag(p)
                                }
                            }
                        }
                        Stepper(value: $course.length, in: 1...3) {
                            LabeledContent("続けて", value: "\(course.length)コマ")
                        }
                    }
                    Picker("学期", selection: $course.term) {
                        ForEach(Term.allCases) { t in Text(t.label).tag(t) }
                    }
                } footer: {
                    if let day = course.day, let p = course.period,
                       let other = store.data.courses.first(where: { $0.id != course.id && $0.covers(day: day, period: p) && $0.term.applies(to: course.term) }) {
                        Text("保存すると、同じ時間の「\(other.name)」と入れ替わります。")
                    }
                }

                Section {
                    RequiredPicker(isRequired: $course.isRequired)
                } header: {
                    Text("区分")
                } footer: {
                    Text("必修は赤、それ以外は青で表示します。")
                }

                Section("メモ") {
                    TextField("課題・持ち物など", text: $course.memo, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(isNew ? "授業を追加" : "授業を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "追加" : "完了") {
                        store.save(course)
                        onSave?()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(course.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var dayBinding: Binding<Int> {
        Binding(get: { course.day?.rawValue ?? 0 }, set: { v in
            course.day = Weekday(rawValue: v)
            if course.day != nil, course.period == nil { course.period = 1 }
            if course.day == nil { course.period = nil }
        })
    }

    private var periodBinding: Binding<Int> {
        Binding(get: { course.period ?? 1 }, set: { course.period = $0 })
    }
}
