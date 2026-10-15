import Foundation
import UserNotifications

/// ウィジェットの状態（ウィジェット拡張の中だけで使う）
enum WidgetStatus: Equatable {
    case idle
    case result(RegisterResult)

    var isResult: Bool {
        if case .result = self { return true }
        return false
    }
}

enum WidgetStore {
    private static let defaults = UserDefaults.standard

    static var digits: String {
        get { defaults.string(forKey: "w.digits") ?? "" }
        set { defaults.set(newValue, forKey: "w.digits") }
    }

    static var status: WidgetStatus {
        get {
            guard let kind = defaults.string(forKey: "w.kind") else { return .idle }
            let text = defaults.string(forKey: "w.text") ?? ""
            switch kind {
            case "success": return .result(.success(course: text))
            case "already": return .result(.already(course: text))
            case "wrong": return .result(.wrongCode)
            case "failure": return .result(.failure(text))
            default: return .idle
            }
        }
        set {
            switch newValue {
            case .idle:
                defaults.removeObject(forKey: "w.kind")
                defaults.removeObject(forKey: "w.text")
            case .result(let r):
                switch r {
                case .success(let c): defaults.set("success", forKey: "w.kind"); defaults.set(c, forKey: "w.text")
                case .already(let c): defaults.set("already", forKey: "w.kind"); defaults.set(c, forKey: "w.text")
                case .wrongCode: defaults.set("wrong", forKey: "w.kind"); defaults.set("", forKey: "w.text")
                case .failure(let m): defaults.set("failure", forKey: "w.kind"); defaults.set(m, forKey: "w.text")
                }
            }
        }
    }

    static var credentials: EdohenCredentials {
        get {
            EdohenCredentials(
                userID: defaults.string(forKey: "w.uid") ?? "",
                password: defaults.string(forKey: "w.pw") ?? "",
                studentNo: defaults.string(forKey: "w.sno") ?? "")
        }
        set {
            defaults.set(newValue.userID, forKey: "w.uid")
            defaults.set(newValue.password, forKey: "w.pw")
            defaults.set(newValue.studentNo, forKey: "w.sno")
        }
    }

    /// 6桁そろったら出席登録して結果を保存
    static func submit(code: String) async {
        let creds = credentials
        let result: RegisterResult
        if !creds.isComplete {
            result = .failure("ウィジェットを長押し→「ウィジェットを編集」で設定してください")
        } else {
            do {
                result = try await EdohenClient(credentials: creds).register(code: code)
            } catch {
                result = .failure(error.localizedDescription)
            }
        }
        digits = ""
        status = .result(result)
        await notify(result)
    }

    private static func notify(_ result: RegisterResult) async {
        let content = UNMutableNotificationContent()
        content.title = result.title
        content.body = result.message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
