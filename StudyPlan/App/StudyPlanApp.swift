import SwiftUI
import UserNotifications

@main
struct StudyPlanApp: App {
    @StateObject var store = Store.shared
    @StateObject var router = AppRouter.shared
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environmentObject(store)
                .environmentObject(router)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: store.reload()
                    case .background: store.flush()
                    default: break
                    }
                }
        }
    }
}

struct AppRoot: View {
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-gallery") {
            NavigationStack { WidgetGallery() }
        } else {
            MainTabView()
        }
    }
}

/// 下のタブ：今日・時間割・出席・通学・設定
struct MainTabView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: AppRouter
    @State var importing: ImportSource?

    var body: some View {
        TabView(selection: $router.tab) {
            TodayView()
                .tabItem { Label("今日", systemImage: "sun.max") }
                .tag(MainTab.today)
            WeekView()
                .tabItem { Label("時間割", systemImage: "calendar") }
                .tag(MainTab.week)
            AttendView()
                .tabItem { Label("出席", systemImage: "checkmark.circle") }
                .tag(MainTab.attend)
            CommuteView()
                .tabItem { Label("通学", systemImage: "bus") }
                .tag(MainTab.commute)
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        // ウィジェットから開いたとき（studyplan://today・studyplan://attend など）
        .onOpenURL { url in
            guard url.scheme == "studyplan" else { return }
            switch url.host {
            case "week": router.tab = .week
            case "courses": router.tab = .week; router.showCourses = true
            case "attend": router.tab = .attend; router.attendMode = .register
            case "status": router.tab = .attend; router.attendMode = .status
            case "commute": router.tab = .commute
            case "settings": router.tab = .settings
            case "import": importing = .portal
            default: router.tab = .today
            }
        }
        .sheet(item: $importing) { source in
            ImportView(source: source)
        }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-import") { importing = .portal }
        }
        .task {
            // 出席登録の結果をウィジェットから通知するため
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await AttendanceStore.shared.refreshIfStale()
        }
    }
}
