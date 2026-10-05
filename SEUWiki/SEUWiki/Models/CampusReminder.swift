import Foundation

/// 用户设定的提醒（报名截止等），在资讯详情页创建。
struct CampusReminder: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var dueDate: Date
    var advanceDays: Int       // 提前几天提醒
    var note: String
    var relatedItemID: String? // 来源资讯

    init(id: UUID = UUID(), title: String, dueDate: Date, advanceDays: Int = 1, note: String = "", relatedItemID: String? = nil) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.advanceDays = advanceDays
        self.note = note
        self.relatedItemID = relatedItemID
    }

    var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: dueDate)).day ?? 0
    }

    /// 是否已过期。
    var isExpired: Bool { dueDate < Date.now }

    /// 系统通知的 request identifier。**必须由这里单点生成** ——
    /// 设定、删除、冷启动对账三处都要用同一个 id，改了提醒时间才能覆盖旧排程。
    var notificationID: String { "seuwiki-reminder-\(id.uuidString)" }

    /// 逐字段容错解码。原因见 `Course.init(from:)`：合成 `Decodable` 下新增一个
    /// 非可选字段就会让**所有**老提醒一起解不出来，而上层会立刻用默认值覆盖写回，
    /// 用户的提醒就此消失。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) as? String ?? "提醒"
        dueDate = (try? c.decodeIfPresent(Date.self, forKey: .dueDate)) as? Date ?? .now
        advanceDays = (try? c.decodeIfPresent(Int.self, forKey: .advanceDays)) as? Int ?? 1
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) as? String ?? ""
        relatedItemID = (try? c.decodeIfPresent(String.self, forKey: .relatedItemID)) as? String
    }
}
