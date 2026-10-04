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
}
