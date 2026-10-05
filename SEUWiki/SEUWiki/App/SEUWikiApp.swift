import SwiftUI

@main
struct SEUWikiApp: App {
    @State private var profile = UserProfile()
    @State private var feedStore = FeedStore()
    /// 外观偏好存在 AppStorage，由这里读出来应用到整棵视图树。
    /// 早期版本个人页里的「外观」开关只写不读，拨了没有任何反应（I-10）。
    @AppStorage("settings.appearance") private var appearance: AppAppearance = .system

    init() {
        #if DEBUG
        // 启动即跑一遍关键纯逻辑自检（日期解析 / 分页去重 / 绩点 / 对比度 / 持久化）。
        // 这两端此前都是零测试，而这些正是历次事故高发区。
        SelfCheck.runAll()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(initialTab: RootTabView.launchTab)
                .environment(profile)
                .environment(feedStore)
                .preferredColorScheme(appearance.colorScheme)
                .onOpenURL { url in
                    #if DEBUG
                    AuthStore.shared.handleDebugURL(url)
                    #endif
                }
                .task {
                    // 冷启动对账：把系统里待触发的通知与本机提醒列表对齐。
                    // 否则界面显示「有提醒」但系统里一条都没排（系统清理过、或用户手动清过）。
                    await ReminderScheduler.shared.reconcile(
                        reminders: profile.reminders.map {
                            (id: $0.notificationID, title: $0.title, deadline: $0.dueDate, advanceDays: $0.advanceDays)
                        }
                    )
                }
        }
    }
}
