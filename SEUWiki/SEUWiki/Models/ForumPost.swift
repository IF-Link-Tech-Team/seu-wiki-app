import Foundation

/// 论坛话题（固定目录制，对应 seu-forum 的 tags catalog：主题 + 子标签）。
struct ForumTopic: Identifiable, Hashable, Codable {
    let id: String            // slug
    var name: String
    var systemImage: String
    var subtags: [String]
    var postCount: Int
}

/// 经验论坛帖子，对应 iflab-forum `posts` 表。
struct ForumPost: Identifiable, Codable, Hashable {
    let id: String
    var authorName: String
    var authorHeadline: String   // 如「19 级 · 保研至清华」
    var title: String
    var excerpt: String
    var tags: [String]           // tag slug 列表，≤3
    var commentsCount: Int
    var likesCount: Int
    var viewsCount: Int
    var createdAt: Date
    var isFeatured: Bool         // 被编辑精选（沉淀到经验）
}

enum ForumFeedTab: String, CaseIterable, Identifiable {
    case hot, following, topics, handbook

    var id: String { rawValue }

    var name: String {
        switch self {
        case .hot: "热门"
        case .following: "关注"
        case .topics: "话题"
        case .handbook: "生存手册"
        }
    }
}
