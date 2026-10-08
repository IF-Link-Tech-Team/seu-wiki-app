import SwiftUI
import UIKit

/// 整个 App 生命周期里**最早**的可挂钩点。
///
/// 存在的唯一理由是装 `UNUserNotificationCenterDelegate`：冷启动点开提醒通知时，
/// 系统交付点击回调发生在 `App.init()` **之后**，那时 delegate 还是 nil，
/// 回调会被直接丢弃 —— 表现就是「点了通知只是回到 App，什么都没发生」。
/// `didFinishLaunchingWithOptions` 早于场景建立，是唯一来得及的时机。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ReminderScheduler.shared.install()
        #if DEBUG
        // 放在这里而不是视图层：注入的值在 SwiftUI 视图树建好**之前**就已就位，
        // 正好顺带验了 `RootTabView` 那句 `initial: true`（冷启动点通知的真实时序）。
        NotificationCenterDelegate.applyDebugPush(arguments: ProcessInfo.processInfo.arguments)
        #endif
        return true
    }
}

@main
struct SEUWikiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var profile = UserProfile()
    @State private var feedStore = FeedStore()
    @State private var forumStore = ForumStore()
    /// 登录态单一事实源（AGENTS.md）：各功能 store 不自己判断登录，
    /// 只在这里统一接「登出→清用户态」。登录侧的刷新由各页面 `.task` 负责。
    @State private var auth = AuthStore.shared
    /// 通知点击的下一步去向。`RootTabView` 观察它并清空。
    @State private var notifications = NotificationCenterDelegate.shared
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
            RootTabView(
                initialTab: RootTabView.launchTab,
                deepLinkDoc: RootTabView.launchDoc,
                notifications: notifications
            )
                .environment(profile)
                .environment(feedStore)
                .environment(forumStore)
                .preferredColorScheme(appearance.colorScheme)
                .onChange(of: auth.isLoggedIn) { _, loggedIn in
                    // 登出 → 清空论坛 store 里的上个账号投影（关注关系/关注流/
                    // 列表收藏标记），防换账号串数据。冷启动即登出态时 store 本来
                    // 就是空的，无需 initial: true。
                    if !loggedIn { forumStore.onSignedOut() }
                }
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
                            (
                                id: $0.notificationID,
                                title: $0.title,
                                deadline: $0.dueDate,
                                advanceDays: $0.advanceDays,
                                relatedItemID: $0.relatedItemID
                            )
                        }
                    )
                }
        }
    }
}
