import SwiftUI
import SafariServices

/// 通学：スクールバス × 電車 × 時間割の乗り継ぎ
struct CommuteView: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) var scheme
    @State var showPage = false

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
                        NextBusRow(title: "大学発 → おおたかの森", times: bus.next(bus.toStation, after: minutes), now: minutes)
                        NextBusRow(title: "おおたかの森発 → 大学", times: bus.next(bus.toUniv, after: minutes), now: minutes)
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
                NavigationLink {
                    BusTimetableView()
                } label: {
                    SettingsLabel(title: "スクールバス時刻表", systemName: "tablecells", color: .green)
                }
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
                                .foregroundStyle(i == 0 ? CommuteColors.bus : Color.primary)
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
struct BusTimetableView: View {
    @State var date = Clock.now
    @State var toUniv = false
    @State var day: BusDay?
    @State var error: String?

    var body: some View {
        List {
            Section {
                DatePicker("日付", selection: $date, displayedComponents: .date)
                Picker("方向", selection: $toUniv) {
                    Text("大学発").tag(false)
                    Text("おおたかの森発").tag(true)
                }
                .pickerStyle(.segmented)
            } footer: {
                if let day { Text(day.dia) }
            }

            if let error {
                Section { Text(error).foregroundStyle(.secondary) }
            } else if let day {
                if !day.running {
                    Section { Text("この日はバスの運行がありません").foregroundStyle(.secondary) }
                } else if day.unknown {
                    Section { Text("\(day.dia)の時刻は大学のページで確認してください").foregroundStyle(.secondary) }
                } else {
                    let list = toUniv ? day.toUniv : day.toStation
                    let hours = Array(Set(list.map { $0 / 60 })).sorted()
                    let isToday = JST.isSameDay(date, Clock.now)
                    let nowMin = JST.minutes(Clock.now)
                    Section(toUniv ? "おおたかの森駅 → 大学" : "大学 → おおたかの森駅") {
                        ForEach(hours, id: \.self) { h in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(h)")
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .frame(width: 30, alignment: .trailing)
                                Text(list.filter { $0 / 60 == h }.map { String(format: "%02d", $0 % 60) }.joined(separator: "  "))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(isToday && h < nowMin / 60 ? Color.secondary : Color.primary)
                            }
                        }
                    }
                }
            } else {
                Section { ProgressView() }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("スクールバス時刻表")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: date) { await load() }
    }

    private func load() async {
        if Store.isDemo {
            day = Sample.commutePlan().bus
            return
        }
        do {
            day = try await BusSource.day(date)
            error = nil
        } catch {
            self.error = "バス時刻表を取得できません"
        }
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
