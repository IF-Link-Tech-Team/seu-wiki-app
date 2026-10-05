import Foundation

/// 课程表中的一节课（工具页课表与主页「下一节课」联动）。
struct Course: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var teacher: String
    var location: String
    /// 1 = 周一 … 7 = 周日
    var weekday: Int
    var startTime: DateComponents   // 只有时分有效
    var endTime: DateComponents

    init(id: UUID = UUID(), name: String = "", teacher: String = "", location: String = "", weekday: Int = 1, startHour: Int = 8, startMinute: Int = 0, endHour: Int = 9, endMinute: Int = 40) {
        self.id = id
        self.name = name
        self.teacher = teacher
        self.location = location
        self.weekday = weekday
        self.startTime = DateComponents(hour: startHour, minute: startMinute)
        self.endTime = DateComponents(hour: endHour, minute: endMinute)
    }

    var timeRangeText: String {
        func fmt(_ c: DateComponents) -> String {
            String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        return "\(fmt(startTime))–\(fmt(endTime))"
    }
}
