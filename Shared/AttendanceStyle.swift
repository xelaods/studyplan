import SwiftUI

// 出席の色と記号（アプリとウィジェットで共通）

extension RegisterResult {
    var tint: Color {
        switch self {
        case .success: return .green
        case .already: return .blue
        case .wrongCode: return .orange
        case .failure: return .red
        }
    }
}

extension SessionStatus {
    var color: Color {
        switch self {
        case .present: return .green
        case .late: return .orange
        case .absent: return .red
        case .unused: return Color(.systemGray3)
        }
    }

    var label: String {
        switch self {
        case .present: return "出席"
        case .late: return "遅刻"
        case .absent: return "欠席"
        case .unused: return "未利用"
        }
    }

    var symbol: String {
        switch self {
        case .present: return "checkmark.circle.fill"
        case .late: return "clock.fill"
        case .absent: return "xmark.circle.fill"
        case .unused: return "minus.circle.fill"
        }
    }
}
