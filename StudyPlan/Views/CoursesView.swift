import SwiftUI

/// 登録した授業の一覧（曜日ごと）
struct CoursesView: View {
    @EnvironmentObject var store: Store
    @State var importing: ImportSource?
    @State var editing: Course?
    @State var showAllTerms = false

    var body: some View {
        NavigationStack {
            List {
                let term = store.term
                let courses = store.data.courses.filter { showAllTerms || $0.term.applies(to: term) }

                Section {
                    Button { importing = .portal } label: {
                        SettingsLabel(title: "エドポタから取り込む", systemName: "square.and.arrow.down", color: .blue)
                    }
                    Button { importing = .syllabus } label: {
                        SettingsLabel(title: "Webシラバスで探す", systemName: "magnifyingglass", color: .indigo)
                    }
                    NavigationLink {
                        CatalogView()
                    } label: {
                        HStack {
                            SettingsLabel(title: "取得した授業", systemName: "tray.full", color: .orange)
                            Spacer()
                            Text("\(store.data.catalog.count)件").foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    if let updated = store.data.catalogUpdated {
                        Text("最後に取得：\(JST.format(updated, "M月d日 H:mm"))")
                    }
                }
                .foregroundStyle(.primary)

                if courses.isEmpty {
                    Section {
                        Text(store.data.courses.isEmpty ? "まだ授業がありません。上から取り込むか、右上の＋から入力してください。" : "\(term.label)の授業はありません")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Weekday.allCases) { day in
                        let list = courses.filter { $0.day == day }.sorted { ($0.period ?? 0) < ($1.period ?? 0) }
                        if !list.isEmpty {
                            Section(day.long) {
                                ForEach(list) { c in
                                    NavigationLink(value: c.id) {
                                        CourseListRow(course: c, showSlot: true)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button(c.isRequired ? "選択にする" : "必修にする") {
                                            store.setRequired(c.id, !c.isRequired)
                                        }
                                        .tint(c.isRequired ? .blue : .red)
                                    }
                                }
                                .onDelete { idx in
                                    for i in idx { store.remove(list[i].id) }
                                }
                            }
                        }
                    }
                    let extra = courses.filter { !$0.isScheduled }
                    if !extra.isEmpty {
                        Section("時間外") {
                            ForEach(extra) { c in
                                NavigationLink(value: c.id) { CourseListRow(course: c, showSlot: false) }
                            }
                            .onDelete { idx in
                                for i in idx { store.remove(extra[i].id) }
                            }
                        }
                    }
                    Section {
                        Toggle("ほかの学期の授業も表示", isOn: $showAllTerms)
                    } footer: {
                        Text(summary(courses))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("授業")
            .navigationDestination(for: UUID.self) { id in
                CourseDetailView(courseID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = store.draft(day: nil, period: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $importing) { ImportView(source: $0) }
            .sheet(item: $editing) { CourseEditor(course: $0, isNew: true) }
        }
    }
}

extension CoursesView {
    func summary(_ courses: [Course]) -> String {
        var slots = 0, absences = 0
        for c in courses {
            if c.isScheduled { slots += c.length }
            absences += c.absences
        }
        return "\(slots)コマ・欠席の合計 \(absences)回"
    }
}

/// 取得した授業の一覧（検索して時間割に入れる）
struct CatalogView: View {
    @EnvironmentObject var store: Store
    @State var query = ""
    @State var confirmClear = false

    var body: some View {
        let q = TimetableParser.fold(query)
        let list = store.data.catalog.filter {
            q.isEmpty || TimetableParser.fold($0.name).contains(q) || TimetableParser.fold($0.teacher).contains(q)
        }
        List {
            if store.data.catalog.isEmpty {
                Text("エドポタの時間割表やWebシラバスから読み取った授業がここに並びます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(list) { c in
                let registered = store.isRegistered(c)
                HStack {
                    CatalogRow(course: c, registered: registered)
                    if !registered {
                        Button {
                            store.add([c], term: store.term)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "授業名・教員で検索")
        .navigationTitle("取得した授業")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.data.catalog.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("消去", role: .destructive) { confirmClear = true }
                }
            }
        }
        .confirmationDialog("取得した授業の一覧を消去しますか？（時間割に入れた授業は消えません）", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("消去", role: .destructive) { store.clearCatalog() }
        }
    }
}
