import Foundation

// MARK: - Models

enum SessionStatus: String, Codable, Hashable {
    case present, late, absent, unused
}

struct AttendanceSession: Identifiable, Hashable, Codable {
    var id = UUID()
    let date: String      // "10/01"
    let period: String    // "３限"
    let status: SessionStatus
    let detail: String    // "13:11" / "×" / "未利用"
}

/// エドヘンの出席状況の1科目（時間割の Course とは別）
struct AttendanceCourse: Identifiable, Hashable, Codable {
    var id = UUID()
    let name: String
    let teacher: String
    let present: Int
    let late: Int
    let absent: Int
    /// 教員名が色付き（未履修・履修放棄）
    let isUnregistered: Bool
    /// 最後の授業日が9〜3月なら後期
    let isLatter: Bool
    let sessions: [AttendanceSession]
}

enum RegisterResult: Equatable {
    case success(course: String)
    case already(course: String)
    case wrongCode
    case failure(String)

    var title: String {
        switch self {
        case .success: return "登録完了"
        case .already: return "登録済み"
        case .wrongCode: return "コード間違い"
        case .failure: return "登録できませんでした"
        }
    }

    var message: String {
        switch self {
        case .success(let c): return c.isEmpty ? "出席を登録しました" : c
        case .already(let c): return c.isEmpty ? "この授業はすでに登録されています" : c
        case .wrongCode: return "講義パスワードを確認してください"
        case .failure(let m): return m
        }
    }

    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .already: return "checkmark.circle"
        case .wrongCode: return "exclamationmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }
}

struct EdohenCredentials {
    var userID: String
    var password: String
    var studentNo: String

    var isComplete: Bool {
        !userID.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !studentNo.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

enum EdohenError: LocalizedError {
    case missingCredentials
    case loginFailed
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "アカウントが設定されていません"
        case .loginFailed: return "ログインできませんでした。IDとパスワードを確認してください"
        case .badResponse: return "エドヘンから正しい応答がありませんでした"
        }
    }
}

// MARK: - Client

final class EdohenClient {
    private static let base = "https://edohen.edogawa-u.ac.jp/mobile/g/"
    /// Shift_JIS（Windows-31J）
    static let cp932 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
    /// 「出席登録」ボタンの値（Shift_JIS）
    private static let submitValue = "%8F%6F%90%C8%93%6F%98%5E"
    /// 「送信」（Shift_JIS）
    private static let sendValue = "%91%97%90M"

    private let session: URLSession
    private let credentials: EdohenCredentials

    init(credentials: EdohenCredentials) {
        self.credentials = credentials
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: config)
    }

    // MARK: Public

    func login() async throws {
        guard credentials.isComplete else { throw EdohenError.missingCredentials }
        var request = URLRequest(url: URL(string: Self.base + "login.php")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "gakusei_id=\(Self.ascii(credentials.userID.trimmingCharacters(in: .whitespaces)))"
            + "&password=\(Self.ascii(credentials.password))&sub_login=1"
        request.httpBody = Data(body.utf8)
        let html = try await fetch(request)
        if html.contains("認証に失敗") { throw EdohenError.loginFailed }
    }

    func register(code: String) async throws -> RegisterResult {
        try await login()

        let sno = Self.ascii(credentials.studentNo.trimmingCharacters(in: .whitespaces))
        let url = URL(string: Self.base
            + "g_usr002.php?gakusei_cd=\(sno)&send=\(Self.sendValue)&jyugyo_password=\(Self.ascii(code))")!
        let page = try await fetch(URLRequest(url: url))

        let hidden = Self.hiddenInputs(page)
        let course = hidden.first { $0.name == "jyugyo_name" }?.value ?? ""

        if let result = Self.classify(page, course: course) { return result }
        guard !hidden.isEmpty else { return .failure("出席登録ページを読み取れませんでした") }

        var body = "s_form=\(Self.submitValue)"
        for input in hidden {
            body += "&\(input.name)=\(Self.sjisPercent(input.value))"
        }
        var request = URLRequest(url: URL(string: Self.base + "g_usr003.php")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(url.absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = Data(body.utf8)
        let result = try await fetch(request)

        if let r = Self.classify(result, course: course) { return r }
        return .success(course: course)
    }

    func fetchCourses() async throws -> [AttendanceCourse] {
        try await login()
        let html = try await fetch(URLRequest(url: URL(string: Self.base + "pinf1001h.php")!))
        return Self.parseCourses(html)
    }

    // MARK: Networking

    private func fetch(_ request: URLRequest) async throws -> String {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw EdohenError.badResponse
        }
        return Self.decode(data)
    }

    static func decode(_ data: Data) -> String {
        let head = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        if head.contains("shift_jis") || head.contains("sjis") {
            if let s = String(data: data, encoding: cp932) { return s }
        }
        if head.contains("euc-jp") {
            if let s = String(data: data, encoding: .japaneseEUC) { return s }
        }
        // 文字コードの指定が無いページ（出席状況など）は、
        // 日本語として正しく読めるものを選ぶ
        let candidates: [String.Encoding] = [.utf8, .japaneseEUC, cp932, .iso2022JP]
        let decoded = candidates.compactMap { String(data: data, encoding: $0) }
        let markers = ["出席", "学籍", "講義", "エラー", "授業"]
        if let good = decoded.first(where: { s in markers.contains { s.contains($0) } }) {
            return good
        }
        return decoded.first ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: Parsing

    /// エラー表示から結果を判定。エラーが無ければ nil
    static func classify(_ html: String, course: String) -> RegisterResult? {
        if html.contains("既に出席登録") { return .already(course: course) }
        guard let message = html.firstMatch(#"エラー[：:][^<。]*"#)?.first else { return nil }
        if message.contains("ﾊﾟｽﾜｰﾄﾞ") || message.contains("パスワード") { return .wrongCode }
        let text = message
            .replacingOccurrences(of: "エラー：", with: "")
            .replacingOccurrences(of: "エラー:", with: "")
            .trimmingCharacters(in: .whitespaces)
        return .failure(text.isEmpty ? "エラーが発生しました" : text)
    }

    static func hiddenInputs(_ html: String) -> [(name: String, value: String)] {
        html.allMatches(#"<input[^>]*type="hidden"[^>]*>"#).compactMap { (match: [String]) -> (name: String, value: String)? in
            let tag = match[0]
            guard let name = tag.firstMatch(#"name="([^"]*)""#)?[1] else { return nil }
            let value = tag.firstMatch(#"value="([^"]*)""#)?[1] ?? ""
            return (name: name, value: value)
        }
    }

    static func parseCourses(_ html: String) -> [AttendanceCourse] {
        html.split(byPattern: #"<table border="1""#).dropFirst().compactMap { (chunk: String) -> AttendanceCourse? in
            guard let name = chunk.firstMatch(#"<font color="black">([^<]+)</font>"#)?[1] else { return nil }
            let headers = chunk.allMatches(#">(\d\d)\D(\d\d)<[^>]*>([^<]*)</font>"#).map { ("\($0[1])/\($0[2])", $0[3]) }
            let cells = chunk.allMatches(#"<td([^>]*)>([^<]*)</td>"#).map { (attrs: $0[1], text: $0[2]) }
            guard cells.count >= 4 else { return nil }

            let sessions: [AttendanceSession] = zip(headers, cells.dropFirst(4)).map { pair -> AttendanceSession in
                let header = pair.0
                let cell = pair.1
                let attrs = cell.attrs.lowercased()
                let status: SessionStatus
                if attrs.contains("ff9999") { status = .absent }
                else if attrs.contains("ffff66") { status = .late }
                else if attrs.contains("cc9966") { status = .unused }
                else { status = .present }
                return AttendanceSession(date: header.0, period: header.1.trimmingCharacters(in: .whitespaces),
                                         status: status, detail: cell.text.trimmingCharacters(in: .whitespaces))
            }

            let lastMonth = headers.last.flatMap { Int($0.0.prefix(2)) } ?? 4
            return AttendanceCourse(
                name: name.trimmingCharacters(in: .whitespaces),
                teacher: cells[0].text.trimmingCharacters(in: .whitespaces),
                present: Int(cells[1].text) ?? 0,
                late: Int(cells[2].text) ?? 0,
                absent: Int(cells[3].text) ?? 0,
                isUnregistered: cells[0].attrs.lowercased().contains("bgcolor"),
                isLatter: lastMonth >= 9 || lastMonth <= 3,
                sessions: sessions)
        }
    }

    // MARK: Encoding

    private static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._*".utf8)

    static func ascii(_ s: String) -> String {
        percent(Data(s.utf8))
    }

    static func sjisPercent(_ s: String) -> String {
        percent(s.data(using: cp932, allowLossyConversion: true) ?? Data(s.utf8))
    }

    private static func percent(_ data: Data) -> String {
        var out = ""
        for byte in data {
            if unreserved.contains(byte) {
                out.append(Character(UnicodeScalar(byte)))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }
}

// MARK: - Regex helpers

extension String {
    func allMatches(_ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = self as NSString
        return regex.matches(in: self, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { i in
                let r = match.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    func firstMatch(_ pattern: String) -> [String]? {
        allMatches(pattern).first
    }

    func split(byPattern pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [self] }
        let ns = self as NSString
        var parts: [String] = []
        var start = 0
        for match in regex.matches(in: self, range: NSRange(location: 0, length: ns.length)) {
            parts.append(ns.substring(with: NSRange(location: start, length: match.range.location - start)))
            start = match.range.location
        }
        parts.append(ns.substring(from: start))
        return parts
    }
}
