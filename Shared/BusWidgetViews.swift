import SwiftUI
import WidgetKit

/// スクールバスの次の便（左：おおたかの森駅 → 大学、右：大学 → おおたかの森駅）
struct BusWidgetView: View {
    let day: BusDay?
    let message: String?
    let now: Date
    let family: WidgetFamily

    static let scheduleURL = URL(string: "https://www.edogawa-u.ac.jp/koutuu/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let day, day.hasTimes {
                timesView(day)
            } else if let day, !day.running {
                notice(title: "運休", detail: "本日のスクールバスは運休です", button: false)
            } else if day != nil {
                notice(title: "特別ダイヤ", detail: "本日は特別ダイヤで運行しています", button: true)
            } else {
                notice(title: "取得できません", detail: message ?? "アプリを開いて時刻表を読み込んでください", button: false)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bus.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(day?.hasTimes == false ? Color.secondary : CommuteColors.bus)
            Text(family == .systemSmall ? "バス" : "スクールバス")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(JST.month(now))/\(JST.day(now))（\(weekdayText)）")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var weekdayText: String {
        ["日", "月", "火", "水", "木", "金", "土"][JST.calendar.component(.weekday, from: now) - 1]
    }

    @ViewBuilder
    private func timesView(_ day: BusDay) -> some View {
        let m = JST.minutes(now)
        let toUniv = day.next(day.toUniv, after: m, count: 2)
        let toStation = day.next(day.toStation, after: m, count: 2)
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 6) {
                smallRow("森 → 大学", toUniv, color: CommuteColors.bus, now: m)
                Divider()
                smallRow("大学 → 森", toStation, color: CommuteColors.train, now: m)
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
        } else {
            HStack(alignment: .top, spacing: 12) {
                column("おおたかの森駅 → 大学", toUniv, color: CommuteColors.bus, now: m)
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1)
                    .padding(.vertical, 2)
                column("大学 → おおたかの森駅", toStation, color: CommuteColors.train, now: m)
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Text(day.dia)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CommuteColors.train)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CommuteColors.train.opacity(0.14), in: Capsule())
            }
        }
    }

    private func column(_ title: String, _ times: [Int], color: Color, now m: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let first = times.first {
                Text(JST.hm(first))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .padding(.top, 2)
                Text("あと \(max(0, first - m))分")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("次発")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(times.count > 1 ? JST.hm(times[1]) : "なし")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(times.count > 1 ? Color.primary : Color.secondary)
                }
                .padding(.top, 6)
            } else {
                Text("本日終了")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smallRow(_ title: String, _ times: [Int], color: Color, now m: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            if let first = times.first {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(JST.hm(first))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("あと\(max(0, first - m))分")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Text("本日終了")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func notice(title: String, detail: String, button: Bool) -> some View {
        Spacer(minLength: 0)
        Text(title)
            .font(.system(size: family == .systemSmall ? 24 : 30, weight: .bold))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
        HStack(alignment: .center) {
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if button && family != .systemSmall {
                Spacer(minLength: 6)
                Link(destination: BusWidgetView.scheduleURL) {
                    HStack(spacing: 4) {
                        Text("運行予定を確認")
                            .font(.system(size: 10, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(CommuteColors.train)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(CommuteColors.train.opacity(0.14), in: Capsule())
                }
            }
        }
        .padding(.top, 4)
        Spacer(minLength: 0)
    }
}
