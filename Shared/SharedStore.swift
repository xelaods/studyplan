import Foundation
import EventKit

/// 保存場所。App Group が使える署名なら、アプリとウィジェットで同じ場所を使う
enum SharedStore {
    static let appGroupID: String? = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }()

    static var groupContainer: URL? {
        guard let id = appGroupID else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// App Group が実際に使えるか（署名に App Group が入っているか）
    static var isShared: Bool { groupContainer != nil }

    static var groupDefaults: UserDefaults? {
        guard isShared, let id = appGroupID else { return nil }
        return UserDefaults(suiteName: id)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: アプリのデータ

    private static let fileName = "studyplan.json"

    static var dataURL: URL {
        let base = groupContainer
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(fileName)
    }

    /// App Group が後から使えるようになったとき、アプリだけの場所にあるデータを移す
    static func migrateIfNeeded() {
        guard let group = groupContainer else { return }
        let fm = FileManager.default
        guard let local = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName),
              fm.fileExists(atPath: local.path) else { return }
        let target = group.appendingPathComponent(fileName)
        if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: local, to: target) }
    }

    static func loadData() -> AppData {
        guard let data = try? Data(contentsOf: dataURL),
              let file = try? decoder.decode(AppData.self, from: data) else { return AppData() }
        return file
    }

    static func saveData(_ file: AppData) {
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: dataURL, options: [.atomic])
    }

    // MARK: ウィジェット用

    private static let snapshotKey = "snapshot.v1"

    static func saveSnapshot(_ snapshot: WidgetSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        groupDefaults?.set(data, forKey: snapshotKey)
        CalendarBridge.write(data)
    }

    /// ウィジェットが読む：App Group → カレンダーのメモ の順
    static func loadSnapshot() -> WidgetSnapshot? {
        if let data = groupDefaults?.data(forKey: snapshotKey),
           let s = try? decoder.decode(WidgetSnapshot.self, from: data) {
            return s
        }
        if let data = CalendarBridge.read(),
           let s = try? decoder.decode(WidgetSnapshot.self, from: data) {
            return s
        }
        return nil
    }
}

/// App Group が使えない署名でも、ウィジェットに時間割を渡すための仕組み（Shift Note・MoneyPlan と同じ方法）。
/// 2001年1月3日に終日の予定を1件だけ作り、メモ欄に時間割を保存する（ふだんのカレンダー表示には出てこない日付）。
enum CalendarBridge {
    static let title = "StudyPlan の時間割"
    static let marker = "[studyplan-v1]"

    static var day: Date {
        var c = DateComponents()
        c.year = 2001; c.month = 1; c.day = 3
        return JST.calendar.date(from: c) ?? Date(timeIntervalSinceReferenceDate: 2 * 86_400)
    }

    static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static var denied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted || s == .writeOnly
    }

    /// 使うかどうか（設定でオフにできる）
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "calendarBridge") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "calendarBridge") }
    }

    private static func events(in store: EKEventStore) -> [EKEvent] {
        let predicate = store.predicateForEvents(withStart: day, end: JST.adding(days: 1, to: day), calendars: nil)
        return store.events(matching: predicate).filter { ($0.notes ?? "").contains(marker) }
    }

    static func read(store: EKEventStore = EKEventStore()) -> Data? {
        guard hasAccess else { return nil }
        for event in events(in: store) {
            guard let notes = event.notes, let range = notes.range(of: marker) else { continue }
            let json = notes[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = json.data(using: .utf8) { return data }
        }
        return nil
    }

    @discardableResult
    static func write(_ data: Data, store: EKEventStore = EKEventStore()) -> Bool {
        guard hasAccess else { return false }
        let existing = events(in: store)
        guard enabled, !SharedStore.isShared else {
            // App Group が使えるならカレンダーには書かない（前に書いた分は消す）
            for e in existing { try? store.remove(e, span: .thisEvent, commit: false) }
            try? store.commit()
            return true
        }
        guard let json = String(data: data, encoding: .utf8) else { return false }
        let notes = "StudyPlan のウィジェット用の時間割です。消してもアプリのデータは消えません。\n\(marker)\n\(json)"
        let event = existing.first ?? EKEvent(eventStore: store)
        if existing.first == nil {
            guard let calendar = store.defaultCalendarForNewEvents
                    ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications }) else { return false }
            event.calendar = calendar
            event.title = title
            event.isAllDay = true
            event.startDate = day
            event.endDate = day
        }
        guard event.notes != notes else { return true }
        event.notes = notes
        do {
            try store.save(event, span: .thisEvent, commit: true)
            for e in existing.dropFirst() { try? store.remove(e, span: .thisEvent, commit: false) }
            try? store.commit()
            return true
        } catch {
            return false
        }
    }

    static func clear(store: EKEventStore = EKEventStore()) {
        guard hasAccess else { return }
        for e in events(in: store) { try? store.remove(e, span: .thisEvent, commit: false) }
        try? store.commit()
    }
}
