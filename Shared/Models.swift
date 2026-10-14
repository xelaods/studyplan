import Foundation

// MARK: - 曜日

enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable, Hashable {
    case mon = 1, tue, wed, thu, fri, sat

    var id: Int { rawValue }

    /// 月・火・水…
    var short: String { ["月", "火", "水", "木", "金", "土"][rawValue - 1] }
    /// 月曜日
    var long: String { short + "曜日" }
    /// 月曜
    var medium: String { short + "曜" }

    /// Calendar の weekday（日曜=1）
    var calendarWeekday: Int { rawValue + 1 }

    init?(calendarWeekday: Int) {
        self.init(rawValue: calendarWeekday - 1)
    }

    /// 「月」「月曜」「月曜日」「Mon」など
    init?(symbol raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = s.first else { return nil }
        let map: [Character: Weekday] = ["月": .mon, "火": .tue, "水": .wed, "木": .thu, "金": .fri, "土": .sat]
        if let d = map[first] { self = d; return }
        let lower = s.lowercased()
        let en: [(String, Weekday)] = [("mon", .mon), ("tue", .tue), ("wed", .wed), ("thu", .thu), ("fri", .fri), ("sat", .sat)]
        for (prefix, d) in en where lower.hasPrefix(prefix) { self = d; return }
        return nil
    }

    static let weekdays: [Weekday] = [.mon, .tue, .wed, .thu, .fri]

    static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - 学期

enum Term: String, Codable, CaseIterable, Identifiable, Hashable {
    case first, second, full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .first: return "前期"
        case .second: return "後期"
        case .full: return "通年"
        }
    }

    /// いまの学期に表示するか
    func applies(to current: Term) -> Bool {
        self == .full || current == .full || self == current
    }
}

/// 表示する学期の決め方
enum TermMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case auto, first, second

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "自動"
        case .first: return "前期"
        case .second: return "後期"
        }
    }

    /// 自動のときは 4〜9月を前期、10〜3月を後期とする
    func resolve(on date: Date) -> Term {
        switch self {
        case .first: return .first
        case .second: return .second
        case .auto:
            let m = JST.month(date)
            return (4...9).contains(m) ? .first : .second
        }
    }
}

/// 年度（4月始まり）
enum AcademicYear {
    static func of(_ date: Date) -> Int {
        let y = JST.year(date)
        return JST.month(date) >= 4 ? y : y - 1
    }
}

// MARK: - 時限

struct PeriodTime: Codable, Hashable, Identifiable {
    var number: Int
    /// 0:00 からの分
    var start: Int
    var end: Int

    var id: Int { number }

    var startText: String { JST.hm(start) }
    var endText: String { JST.hm(end) }
    var rangeText: String { "\(startText)〜\(endText)" }

    /// 江戸川大学の時限（1〜5限は大学の時間。6・7限は5限のあとに10分休みで続けた目安）
    static let edogawa: [PeriodTime] = [
        PeriodTime(number: 1, start: 9 * 60, end: 10 * 60 + 40),
        PeriodTime(number: 2, start: 10 * 60 + 50, end: 12 * 60 + 30),
        PeriodTime(number: 3, start: 13 * 60 + 10, end: 14 * 60 + 50),
        PeriodTime(number: 4, start: 15 * 60, end: 16 * 60 + 40),
        PeriodTime(number: 5, start: 16 * 60 + 50, end: 18 * 60 + 30),
        PeriodTime(number: 6, start: 18 * 60 + 40, end: 20 * 60 + 20),
        PeriodTime(number: 7, start: 20 * 60 + 30, end: 22 * 60 + 10),
    ]

    static let maxCount = 7
}

// MARK: - 色（カレンダーの色と同じ並び）

enum CourseColor: String, Codable, CaseIterable, Identifiable, Hashable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: return "レッド"
        case .orange: return "オレンジ"
        case .yellow: return "イエロー"
        case .green: return "グリーン"
        case .mint: return "ミント"
        case .teal: return "ティール"
        case .cyan: return "シアン"
        case .blue: return "ブルー"
        case .indigo: return "インディゴ"
        case .purple: return "パープル"
        case .pink: return "ピンク"
        case .brown: return "ブラウン"
        }
    }

    /// まだ使っていない色を順に（すべて使っていれば名前から決める）
    static func suggest(for name: String, used: [CourseColor]) -> CourseColor {
        let order: [CourseColor] = [.blue, .orange, .green, .purple, .red, .teal, .pink, .indigo, .yellow, .mint, .cyan, .brown]
        if let free = order.first(where: { !used.contains($0) }) { return free }
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return order[sum % order.count]
    }
}

// MARK: - 時間割に入れた授業

struct Course: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var teacher: String
    var room: String
    /// nil は時間外（集中講義・オンデマンドなど）
    var day: Weekday?
    var period: Int?
    /// 続けて何コマか
    var length: Int
    var term: Term
    var color: CourseColor
    var code: String
    var memo: String
    var absences: Int
    var lates: Int
    /// 取得した授業から入れたときの元の授業
    var sourceID: String?

    init(id: UUID = UUID(), name: String, teacher: String = "", room: String = "",
         day: Weekday?, period: Int?, length: Int = 1, term: Term = .full,
         color: CourseColor = .blue, code: String = "", memo: String = "",
         absences: Int = 0, lates: Int = 0, sourceID: String? = nil) {
        self.id = id
        self.name = name
        self.teacher = teacher
        self.room = room
        self.day = day
        self.period = period
        self.length = max(1, length)
        self.term = term
        self.color = color
        self.code = code
        self.memo = memo
        self.absences = absences
        self.lates = lates
        self.sourceID = sourceID
    }

    enum CodingKeys: String, CodingKey {
        case id, name, teacher, room, day, period, length, term, color, code, memo, absences, lates, sourceID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        teacher = try c.decodeIfPresent(String.self, forKey: .teacher) ?? ""
        room = try c.decodeIfPresent(String.self, forKey: .room) ?? ""
        day = try c.decodeIfPresent(Weekday.self, forKey: .day)
        period = try c.decodeIfPresent(Int.self, forKey: .period)
        length = max(1, try c.decodeIfPresent(Int.self, forKey: .length) ?? 1)
        term = try c.decodeIfPresent(Term.self, forKey: .term) ?? .full
        color = (try? c.decodeIfPresent(CourseColor.self, forKey: .color)) ?? .blue
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""
        absences = try c.decodeIfPresent(Int.self, forKey: .absences) ?? 0
        lates = try c.decodeIfPresent(Int.self, forKey: .lates) ?? 0
        sourceID = try c.decodeIfPresent(String.self, forKey: .sourceID)
    }

    var lastPeriod: Int? { period.map { $0 + length - 1 } }

    var isScheduled: Bool { day != nil && period != nil }

    func covers(day d: Weekday, period p: Int) -> Bool {
        guard day == d, let start = period else { return false }
        return (start...(start + length - 1)).contains(p)
    }

    /// 「月曜 3限」「月曜 4・5限」
    var slotText: String {
        guard let day, let period else { return "時間外" }
        if length > 1 { return "\(day.medium) \(period)〜\(period + length - 1)限" }
        return "\(day.medium) \(period)限"
    }
}

// MARK: - 取得した授業（エドポタ・シラバスから読み取った候補）

struct Slot: Codable, Hashable, Comparable {
    var day: Weekday
    var period: Int

    static func < (a: Slot, b: Slot) -> Bool {
        a.day == b.day ? a.period < b.period : a.day < b.day
    }

    var text: String { "\(day.short)\(period)" }
}

struct CatalogCourse: Codable, Identifiable, Hashable {
    /// 授業名と教員から作るキー
    var id: String
    var name: String
    var teacher: String
    var room: String
    var code: String
    var slots: [Slot]
    var term: Term?
    var source: String

    init(name: String, teacher: String = "", room: String = "", code: String = "",
         slots: [Slot] = [], term: Term? = nil, source: String = "") {
        self.name = name
        self.teacher = teacher
        self.room = room
        self.code = code
        self.slots = Array(Set(slots)).sorted()
        self.term = term
        self.source = source
        self.id = CatalogCourse.key(name: name, teacher: teacher, term: term)
    }

    static func key(name: String, teacher: String, term: Term?) -> String {
        let n = TimetableParser.fold(name)
        let t = TimetableParser.fold(teacher)
        return "\(n)|\(t)|\(term?.rawValue ?? "")"
    }

    /// 「月3・木3」
    var slotText: String {
        guard !slots.isEmpty else { return "時間外" }
        let byDay = Dictionary(grouping: slots, by: \.day)
        return byDay.keys.sorted().map { day -> String in
            let ps = byDay[day]!.map(\.period).sorted()
            if ps.count > 1, ps.last! - ps.first! == ps.count - 1 {
                return "\(day.short)\(ps.first!)〜\(ps.last!)"
            }
            return ps.map { "\(day.short)\($0)" }.joined(separator: "・")
        }.joined(separator: "・")
    }

    func has(day: Weekday, period: Int) -> Bool {
        slots.contains(Slot(day: day, period: period))
    }

    /// 曜日ごとに続いた時限をまとめて、時間割の授業にする
    func makeCourses(term fallback: Term, color: CourseColor) -> [Course] {
        let term = self.term ?? fallback
        guard !slots.isEmpty else {
            return [Course(name: name, teacher: teacher, room: room, day: nil, period: nil,
                           term: term, color: color, code: code, sourceID: id)]
        }
        var result: [Course] = []
        let byDay = Dictionary(grouping: slots, by: \.day)
        for day in byDay.keys.sorted() {
            let periods = Array(Set(byDay[day]!.map(\.period))).sorted()
            var runStart = periods[0], prev = periods[0]
            func flush() {
                result.append(Course(name: name, teacher: teacher, room: room, day: day, period: runStart,
                                     length: prev - runStart + 1, term: term, color: color, code: code, sourceID: id))
            }
            for p in periods.dropFirst() {
                if p == prev + 1 { prev = p } else { flush(); runStart = p; prev = p }
            }
            flush()
        }
        return result
    }

    /// 同じ授業の情報をまとめる
    mutating func merge(_ other: CatalogCourse) {
        slots = Array(Set(slots + other.slots)).sorted()
        if room.isEmpty { room = other.room }
        if code.isEmpty { code = other.code }
        if teacher.isEmpty { teacher = other.teacher }
    }
}

// MARK: - 保存するデータ

struct AppData: Codable, Equatable {
    var courses: [Course] = []
    var catalog: [CatalogCourse] = []
    var catalogUpdated: Date?
    var periods: [PeriodTime] = PeriodTime.edogawa
    var periodCount: Int = 5
    var showSaturday: Bool = false
    var termMode: TermMode = .auto

    init() {}

    enum CodingKeys: String, CodingKey {
        case courses, catalog, catalogUpdated, periods, periodCount, showSaturday, termMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        courses = try c.decodeIfPresent([Course].self, forKey: .courses) ?? []
        catalog = (try? c.decodeIfPresent([CatalogCourse].self, forKey: .catalog)) ?? []
        catalogUpdated = try c.decodeIfPresent(Date.self, forKey: .catalogUpdated)
        let stored = try c.decodeIfPresent([PeriodTime].self, forKey: .periods) ?? []
        periods = PeriodTime.edogawa.map { base in stored.first { $0.number == base.number } ?? base }
        periodCount = min(PeriodTime.maxCount, max(1, try c.decodeIfPresent(Int.self, forKey: .periodCount) ?? 5))
        showSaturday = try c.decodeIfPresent(Bool.self, forKey: .showSaturday) ?? false
        termMode = try c.decodeIfPresent(TermMode.self, forKey: .termMode) ?? .auto
    }

    /// ウィジェットに渡す分
    var snapshot: WidgetSnapshot {
        WidgetSnapshot(courses: courses, periods: periods, periodCount: periodCount,
                       showSaturday: showSaturday, termMode: termMode, updated: Date())
    }
}

/// ウィジェット用（取得した授業の一覧は含めない）
struct WidgetSnapshot: Codable {
    var courses: [Course]
    var periods: [PeriodTime]
    var periodCount: Int
    var showSaturday: Bool
    var termMode: TermMode
    var updated: Date

    var schedule: Schedule {
        Schedule(courses: courses, periods: periods, periodCount: periodCount,
                 showSaturday: showSaturday, termMode: termMode)
    }
}
