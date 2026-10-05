import Foundation
import UserNotifications

/// `UNUserNotificationCenter` 的 delegate。
///
/// **这个类型早期版本根本不存在。** [ReminderScheduler] 照常把提醒排进了系统队列、
/// `userInfo` 也写好了 `reminderID`，但没有任何 delegate 去接，于是：
///
/// 1. **App 在前台时提醒不会弹。** iOS 的默认行为是「App 在前台就静默丢弃通知」，
///    必须实现 `willPresent` 才有横幅和声音。而学生设提醒的典型场景恰恰是
///    「我正开着 App 写作业」—— 这条提醒看上去完全没生效。
/// 2. **点通知没有任何反应。** `userInfo` 写了却没人读，点下去只是把 App 切到
///    前台并停在当前页面，用户无从知道这条通知在说哪条资讯。
///
/// Android 侧的对应实现是 `ReminderReceiver` 的 `contentIntent` +
/// `MainActivity` 的 `EXTRA_OPEN_ITEM_ID` 深链，两端行为现已对齐。
///
/// **必须由 `AppDelegate.application(_:didFinishLaunchingWithOptions:)` 装上**
/// （见 `SEUWikiApp`），不能等到 SwiftUI 的 `App.init()`：冷启动点通知时，
/// 系统交付点击回调发生在 `App.init()` 之后，那时 delegate 还是 nil，回调就丢了。
@Observable
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// 单例：`UNUserNotificationCenter.delegate` 是 **weak** 引用，
    /// 必须有人一直持有这个实例，否则置空之后所有回调静默消失。
    nonisolated static let shared = NotificationCenterDelegate()

    /// 本工程的构建开了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，合成的
    /// 初始化器会带上 MainActor 隔离，于是上面那行 `nonisolated static let`
    /// 就成了「在非隔离上下文里造一个 MainActor 对象」而编译不过。
    /// 显式声明非隔离初始化器把它解开 —— 单例本身没有可变的隔离状态。
    nonisolated override init() {
        super.init()
    }

    /// `userInfo` 里携带「这条提醒属于哪条资讯」的 key。
    /// 排程侧见 [ReminderScheduler.userInfo(id:relatedItemID:)]。
    nonisolated static let feedItemIDKey = "feedItemID"

    /// 点提醒通知后要打开的资讯 id。由 [RootTabView] 消费后清空。
    ///
    /// 冷启动时 delegate 收到点击早于 SwiftUI 视图树建好，所以先存着等视图来取 ——
    /// 与 Android `pendingFeedItemId` 是同一套做法。
    private(set) var pendingFeedItemID: String?

    /// 消费后必须清空，否则视图重建时 `onChange` 会把用户反复拽回同一个详情页。
    func consumePendingFeedItemID() {
        pendingFeedItemID = nil
    }

    /// App 在前台时照常弹横幅。
    ///
    /// 不返回 `.banner` 的话系统会**直接丢掉**这条通知，用户在设提醒的当场
    /// 什么反馈都收不到。抽成静态常量是为了让自检能挡住「被改成 `[]` 或
    /// `.badge`」这种回归 —— 它正是本 bug 的成因。
    nonisolated static let foregroundPresentation: UNNotificationPresentationOptions = [.banner, .list, .sound]

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.foregroundPresentation
    }

    /// 点开通知 → 记下要打开的资讯。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // 划掉通知也会走到这里；只有真的点开才导航。
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        // 先在非隔离侧把 `userInfo` 解成 String 再跳：`[AnyHashable: Any]` 不是
        // Sendable，整个字典跨隔离边界传会被 Swift 6 的严格并发拦下。
        guard let itemID = Self.feedItemID(from: response.notification.request.content.userInfo) else { return }
        await open(itemID)
    }

    /// 通知 `userInfo` → 待打开的资讯 id。
    ///
    /// 系统回调的 `didReceive` 和 Debug 注入（`-uipush`）都走这里，
    /// 免得测的是一条平行的假路径。
    func handle(userInfo: [AnyHashable: Any]) {
        guard let itemID = Self.feedItemID(from: userInfo) else { return }
        pendingFeedItemID = itemID
    }

    private func open(_ itemID: String) {
        pendingFeedItemID = itemID
    }

    /// 从 `userInfo` 里取资讯 id。空串与缺失都当「没有」，绝不返回空 id ——
    /// 空 id 会让详情页拿着空字符串去请求。
    nonisolated static func feedItemID(from userInfo: [AnyHashable: Any]) -> String? {
        guard let raw = userInfo[feedItemIDKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    #if DEBUG
    /// Debug 专用：`-uipush <feedItemID>` 模拟一次「点开提醒通知」。
    ///
    /// 存在的理由和 `-uitab` / `-uidoc` 一样：**本机模拟器是无头的**，
    /// `Simulator.app` 不在 Xcode 包里、没有合成点击能力，真实通知横幅
    /// 弹出来也没法点。没有这个开关就验证不了「点通知 → 落到那条资讯」
    /// 这条链路，而它恰恰是提醒功能做不做得完的最后一环。
    ///
    /// 走的是 [handle(userInfo:)] —— 与系统回调**同一个入口**，只把
    /// 「用户点了」这一步换成启动参数注入。Release 构建里整个分支不存在。
    static func applyDebugPush(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-uipush"), index + 1 < arguments.count else { return }
        let itemID = arguments[index + 1]
        guard !itemID.isEmpty else { return }
        shared.handle(userInfo: [feedItemIDKey: itemID])
        NSLog("[Debug] 注入通知点击：feedItemID=%@", itemID)
    }
    #endif
}
