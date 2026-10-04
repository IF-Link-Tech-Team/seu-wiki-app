import Foundation
import SwiftUI

/// 用户画像与本地的 app 级状态。学院/学段/年级/兴趣对应 seu-wiki-v2 的 for-you 画像参数。
@Observable
final class UserProfile {
    var college = "信息科学与工程学院"
    var degree = "本科"
    var grade = "大三"
    var interests: [String] = ["保研", "SRTP", "机器学习"]

    var reminders: [CampusReminder] = MockData.reminders
    var courses: [Course] = MockData.courses
    var followedTopicIDs: Set<String> = ["baoyan", "srtp"]
    var bookmarkedPostIDs: Set<String> = []

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
}
