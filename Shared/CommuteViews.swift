import SwiftUI
import WidgetKit

// 乗り継ぎ表の表示（アプリとウィジェットで共通）

enum CommuteColors {
    static let bus = Soft.green
    static let train = Soft.blue
    static let warn = Soft.orange
    static func highlight(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Soft.blue.opacity(0.18) : Soft.blue.opacity(0.10)
    }
}

/// 列の見出し（自宅発・森着・バス発 など）
struct CommuteColumnHeader: View {
    let direction: CommuteDirection
    let settings: CommuteSettings
    var widths: [CGFloat] = [72, 66, 66]
    var font: Font = .system(size: 10, weight: .semibold)

    var body: some View {
        let labels: [(String, Color)] = direction == .go
            ? [("\(settings.homeShort)発", CommuteColors.train), ("森 着", .secondary), ("バス発", CommuteColors.bus)]
            : [("バス発", CommuteColors.bus), ("森 発", CommuteColors.train), ("\(settings.homeShort)着", .secondary)]
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                Text(labels[i].0)
                    .font(font)
                    .foregroundStyle(labels[i].1)
                    .lineLimit(1)
                    .frame(width: widths[i], alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 1本分の行
struct CommuteRowView: View {
    let row: CommuteRow
    let direction: CommuteDirection
    let label: (text: String, warn: Bool)
    let highlighted: Bool
    var widths: [CGFloat] = [72, 66, 66]
    var big: CGFloat = 19
    var small: CGFloat = 14

    var body: some View {
        let dep = row.train.map { JST.hm($0.dep) } ?? "--:--"
        let arr = row.train.map { JST.hm($0.arr) } ?? "--:--"
        let bus = JST.hm(row.bus)
        HStack(spacing: 0) {
            if direction == .go {
                time(dep, size: big, color: row.late ? .secondary : CommuteColors.train, bold: true, width: widths[0])
                time(arr, size: small, color: .secondary, bold: false, width: widths[1])
                time(bus, size: big, color: row.late ? .secondary : CommuteColors.bus, bold: true, width: widths[2])
            } else {
                time(bus, size: big, color: CommuteColors.bus, bold: true, width: widths[0])
                time(dep, size: big, color: CommuteColors.train, bold: true, width: widths[1])
                time(arr, size: small, color: .secondary, bold: false, width: widths[2])
            }
            Spacer(minLength: 2)
            if !label.text.isEmpty {
                Text(label.text)
                    .font(.system(size: highlighted ? 13 : 12, weight: highlighted ? .bold : .regular))
                    .foregroundStyle(label.warn ? CommuteColors.warn : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func time(_ s: String, size: CGFloat, color: Color, bold: Bool, width: CGFloat) -> some View {
        Text(s)
            .font(.system(size: size, weight: bold ? .bold : .regular, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: .leading)
    }
}

/// 見出し＋列見出し＋行（ウィジェットのカード表示）
struct CommuteSectionCard: View {
    let section: CommuteSection
    let settings: CommuteSettings
    let now: Int
    var maxRows: Int = 10
    var widths: [CGFloat] = [72, 66, 66]
    var big: CGFloat = 19
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let rows = Array(CommuteLabel.visibleRows(section, now: now).prefix(maxRows))
        let shown = CommuteSection(direction: section.direction, title: section.title, subtitle: section.subtitle,
                                   date: section.date, isToday: section.isToday, rows: rows)
        let hi = CommuteLabel.highlight(shown, now: now)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(section.title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if !section.subtitle.isEmpty {
                    Text(section.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            CommuteColumnHeader(direction: section.direction, settings: settings, widths: widths)
                .padding(.horizontal, 8)
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                CommuteRowView(row: row, direction: section.direction,
                               label: CommuteLabel.label(row, index: i, section: shown, now: now),
                               highlighted: hi == i, widths: widths, big: big, small: big * 0.74)
                    .padding(.vertical, big * 0.2)
                    .padding(.horizontal, 8)
                    .background(hi == i ? CommuteColors.highlight(scheme) : Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

/// 通学ウィジェット
struct CommuteWidgetView: View {
    let plan: CommutePlan?
    let settings: CommuteSettings
    let now: Date
    let family: WidgetFamily

    var body: some View {
        let minutes = JST.minutes(now)
        VStack(alignment: .leading, spacing: family == .systemLarge ? 6 : 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan?.title ?? "通学")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text([plan?.dia ?? "", JST.hm(now)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let plan, plan.message == nil, !plan.sections.isEmpty {
                if family == .systemLarge {
                    ForEach(plan.sections) { section in
                        CommuteSectionCard(section: section, settings: settings, now: minutes,
                                           maxRows: section.direction == .go && section.isToday ? 6 : 6, big: 17)
                    }
                    Spacer(minLength: 0)
                } else if let first = plan.sections.first(where: { !CommuteLabel.visibleRows($0, now: minutes).isEmpty }) {
                    CommuteSectionCard(section: first, settings: settings, now: minutes, maxRows: 2, big: 16)
                    Spacer(minLength: 0)
                }
            } else {
                Spacer()
                Text(plan?.message ?? "アプリを開いて時刻表を読み込んでください")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }
}
