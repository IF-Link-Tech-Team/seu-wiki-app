import Foundation

/// 资讯分类，对应 seu-wiki-v2 `industry/taxonomy.ts` 的 8 个 CATEGORIES。
enum FeedCategory: String, CaseIterable, Identifiable, Codable {
    case academic, aid, competition, exchange, career, club, life, news

    var id: String { rawValue }

    var name: String {
        switch self {
        case .academic: "教务"
        case .aid: "奖助"
        case .competition: "竞赛科研"
        case .exchange: "交流升学"
        case .career: "实习就业"
        case .club: "社团活动"
        case .life: "生活服务"
        case .news: "校园新闻"
        }
    }

    var systemImage: String {
        switch self {
        case .academic: "building.columns"
        case .aid: "gift"
        case .competition: "trophy"
        case .exchange: "airplane"
        case .career: "briefcase"
        case .club: "person.3"
        case .life: "fork.knife"
        case .news: "newspaper"
        }
    }
}

/// 校园受众语义，对应 seu-wiki-v2 `CampusAudience`。
struct CampusAudience: Codable, Hashable {
    var identities: [String] = []   // 本科生 / 硕士生 / 博士生
    var colleges: [String] = []     // 空或含「全校」表示面向全校
    var grades: [String] = []       // 大一 … 大四
    var deadline: Date?             // 报名截止
    var valueTier: ValueTier = .news

    enum ValueTier: String, Codable {
        case action, opportunity, news
    }
}

/// 一条资讯，对应 seu-wiki-v2 `FeedItemSummary`（/api/site/timeline、/api/site/for-you）。
struct FeedItem: Identifiable, Codable, Hashable {
    let id: String
    var title: String          // AI 改写的中文标题
    var summary: String        // AI 摘要
    var sourceName: String     // 信源（如「教务处」「信息科学与工程学院」）
    var category: FeedCategory
    var tags: [String]
    var publishedAt: Date
    var originalURL: URL?
    var score: Int             // 0–100 精选分
    var isSelected: Bool       // 是否精选
    var audience: CampusAudience
    var matchReasons: [String] = []  // for-you 命中理由（如「你的学院」）
}
