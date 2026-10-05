import SwiftUI

/// 主页 bento：最近的**未过期**提醒（报名截止倒计时）。
///
/// 早期版本直接 `min { $0.dueDate < $1.dueDate }`，过期提醒会被选中、天数变负
/// 又落进「今天」分支。现在只显示未过期的，过期的在个人页单列。
struct ReminderCard: View {
    let reminder: CampusReminder?
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label("提醒", systemImage: "bell.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)

                if let reminder {
                    CountdownText(
                        date: reminder.dueDate,
                        font: .system(.largeTitle, design: .rounded, weight: .bold),
                        color: reminder.daysRemaining <= 2 ? .red : .primary
                    )
                    Text(reminder.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("暂无提醒")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("在资讯详情页可设定提醒")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityLabel(reminder.map { "提醒：\($0.title)" } ?? "暂无提醒")
    }
}

/// 主页 bento：下一节课（与工具页课表联动）。点进去直达课表。
struct NextCourseCard: View {
    let course: Course?
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label("下一节课", systemImage: "calendar.day.timeline.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)

                if let course {
                    Text(course.timeRangeText)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(course.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(course.location)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("今天没课了")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("去工具页查看完整课表")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityLabel(course.map { "下一节课：\($0.name) \($0.timeRangeText)" } ?? "今天没课了")
    }
}
