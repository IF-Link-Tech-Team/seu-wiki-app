import Foundation

/// 东大生存手册：分类 → 条目（list 文档结构）。
struct HandbookSection: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var systemImage: String
    var entries: [HandbookEntry]
}

struct HandbookEntry: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var subtitle: String
    var body: String
    var updatedAt: Date
}
