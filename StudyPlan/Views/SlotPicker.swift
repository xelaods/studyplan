import SwiftUI

/// 空いているマスをタップしたときの、授業を選ぶ画面
struct SlotPicker: View {
    let target: SlotTarget
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var query = ""
    @State var editing: Course?
    @State var importing: ImportSource?

    var body: some View {
        NavigationStack {
            List {
                let candidates = store.candidates(day: target.day, period: target.period)
                let others = filteredOthers(excluding: Set(candidates.map(\.id)))

                if query.isEmpty {
                    Section {
                        if candidates.isEmpty {
                            if store.data.catalog.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("まだ授業を取得していません")
                                        .font(.subheadline.weight(.semibold))
                                    Text("エドポタの時間割表やWebシラバスから授業を取得すると、ここから選ぶだけで入れられます。")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            } else {
                                Text("この時間に開講している取得済みの授業はありません")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(candidates) { c in
                                pickButton(c)
                            }
                        }
                    } header: {
                        Text("\(target.day.medium)\(target.period)限の授業")
                    } footer: {
                        if let t = store.schedule.period(target.period) {
                            Text(t.rangeText)
                        }
                    }
                }

                Section {
                    Button {
                        editing = store.draft(day: target.day, period: target.period)
                    } label: {
                        SettingsLabel(title: "自分で入力", systemName: "square.and.pencil", color: .gray)
                    }
                    Button {
                        importing = .portal
                    } label: {
                        SettingsLabel(title: "エドポタから取り込む", systemName: "square.and.arrow.down", color: .blue)
                    }
                    Button {
                        importing = .syllabus
                    } label: {
                        SettingsLabel(title: "Webシラバスで探す", systemName: "magnifyingglass", color: .indigo)
                    }
                }
                .foregroundStyle(.primary)

                if !others.isEmpty {
                    Section(query.isEmpty ? "ほかの取得済みの授業" : "検索結果") {
                        ForEach(others) { c in
                            pickButton(c)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "取得済みの授業を検索")
            .navigationTitle("\(target.day.long) \(target.period)限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .sheet(item: $editing) { course in
                CourseEditor(course: course, isNew: true) { dismiss() }
            }
            .sheet(item: $importing) { ImportView(source: $0) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func pickButton(_ c: CatalogCourse) -> some View {
        Button {
            store.add(c, day: target.day, period: target.period)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } label: {
            HStack {
                CatalogRow(course: c, registered: false)
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .foregroundStyle(.primary)
    }

    private func filteredOthers(excluding: Set<String>) -> [CatalogCourse] {
        let q = TimetableParser.fold(query)
        let list = store.data.catalog.filter { !excluding.contains($0.id) }
        if q.isEmpty { return Array(list.prefix(30)) }
        return list.filter {
            TimetableParser.fold($0.name).contains(q) || TimetableParser.fold($0.teacher).contains(q) || TimetableParser.fold($0.code).contains(q)
        }
    }
}
