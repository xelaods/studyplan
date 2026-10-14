import Foundation

/// ある日の1回分の授業
struct ClassItem: Identifiable, Hashable {
    let course: Course
    let start: Date
    let end: Date

    var id: String { course.id.uuidString + "@" + String(Int(start.timeIntervalSince1970)) }

    func isNow(_ now: Date) -> Bool { start <= now && now < end }
    func isPast(_ now: Date) -> Bool { end <= now }

    func progress(_ now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    /// 「3限」「4・5限」
    var periodText: String {
        guard let p = course.period else { return "" }
        return course.length > 1 ? "\(p)〜\(p + course.length - 1)限" : "\(p)限"
    }

    var timeText: String { "\(JST.hm(start))〜\(JST.hm(end))" }
}

/// 時間割の計算（アプリとウィジェットで共通）
struct Schedule {
    var courses: [Course]
    var periods: [PeriodTime]
    var periodCount: Int
    var showSaturday: Bool
    var termMode: TermMode

    init(courses: [Course], periods: [PeriodTime], periodCount: Int, showSaturday: Bool, termMode: TermMode) {
        self.courses = courses
        self.periods = periods
        self.periodCount = periodCount
        self.showSaturday = showSaturday
        self.termMode = termMode
    }

    init(_ data: AppData) {
        self.init(courses: data.courses, periods: data.periods, periodCount: data.periodCount,
                  showSaturday: data.showSaturday, termMode: data.termMode)
    }

    func term(on date: Date) -> Term { termMode.resolve(on: date) }

    func period(_ n: Int) -> PeriodTime? {
        periods.first { $0.number == n } ?? PeriodTime.edogawa.first { $0.number == n }
    }

    /// その学期に表示する授業
    func courses(term: Term) -> [Course] {
        courses.filter { $0.term.applies(to: term) }
    }

    func courses(on day: Weekday, term: Term) -> [Course] {
        courses.filter { $0.day == day && $0.period != nil && $0.term.applies(to: term) }
            .sorted { ($0.period ?? 0) < ($1.period ?? 0) }
    }

    /// その時間に入っている授業（続きのコマも含む）
    func course(day: Weekday, period: Int, term: Term) -> Course? {
        courses.first { $0.covers(day: day, period: period) && $0.term.applies(to: term) }
    }

    func items(on date: Date) -> [ClassItem] {
        guard let wd = JST.weekday(date) else { return [] }
        return courses(on: wd, term: term(on: date)).compactMap { c in
            guard let p = c.period, let s = period(p) else { return nil }
            let e = period(p + c.length - 1) ?? s
            return ClassItem(course: c, start: JST.date(date, minutes: s.start), end: JST.date(date, minutes: e.end))
        }
    }

    func current(at now: Date) -> ClassItem? {
        items(on: now).first { $0.isNow(now) }
    }

    /// これから始まる授業（今日から順に）
    func upcoming(after now: Date, limit: Int = 1, days: Int = 14) -> [ClassItem] {
        var out: [ClassItem] = []
        let today = JST.startOfDay(now)
        for i in 0..<days {
            let d = JST.adding(days: i, to: today)
            for item in items(on: d) where item.start > now {
                out.append(item)
                if out.count >= limit { return out }
            }
        }
        return out
    }

    func next(after now: Date) -> ClassItem? { upcoming(after: now).first }

    /// 授業がある次の日（今日を除く）
    func nextClassDay(after now: Date, days: Int = 14) -> (date: Date, items: [ClassItem])? {
        let today = JST.startOfDay(now)
        for i in 1...days {
            let d = JST.adding(days: i, to: today)
            let list = items(on: d)
            if !list.isEmpty { return (d, list) }
        }
        return nil
    }

    /// 表示する曜日
    var days: [Weekday] {
        showSaturday || courses.contains { $0.day == .sat } ? Weekday.allCases : Weekday.weekdays
    }

    /// 表示する時限の数（設定より後ろに授業があれば広げる）
    var rows: Int {
        let last = courses.compactMap(\.lastPeriod).max() ?? 0
        return min(PeriodTime.maxCount, max(periodCount, last))
    }

    /// ウィジェットの表示が変わる時刻（授業の始まり・終わり・日付の変わり目）
    func boundaries(from now: Date, hours: Double = 24) -> [Date] {
        let limit = now.addingTimeInterval(hours * 3600)
        var set = Set<Date>()
        let today = JST.startOfDay(now)
        for i in 0...2 {
            let d = JST.adding(days: i, to: today)
            for item in items(on: d) {
                set.insert(item.start)
                set.insert(item.end)
            }
            set.insert(d)
        }
        return set.filter { $0 > now && $0 <= limit }.sorted()
    }

    var isEmpty: Bool { courses.isEmpty }
}
