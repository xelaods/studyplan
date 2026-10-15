import AppIntents
import WidgetKit

/// ウィジェットの設定（長押し→ウィジェットを編集）
struct AttendConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "出席登録"
    static var description = IntentDescription("エドヘンのアカウントを設定します。")

    @Parameter(title: "edo-net ID")
    var userID: String?

    @Parameter(title: "パスワード")
    var password: String?

    @Parameter(title: "学籍番号")
    var studentNo: String?

    init() {}
}

struct PressDigitIntent: AppIntent {
    static var title: LocalizedStringResource = "数字を入力"
    static var isDiscoverable: Bool = false

    @Parameter(title: "数字")
    var digit: Int

    init() {}
    init(digit: Int) { self.digit = digit }

    func perform() async throws -> some IntentResult {
        if WidgetStore.status.isResult { WidgetStore.status = .idle }
        var code = WidgetStore.digits
        guard code.count < 6 else { return .result() }
        code.append(String(digit))
        WidgetStore.digits = code
        if code.count == 6 {
            await WidgetStore.submit(code: code)
        }
        return .result()
    }
}

struct DeleteDigitIntent: AppIntent {
    static var title: LocalizedStringResource = "1文字消す"
    static var isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        WidgetStore.status = .idle
        var code = WidgetStore.digits
        if !code.isEmpty { code.removeLast() }
        WidgetStore.digits = code
        return .result()
    }
}

struct ClearDigitsIntent: AppIntent {
    static var title: LocalizedStringResource = "クリア"
    static var isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        WidgetStore.status = .idle
        WidgetStore.digits = ""
        return .result()
    }
}
