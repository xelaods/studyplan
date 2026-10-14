import SwiftUI
import WidgetKit
import EventKit

final class Store: ObservableObject {
    static let shared = Store()
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    @Published var data: AppData {
        didSet { if data != oldValue { scheduleSave() } }
    }
    @Published var calendarAccess: Bool = CalendarBridge.hasAccess

    private var saveTask: Task<Void, Never>?

    private init() {
        if Store.isDemo {
            data = Sample.data()
        } else {
            SharedStore.migrateIfNeeded()
            data = SharedStore.loadData()
        }
    }

    var schedule: Schedule { Schedule(data) }

    /// いま表示している学期
    var term: Term { data.termMode.resolve(on: Clock.now) }

    // MARK: 保存

    private func scheduleSave() {
        guard !Store.isDemo else { return }
        saveTask?.cancel()
        let snapshot = data
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.write(snapshot) }
        }
    }

    private func write(_ value: AppData) {
        SharedStore.saveData(value)
        SharedStore.saveSnapshot(value.snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// アプリを閉じるときなど、すぐに保存
    func flush() {
        guard !Store.isDemo else { return }
        saveTask?.cancel()
        write(data)
    }

    func reload() {
        guard !Store.isDemo else { return }
        calendarAccess = CalendarBridge.hasAccess
        let fresh = SharedStore.loadData()
        if fresh != data { data = fresh }
    }

    // MARK: 授業

    func course(_ id: UUID) -> Course? { data.courses.first { $0.id == id } }

    func binding(_ id: UUID) -> Binding<Course>? {
        guard data.courses.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in self?.data.courses.first { $0.id == id } ?? Course(name: "", day: nil, period: nil) },
            set: { [weak self] new in
                guard let self, let i = self.data.courses.firstIndex(where: { $0.id == id }) else { return }
                self.data.courses[i] = new
            })
    }

    func save(_ course: Course) {
        var c = course
        c.name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 同じ学期・同じ時間に重なる授業は外す（入れ替え）
        if let day = c.day, let p = c.period {
            data.courses.removeAll { other in
                other.id != c.id && other.day == day && other.term.applies(to: c.term) && c.term.applies(to: other.term) &&
                    (p...(p + c.length - 1)).contains(where: { other.covers(day: day, period: $0) })
            }
        }
        if let i = data.courses.firstIndex(where: { $0.id == c.id }) {
            data.courses[i] = c
        } else {
            data.courses.append(c)
        }
        // 同じ授業名の色はそろえる
        for i in data.courses.indices where data.courses[i].id != c.id && TimetableParser.fold(data.courses[i].name) == TimetableParser.fold(c.name) {
            data.courses[i].color = c.color
        }
    }

    func remove(_ id: UUID) {
        data.courses.removeAll { $0.id == id }
    }

    func removeAll() {
        data.courses.removeAll()
    }

    func suggestedColor(for name: String) -> CourseColor {
        if let same = data.courses.first(where: { TimetableParser.fold($0.name) == TimetableParser.fold(name) }) {
            return same.color
        }
        return CourseColor.suggest(for: name, used: data.courses.map(\.color))
    }

    /// 新しい授業のひな形
    func draft(day: Weekday?, period: Int?) -> Course {
        Course(name: "", day: day, period: period, term: term, color: CourseColor.suggest(for: UUID().uuidString, used: data.courses.map(\.color)))
    }

    // MARK: 取得した授業

    func isRegistered(_ c: CatalogCourse) -> Bool {
        data.courses.contains { $0.sourceID == c.id } ||
            data.courses.contains { TimetableParser.fold($0.name) == TimetableParser.fold(c.name) && $0.term.applies(to: c.term ?? term) }
    }

    /// 取得した授業をそのまま（曜日・時限どおりに）入れる
    func add(_ catalog: [CatalogCourse], term fallback: Term) {
        for c in catalog where !isRegistered(c) {
            for course in c.makeCourses(term: fallback, color: suggestedColor(for: c.name)) {
                save(course)
            }
        }
    }

    /// 取得した授業を、選んだ時間に入れる
    func add(_ c: CatalogCourse, day: Weekday, period: Int) {
        let term = c.term ?? self.term
        // その曜日に続きのコマがあればまとめる
        let periods = c.slots.filter { $0.day == day }.map(\.period).sorted()
        var length = 1
        if periods.contains(period) {
            var p = period
            while periods.contains(p + 1) { p += 1; length += 1 }
        }
        save(Course(name: c.name, teacher: c.teacher, room: c.room, day: day, period: period, length: length,
                    term: term, color: suggestedColor(for: c.name), code: c.code, sourceID: c.id))
    }

    func mergeCatalog(_ list: [CatalogCourse]) {
        var map = Dictionary(data.catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var order = data.catalog.map(\.id)
        for c in list {
            if var old = map[c.id] {
                old.slots = c.slots.isEmpty ? old.slots : c.slots
                if !c.room.isEmpty { old.room = c.room }
                if !c.code.isEmpty { old.code = c.code }
                old.source = c.source
                map[c.id] = old
            } else {
                map[c.id] = c
                order.append(c.id)
            }
        }
        data.catalog = order.compactMap { map[$0] }
        data.catalogUpdated = Date()
    }

    func clearCatalog() {
        data.catalog.removeAll()
        data.catalogUpdated = nil
    }

    /// その時間の候補
    func candidates(day: Weekday, period: Int) -> [CatalogCourse] {
        data.catalog.filter { $0.has(day: day, period: period) && ($0.term?.applies(to: term) ?? true) }
    }

    // MARK: ウィジェット（カレンダー経由）

    func requestCalendarAccess() async {
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        await MainActor.run {
            self.calendarAccess = granted
            if granted { self.flush() }
        }
    }

    func setCalendarBridge(_ on: Bool) {
        CalendarBridge.enabled = on
        if on { flush() } else { CalendarBridge.clear() }
        objectWillChange.send()
    }
}

/// ウィジェットなどから開いたときの行き先
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var tab: MainTab = MainTab.initial
    @Published var openCourse: UUID?
}

enum MainTab: Hashable {
    case today, week, courses, settings

    static var initial: MainTab {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return .today }
        switch args[i + 1] {
        case "week": return .week
        case "courses": return .courses
        case "settings": return .settings
        default: return .today
        }
    }
}
