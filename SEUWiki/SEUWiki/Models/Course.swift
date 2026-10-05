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

    /// 逐字段容错解码。
    ///
    /// 用编译器合成的 `Decodable` 时，**任何一个**新增的非可选字段缺失都会让整条记录
    /// 解码失败；配合 `ProfileStorage` 的默认值回退，用户的整学期课表会在一次模型
    /// 改动后静默清空。这里让每个字段都独立降级：加字段不会影响老数据。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) as? String ?? ""
        teacher = (try? c.decodeIfPresent(String.self, forKey: .teacher)) as? String ?? ""
        location = (try? c.decodeIfPresent(String.self, forKey: .location)) as? String ?? ""
        weekday = (try? c.decodeIfPresent(Int.self, forKey: .weekday)) as? Int ?? 1
        startTime = (try? c.decodeIfPresent(DateComponents.self, forKey: .startTime)) as? DateComponents
            ?? DateComponents(hour: 8, minute: 0)
        endTime = (try? c.decodeIfPresent(DateComponents.self, forKey: .endTime)) as? DateComponents
            ?? DateComponents(hour: 9, minute: 40)
    }
}
