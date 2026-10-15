import SwiftUI
import SafariServices

/// 通学：スクールバス × 電車 × 時間割の乗り継ぎ
struct CommuteView: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) var scheme
    @State var showPage = false
    @State var showTimetable = ProcessInfo.processInfo.arguments.contains("-bus")

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                content(now: Clock.fixed ?? context.date)
            }
            .navigationTitle("通学")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CommuteSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.commuteLoading {
                        ProgressView()
                    } else {
                        Button {
                            store.refreshCommute(force: true)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable { store.refreshCommute(force: true) }
            .navigationDestination(isPresented: $showTimetable) { BusTimetableView() }
            .sheet(isPresented: $showPage) {
                SafariView(url: BusSource.url).ignoresSafeArea()
            }
            .onAppear {
                if store.commutePlan == nil || Date().timeIntervalSince(store.commutePlan!.generated) > 300 {
                    store.refreshCommute()
                }
            }
            .onChange(of: store.commuteMode) { _, _ in store.refreshCommute() }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let minutes = JST.minutes(now)
        let plan = store.commutePlan
        List {
            Section {
                Picker("表示", selection: $store.commuteMode) {
                    ForEach(CommuteMode.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            } footer: {
                HStack {
                    Text("\(store.data.commute.home) ⇄ \(store.data.commute.station) ⇄ 大学")
                    Spacer()
                    if let plan { Text(plan.dia) }
                }
            }

            if let bus = plan?.bus, JST.isSameDay(bus.date, now) {
                Section("次のスクールバス") {
                    if bus.hasTimes {
                        NextBusRow(title: "おおたかの森駅発 → 大学", times: bus.next(bus.toUniv, after: minutes), now: minutes, color: CommuteColors.bus)
                        NextBusRow(title: "大学発 → おおたかの森駅", times: bus.next(bus.toStation, after: minutes), now: minutes, color: CommuteColors.train)
                    } else {
                        Label(bus.running ? "\(bus.dia)（時刻はページで確認してください）" : "今日はバスの運行がありません",
                              systemImage: "bus")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let plan {
                if let message = plan.message {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
                ForEach(plan.sections) { section in
                    let rows = CommuteLabel.visibleRows(section, now: minutes)
                    let shown = CommuteSection(direction: section.direction, title: section.title, subtitle: section.subtitle,
                                               date: section.date, isToday: section.isToday, rows: rows)
                    let hi = CommuteLabel.highlight(shown, now: minutes)
                    Section {
                        CommuteColumnHeader(direction: section.direction, settings: store.data.commute,
                                            widths: [82, 76, 76], font: .caption.weight(.semibold))
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            CommuteRowView(row: row, direction: section.direction,
                                           label: CommuteLabel.label(row, index: i, section: shown, now: minutes),
                                           highlighted: hi == i, widths: [82, 76, 76], big: 21, small: 15)
                                .listRowBackground(hi == i ? CommuteColors.highlight(scheme) : Color(.secondarySystemGroupedBackground))
                        }
                    } header: {
                        HStack {
                            Text(section.title)
                            Spacer()
                            Text(section.subtitle)
                        }
                    } footer: {
                        if section.direction == .go {
                            Text("授業開始の\(store.data.commute.walk + store.data.commute.busRide)分前までに出るバスが「ギリ」です（バス\(store.data.commute.busRide)分＋徒歩\(store.data.commute.walk)分）。")
                        }
                    }
                }
            } else if store.commuteLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("バスと電車を調べています…").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    showTimetable = true
                } label: {
                    HStack {
                        SettingsLabel(title: "スクールバス時刻表", systemName: "tablecells", color: .green)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
                Button {
                    showPage = true
                } label: {
                    SettingsLabel(title: "大学のバス時刻表ページ", systemName: "safari", color: .blue)
                }
                .foregroundStyle(.primary)
                Link(destination: transitURL(now: now)) {
                    SettingsLabel(title: "乗換案内で調べる", systemName: "tram.fill", color: .indigo)
                }
                .foregroundStyle(.primary)
            } footer: {
                Text("バスの時刻は大学のサイネージページ、電車はYahoo!乗換案内から調べています。結果は数時間保存して使います。")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func transitURL(now: Date) -> URL {
        var c = URLComponents(string: "https://transit.yahoo.co.jp/search/result")!
        c.queryItems = [.init(name: "from", value: store.data.commute.home), .init(name: "to", value: store.data.commute.station)]
        return c.url ?? URL(string: "https://transit.yahoo.co.jp/")!
    }
}

/// 次のバス（先発・次発・次々発）
struct NextBusRow: View {
    let title: String
    let times: [Int]
    let now: Int
    var color: Color = CommuteColors.bus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            if times.isEmpty {
                Text("本日の運行は終了しました").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(times.enumerated()), id: \.offset) { i, t in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(["先発", "次発", "次々発"][min(i, 2)])
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(JST.hm(t))
                                .font(.system(size: i == 0 ? 24 : 18, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(i == 0 ? color : Color.primary)
                            Text(CommuteLabel.left(t - now))
                                .font(.caption)
                                .foregroundStyle(t - now <= 5 ? CommuteColors.warn : Color.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// スクールバスの時刻表（大学のページと同じダイヤ判定）
/// 1時間ごとの行に、左＝おおたかの森駅発、右＝大学発の分を並べる（バス停の時刻表と同じ形）
struct BusTimetableView: View {
    @State var selected = JST.startOfDay(Clock.now)
    @State var html: String?
    @State var error: String?

    private var days: [Date] {
        let today = JST.startOfDay(Clock.now)
        return (0..<7).map { JST.adding(days: $0, to: today) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    dayStrip
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                if let error {
                    Section { Text(error).foregroundStyle(.secondary) }
                } else if let day = currentDay {
                    content(day, proxy: proxy)
                } else {
                    Section { HStack { ProgressView(); Text("読み込み中…").foregroundStyle(.secondary) } }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("スクールバス時刻表")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load(force: true) }
            .onChange(of: selected) { _, _ in scrollToNow(proxy) }
            .onChange(of: html) { _, _ in scrollToNow(proxy) }
        }
    }

    private var currentDay: BusDay? {
        if Store.isDemo { return Sample.commutePlan().bus.map { var d = $0; d.date = selected; return d } }
        guard let html else { return nil }
        return BusSource.day(JST.date(selected, minutes: 12 * 60), html: html)
    }

    private var isToday: Bool { JST.isSameDay(selected, Clock.now) }

    // MARK: 日付の切り替え（1週間分）

    private var dayStrip: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { d in
                let on = JST.isSameDay(d, selected)
                let wd = JST.calendar.component(.weekday, from: d) - 1
                let info = badge(for: d)
                Button {
                    selected = d
                } label: {
                    VStack(spacing: 3) {
                        Text(["日", "月", "火", "水", "木", "金", "土"][wd])
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(on ? Color.white.opacity(0.9) : (wd == 0 ? Soft.red : Color.secondary))
                        Text("\(JST.day(d))")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(on ? Color.white : Color.primary)
                        Text(info)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(on ? Color.white.opacity(0.9) : (info == "運休" ? Color.secondary : Soft.green))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(on ? Soft.blue : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func badge(for d: Date) -> String {
        if Store.isDemo {
            let wd = JST.calendar.component(.weekday, from: d)
            return wd == 1 ? "運休" : "A"
        }
        guard let html else { return " " }
        let day = BusSource.day(JST.date(d, minutes: 12 * 60), html: html)
        if !day.running { return "運休" }
        if day.diaKey == "A" || day.diaKey == "B" { return day.diaKey }
        return "特別"
    }

    // MARK: 時刻表

    @ViewBuilder
    private func content(_ day: BusDay, proxy: ScrollViewProxy) -> some View {
        let now = JST.minutes(Clock.now)
        if !day.running {
            Section {
                Label("この日はスクールバスの運行がありません", systemImage: "moon.zzz")
                    .foregroundStyle(.secondary)
            }
        } else if day.unknown {
            Section {
                Label("\(day.dia)です。時刻は大学のページで確認してください", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                Link("運行予定を確認", destination: BusWidgetView.scheduleURL)
            }
        } else {
            if isToday {
                Section("次のバス") {
                    NextBusRow(title: "おおたかの森駅発 → 大学", times: day.next(day.toUniv, after: now), now: now, color: CommuteColors.bus)
                    NextBusRow(title: "大学発 → おおたかの森駅", times: day.next(day.toStation, after: now), now: now, color: CommuteColors.train)
                }
            }
            let nextUniv = isToday ? day.toUniv.first { $0 >= now } : nil
            let nextStation = isToday ? day.toStation.first { $0 >= now } : nil
            let hours = Array(Set((day.toUniv + day.toStation).map { $0 / 60 })).sorted()
            Section {
                header
                ForEach(hours, id: \.self) { h in
                    HourRow(hour: h,
                            left: day.toUniv.filter { $0 / 60 == h },
                            right: day.toStation.filter { $0 / 60 == h },
                            now: isToday ? now : nil,
                            nextLeft: nextUniv, nextRight: nextStation)
                        .id(h)
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                }
            } header: {
                HStack {
                    Text("\(JST.month(selected))月\(JST.day(selected))日")
                    Spacer()
                    Text(day.dia)
                }
            } footer: {
                Text("色付きの時刻が次のバスです。過ぎた便は薄く表示します。")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("時")
                .frame(width: 34)
            Color.clear.frame(width: 1)
            Label("おおたかの森駅発", systemImage: "arrow.right")
                .labelStyle(TrailingIconLabel())
                .foregroundStyle(CommuteColors.bus)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
            Label("大学発", systemImage: "arrow.right")
                .labelStyle(TrailingIconLabel())
                .foregroundStyle(CommuteColors.train)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
        }
        .font(.caption.weight(.semibold))
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
    }

    private func scrollToNow(_ proxy: ScrollViewProxy) {
        guard isToday else { return }
        let h = JST.minutes(Clock.now) / 60
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation { proxy.scrollTo(max(8, h - 1), anchor: .top) }
        }
    }

    private func load(force: Bool = false) async {
        if Store.isDemo { html = ""; return }
        do {
            html = try await BusSource.html(force: force)
            error = nil
        } catch {
            self.error = "バス時刻表を取得できません"
        }
    }
}

private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon.font(.caption2.weight(.bold))
        }
    }
}

/// 1時間分の行：時｜駅発の分｜大学発の分
private struct HourRow: View {
    let hour: Int
    let left: [Int]
    let right: [Int]
    let now: Int?
    let nextLeft: Int?
    let nextRight: Int?

    var body: some View {
        let past = now.map { (hour + 1) * 60 <= $0 } ?? false
        HStack(alignment: .top, spacing: 0) {
            Text("\(hour)")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(past ? Color.secondary : Color.primary)
                .frame(width: 34)
                .padding(.vertical, 8)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1)
            minutes(left, next: nextLeft, color: CommuteColors.bus)
            Rectangle().fill(Color.secondary.opacity(0.12)).frame(width: 1)
            minutes(right, next: nextRight, color: CommuteColors.train)
        }
        .opacity(past ? 0.45 : 1)
    }

    private func minutes(_ list: [Int], next: Int?, color: Color) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 4), alignment: .leading, spacing: 4) {
            ForEach(list, id: \.self) { t in
                let isNext = t == next
                let gone = now.map { t < $0 } ?? false
                Text(String(format: "%02d", t % 60))
                    .font(.system(size: 17, weight: isNext ? .bold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isNext ? Color.white : (gone ? Color.secondary : Color.primary))
                    .frame(width: 32, height: 26)
                    .background(isNext ? color : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 通学の設定
struct CommuteSettingsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            Section {
                TextField("自宅の最寄り駅", text: $store.data.commute.home)
                TextField("バスに乗り換える駅", text: $store.data.commute.station)
            } header: {
                Text("駅")
            } footer: {
                Text("乗換案内で使う駅名です。スクールバスは流山おおたかの森駅⇔大学です。")
            }
            Section("かかる時間（分）") {
                Stepper("自宅の駅 → 森（最短） \(store.data.commute.minGoTravel)分", value: $store.data.commute.minGoTravel, in: 10...120, step: 5)
                Stepper("森：ホーム → バス停 \(store.data.commute.transferGo)分", value: $store.data.commute.transferGo, in: 0...15)
                Stepper("森：バス停 → ホーム \(store.data.commute.transferBack)分", value: $store.data.commute.transferBack, in: 0...15)
                Stepper("バスの乗車 \(store.data.commute.busRide)分", value: $store.data.commute.busRide, in: 1...20)
                Stepper("大学のバス停 → 教室 \(store.data.commute.walk)分", value: $store.data.commute.walk, in: 0...20)
            }
            Section {
                Button("保存した検索結果を消して調べ直す") { store.clearCommuteCache() }
            }
        }
        .navigationTitle("通学の設定")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.refreshCommute() }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
