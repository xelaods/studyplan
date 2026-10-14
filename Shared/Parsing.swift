import Foundation

/// エドポタ（時間割表・シラバス検索結果）の画面から授業を読み取る
enum TimetableParser {

    // MARK: 文字の正規化

    /// 全角英数字を半角に、空白をまとめる
    static func normalize(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0xFF01...0xFF5E:
                out.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFEE0)!)
            case 0x3000, 0x00A0:
                out.append(" ")
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        // 漢数字の時限（「三限」）
        let kanji: [(String, String)] = [("一", "1"), ("二", "2"), ("三", "3"), ("四", "4"), ("五", "5"), ("六", "6"), ("七", "7")]
        for (k, d) in kanji {
            out = out.replacingOccurrences(of: k + "時限", with: d + "時限")
            out = out.replacingOccurrences(of: k + "限", with: d + "限")
        }
        let lines = out.components(separatedBy: .newlines).map { line -> String in
            line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 比較用（空白・記号を除き、ローマ数字を揃える）
    static func fold(_ s: String) -> String {
        var t = normalize(s).lowercased()
        let roman: [(String, String)] = [("Ⅰ", "i"), ("Ⅱ", "ii"), ("Ⅲ", "iii"), ("Ⅳ", "iv"), ("Ⅴ", "v"), ("ⅰ", "i"), ("ⅱ", "ii"), ("ⅲ", "iii")]
        for (r, a) in roman { t = t.replacingOccurrences(of: r, with: a) }
        let drop = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
        return String(t.unicodeScalars.filter { !drop.contains($0) })
    }

    // MARK: 曜日・時限

    private static let slotRegex = try! NSRegularExpression(
        pattern: "(?<!\\d)([月火水木金土])(?:曜日?)?\\s*[・･/／:：\\-]?\\s*(\\d)(?!\\d)\\s*(?:時限|限)?(?:\\s*[-~〜～・･,、]\\s*(\\d)(?!\\d)\\s*(?:時限|限)?)?",
        options: [])

    /// 「月3」「月曜3限」「月曜日 3時限」「月3・4」「月3-4」「月3,木3」などを読む
    static func parseSlots(_ raw: String) -> [Slot] {
        let s = normalize(raw)
        let ns = s as NSString
        var result: [Slot] = []
        for m in slotRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard let day = Weekday(symbol: ns.substring(with: m.range(at: 1))),
                  let p1 = Int(ns.substring(with: m.range(at: 2))), (1...PeriodTime.maxCount).contains(p1) else { continue }
            var last = p1
            if m.range(at: 3).location != NSNotFound, let p2 = Int(ns.substring(with: m.range(at: 3))),
               p2 > p1, p2 <= PeriodTime.maxCount {
                last = p2
            }
            for p in p1...last { result.append(Slot(day: day, period: p)) }
        }
        return Array(Set(result)).sorted()
    }

    /// 曜日と時限が別の列のとき
    static func parseSlots(day: String, period: String) -> [Slot] {
        let d = normalize(day), p = normalize(period)
        if let wd = Weekday(symbol: d) {
            let nums = numbers(in: p).filter { (1...PeriodTime.maxCount).contains($0) }
            if nums.count == 2, nums[1] > nums[0], p.contains("-") || p.contains("〜") || p.contains("~") {
                return (nums[0]...nums[1]).map { Slot(day: wd, period: $0) }
            }
            return nums.map { Slot(day: wd, period: $0) }
        }
        return parseSlots(d + " " + p)
    }

    static func numbers(in s: String) -> [Int] {
        var out: [Int] = []
        var cur = ""
        for ch in s {
            if ch.isASCII, ch.isNumber { cur.append(ch) } else if !cur.isEmpty { out.append(Int(cur)!); cur = "" }
        }
        if !cur.isEmpty { out.append(Int(cur)!) }
        return out
    }

    static func parseTerm(_ raw: String) -> Term? {
        let s = normalize(raw)
        if s.contains("通年") { return .full }
        if s.contains("前期") || s.contains("春") || s.contains("前学期") || s.contains("第1学期") || s.contains("1学期") { return .first }
        if s.contains("後期") || s.contains("秋") || s.contains("後学期") || s.contains("第2学期") || s.contains("2学期") { return .second }
        return nil
    }

    // MARK: 授業のマス（「科目名\n教員\n教室」など）

    struct CellInfo: Equatable {
        var name: String
        var teacher: String
        var room: String
        var code: String
        var term: Term?
    }

    private static let roomRegex = try! NSRegularExpression(
        pattern: "(教室|号館|ホール|ラボ|演習室|実習室|講義室|情報処理室|体育館|グラウンド|スタジオ|^[A-Za-z]{0,3}\\s?-?\\d{2,4}[A-Za-z]?$|^[A-Za-z]\\d?棟)",
        options: [.caseInsensitive])
    private static let codeRegex = try! NSRegularExpression(pattern: "^[A-Za-z]{0,4}[-_]?\\d{5,}[A-Za-z0-9-]*$", options: [])
    private static let timeRegex = try! NSRegularExpression(pattern: "\\d{1,2}:\\d{2}", options: [])

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    static func isRoom(_ s: String) -> Bool { matches(roomRegex, s) || matches(roomCodeRegex, s) }

    /// 「E302」「B-702」のような教室番号で始まる行（後ろに「AVラック」「PC」などの設備が付く）
    private static let roomCodeRegex = try! NSRegularExpression(pattern: "^[A-Za-z]{1,3}-?\\d{2,4}[A-Za-z]?(\\s|$)", options: [])

    /// 「E302 AVラック」→「E302」
    static func cleanRoom(_ s: String) -> String {
        let first = s.split(separator: " ").first.map(String.init) ?? s
        if matches(roomCodeRegex, first) { return first }
        return s
    }

    static func splitCell(_ raw: String) -> CellInfo? {
        let lines = normalize(raw).components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var term: Term?
        var code = ""
        var rest: [String] = []
        for line in lines {
            if let t = parseTerm(line), line.count <= 6 { term = t; continue }
            if matches(codeRegex, line) { if code.isEmpty { code = line }; continue }
            if matches(timeRegex, line) && line.count <= 13 { continue }
            if line.count <= 4 && (line.hasSuffix("単位") || line == "-" || line == "－" || line == "―") { continue }
            if ["受講", "履修", "登録済", "抽選", "確定", "複数学期", "エラー", "休講", "補講"].contains(where: { line == $0 }) { continue }
            rest.append(line)
        }
        guard !rest.isEmpty else { return nil }
        // 括弧の中の教室・教員（「統計学概論（A201）」）
        var name = stripBrackets(rest.removeFirst())
        var room = "", teacher = ""
        if let i = rest.firstIndex(where: isRoom) { room = cleanRoom(rest.remove(at: i)) }
        if let first = rest.first { teacher = stripTeacher(first) }
        // 1行に「科目名 教室」とあるとき
        if room.isEmpty, rest.isEmpty {
            let parts = name.split(separator: " ").map(String.init)
            if parts.count >= 2, isRoom(parts.last!) {
                room = parts.last!
                name = parts.dropLast().joined(separator: " ")
            }
        }
        guard name.count >= 2, !isHeaderWord(name) else { return nil }
        return CellInfo(name: name, teacher: teacher, room: room, code: code, term: term)
    }

    private static func stripBrackets(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "【】[]「」 "))
    }

    private static let parenRegex = try! NSRegularExpression(pattern: "\\s*[(（][^)）]*[)）]", options: [])

    /// 「松尾由美 (T-0504)」→「松尾由美」
    static func stripTeacher(_ s: String) -> String {
        var t = parenRegex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
        for prefix in ["担当:", "担当：", "教員:", "教員：", "担当教員:", "担当教員："] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count))
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func isHeaderWord(_ s: String) -> Bool {
        let words = ["科目名", "授業科目", "授業名", "曜日", "時限", "担当教員", "教室", "時間割", "講義名"]
        return words.contains(s)
    }

    // MARK: 表

    /// 週の時間割（曜日が横、時限が縦）
    static func parseGrid(_ rows: [[String]], term: Term?, source: String) -> [CatalogCourse] {
        let table = rows.map { $0.map(normalize) }
        // 曜日の見出しの行（曜日の列は横向き、または縦向き）
        for (h, row) in table.enumerated() {
            var dayCols: [Int: Weekday] = [:]
            for (c, cell) in row.enumerated() where cell.count <= 4 {
                if let d = Weekday(symbol: cell), cell.first.map({ "月火水木金土MTWFSmtwfs".contains($0) }) == true {
                    if !dayCols.values.contains(d) { dayCols[c] = d }
                }
            }
            guard dayCols.count >= 4 else { continue }
            var found: [CatalogCourse] = []
            for r in (h + 1)..<table.count {
                let cells = table[r]
                // 時限の列（曜日の列以外で、最初の数字）
                guard let periodCell = cells.enumerated().first(where: { dayCols[$0.offset] == nil && !$0.element.isEmpty })?.element,
                      let period = periodNumber(periodCell) else { continue }
                for (c, day) in dayCols where c < cells.count {
                    let text = cells[c]
                    guard !text.isEmpty, let info = splitCell(text) else { continue }
                    found.append(CatalogCourse(name: info.name, teacher: info.teacher, room: info.room, code: info.code,
                                               slots: [Slot(day: day, period: period)], term: info.term ?? term, source: source))
                }
            }
            if !found.isEmpty { return merged(found) }
        }
        // 曜日が縦に並ぶ表（1列目が曜日、見出しの行に時限）
        for (h, row) in table.enumerated() {
            var periodCols: [Int: Int] = [:]
            for (c, cell) in row.enumerated() where cell.count <= 8 {
                if let p = periodNumber(cell), !periodCols.values.contains(p) { periodCols[c] = p }
            }
            guard periodCols.count >= 4 else { continue }
            var found: [CatalogCourse] = []
            for r in (h + 1)..<table.count {
                let cells = table[r]
                guard let dayCell = cells.enumerated().first(where: { periodCols[$0.offset] == nil && !$0.element.isEmpty })?.element,
                      dayCell.count <= 4, let day = Weekday(symbol: dayCell) else { continue }
                for (c, period) in periodCols where c < cells.count {
                    guard !cells[c].isEmpty, let info = splitCell(cells[c]) else { continue }
                    found.append(CatalogCourse(name: info.name, teacher: info.teacher, room: info.room, code: info.code,
                                               slots: [Slot(day: day, period: period)], term: info.term ?? term, source: source))
                }
            }
            if !found.isEmpty { return merged(found) }
        }
        return []
    }

    /// 「1」「1限」「1時限」「1\n9:00〜10:40」
    static func periodNumber(_ cell: String) -> Int? {
        let s = normalize(cell)
        guard let first = s.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else { return nil }
        let compact = first.replacingOccurrences(of: " ", with: "")
        let allowed = ["", "限", "時限", "限目", "講時", "コマ"]
        for suffix in allowed where compact.hasSuffix(suffix) {
            let body = String(compact.dropLast(suffix.count))
            if let n = Int(body), (1...PeriodTime.maxCount).contains(n) { return n }
            if body.hasPrefix("第"), let n = Int(body.dropFirst()), (1...PeriodTime.maxCount).contains(n) { return n }
        }
        return nil
    }

    /// 一覧の表（シラバス検索結果・履修中の授業の一覧など）
    static func parseList(_ rows: [[String]], term: Term?, source: String) -> [CatalogCourse] {
        let table = rows.map { $0.map(normalize) }
        for (h, header) in table.enumerated() {
            let cols = header.map { $0.replacingOccurrences(of: " ", with: "") }
            func col(_ keys: [String], excluding: [String] = []) -> Int? {
                for key in keys {
                    if let i = cols.firstIndex(where: { $0.count <= 20 && $0.contains(key) && !excluding.contains(where: $0.contains) }) {
                        return i
                    }
                }
                return nil
            }
            guard let nameCol = col(["授業科目名", "科目名", "授業名", "講義名", "授業科目", "科目"],
                                    excluding: ["コード", "区分", "分類", "番号", "ナンバ"]) else { continue }
            let slotCol = col(["曜日時限", "曜日・時限", "曜日/時限", "曜日／時限", "曜時", "曜限", "開講曜限", "曜日・講時", "時間割"],
                              excluding: ["コード"])
            let dayCol = col(["曜日"])
            let periodCol = col(["時限", "講時", "限"])
            guard slotCol != nil || (dayCol != nil && periodCol != nil) || dayCol != nil else { continue }
            let teacherCol = col(["担当教員", "教員", "担当者", "担当", "講師"])
            let roomCol = col(["教室"])
            let termCol = col(["学期", "開講期", "開講時期", "期間", "開講区分"])
            let codeCol = col(["時間割コード", "講義コード", "授業コード", "科目コード", "コード"])

            var found: [CatalogCourse] = []
            for r in (h + 1)..<table.count {
                let row = table[r]
                func cell(_ i: Int?) -> String {
                    guard let i, i < row.count else { return "" }
                    return row[i]
                }
                let nameRaw = cell(nameCol)
                guard !nameRaw.isEmpty, nameRaw != header[nameCol] else { continue }
                let nameLines = nameRaw.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                var name = nameLines.first ?? nameRaw
                // 1行目がコードなら次の行
                if matches(codeRegex, name), nameLines.count > 1 { name = nameLines[1] }
                name = stripBrackets(name)
                guard name.count >= 2 else { continue }
                var slots: [Slot] = []
                if let slotCol { slots = parseSlots(cell(slotCol)) }
                if slots.isEmpty, dayCol != nil {
                    slots = periodCol != nil && periodCol != dayCol ? parseSlots(day: cell(dayCol), period: cell(periodCol)) : parseSlots(cell(dayCol))
                }
                let teacher = stripTeacher(cell(teacherCol).components(separatedBy: "\n").first ?? "")
                let room = cell(roomCol).components(separatedBy: "\n").first ?? ""
                let t = parseTerm(cell(termCol)) ?? parseTerm(cell(slotCol)) ?? term
                found.append(CatalogCourse(name: name, teacher: teacher, room: room,
                                           code: cell(codeCol).components(separatedBy: "\n").first ?? "",
                                           slots: slots, term: t, source: source))
            }
            if !found.isEmpty { return merged(found) }
        }
        return []
    }

    /// 表が見つからないときの最後の手段：「月3 統計学概論」のような行
    static func parseText(_ text: String, term: Term?, source: String) -> [CatalogCourse] {
        var found: [CatalogCourse] = []
        for raw in normalize(text).components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.count >= 4, line.count <= 80 else { continue }
            let slots = parseSlots(line)
            guard !slots.isEmpty else { continue }
            let ns = line as NSString
            let stripped = slotRegex.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
            let parts = stripped.components(separatedBy: CharacterSet(charactersIn: " \t/／|｜,、"))
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ・:：()（）[]【】")) }
                .filter { $0.count >= 2 && !matches(codeRegex, $0) && parseTerm($0) == nil }
            guard let name = parts.first, !isHeaderWord(name) else { continue }
            let room = parts.dropFirst().first(where: isRoom) ?? ""
            found.append(CatalogCourse(name: name, room: room, slots: slots, term: parseTerm(line) ?? term, source: source))
        }
        return merged(found)
    }

    /// 画面全体から。tables は表ごとに、その前に書いてある見出し（「2026年度 前期」など）も受け取る
    static func parse(tables: [(rows: [[String]], label: String)], text: String, term: Term?, source: String) -> [CatalogCourse] {
        var all: [CatalogCourse] = []
        // 小さい表（内側の表）から順に
        for table in tables.sorted(by: { $0.rows.count < $1.rows.count }) {
            let t = parseTerm(table.label) ?? term
            all += parseGrid(table.rows, term: t, source: source)
            all += parseList(table.rows, term: t, source: source)
        }
        if all.isEmpty { all = parseText(text, term: term, source: source) }
        return merged(all)
    }

    /// 同じ授業（授業名・教員・学期が同じ）をまとめる
    static func merged(_ list: [CatalogCourse]) -> [CatalogCourse] {
        var order: [String] = []
        var map: [String: CatalogCourse] = [:]
        for c in list {
            if var existing = map[c.id] {
                existing.merge(c)
                map[c.id] = existing
            } else {
                order.append(c.id)
                map[c.id] = c
            }
        }
        // 教員の名前がない方を、同じ名前のある方にまとめる
        var result = order.compactMap { map[$0] }
        for (i, c) in result.enumerated().reversed() where c.teacher.isEmpty {
            if let j = result.firstIndex(where: { $0.id != c.id && fold($0.name) == fold(c.name) && !$0.teacher.isEmpty && $0.term == c.term }) {
                result[j].merge(c)
                result.remove(at: i)
            }
        }
        return result.sorted { ($0.slots.first ?? Slot(day: .sat, period: 9)) < ($1.slots.first ?? Slot(day: .sat, period: 9)) }
    }
}
