import SwiftUI

extension CourseColor {
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        }
    }
}

/// カレンダーの予定のような、色付きのマスの塗りと文字色
struct CourseTint {
    let base: Color
    let scheme: ColorScheme

    var fill: Color { base.opacity(scheme == .dark ? 0.30 : 0.16) }
    var strong: Color { base.opacity(scheme == .dark ? 0.55 : 0.32) }

    /// 文字は少し暗め（ダークでは明るめ）にして読みやすく
    var text: Color {
        scheme == .dark ? base.blended(with: .white, by: 0.45) : base.blended(with: .black, by: 0.45)
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
