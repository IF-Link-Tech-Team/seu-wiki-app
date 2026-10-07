import SwiftUI

/// 搜索信源：「全部」聚合三个信源，或限定单一信源。
enum SearchScope: String, CaseIterable, Identifiable, Hashable {
    case all, feed, forum, handbook

    var id: String { rawValue }

    var name: String {
        switch self {
        case .all: "全部"
        case .feed: "通知"
        case .forum: "经验"
        case .handbook: "手册"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "magnifyingglass"
        case .feed: "newspaper"
        case .forum: "bubble.left.and.text.bubble.right"
        case .handbook: "book.closed"
        }
    }

    var tint: Color {
        switch self {
        case .all: Color.accentColor
        case .feed: Color.accentColor
        case .forum: .orange
        case .handbook: .green
        }
    }

    /// 空态「搜索范围」卡片的说明文案。
    var detail: String {
        switch self {
        case .all: ""
        case .feed: "教务、奖助、竞赛、招聘等校园资讯"
        case .forum: "论坛里的经验帖与讨论"
        case .handbook: "东大生存手册的沉淀文章"
        }
    }
}
