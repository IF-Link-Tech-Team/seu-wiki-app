import Foundation
import UserNotifications

/// 提醒的本地通知调度。
///
/// 早期版本 `advanceDays` 只用来显示文字，工程里**没有任何** `UserNotifications`
/// 代码 —— 用户设好提醒、到期什么都不会发生。这是最严重的一类「界面做完了、
/// 功能没接上」。
///
/// 排程用 `UNCalendarNotificationTrigger`，触发时间由
/// `Calendar.date(byAdding: .day, value: -n, to: deadline)` 算出。
/// **不要**用「减 86400 秒」—— 跨夏令时切换时那会差一小时，提醒就早/晚一小时。
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    private let center = UNUserNotificationCenter.current()
    /// 设置页的「接收通知」总开关。
    private let enabledKey = "settings.notificationsEnabled"

    private init() {}

    /// 装上 [NotificationCenterDelegate]。**必须在 `didFinishLaunchingWithOptions`
    /// 里调用**（见 `SEUWikiApp` 的 `AppDelegate`）：冷启动点通知的回调早于
    /// SwiftUI 的 `App.init()`，那时还没装就丢了。重复调用幂等。
    func install() {
        center.delegate = NotificationCenterDelegate.shared
    }

    var isGloballyEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// 通知携带的 `userInfo`。
    ///
    /// 抽成纯函数是为了能进 [SelfCheck]：key 写错（比如手滑写成 `feedId`）不会
    /// 编译报错，只会让点通知静默地什么都不做 —— 这类错误必须由自检挡住。
    /// 没有关联资讯时**不要**塞空串：delegate 侧 `!itemID.isEmpty` 会挡掉，
    /// 但留着空 key 会让排查时分不清「没有关联」和「关联丢了」。
    nonisolated static func userInfo(id: String, relatedItemID: String?) -> [String: Any] {
        var info: [String: Any] = ["reminderID": id]
        if let relatedItemID, !relatedItemID.isEmpty {
            info[NotificationCenterDelegate.feedItemIDKey] = relatedItemID
        }
        return info
    }

    // MARK: - 授权

    /// 请求通知授权。返回是否已获准。
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            NSLog("[ReminderScheduler] 请求通知授权失败：%d", (error as NSError).code)
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - 排程

    /// 提醒的**实际触发时刻**：截止日往前推 N 天的当天 09:00。
    ///
    /// 抽成纯函数是为了能进 [SelfCheck]。这里有两处容易错的地方：
    ///
    /// 1. **不要用「减 86400 秒」** 往前推天数。夏令时切换那天一天不是 24 小时，
    ///    减出来的时刻会差一小时，提醒就早/晚一小时。用
    ///    `Calendar.date(byAdding: .day:)` 让日历自己处理。
    /// 2. 提醒时间取 **09:00** 而不是截止时刻本身 —— 学生不会想被凌晨的提醒炸醒。
    ///
    /// - Returns: 触发时刻；截止日往前推 N 天后当天 09:00 构不出来时返回 nil。
    nonisolated static func fireDate(
        deadline: Date,
        advanceDays: Int,
        calendar: Calendar = .current
    ) -> Date? {
        // N ≥ 0；N 为 0 表示截止当天提醒。负数当成 0，别往截止日**之后**排。
        let day = calendar.date(byAdding: .day, value: -max(0, advanceDays), to: deadline) ?? deadline
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components)
    }

    /// 为一条提醒排程通知。同一条提醒重复设定时先撤掉旧的，避免叠加多次提醒。
    func schedule(
        id: String,
        title: String,
        deadline: Date,
        advanceDays: Int,
        relatedItemID: String? = nil
    ) async {
        guard isGloballyEnabled else { return }
        guard await requestAuthorization() else { return }

        let calendar = Calendar.current
        guard let scheduled = Self.fireDate(deadline: deadline, advanceDays: advanceDays, calendar: calendar) else { return }
        // UNCalendarNotificationTrigger 要的是「日历分量」而不是绝对时刻。
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduled)

        // 已经过去的时间点排程没有意义（系统会直接忽略），不排。
        guard scheduled > .now else {
            cancel(id: id)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "SEU.wiki 提醒"
        content.body = title
        content.sound = .default
        // 点通知直接进 App 对应那条资讯；不指定的话只会弹个横幅然后停在主页。
        content.userInfo = Self.userInfo(id: id, relatedItemID: relatedItemID)

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        // 先撤旧的再排新的：用户改了时间或提前量时不能弹两次。
        center.removePendingNotificationRequests(withIdentifiers: [id])
        do {
            try await center.add(request)
            NSLog("[ReminderScheduler] 已排程「%@」，%@ 触发", title, Self.describe(scheduled))
        } catch {
            NSLog("[ReminderScheduler] 排程失败：%d", (error as NSError).code)
        }
    }

    private static func describe(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm ZZZZZ"
        return formatter.string(from: date)
    }

    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    /// 关闭总开关时撤掉全部排程；重新打开时不必重排 —— 下次编辑提醒会重新排。
    func setGloballyEnabled(_ enabled: Bool) {
        if !enabled { cancelAll() }
    }

    /// 冷启动时对账：把 UserDefaults 里的提醒与系统里待触发的通知对齐。
    ///
    /// 必要场景：App 被系统清理待处理通知、或用户手动在系统设置里清过通知。
    /// 没有这一步，界面显示「有提醒」但系统里其实一条都没排。
    func reconcile(reminders: [(id: String, title: String, deadline: Date, advanceDays: Int, relatedItemID: String?)]) async {
        guard isGloballyEnabled else { return }
        guard await authorizationStatus() == .authorized else { return }

        let pending = await center.pendingNotificationRequests()
        let pendingIDs = Set(pending.map(\.identifier))
        let expected = Set(reminders.map(\.id))
        // 界面有、系统没有 → 补排。
        for reminder in reminders where !pendingIDs.contains(reminder.id) {
            await schedule(
                id: reminder.id,
                title: reminder.title,
                deadline: reminder.deadline,
                advanceDays: reminder.advanceDays,
                relatedItemID: reminder.relatedItemID
            )
        }
        // 系统有、界面没有 → 撤掉（用户删了但系统还留着）。
        for id in pendingIDs.subtracting(expected) {
            cancel(id: id)
        }
    }
}
