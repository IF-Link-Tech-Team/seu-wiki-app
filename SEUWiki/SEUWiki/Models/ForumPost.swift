import Foundation

/// 经验 tab 的三个 console（2026-10-07 产品对齐：热门 / 关注 / 东大生存手册）。
///
/// 早期版本有四个 console（多了「话题」），话题广场的数据来自已废弃的
/// `/api/site/docs/experience` 分面，已随经验长文一并移除。
enum ForumFeedTab: String, CaseIterable, Identifiable {
    case hot, following, handbook

    var id: String { rawValue }

    var name: String {
        switch self {
        case .hot: "热门"
        case .following: "关注"
        case .handbook: "东大生存手册"
        }
    }
}

// MARK: - 标签目录

/// 论坛标签（slug + 中文名）。slug 是唯一真相，与后端 `tags` 表一一对应。
struct ForumTag: Identifiable, Hashable, Sendable {
    let slug: String
    let name: String

    var id: String { slug }
}

/// 主题分区：8 个主题，各自带若干子标签（两级目录）。
struct ForumTopicGroup: Identifiable, Hashable, Sendable {
    let slug: String
    let name: String
    let children: [ForumTag]

    var id: String { slug }
    var tag: ForumTag { ForumTag(slug: slug, name: name) }
}

/// 固定学习向话题目录：**与 seu-wiki-forum `src/lib/tags/catalog.mjs` 内嵌同一份**
/// （8 主题 + 29 子标签）。后端用它做白名单校验，客户端发帖的可选标签也来自这里；
/// 后端目录变更时必须同步更新本表，`SelfCheck.checkForumTagCatalog` 会校验结构完整性。
enum ForumTagCatalog {
    /// 后端 `MAX_POST_TAGS`：每帖最多 3 个标签。
    static let maxPostTags = 3

    static let topics: [ForumTopicGroup] = [
        ForumTopicGroup(slug: "baoyan", name: "保研", children: [
            ForumTag(slug: "baoyan-jingyan", name: "经验分享"),
            ForumTag(slug: "baoyan-xialingying", name: "夏令营"),
            ForumTag(slug: "baoyan-yutuimian", name: "预推免"),
            ForumTag(slug: "baoyan-wenshu", name: "文书修改"),
            ForumTag(slug: "baoyan-taoci", name: "导师套磁"),
        ]),
        ForumTopicGroup(slug: "kaoyan", name: "考研", children: [
            ForumTag(slug: "kaoyan-zexiao", name: "择校择专业"),
            ForumTag(slug: "kaoyan-chushi", name: "初试经验"),
            ForumTag(slug: "kaoyan-fushi", name: "复试调剂"),
            ForumTag(slug: "kaoyan-ziliao", name: "资料分享"),
        ]),
        ForumTopicGroup(slug: "liuxue", name: "留学", children: [
            ForumTag(slug: "liuxue-dingwei", name: "申请定位"),
            ForumTag(slug: "liuxue-yuyan", name: "语言考试"),
            ForumTag(slug: "liuxue-wenshu", name: "文书推荐信"),
            ForumTag(slug: "liuxue-offer", name: "offer比较"),
        ]),
        ForumTopicGroup(slug: "srtp", name: "科研与 SRTP", children: [
            ForumTag(slug: "srtp-shenqing", name: "项目申请"),
            ForumTag(slug: "srtp-jinzu", name: "进组经验"),
            ForumTag(slug: "srtp-lunwen", name: "论文写作"),
            ForumTag(slug: "srtp-zhongqi", name: "中期答辩"),
        ]),
        ForumTopicGroup(slug: "jingsai", name: "学科竞赛", children: [
            ForumTag(slug: "jingsai-shumo", name: "数学建模"),
            ForumTag(slug: "jingsai-dianzi", name: "电子设计"),
            ForumTag(slug: "jingsai-tiaozhanbei", name: "挑战杯"),
            ForumTag(slug: "jingsai-acm", name: "ACM"),
        ]),
        ForumTopicGroup(slug: "zhuanye", name: "转专业", children: [
            ForumTag(slug: "zhuanye-zhengce", name: "政策解读"),
            ForumTag(slug: "zhuanye-kaohe", name: "考核经验"),
        ]),
        ForumTopicGroup(slug: "shixi", name: "实习就业", children: [
            ForumTag(slug: "shixi-neitui", name: "实习内推"),
            ForumTag(slug: "shixi-qiuzhao", name: "秋招春招"),
            ForumTag(slug: "shixi-mianjing", name: "面经"),
        ]),
        ForumTopicGroup(slug: "shenghuo", name: "校园生活", children: [
            ForumTag(slug: "shenghuo-shitang", name: "食堂测评"),
            ForumTag(slug: "shenghuo-sushe", name: "宿舍"),
            ForumTag(slug: "shenghuo-xuanke", name: "选课避雷"),
        ]),
    ]

    /// 全部合法 slug（主题 + 子标签），与后端 `POST_TAG_CATALOG` 同集合。
    static let allTags: [ForumTag] = topics.flatMap { [$0.tag] + $0.children }

    static func name(for slug: String) -> String? {
        allTags.first { $0.slug == slug }?.name
    }

    static func contains(_ slug: String) -> Bool {
        allTags.contains { $0.slug == slug }
    }
}

// MARK: - 作者

/// 公开作者名片（后端 `PublicUserCard`：只暴露卡片字段）。
struct ForumAuthor: Identifiable, Hashable, Sendable {
    let id: String
    var displayName: String?
    var username: String?
    var avatarURL: String?

    /// 展示名回退链：display_name → username → 「东大同学」。
    var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let username, !username.isEmpty { return username }
        return "东大同学"
    }
}

// MARK: - 帖子

/// 帖子（列表与详情共用同一模型；列表响应里的 `content` 就是全文，卡片只展示节选）。
struct ForumPost: Identifiable, Hashable, Sendable {
    let id: String
    /// 后端允许无标题（title 可空），无标题时卡片用正文节选充当主行。
    var title: String?
    var content: String
    var createdAt: Date?
    var likesCount: Int
    var commentsCount: Int
    var viewsCount: Int
    var pinnedAt: Date?
    var author: ForumAuthor?
    /// 图片附件的 `asset_url`（相对路径，如 `/api/media/...`），由客户端相对 baseURL 解析。
    var imagePaths: [String]
    var tags: [ForumTag]

    var isPinned: Bool { pinnedAt != nil }

    /// 卡片正文节选：去首尾空白后截断。全文可能上万字，绝不能整段塞进卡片。
    var excerpt: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 140 { return trimmed }
        return String(trimmed.prefix(140)) + "…"
    }

    /// 卡片主行文案：标题优先，无标题用正文节选。
    var headline: String {
        if let title, !title.isEmpty { return title }
        return excerpt
    }
}

/// 帖子详情：`GET /api/posts/:id` 的完整响应。
struct ForumPostDetail: Sendable {
    var post: ForumPost
    var featured: Bool
    /// 是否已被当前用户收藏。未登录时后端恒为 false。
    var bookmarked: Bool
    /// 若该帖已被收录进手册，指向对应文章。
    var handbookArticle: HandbookArticleLink?
}

struct HandbookArticleLink: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
}

/// 评论。`parent_id` 实现单层楼中楼：回复可以挂在任一条评论上，
/// 但展示时统一归并到顶层评论之下（与 Web 端一致）。
struct ForumComment: Identifiable, Hashable, Sendable {
    let id: String
    var author: ForumAuthor?
    var content: String
    var parentID: String?
    var likesCount: Int
    var createdAt: Date?
}

// MARK: - 手册

/// 手册板块（主题分区 + 文章数）。来自 `GET /api/handbook/sections`。
struct HandbookSectionInfo: Identifiable, Hashable, Sendable {
    struct Child: Identifiable, Hashable, Sendable {
        let slug: String
        var name: String
        var articleCount: Int

        var id: String { slug }
    }

    let slug: String
    var name: String
    var articleCount: Int
    var children: [Child]

    var id: String { slug }
}

/// 手册文章摘要（板块列表 / 搜索命中）。
struct HandbookArticleSummary: Identifiable, Hashable, Sendable {
    let id: String
    var tagSlug: String
    var title: String
    var authorDisplay: String?
    var publishedAt: Date?
    var sourcePost: HandbookArticleLink?
}

/// 手册文章详情：`content_html` 已由服务端渲染并消毒，直接走 HTMLRenderer 管线。
struct HandbookArticle: Sendable {
    struct SourcePost: Sendable {
        var id: String
        var title: String?
        var likesCount: Int
        var commentsCount: Int
        var viewsCount: Int
        var author: ForumAuthor?
    }

    var id: String
    var tagSlug: String
    var title: String
    var authorDisplay: String?
    var contentHTML: String
    var publishedAt: Date?
    var updatedAt: Date?
    var sourcePost: SourcePost?
}

// MARK: - 收藏

/// 服务器收藏的帖子（`GET /api/bookmarks` 的 `target` 卡片）。
struct ForumBookmarkItem: Identifiable, Hashable, Sendable {
    /// 收藏记录 id（不是帖子 id）。
    let id: String
    var postID: String
    var title: String?
    var excerpt: String
    var createdAt: Date?
    var likesCount: Int
    var commentsCount: Int
    var author: ForumAuthor?
}

// MARK: - 关注

/// 一条关注关系（阶段 2 契约：`POST/DELETE /api/follows`、`GET /api/follows`）。
struct ForumFollow: Identifiable, Hashable, Sendable {
    enum TargetType: String, Sendable {
        case tag, user
    }

    var targetType: TargetType
    var targetID: String

    var id: String { "\(targetType.rawValue):\(targetID)" }
}

// MARK: - 身份投影

/// `/api/me` 返回的论坛侧身份投影。
///
/// 只用于**展示**授权入口（编辑/管理删除按钮的可见性），真正的门禁在服务端
/// （越权调用只会 403）；登录门禁永远看 `AuthStore.isLoggedIn`，
/// 不拿这个投影当登录判断（见仓库 AGENTS.md 账号体系规则 2）。
struct ForumViewer: Identifiable, Hashable, Sendable {
    let id: String
    var displayName: String?
    var forumRole: String?
    var capabilities: [String]

    var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return "东大同学"
    }

    func hasCapability(_ capability: String) -> Bool {
        capabilities.contains(capability)
    }
}

/// 可删除内容的目标类型（作者自删与管理删除共用同一组路由参数）。
enum ForumContentTargetType: String, Sendable {
    case post, comment
}

// MARK: - 通知

/// 一条通知（`GET /api/notifications` 的 `notifications[]`）。
///
/// 契约要点（`src/lib/services/notifications.ts`）：
/// - `type` 目前只有 comment / reply / like，target 只有 post；
/// - `actor`（动作方被软删）与 `post`（目标帖已删/不可见）都可能为 null，条目仍下发；
/// - `readAt == nil` 即未读。
struct ForumNotification: Identifiable, Hashable, Sendable {
    /// 目标帖摘要；帖子已删/不可见时整个为 nil（条目仍要渲染，不可点击）。
    struct Post: Identifiable, Hashable, Sendable {
        let id: String
        var title: String?
        var excerpt: String
    }

    let id: String
    var type: String
    /// 目标帖 id（target_type 目前只有 post）。
    var targetID: String
    var readAt: Date?
    var createdAt: Date?
    var actor: ForumAuthor?
    var post: Post?

    var isUnread: Bool { readAt == nil }

    /// 动作文案：服务端只给 type 代码，文案归客户端。
    var actionText: String {
        switch type {
        case "comment": "评论了你的帖子"
        case "reply": "回复了你的评论"
        case "like": "赞了你的帖子"
        default: "与你互动了"
        }
    }
}

// MARK: - 展示辅助

/// 数字紧凑格式：过万显示「x.x万」。
func forumCompactCount(_ value: Int) -> String {
    if value >= 10000 {
        String(format: "%.1f万", Double(value) / 10000)
    } else {
        "\(value)"
    }
}
