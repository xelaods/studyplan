import Foundation

// 江戸大スクールバス × 電車（自宅の駅 ⇔ 流山おおたかの森）× 時間割 の乗り継ぎ
// Scriptable の乗継ウィジェットと同じ考え方をアプリとウィジェットで使えるようにしたもの

// MARK: - 設定

struct CommuteSettings: Codable, Equatable {
    /// 自宅の最寄り駅
    var home: String = "舞浜"
    /// バスに乗り換える駅
    var station: String = "流山おおたかの森"
    /// おおたかの森：ホーム → バス停（分）
    var transferGo: Int = 2
    /// おおたかの森：バス停 → ホーム（分）
    var transferBack: Int = 2
    /// 大学 ⇔ おおたかの森 のバス乗車時間（分）
    var busRide: Int = 6
    /// 大学のバス停 ⇔ 教室（分）
    var walk: Int = 5
    /// 自宅の駅 → おおたかの森 の最短所要（分）。これより先のバスだけ探す
    var minGoTravel: Int = 45

    init() {}

    enum CodingKeys: String, CodingKey {
        case home, station, transferGo, transferBack, busRide, walk, minGoTravel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CommuteSettings()
        home = try c.decodeIfPresent(String.self, forKey: .home) ?? d.home
        station = try c.decodeIfPresent(String.self, forKey: .station) ?? d.station
        transferGo = try c.decodeIfPresent(Int.self, forKey: .transferGo) ?? d.transferGo
        transferBack = try c.decodeIfPresent(Int.self, forKey: .transferBack) ?? d.transferBack
        busRide = try c.decodeIfPresent(Int.self, forKey: .busRide) ?? d.busRide
        walk = try c.decodeIfPresent(Int.self, forKey: .walk) ?? d.walk
        minGoTravel = try c.decodeIfPresent(Int.self, forKey: .minGoTravel) ?? d.minGoTravel
    }

    /// 「舞浜」→「舞浜発」のような短い表示
    var homeShort: String { home.count > 4 ? String(home.prefix(4)) : home }
}

// MARK: - キャッシュ（ファイル）

enum CommuteCache {
    static var dir: URL {
        let base = SharedStore.groupContainer?.appendingPathComponent("Library/Caches", isDirectory: true)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("commute", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(_ key: String) -> URL {
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return dir.appendingPathComponent(String(safe.prefix(180)))
    }

    /// maxAge 秒より新しければ返す（nil なら古くても返す）
    static func read(_ key: String, maxAge: TimeInterval?) -> Data? {
        let u = url(key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: u.path),
              let modified = attrs[.modificationDate] as? Date else { return nil }
        if let maxAge, Date().timeIntervalSince(modified) > maxAge { return nil }
        return try? Data(contentsOf: u)
    }

    static func write(_ key: String, _ data: Data) {
        try? data.write(to: url(key), options: .atomic)
    }

    /// 2日より古いものを消す
    static func clean() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for f in files {
            let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(d) > 2 * 86_400 { try? fm.removeItem(at: f) }
        }
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - スクールバス（大学のサイネージページ bus.html）

struct BusDay: Codable, Equatable {
    var date: Date
    var diaKey: String
    var dia: String
    /// おおたかの森発 → 大学（分）
    var toUniv: [Int]
    /// 大学発 → おおたかの森（分）
    var toStation: [Int]
    /// 時刻表データのない特別ダイヤ
    var unknown: Bool

    var running: Bool { diaKey != "ND" }
    var hasTimes: Bool { running && !unknown }

    func next(_ list: [Int], after minutes: Int, count: Int = 3) -> [Int] {
        Array(list.filter { $0 >= minutes }.prefix(count))
    }
}

enum BusError: LocalizedError {
    case unavailable
    var errorDescription: String? { "バス時刻表を取得できません" }
}

enum BusSource {
    static let url = URL(string: "https://www1.edogawa-u.ac.jp/~tyamaguc/DigSig/bus.html")!

    static let names: [String: String] = [
        "A": "Aダイヤ", "B": "Bダイヤ", "SC": "集中講義ダイヤ", "SS": "SSダイヤ", "fes1": "駒木祭ダイヤ",
        "AO": "総合型選抜ダイヤ", "suisen": "学校推薦型選抜ダイヤ", "Oct10": "10月10日特別ダイヤ",
        "OC": "OC特別ダイヤ", "ND": "バス運行なし",
    ]

    private static let cacheKey = "bus.html"

    /// ページを取得（12時間はキャッシュ。通信できないときは前回の内容）
    static func html(force: Bool = false) async throws -> String {
        if !force, let data = CommuteCache.read(cacheKey, maxAge: 12 * 3600), let s = decode(data) {
            return s
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let (data, _) = try? await URLSession.shared.data(for: req), let s = decode(data), s.contains("jkndaiR_A") {
            CommuteCache.write(cacheKey, data)
            return s
        }
        if let data = CommuteCache.read(cacheKey, maxAge: nil), let s = decode(data) { return s }
        throw BusError.unavailable
    }

    private static func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS)
    }

    static func day(_ date: Date, force: Bool = false) async throws -> BusDay {
        let page = try await html(force: force)
        return day(date, html: page)
    }

    static func day(_ date: Date, html: String) -> BusDay {
        let key = decideDia(html, date: date)
        let name = names[key] ?? key
        guard key != "ND" else {
            return BusDay(date: date, diaKey: key, dia: name, toUniv: [], toStation: [], unknown: false)
        }
        let r = grabArray(html, name: key == "A" || key == "B" ? "jkndaiR_\(key)" : "jkndai_\(key)")
        let s = grabArray(html, name: "jkndaiS_\(key)")
        guard let r, let s, let header = s.first else {
            return BusDay(date: date, diaKey: key, dia: name, toUniv: [], toStation: [], unknown: true)
        }
        return BusDay(date: date, diaKey: key, dia: name,
                      toUniv: flatten(s, hourCol: header.count - 1),
                      toStation: flatten(r, hourCol: 0), unknown: false)
    }

    // "const 名前 = [ ... ];" の配列を取り出す（中身は数値と "" だけなのでJSONとして読める）
    static func grabArray(_ html: String, name: String) -> [[Any]]? {
        let pattern = "const\\s+\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*(\\[[\\s\\S]*?\\]\\s*\\]);"
        guard let m = firstMatch(pattern, in: html), let data = m.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return nil }
        return arr
    }

    private static func firstMatch(_ pattern: String, in s: String, group: Int = 1) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group, m.range(at: group).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: group))
    }

    private static func json(_ pattern: String, in s: String) -> Any? {
        guard let text = firstMatch(pattern, in: s), let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func ints(_ any: Any?) -> [Int] {
        (any as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
    }

    /// ページ内の「自動でその日のダイヤが選ばれる」処理と同じ判定
    static func decideDia(_ html: String, date: Date) -> String {
        let y = JST.year(date), mo = JST.month(date), d = JST.day(date)
        let wd = JST.calendar.component(.weekday, from: date) - 1 // 0=日
        let g = mo * 100 + d
        let rekiYear = (json("let\\s+reki_year\\s*=\\s*(\\d+)", in: html) as? NSNumber)?.intValue
        let st = ints(json("let\\s+reki_st\\s*=\\s*(\\[[^\\]]*\\])", in: html))
        let fin = ints(json("let\\s+reki_fin\\s*=\\s*(\\[[^\\]]*\\])", in: html))
        let jogai = ints(json("let\\s+reki_jogai\\s*=\\s*(\\[[^\\]]*\\])", in: html))
        let toku = json("toku\\[\(mo)\\]\\s*=\\s*(\\{[^\\n]*?\\})\\s*;", in: html) as? [String: Any] ?? [:]

        var dia = "ND"
        let acadYear = mo <= 3 ? y - 1 : y
        let weekday = wd >= 1 && wd <= 5
        if rekiYear != acadYear {
            // 学年暦が未更新の年は、平日だけAダイヤとみなす
            dia = weekday ? "A" : "ND"
        } else {
            var inTerm = false
            for i in 0..<min(3, min(st.count, fin.count)) where g >= st[i] && g <= fin[i] { inTerm = true }
            if inTerm && weekday && !jogai.contains(g) { dia = "A" }
        }
        for key in toku.keys.sorted() {
            if ints(toku[key]).contains(d) { dia = key }
        }
        return dia
    }

    /// hourCol: 0 = 先頭列が「時」（大学発）, 末尾 = 末尾列が「時」（おおたかの森発）
    static func flatten(_ table: [[Any]], hourCol: Int) -> [Int] {
        var out: [Int] = []
        for row in table.dropFirst() {
            guard hourCol < row.count, let h = (row[hourCol] as? NSNumber)?.intValue else { continue }
            for (j, v) in row.enumerated() where j != hourCol {
                if let n = v as? NSNumber, !(v is String) { out.append(h * 60 + n.intValue) }
            }
        }
        return out.sorted()
    }
}

// MARK: - 電車（Yahoo!乗換案内）

struct TrainRoute: Codable, Hashable {
    var dep: Int
    var arr: Int
    var transfers: Int?
}

enum Transit {
    /// arrive: true = 到着時刻指定（その時刻までに着く一番遅い電車）, false = 出発時刻指定（一番早く着く電車）
    static func search(from: String, to: String, date: Date, minutes: Int, arrive: Bool) async -> TrainRoute? {
        let type = arrive ? 4 : 1
        let key = "t_\(JST.format(date, "yyyyMMdd"))_\(type)_\(minutes)_\(from)_\(to)"
        if let data = CommuteCache.read(key, maxAge: 6 * 3600),
           let cached = try? JSONDecoder().decode(TrainRoute.self, from: data) {
            return cached
        }
        let mm = minutes % 60
        var comps = URLComponents(string: "https://transit.yahoo.co.jp/search/result")!
        comps.queryItems = [
            .init(name: "from", value: from), .init(name: "to", value: to),
            .init(name: "y", value: JST.format(date, "yyyy")), .init(name: "m", value: JST.format(date, "MM")),
            .init(name: "d", value: JST.format(date, "dd")),
            .init(name: "hh", value: String(format: "%02d", minutes / 60)),
            .init(name: "m1", value: String(mm / 10)), .init(name: "m2", value: String(mm % 10)),
            .init(name: "type", value: String(type)), .init(name: "ticket", value: "ic"), .init(name: "s", value: "0"),
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) else { return nil }
        let routes = parseRoutes(html)
        guard !routes.isEmpty else { return nil }
        let best: TrainRoute?
        if arrive {
            let ok = routes.filter { $0.arr <= minutes }
            best = (ok.isEmpty ? routes : ok).max { $0.dep < $1.dep }
        } else {
            let ok = routes.filter { $0.dep >= minutes }
            best = (ok.isEmpty ? routes : ok).min { a, b in a.arr != b.arr ? a.arr < b.arr : a.dep > b.dep }
        }
        if let best, let data = try? JSONEncoder().encode(best) { CommuteCache.write(key, data) }
        return best
    }

    private static let blockRegex = try! NSRegularExpression(pattern: "id=[\"']route0?\\d+[\"']")
    private static let tagRegex = try! NSRegularExpression(pattern: "<[^>]+>")
    private static let spaceRegex = try! NSRegularExpression(pattern: "\\s+")
    private static let timeRegex1 = try! NSRegularExpression(pattern: "(\\d{1,2}):(\\d{2})\\s*発\\s*→\\s*(\\d{1,2}):(\\d{2})\\s*着")
    private static let timeRegex2 = try! NSRegularExpression(pattern: "(\\d{1,2}):(\\d{2})\\s*→\\s*(\\d{1,2}):(\\d{2})")
    private static let transferRegex = try! NSRegularExpression(pattern: "乗換[：:\\s]*(\\d+)\\s*回")

    static func parseRoutes(_ html: String) -> [TrainRoute] {
        let ns = html as NSString
        let marks = blockRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var blocks: [String] = []
        if marks.isEmpty {
            blocks = [html]
        } else {
            for (i, m) in marks.enumerated() {
                let start = m.range.location + m.range.length
                let end = i + 1 < marks.count ? marks[i + 1].range.location : ns.length
                blocks.append(ns.substring(with: NSRange(location: start, length: max(0, end - start))))
            }
        }
        var routes: [TrainRoute] = []
        var seen = Set<String>()
        for b in blocks {
            var text = replace(tagRegex, in: b, with: " ")
            text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            text = replace(spaceRegex, in: text, with: " ")
            let tn = text as NSString
            let range = NSRange(location: 0, length: tn.length)
            guard let m = timeRegex1.firstMatch(in: text, range: range) ?? timeRegex2.firstMatch(in: text, range: range) else { continue }
            func int(_ i: Int) -> Int { Int(tn.substring(with: m.range(at: i))) ?? 0 }
            let dep = int(1) * 60 + int(2), arr = int(3) * 60 + int(4)
            var transfers: Int?
            if let t = transferRegex.firstMatch(in: text, range: range) { transfers = Int(tn.substring(with: t.range(at: 1))) }
            let k = "\(dep)-\(arr)"
            if seen.insert(k).inserted { routes.append(TrainRoute(dep: dep, arr: arr, transfers: transfers)) }
        }
        return routes
    }

    private static func replace(_ re: NSRegularExpression, in s: String, with t: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: t)
    }
}

// MARK: - 乗り継ぎの組み立て

enum CommuteDirection: String, Codable {
    case go, back
}

enum CommuteMode: String, Codable, CaseIterable, Identifiable {
    case auto, go, back
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "自動"
        case .go: return "通学"
        case .back: return "帰宅"
        }
    }
}

struct CommuteRow: Codable, Hashable, Identifiable {
    var bus: Int
    var train: TrainRoute?
    var late = false
    var lateBy = 0
    /// 授業に間に合う一番遅い便（ギリ）
    var isLast = false

    var id: String { "\(bus)-\(train?.dep ?? -1)-\(train?.arr ?? -1)" }
}

struct CommuteSection: Codable, Identifiable {
    var direction: CommuteDirection
    var title: String
    var subtitle: String
    var date: Date
    var isToday: Bool
    var rows: [CommuteRow]

    var id: String { "\(direction.rawValue)-\(title)" }
}

struct CommutePlan: Codable {
    var title: String
    var dia: String
    var sections: [CommuteSection]
    var message: String?
    var generated: Date
    var bus: BusDay?
}

enum CommutePlanner {
    static let around = 2

    struct DayClasses {
        let first: ClassItem
        let last: ClassItem
        var firstStart: Int { JST.minutes(first.start) }
        var lastEnd: Int { JST.minutes(last.end) }
    }

    static func classes(_ schedule: Schedule, on date: Date) -> DayClasses? {
        let items = schedule.items(on: date).sorted { $0.start < $1.start }
        guard let f = items.first, let l = items.max(by: { $0.end < $1.end }) else { return nil }
        return DayClasses(first: f, last: l)
    }

    static func classLine(_ c: DayClasses) -> String {
        "\(c.first.periodText) \(JST.hm(c.first.start)) \(c.first.course.name)"
    }

    /// 通学：電車1本ごとに「降りてから最初に乗れるバス」を1行にする。授業にぴったり間に合う行（ギリ）と、その前後
    static func buildGo(date: Date, bus: BusDay, classes: DayClasses, now: Int, limit: Int, s: CommuteSettings) async -> [CommuteRow] {
        let deadline = classes.firstStart - s.walk - s.busRide
        let all = bus.toUniv
        guard !all.isEmpty else { return [] }
        var idx = -1
        for (i, b) in all.enumerated() where b <= deadline { idx = i }
        if idx < 0 { idx = 0 }
        let span = all[max(0, idx - 7)..<min(all.count, idx + 12)].filter { $0 >= now + s.minGoTravel - 10 }

        let found: [(Int, TrainRoute?)] = await withTaskGroup(of: (Int, TrainRoute?).self) { group in
            for b in span {
                group.addTask {
                    (b, await Transit.search(from: s.home, to: s.station, date: date, minutes: b - s.transferGo, arrive: true))
                }
            }
            var out: [(Int, TrainRoute?)] = []
            for await r in group { out.append(r) }
            return out
        }

        // 同じ電車なら一番早いバスだけ残す
        var byTrain: [String: (Int, TrainRoute)] = [:]
        for (b, train) in found {
            guard let train, train.dep >= now else { continue }
            let k = "\(train.dep)-\(train.arr)"
            if let cur = byTrain[k], cur.0 <= b { continue }
            byTrain[k] = (b, train)
        }
        var list: [CommuteRow] = byTrain.values.sorted { $0.0 < $1.0 }.map { pair in
            CommuteRow(bus: pair.0, train: pair.1, late: pair.0 > deadline, lateBy: pair.0 - deadline)
        }
        guard !list.isEmpty else { return [] }
        let g = list.lastIndex { !$0.late } ?? -1
        if g >= 0 { list[g].isLast = true }
        let n = min(limit, around * 2 + 1)
        let before = min(around, (n - 1) / 2)
        let start = max(0, min(g - before, list.count - n))
        return Array(list[start..<min(list.count, start + n)])
    }

    /// 帰宅：最後の授業が終わってから乗れるバス以降。同じ電車になるバスは一番遅いものだけ
    static func buildBack(date: Date, bus: BusDay, classes: DayClasses?, now: Int, limit: Int, s: CommuteSettings) async -> [CommuteRow] {
        let earliest = max(now, classes.map { $0.lastEnd + s.walk } ?? now)
        let buses = Array(bus.toStation.filter { $0 >= earliest }.prefix(limit * 2 + 2))
        let found: [(Int, TrainRoute?)] = await withTaskGroup(of: (Int, TrainRoute?).self) { group in
            for b in buses {
                group.addTask {
                    (b, await Transit.search(from: s.station, to: s.home, date: date, minutes: b + s.busRide + s.transferBack, arrive: false))
                }
            }
            var out: [(Int, TrainRoute?)] = []
            for await r in group { out.append(r) }
            return out
        }
        var byTrain: [String: (Int, TrainRoute?)] = [:]
        for (b, train) in found {
            let k = train.map { "\($0.dep)-\($0.arr)" } ?? "x\(b)"
            if let cur = byTrain[k], cur.0 >= b { continue }
            byTrain[k] = (b, train)
        }
        return Array(byTrain.values.sorted { $0.0 < $1.0 }.prefix(limit).map { CommuteRow(bus: $0.0, train: $0.1) })
    }

    static func dayText(_ d: Date) -> String {
        "\(JST.month(d))/\(JST.day(d))(\(["日", "月", "火", "水", "木", "金", "土"][JST.calendar.component(.weekday, from: d) - 1]))"
    }

    /// 次に授業があってバスも走る日の通学表
    static func nextClassDay(schedule: Schedule, from date: Date, limit: Int, s: CommuteSettings, html: String) async -> CommuteSection? {
        let today = JST.startOfDay(date)
        for i in 1...10 {
            let d = JST.date(JST.adding(days: i, to: today), minutes: 12 * 60)
            guard let info = classes(schedule, on: d) else { continue }
            let bus = BusSource.day(d, html: html)
            guard bus.hasTimes, !bus.toUniv.isEmpty else { continue }
            let rows = await buildGo(date: d, bus: bus, classes: info, now: -9999, limit: limit, s: s)
            let label = i == 1 ? "明日" : dayText(d)
            return CommuteSection(direction: .go, title: "\(label) \(classLine(info))", subtitle: i == 1 ? dayText(d) : "",
                                  date: d, isToday: false, rows: rows)
        }
        return nil
    }

    /// rows: 全体の行数（大サイズのウィジェットを埋める数）
    static func plan(schedule: Schedule, settings s: CommuteSettings, now date: Date, mode: CommuteMode = .auto,
                     rows: Int = 7, force: Bool = false) async -> CommutePlan {
        CommuteCache.clean()
        let now = JST.minutes(date)
        var title = "通学"
        let html: String
        do {
            html = try await BusSource.html(force: force)
        } catch {
            return CommutePlan(title: title, dia: "", sections: [], message: "バス時刻表を取得できません", generated: Date(), bus: nil)
        }
        let bus = BusSource.day(date, html: html)
        let info = classes(schedule, on: date)
        var sections: [CommuteSection] = []

        // 今日の通学：1限目の開始前なら
        if bus.hasTimes, let info, mode != .back, now < info.firstStart {
            let r = await buildGo(date: date, bus: bus, classes: info, now: now, limit: rows - 1, s: s)
            if !r.isEmpty {
                sections.append(CommuteSection(direction: .go, title: "今日 \(classLine(info))", subtitle: "", date: date, isToday: true, rows: r))
                title = "通学"
            }
        }
        // 今日の帰宅：授業がある日の帰り（帰宅を選んだときは授業がなくても）
        if sections.isEmpty, bus.hasTimes, mode != .go, info != nil || mode == .back {
            let r = await buildBack(date: date, bus: bus, classes: info, now: now, limit: rows - 1, s: s)
            if !r.isEmpty {
                let sec = info.map { "\($0.last.periodText) \($0.last.course.name) \(JST.hm($0.last.end))終了" } ?? "大学発"
                sections.append(CommuteSection(direction: .back, title: sec, subtitle: "", date: date, isToday: true, rows: r))
                title = "帰宅"
            }
        }
        // 残りの行は、次に授業がある日の通学表で埋める
        let shown = sections.reduce(0) { $0 + $1.rows.count }
        let rest = rows - shown - (shown > 0 ? 1 : 0)
        if rest > 1 {
            if shown == 0 { title = "次の通学" }
            if let next = await nextClassDay(schedule: schedule, from: date, limit: shown == 0 ? rest : rest - 1, s: s, html: html) {
                sections.append(next)
            }
        }
        let dia = bus.running ? bus.dia : "運休"
        return CommutePlan(title: title, dia: dia, sections: sections,
                           message: sections.isEmpty ? "表示できる便がありません" : nil, generated: Date(), bus: bus)
    }
}

// MARK: - 表示用のラベル

enum CommuteLabel {
    static func left(_ minutes: Int?) -> String {
        guard let m = minutes else { return "検索失敗" }
        if m <= 0 { return "今すぐ" }
        if m >= 60 { return "\(m / 60)時間\(m % 60)分" }
        return "あと\(m)分"
    }

    /// 行のラベルと、注意の色にするか
    static func label(_ row: CommuteRow, index: Int, section: CommuteSection, now: Int) -> (text: String, warn: Bool) {
        switch section.direction {
        case .go:
            let left = row.train.map { $0.dep - now }
            if row.late { return ("\(row.lateBy)分遅刻", true) }
            if section.isToday {
                let warn = (left ?? 99) <= 10
                return (self.left(left) + (row.isLast ? " ギリ" : ""), warn)
            }
            if row.isLast { return ("ギリ", true) }
            return ("", false)
        case .back:
            let left = row.bus - now
            if left > 90 { return ("授業後" + (index == 0 ? "最初" : ""), false) }
            return (self.left(left), left <= 10)
        }
    }

    /// 強調する行
    static func highlight(_ section: CommuteSection, now: Int) -> Int? {
        switch section.direction {
        case .back:
            return section.rows.isEmpty ? nil : 0
        case .go:
            if !section.isToday { return section.rows.firstIndex { $0.isLast } }
            let allLate = section.rows.allSatisfy(\.late)
            return section.rows.firstIndex { r in
                guard let t = r.train else { return false }
                return t.dep - now >= 0 && (!r.late || allLate)
            }
        }
    }

    /// 今日の行のうち、もう乗れないものを外す
    static func visibleRows(_ section: CommuteSection, now: Int) -> [CommuteRow] {
        guard section.isToday else { return section.rows }
        switch section.direction {
        case .go: return section.rows.filter { ($0.train?.dep ?? Int.max) >= now }
        case .back: return section.rows.filter { $0.bus >= now }
        }
    }
}
