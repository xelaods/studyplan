import SwiftUI
import Security

/// エドヘンのアカウント（パスワードはキーチェーン）
enum CredentialStore {
    private static let defaults = UserDefaults.standard
    private static let service = "studyplan.edohen.password"

    static func load() -> EdohenCredentials {
        if Store.isDemo {
            return EdohenCredentials(userID: "demo", password: "demo", studentNo: "0000000")
        }
        return EdohenCredentials(
            userID: defaults.string(forKey: "edohen.userID") ?? "",
            password: readPassword(),
            studentNo: defaults.string(forKey: "edohen.studentNo") ?? "")
    }

    static func save(_ credentials: EdohenCredentials) {
        guard !Store.isDemo else { return }
        defaults.set(credentials.userID, forKey: "edohen.userID")
        defaults.set(credentials.studentNo, forKey: "edohen.studentNo")
        writePassword(credentials.password)
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service]
    }

    private static func readPassword() -> String {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func writePassword(_ password: String) {
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }
        var q = query
        q[kSecValueData as String] = Data(password.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// エドヘンの出席状況（最後に取得した分を保存しておき、時間割の授業にも表示する）
@MainActor
final class AttendanceStore: ObservableObject {
    static let shared = AttendanceStore()

    @Published private(set) var courses: [AttendanceCourse] = []
    @Published private(set) var updatedAt: Date?
    @Published private(set) var isLoading = false
    @Published var errorText: String?

    private static let cacheKey = "edohen.attendance.v1"
    private static let dateKey = "edohen.attendance.updated"

    private init() {
        if Store.isDemo {
            courses = Self.sample()
            updatedAt = Clock.now
            return
        }
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let list = try? JSONDecoder().decode([AttendanceCourse].self, from: data) {
            courses = list
        }
        updatedAt = UserDefaults.standard.object(forKey: Self.dateKey) as? Date
    }

    var hasAccount: Bool { CredentialStore.load().isComplete }

    var latter: [AttendanceCourse] { courses.filter { $0.isLatter && !$0.isUnregistered } }
    var former: [AttendanceCourse] { courses.filter { !$0.isLatter && !$0.isUnregistered } }
    var unregistered: [AttendanceCourse] { courses.filter { $0.isUnregistered } }

    func load() async {
        guard !Store.isDemo else { return }
        let credentials = CredentialStore.load()
        guard credentials.isComplete else {
            errorText = "「設定」でエドヘンのアカウントを登録してください"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await EdohenClient(credentials: credentials).fetchCourses()
            courses = list
            errorText = nil
            updatedAt = .now
            if let data = try? JSONEncoder().encode(list) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
            UserDefaults.standard.set(updatedAt, forKey: Self.dateKey)
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// 少し時間がたっていたら取り直す
    func refreshIfStale() async {
        guard hasAccount, !isLoading else { return }
        if let updatedAt, Date().timeIntervalSince(updatedAt) < 10 * 60 { return }
        await load()
    }

    func clear() {
        courses = []
        updatedAt = nil
        errorText = nil
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.dateKey)
    }

    /// 時間割の授業に当たるエドヘンの科目（授業名で照らし合わせる）
    func record(for course: Course) -> AttendanceCourse? {
        Self.match(course, in: courses, currentIsLatter: Store.shared.term == .second)
    }

    nonisolated static func match(_ course: Course, in courses: [AttendanceCourse], currentIsLatter: Bool) -> AttendanceCourse? {
        let name = TimetableParser.fold(course.name)
        guard !name.isEmpty else { return nil }
        let pool = courses.filter { !$0.isUnregistered }
        let exact = pool.filter { TimetableParser.fold($0.name) == name }
        let found = exact.isEmpty
            ? pool.filter {
                let other = TimetableParser.fold($0.name)
                return min(other.count, name.count) >= 4 && (other.contains(name) || name.contains(other))
            }
            : exact
        guard !found.isEmpty else { return nil }
        // 学期が合うものを優先
        let wantLatter: Bool? = course.term == .second ? true : (course.term == .first ? false : nil)
        if let wantLatter, let same = found.first(where: { $0.isLatter == wantLatter }) { return same }
        return found.first(where: { $0.isLatter == currentIsLatter }) ?? found.first
    }

    // MARK: 見本

    nonisolated static func sample() -> [AttendanceCourse] {
        func s(_ list: [(String, String, SessionStatus, String)]) -> [AttendanceSession] {
            list.map { AttendanceSession(date: $0.0, period: $0.1, status: $0.2, detail: $0.3) }
        }
        let mon3 = s([("09/29", "3限", .present, "13:08"), ("10/06", "3限", .present, "13:05"), ("10/13", "3限", .unused, "未利用")])
        let tue2 = s([("09/30", "2限", .present, "10:46"), ("10/07", "2限", .absent, "×"), ("10/14", "2限", .late, "11:07")])
        let tue3 = s([("09/30", "3限", .present, "13:02"), ("10/07", "3限", .present, "13:09"), ("10/14", "3限", .present, "13:04")])
        let thu1 = s([("10/02", "1限", .absent, "×"), ("10/09", "1限", .absent, "×"), ("10/16", "1限", .absent, "×")])
        return [
            AttendanceCourse(name: "アカデミック・スキル演習", teacher: "佐藤 健一", present: 2, late: 0, absent: 0,
                             isUnregistered: false, isLatter: true, sessions: mon3),
            AttendanceCourse(name: "統計学入門", teacher: "田中 浩", present: 1, late: 1, absent: 1,
                             isUnregistered: false, isLatter: true, sessions: tue2),
            AttendanceCourse(name: "社会学概論", teacher: "伊藤 由美", present: 3, late: 0, absent: 0,
                             isUnregistered: false, isLatter: true, sessions: tue3),
            AttendanceCourse(name: "Webデザイン", teacher: "渡辺 翔", present: 0, late: 0, absent: 3,
                             isUnregistered: false, isLatter: true, sessions: thu1),
            AttendanceCourse(name: "情報リテラシー", teacher: "鈴木 美咲", present: 14, late: 1, absent: 0,
                             isUnregistered: false, isLatter: false,
                             sessions: s([("07/14", "4限", .present, "15:01"), ("07/21", "4限", .late, "15:12")])),
            AttendanceCourse(name: "観光文化論", teacher: "松本 亮", present: 0, late: 0, absent: 0,
                             isUnregistered: true, isLatter: true, sessions: []),
        ]
    }
}
