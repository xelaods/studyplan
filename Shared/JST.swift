import Foundation

/// 日本時間での日付計算
enum JST {
    static let timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
    static let locale = Locale(identifier: "ja_JP")

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = locale
        return c
    }()

    static func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    /// その日の 0:00 からの分
    static func minutes(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// その日の 0:00 から minutes 分後
    static func date(_ day: Date, minutes: Int) -> Date {
        startOfDay(day).addingTimeInterval(TimeInterval(minutes * 60))
    }

    static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(TimeInterval(days * 86_400))
    }

    static func weekday(_ date: Date) -> Weekday? {
        Weekday(calendarWeekday: calendar.component(.weekday, from: date))
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }

    static func month(_ date: Date) -> Int { calendar.component(.month, from: date) }
    static func year(_ date: Date) -> Int { calendar.component(.year, from: date) }
    static func day(_ date: Date) -> Int { calendar.component(.day, from: date) }

    private static var formatters: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    static func format(_ date: Date, _ pattern: String) -> String {
        lock.lock(); defer { lock.unlock() }
        let f: DateFormatter
        if let cached = formatters[pattern] {
            f = cached
        } else {
            f = DateFormatter()
            f.calendar = calendar
            f.timeZone = timeZone
            f.locale = locale
            f.dateFormat = pattern
            formatters[pattern] = f
        }
        return f.string(from: date)
    }

    /// 9:00 のような表記
    static func hm(_ minutes: Int) -> String {
        "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    static func hm(_ date: Date) -> String { hm(Self.minutes(date)) }
}

/// いまの時刻。スクリーンショット用に起動引数 `-now 2026-10-14T10:20` で固定できる
enum Clock {
    static let fixed: Date? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-now"), i + 1 < args.count else { return nil }
        let f = DateFormatter()
        f.calendar = JST.calendar
        f.timeZone = JST.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.date(from: args[i + 1])
    }()

    static var now: Date { fixed ?? Date() }
}

/// 「あと23分」「あと1時間5分」
enum Remaining {
    static func text(from now: Date, to target: Date) -> String {
        let m = max(0, Int((target.timeIntervalSince(now) / 60).rounded(.up)))
        if m < 60 { return "\(m)分" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h)時間" : "\(h)時間\(r)分"
    }
}
