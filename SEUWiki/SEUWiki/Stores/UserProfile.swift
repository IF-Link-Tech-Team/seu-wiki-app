import Foundation
import SwiftUI

/// 用户画像与本地的 app 级状态。学院/学段/年级/兴趣对应 seu-wiki-v2 的 for-you 画像参数。
/// 所有可变属性在写入侧自动持久化到 UserDefaults（见 ProfileStorage），调用方无感知。
@Observable
final class UserProfile {
    static let defaultCollege = "信息科学与工程学院"
    static let defaultDegree = "本科"
    static let defaultGrade = "大三"
    static let defaultInterests: [String] = ["保研", "SRTP", "机器学习"]
    static let defaultFollowedTopicIDs: Set<String> = ["baoyan", "srtp"]

    @ObservationIgnored
    private let defaults: UserDefaults

    var college = UserProfile.defaultCollege { didSet { persist(college, for: .college) } }
    var degree = UserProfile.defaultDegree { didSet { persist(degree, for: .degree) } }
    var grade = UserProfile.defaultGrade { didSet { persist(grade, for: .grade) } }
    var interests = UserProfile.defaultInterests { didSet { persist(interests, for: .interests) } }

    var reminders: [CampusReminder] = MockData.reminders { didSet { persist(reminders, for: .reminders) } }
    var courses: [Course] = MockData.courses { didSet { persist(courses, for: .courses) } }
    var followedTopicIDs = UserProfile.defaultFollowedTopicIDs { didSet { persist(followedTopicIDs, for: .followedTopicIDs) } }
    var bookmarkedPostIDs: Set<String> = [] { didSet { persist(bookmarkedPostIDs, for: .bookmarkedPostIDs) } }

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
            if let v = ProfileStorage.load(Set<String>.self, for: .followedTopicIDs, defaults: defaults) { followedTopicIDs = v }
            if let v = ProfileStorage.load(Set<String>.self, for: .bookmarkedPostIDs, defaults: defaults) { bookmarkedPostIDs = v }
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

    /// 重置为默认：清空持久化 key 并恢复 MockData 初始值（didSet 会重新落盘）。
    func resetToDefaults() {
        ProfileStorage.reset(defaults: defaults)
        ProfileStorage.markInitialized(defaults: defaults)
        college = UserProfile.defaultCollege
        degree = UserProfile.defaultDegree
        grade = UserProfile.defaultGrade
        interests = UserProfile.defaultInterests
        reminders = MockData.reminders
        courses = MockData.courses
        followedTopicIDs = UserProfile.defaultFollowedTopicIDs
        bookmarkedPostIDs = []
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
        persist(followedTopicIDs, for: .followedTopicIDs)
        persist(bookmarkedPostIDs, for: .bookmarkedPostIDs)
    }
}
