import Foundation
import SwiftUI

/// 用户画像与本地的 app 级状态。学院/学段/年级/兴趣原先是 for-you 画像参数；
/// 网页端 for-you 已下线（2026-10-08 信息架构重构），资讯流不再消费画像，
/// 数据保留在本机供其他功能使用。
/// 所有可变属性在写入侧自动持久化到 UserDefaults（见 ProfileStorage），调用方无感知。
@Observable
final class UserProfile {
    static let defaultCollege = "信息科学与工程学院"
    static let defaultDegree = "本科"
    static let defaultGrade = "大三"
    static let defaultInterests: [String] = ["保研", "SRTP", "机器学习"]

    @ObservationIgnored
    private let defaults: UserDefaults

    var college = UserProfile.defaultCollege { didSet { persist(college, for: .college) } }
    var degree = UserProfile.defaultDegree { didSet { persist(degree, for: .degree) } }
    var grade = UserProfile.defaultGrade { didSet { persist(grade, for: .grade) } }
    var interests = UserProfile.defaultInterests { didSet { persist(interests, for: .interests) } }

    /// 提醒与课表默认**为空**。
    ///
    /// 早期版本默认塞了「信号与系统」课程和「推免申请材料提交截止」提醒，于是首次启动的
    /// 用户一打开就看到自己从没添加过的内容，还被当成真实数据写进了 UserDefaults。
    /// 演示数据只能在 `#if DEBUG` 下由 Preview 注入，不能进生产默认值。
    var reminders: [CampusReminder] = [] { didSet { persist(reminders, for: .reminders) } }
    var courses: [Course] = [] { didSet { persist(courses, for: .courses) } }
    // 关注关系全部走论坛服务端（`GET/POST/DELETE /api/follows`），不再存本地
    // `followedTopicIDs` —— 本地默认值曾是假数据（用户从没关注过 baoyan/srtp）。
    var bookmarkedSlugs: Set<String> = [] { didSet { persist(bookmarkedSlugs, for: .bookmarkedSlugs) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProfileStorage.isInitialized(defaults: defaults) {
            // 已初始化：从持久化恢复；个别 key 缺失时回退默认值。
            if let v = ProfileStorage.load(String.self, for: .college, defaults: defaults) { college = v }
            if let v = ProfileStorage.load(String.self, for: .degree, defaults: defaults) { degree = v }
            if let v = ProfileStorage.load(String.self, for: .grade, defaults: defaults) { grade = v }
            if let v = ProfileStorage.load([String].self, for: .interests, defaults: defaults) { interests = v }
            if let v = ProfileStorage.load([CampusReminder].self, for: .reminders, defaults: defaults) { reminders = v }
            if let v = ProfileStorage.load([Course].self, for: .courses, defaults: defaults) { courses = v }
            if let v = ProfileStorage.load(Set<String>.self, for: .bookmarkedSlugs, defaults: defaults) { bookmarkedSlugs = v }
        } else {
            // 首次启动：把默认值落盘并写入初始化标记。
            saveAll()
            ProfileStorage.markInitialized(defaults: defaults)
        }
    }

    /// 主页「下一节课」：今天剩余课程中最近的一节。
    var nextCourse: Course? {
        let now = Date.now
        let weekday = Calendar.current.component(.weekday, from: now) // 1=周日
        let mapped = weekday == 1 ? 7 : weekday - 1
        let nowMinutes = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
        return courses
            .filter { $0.weekday == mapped && ($0.endTime.hour ?? 0) * 60 + ($0.endTime.minute ?? 0) > nowMinutes }
            .min { a, b in
                (a.startTime.hour ?? 0) * 60 + (a.startTime.minute ?? 0) < (b.startTime.hour ?? 0) * 60 + (b.startTime.minute ?? 0)
            }
    }

    /// 主页提醒卡要显示的那条：**最近的、尚未过期的**提醒。
    ///
    /// 早期版本直接取 `reminders.min { $0.dueDate < $1.dueDate }`，已过期的提醒会被算进来，
    /// 天数为负时又落进「今天」分支，于是过期一周的提醒仍然显示「今天」——
    /// 明显错误的主张比不显示更糟。
    var nextPendingReminder: CampusReminder? {
        let now = Date.now
        return reminders
            .filter { $0.dueDate >= now }
            .min { $0.dueDate < $1.dueDate }
    }

    /// 已过期但还没删掉的提醒，个人页里要单独标成「已过期」。
    var expiredReminders: [CampusReminder] {
        let now = Date.now
        return reminders.filter { $0.dueDate < now }.sorted { $0.dueDate < $1.dueDate }
    }

    /// 画像参数（原 for-you 接口的 `parseForYouProfile` 读的就是这四个）。
    ///
    /// for-you 接口已随网页端 2026-10-08 重构下线，这组参数当前没有网络消费方，
    /// 保留它是为了让 [profileFingerprint] 仍能作为「画像是否变化」的标识。
    var forYouParams: [(String, String)] {
        var params: [(String, String)] = []
        if !college.isEmpty { params.append(("college", college)) }
        if !degree.isEmpty { params.append(("degree", degree)) }
        if !grade.isEmpty { params.append(("grade", grade)) }
        if !interests.isEmpty { params.append(("interests", interests.joined(separator: ","))) }
        return params
    }

    /// 画像指纹：画像内容一变指纹就变。原用于 for-you cursor 失效判定；
    /// for-you 下线后保留为通用的画像变更标识（SelfCheck 有断言覆盖）。
    var profileFingerprint: String {
        forYouParams.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    /// 重置为默认：清空持久化 key 并恢复默认值（didSet 会重新落盘）。
    func resetToDefaults() {
        ProfileStorage.reset(defaults: defaults)
        ProfileStorage.markInitialized(defaults: defaults)
        college = UserProfile.defaultCollege
        degree = UserProfile.defaultDegree
        grade = UserProfile.defaultGrade
        interests = UserProfile.defaultInterests
        reminders = []
        courses = []
        bookmarkedSlugs = []
    }

    private func persist(_ value: some Encodable, for key: ProfileStorage.Key) {
        ProfileStorage.save(value, for: key, defaults: defaults)
    }

    private func saveAll() {
        persist(college, for: .college)
        persist(degree, for: .degree)
        persist(grade, for: .grade)
        persist(interests, for: .interests)
        persist(reminders, for: .reminders)
        persist(courses, for: .courses)
        persist(bookmarkedSlugs, for: .bookmarkedSlugs)
    }
}
