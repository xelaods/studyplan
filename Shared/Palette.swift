import SwiftUI

/// アプリの色（iOS 標準の色。ライト・ダークは自動で切り替わる）
enum Soft {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    // 出席アプリと同じ、iOS 標準のはっきりした色
    /// 必修・今日の印
    static let red = Color(.systemRed)
    /// 選択・リンク
    static let blue = Color(.systemBlue)
    /// スクールバス・出席
    static let green = Color(.systemGreen)
    /// 注意（あと少し・遅刻）
    static let orange = Color(.systemOrange)
}

extension CourseColor {
    var color: Color {
        switch self {
        case .red: return Soft.red
        case .blue: return Soft.blue
        }
    }
}

/// カレンダーの予定のような、色付きのマスの塗りと文字色
struct CourseTint {
    let base: Color
    let scheme: ColorScheme

    var fill: Color { base.opacity(scheme == .dark ? 0.24 : 0.13) }
    var strong: Color { base.opacity(scheme == .dark ? 0.45 : 0.26) }

    /// 文字は少し暗め（ダークでは明るめ）にして読みやすく
    var text: Color {
        scheme == .dark ? base.blended(with: .white, by: 0.35) : base.blended(with: .black, by: 0.35)
    }
}

extension Color {
    /// iOS 17 でも使えるように自前で混ぜる
    func blended(with other: Color, by amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(min(1, max(0, amount)))
        return Color(red: Double(r1 + (r2 - r1) * t), green: Double(g1 + (g2 - g1) * t),
                     blue: Double(b1 + (b2 - b1) * t), opacity: Double(a1 + (a2 - a1) * t))
    }
}
