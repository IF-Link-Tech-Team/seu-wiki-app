import Foundation
import SwiftUI

/// 全 App 统一的时间显示规则。
///
/// 规则来自 UI/UX 对齐方案 §5：相对时间显示为「3 小时前」「昨天 14:20」「10月5日」。
///
/// **不要再用 `Text(date, style: .relative)`。** 它有两个问题：
/// 1. 输出的是「时长」而不是「多久以前」——没有「前」，语义反了；
/// 2. 工程 `developmentRegion` 之前是 `en` 且没有 `.xcstrings`，中文系统上它会直接
///    吐出英文，实测首页显示成 `6 days`。
///
/// 同样不要用 `Text(date, format: .relative(presentation: .named))` —— 它依赖系统
/// 本地化，且更新粒度由系统决定，我们控制不了「昨天 14:20」这种日界格式。
enum TimeFormat {
    /// 相对时间文案。`now` 显式传入便于测试与 `TimelineView` 驱动。
    static func relative(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)

        // 未来时间不显示「还有 x」这类容易误读的表述，直接给绝对日期。
        if seconds < 0 { return absolute(date, now: now) }

        if seconds < 60 { return "刚刚" }

        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) 分钟前" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时前" }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天 \(time(date))" }
        if calendar.isDateInYesterday(date) { return "昨天 \(time(date))" }

        let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if days < 7 { return "\(days) 天前" }
        return absolute(date, now: now)
    }

    /// 绝对日期：同年只显示月日，跨年才带年份。
    static func absolute(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        if sameYear {
            return date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
        }
        return date.formatted(.dateTime.year().month(.defaultDigits).day(.defaultDigits))
    }

    /// 时分。
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// 完整日期时间，用于详情页的「截止时间」。
    static func deadline(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天 \(time(date))" }
        if calendar.isDateInYesterday(date) { return "昨天 \(time(date))" }
        return "\(absolute(date)) \(time(date))"
    }
}

/// 会自己周期性刷新的相对时间标签。
///
/// 为什么要它：`Date.now` 在 body 里只求值一次，App 长时间挂在前台时倒计时会**停住**。
/// `TimelineView` 让 SwiftUI 定期重新求值 body，倒计时才会走。分钟粒度足够，
/// 也没有必要把它做成可配置项。
struct RelativeTimeText: View {
    let date: Date
    var font: Font = .caption
    var color: Color = .secondary

    var body: some View {
        TimelineView(.everyMinute) { _ in
            Text(TimeFormat.relative(date))
                .font(font)
                .foregroundStyle(color)
        }
    }
}

/// 倒计时专用：随时间自动更新，且对读屏暴露完整语义。
struct CountdownText: View {
    let date: Date
    var font: Font = .title.bold()
    var color: Color = .primary

    var body: some View {
        TimelineView(.everyMinute) { _ in
            Text(TimeFormat.relative(date))
                .font(font)
                .foregroundStyle(color)
                .monospacedDigit()
        }
        // 读屏要读出「还有 7 天」而不是「7 天前」这种主客关系颠倒的话。
        .accessibilityLabel("距离截止 \(TimeFormat.relative(date))")
    }
}
