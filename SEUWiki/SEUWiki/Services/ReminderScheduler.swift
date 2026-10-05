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

    var isGloballyEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
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

    /// 为一条提醒排程通知。同一条提醒重复设定时先撤掉旧的，避免叠加多次提醒。
    func schedule(id: String, title: String, deadline: Date, advanceDays: Int) async {
        guard isGloballyEnabled else { return }
        guard await requestAuthorization() else { return }

        let calendar = Calendar.current
        // 提醒日 = 截止日往前推 N 天；N ≥ 0。N 为 0 表示截止当天提醒。
        let fireDate = calendar.date(byAdding: .day, value: -max(0, advanceDays), to: deadline) ?? deadline
        // 提醒时间取当天的 9:00 —— 学生不会想被凌晨的提醒炸醒。
        var components = calendar.dateComponents([.year, .month, .day], from: fireDate)
        components.hour = 9
        components.minute = 0
        guard let scheduled = calendar.date(from: components) else { return }

        // 已经过去的时间点排程没有意义（系统会直接忽略），不排。
        guard scheduled > .now else {
            cancel(id: id)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "SEU.wiki 提醒"
        content.body = title
        content.sound = .default
        // 点通知直接进 App；不指定的话只会弹个横幅。
        content.userInfo = ["reminderID": id]

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        // 先撤旧的再排新的：用户改了时间或提前量时不能弹两次。
        center.removePendingNotificationRequests(withIdentifiers: [id])
        do {
            try await center.add(request)
        } catch {
            NSLog("[ReminderScheduler] 排程失败：%d", (error as NSError).code)
        }
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
    func reconcile(reminders: [(id: String, title: String, deadline: Date, advanceDays: Int)]) async {
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
                advanceDays: reminder.advanceDays
            )
        }
        // 系统有、界面没有 → 撤掉（用户删了但系统还留着）。
        for id in pendingIDs.subtracting(expected) {
            cancel(id: id)
        }
    }
}
