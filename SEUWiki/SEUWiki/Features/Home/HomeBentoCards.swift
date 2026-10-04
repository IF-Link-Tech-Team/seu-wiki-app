import SwiftUI

/// 主页 bento：最近的提醒（报名截止倒计时）。
struct ReminderCard: View {
    let reminder: CampusReminder?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("提醒", systemImage: "bell.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            if let reminder {
                Text(reminder.daysRemaining > 0 ? "\(reminder.daysRemaining) 天" : "今天")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(reminder.daysRemaining <= 2 ? .red : .primary)
                    .contentTransition(.numericText())
                Text(reminder.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("暂无提醒")
                    .font(.title3.weight(.semibold))
                Text("在资讯详情页可设定提醒")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
    }
}

/// 主页 bento：下一节课（与工具页课表联动）。
struct NextCourseCard: View {
    let course: Course?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("下一节课", systemImage: "calendar.day.timeline.left")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)

            if let course {
                Text(course.timeRangeText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(course.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(course.location)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("今天没课了")
                    .font(.title3.weight(.semibold))
                Text("去工具页查看完整课表")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
    }
}
