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

/// 精选接口提供的活动时间；显示保留服务端原文与精度。
struct ActivityScheduleTime: Codable, Hashable {
    var text: String
    var value: String? = nil
    var precision: String? = nil
}

struct ActivityScheduleEntry: Codable, Hashable {
    var name: String
    var registrationStart: ActivityScheduleTime? = nil
    var registrationEnd: ActivityScheduleTime? = nil
    var activityStart: ActivityScheduleTime? = nil
    var activityEnd: ActivityScheduleTime? = nil
    var registrationNote: String? = nil

    func lines() -> [String] {
        [range("报名", registrationStart, registrationEnd, registrationNote),
         range("活动", activityStart, activityEnd, nil)].compactMap { $0 }
    }

    private func range(_ label: String, _ start: ActivityScheduleTime?, _ end: ActivityScheduleTime?, _ note: String?) -> String? {
        if note == "无需报名" { return start != nil || end != nil ? "\(label)：时间待核实" : "\(label)：无需报名" }
        let first = start?.text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let last = end?.text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let first, let last { return "\(label)：\(first) → \(last)" }
        if let first { return "\(label)：\(first) 开始 · \(label == "报名" ? "截止" : "结束")未注明" }
        if let last { return label == "报名" ? "报名：截至 \(last)" : "活动：\(last) 结束 · 开始未注明" }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct ActivitySchedule: Codable, Hashable {
    var activities: [ActivityScheduleEntry] = []
    var notice: String? = nil

    func lines() -> [String] {
        if let notice, !notice.isEmpty { return [notice] }
        return activities.flatMap { entry in
            let rows = entry.lines()
            return !rows.isEmpty && activities.count > 1 && !entry.name.isEmpty ? [entry.name] + rows : rows
        }
    }
}

/// 一条资讯，对应 seu-wiki-v2 `FeedItemSummary`（/api/site/timeline、/api/site/pool）。
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
    var matchReasons: [String] = []  // for-you 命中理由；for-you 已下线，当前接口不下发，仅 Preview 样例使用
    var activitySchedule: ActivitySchedule? = nil

    /// 只知道 id 时的占位条目。
    ///
    /// 通知深链冷启动进来时，任何分页都还没加载，这条资讯的标题、来源、分类
    /// 一个都拿不到。先用空壳把详情页顶上去，由 `FeedItemDetailView` 调
    /// `/api/site/items/:id` 把真实内容拉回来。
    ///
    /// ⚠️ **不要在这里编造标题或摘要。** 空着，界面会如实显示「没有内容」，
    /// 这比凭空捏一条像模像样的假通知好 —— 用户分不清哪个是真的。
    static func placeholder(id: String) -> FeedItem {
        FeedItem(
            id: id,
            title: "",
            summary: "",
            sourceName: "",
            category: .news,
            tags: [],
            publishedAt: .now,
            originalURL: nil,
            score: 0,
            isSelected: false,
            audience: CampusAudience()
        )
    }
}
