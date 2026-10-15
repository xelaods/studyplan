import SwiftUI
import WebKit

/// 設定アプリのような画面
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State var importing: ImportSource?
    @State var confirmDeleteAll = false
    @State var confirmLogout = false
    @State var loggedOut = false

    var body: some View {
        NavigationStack {
            Form {
                EdohenAccountSection()

                Section {
                    Picker(selection: $store.data.termMode) {
                        Text("自動（今は\(TermMode.auto.resolve(on: Clock.now).label)）").tag(TermMode.auto)
                        Text("前期").tag(TermMode.first)
                        Text("後期").tag(TermMode.second)
                    } label: {
                        SettingsLabel(title: "表示する学期", systemName: "calendar", color: .red)
                    }
                } footer: {
                    Text("自動では4〜9月を前期、10〜3月を後期として表示します。")
                }

                Section("時間割") {
                    Toggle(isOn: $store.data.showSaturday) {
                        SettingsLabel(title: "土曜日を表示", systemName: "6.square", color: .blue)
                    }
                    Picker(selection: $store.data.periodCount) {
                        ForEach(4...PeriodTime.maxCount, id: \.self) { n in
                            Text("\(n)限まで").tag(n)
                        }
                    } label: {
                        SettingsLabel(title: "表示する時限", systemName: "list.number", color: .orange)
                    }
                    NavigationLink {
                        PeriodTimesView()
                    } label: {
                        SettingsLabel(title: "時限の時間", systemName: "clock", color: .teal)
                    }
                }

                Section {
                    Button { importing = .portal } label: {
                        SettingsLabel(title: "エドポタから取り込む", systemName: "square.and.arrow.down", color: .blue)
                    }
                    Button { importing = .syllabus } label: {
                        SettingsLabel(title: "Webシラバスで探す", systemName: "magnifyingglass", color: .indigo)
                    }
                    Button { confirmLogout = true } label: {
                        SettingsLabel(title: "エドポタからログアウト", systemName: "rectangle.portrait.and.arrow.right", color: .gray)
                    }
                } header: {
                    Text("授業の取得")
                } footer: {
                    Text(loggedOut ? "アプリ内のブラウザのログイン情報を消去しました。" :
                            "IDとパスワードはこのアプリには保存されません。ログインの状態はアプリ内のブラウザにだけ残ります。")
                }

                Section {
                    widgetStatus
                    if !SharedStore.isShared {
                        if !store.calendarAccess {
                            Button {
                                Task { await store.requestCalendarAccess() }
                            } label: {
                                SettingsLabel(title: "カレンダーへのアクセスを許可", systemName: "calendar.badge.checkmark", color: .red)
                            }
                        } else {
                            Toggle(isOn: Binding(get: { CalendarBridge.enabled }, set: { store.setCalendarBridge($0) })) {
                                SettingsLabel(title: "カレンダー経由で渡す", systemName: "calendar", color: .red)
                            }
                        }
                    }
                    NavigationLink {
                        WidgetGallery()
                    } label: {
                        SettingsLabel(title: "ウィジェットの見本", systemName: "square.grid.2x2", color: .purple)
                    }
                    NavigationLink {
                        AttendWidgetHelpView()
                    } label: {
                        SettingsLabel(title: "出席登録ウィジェットの使い方", systemName: "number.square", color: .green)
                    }
                } header: {
                    Text("ウィジェット")
                } footer: {
                    if SharedStore.isShared {
                        Text("App Group でウィジェットと共有しています。")
                    } else {
                        Text("署名に App Group が入っていないため、カレンダーの2001年1月3日に時間割のメモを1件だけ保存してウィジェットに渡します（Shift Note・MoneyPlan と同じ方法）。ほかの予定には触れません。")
                    }
                }

                Section {
                    Button("時間割の授業をすべて削除", role: .destructive) {
                        confirmDeleteAll = true
                    }
                    .disabled(store.data.courses.isEmpty)
                }

                Section {
                    LabeledContent("バージョン", value: version)
                } footer: {
                    Text("江戸川大学の時限（1限 9:00〜 / 5限 〜18:30）に合わせています。")
                }
            }
            .navigationTitle("設定")
            .sheet(item: $importing) { ImportView(source: $0) }
            .confirmationDialog("時間割の授業をすべて削除しますか？", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("すべて削除", role: .destructive) { store.removeAll() }
            }
            .confirmationDialog("アプリ内のブラウザのログイン情報（Cookie）を消去しますか？", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("消去する", role: .destructive) {
                    let types = WKWebsiteDataStore.allWebsiteDataTypes()
                    WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
                        loggedOut = true
                    }
                }
            }
        }
    }

    private var widgetStatus: some View {
        HStack {
            SettingsLabel(title: "状態", systemName: "checkmark.seal", color: .green)
            Spacer()
            Text(statusText).foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if SharedStore.isShared { return "共有中" }
        if store.calendarAccess { return CalendarBridge.enabled ? "カレンダー経由" : "オフ" }
        return "未設定"
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v)（\(b)）"
    }
}

/// 時限の時間を変える
struct PeriodTimesView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            ForEach(store.data.periods.indices, id: \.self) { i in
                Section("\(store.data.periods[i].number)限") {
                    DatePicker("開始", selection: timeBinding(i, start: true), displayedComponents: .hourAndMinute)
                    DatePicker("終了", selection: timeBinding(i, start: false), displayedComponents: .hourAndMinute)
                }
            }
            Section {
                Button("江戸川大学の時間に戻す") {
                    store.data.periods = PeriodTime.edogawa
                }
            } footer: {
                Text("1〜5限は大学の時間です。6・7限は目安なので、必要なら変えてください。")
            }
        }
        .navigationTitle("時限の時間")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeBinding(_ i: Int, start: Bool) -> Binding<Date> {
        let base = JST.startOfDay(Date())
        return Binding(
            get: {
                let p = store.data.periods[i]
                return JST.date(base, minutes: start ? p.start : p.end)
            },
            set: { date in
                let m = JST.minutes(date)
                if start { store.data.periods[i].start = m } else { store.data.periods[i].end = m }
            })
    }
}

/// ウィジェットの見本（見本のデータで表示）
struct WidgetGallery: View {
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let schedule = Store.isDemo ? Store.shared.schedule : Sample.snapshot().schedule
        let now = Clock.fixed ?? Sample.previewNow
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("ホーム画面")
                    .font(.headline)
                HStack(spacing: 16) {
                    tile(width: 170, height: 170) { NextClassWidgetView(schedule: schedule, now: now, family: .systemSmall) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("次の授業").font(.subheadline.weight(.semibold))
                        Text("授業中は残り時間とバー").font(.caption).foregroundStyle(.secondary)
                    }
                }
                tile(width: 364, height: 170) { TodayWidgetView(schedule: schedule, now: now, family: .systemMedium) }
                tile(width: 364, height: 170) { BusWidgetView(day: Sample.commutePlan().bus, message: nil, now: now, family: .systemMedium) }
                HStack(spacing: 16) {
                    tile(width: 170, height: 170) { BusWidgetView(day: Sample.commutePlan().bus, message: nil, now: now, family: .systemSmall) }
                    tile(width: 170, height: 170) {
                        BusWidgetView(day: BusDay(date: now, diaKey: "Oct10", dia: "特別ダイヤ", toUniv: [], toStation: [], unknown: true),
                                      message: nil, now: now, family: .systemSmall)
                    }
                }
                tile(width: 364, height: 382) { WeekWidgetView(schedule: schedule, now: now) }
                CommuteWidgetView(plan: Sample.commutePlan(), settings: CommuteSettings(), now: now, family: .systemLarge)
                    .padding(14)
                    .frame(width: 364, height: 382)
                    .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.secondary.opacity(0.2)))
                tile(width: 364, height: 382) { TodayWidgetView(schedule: schedule, now: now, family: .systemLarge) }

                Text("ロック画面")
                    .font(.headline)
                    .padding(.top, 6)
                HStack(spacing: 12) {
                    accessory(width: 170, height: 72) { NextClassWidgetView(schedule: schedule, now: now, family: .accessoryRectangular) }
                    accessory(width: 72, height: 72) { NextClassWidgetView(schedule: schedule, now: now, family: .accessoryCircular) }
                }
                accessory(width: 260, height: 26) { NextClassWidgetView(schedule: schedule, now: now, family: .accessoryInline) }

                Text("ホーム画面を長押し →「編集」→「ウィジェットを追加」→「時間割」から追加できます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("ウィジェット")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile<V: View>(width: CGFloat, height: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(16)
            .frame(width: width, height: height)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 8, y: 2)
    }

    private func accessory<V: View>(width: CGFloat, height: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: width, height: height)
            .padding(8)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
    }
}
