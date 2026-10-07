import Foundation

/// 论坛客户端：对接 `https://forum.seu.wiki`（seu-wiki-forum，契约以仓库
/// `src/app/api/` 路由代码为准）。
///
/// 与 `FeedAPIClient` 的关键差异：**这一组 API 要鉴权**。
/// - 读接口匿名可用；登录后带 token 可拿到 `bookmarked` 等个性化字段。
/// - 写接口（发帖 / 评论 / 点赞 / 收藏 / 关注）必须带
///   `Authorization: Bearer <Logto access_token>`（`AuthStore.accessToken()`），
///   **绝不带 Cookie**。
/// - token **只发给 forum.seu.wiki**：host 白名单在请求构造处校验，
///   重定向或拼接错误都不会把 token 漏给别的域。
/// - `/api/site/*` 的「不带 token」约定不变，那是 `FeedAPIClient` 的事。
///
/// 401 不等于「服务挂了」：UI 层收到 `unauthorized` 应展示登录引导而不是错误页。
/// 404 且响应体不是论坛的 JSON 错误模型（`{"error": "CODE"}`）说明该路由还没部署
/// （阶段 2 的关注/信息流/搜索接口在并行开发中），映射为 `routeUnavailable`，
/// UI 显式标注「即将上线」而不是报「加载失败」。
struct ForumAPIClient: Sendable {
    var baseURL = URL(string: "https://forum.seu.wiki")!
    var session: URLSession = .shared
    var pageSize = 20

    /// access token 来源。默认走应用级单例的 `AuthStore.accessToken()`
    /// （必要时会先用 refresh token 续期）。返回 nil 表示没有可用登录态。
    var tokenProvider: @Sendable () async -> String?

    init(
        baseURL: URL = URL(string: "https://forum.seu.wiki")!,
        session: URLSession = .shared,
        pageSize: Int = 20,
        tokenProvider: @escaping @Sendable () async -> String? = { await AuthStore.shared.accessToken() }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.pageSize = pageSize
        self.tokenProvider = tokenProvider
    }

    /// 该请求是否需要登录态。
    enum AuthRequirement: Sendable {
        /// 匿名可读，永不带 token（手册、公开列表的匿名场景）。
        case none
        /// 有 token 就带（公开读 + 个性化字段，如帖子详情的 bookmarked）。
        case optional
        /// 必须带 token；拿不到就抛 `.unauthorized`，由 UI 展示登录引导。
        case required
    }

    enum ForumAPIError: Error, LocalizedError {
        case http(statusCode: Int, code: String?)
        /// 未登录 / token 失效。UI 应展示登录引导，不是错误页。
        case unauthorized
        case badURL
        /// 路由返回 404 但响应体不是论坛 JSON 错误模型 → 该功能后端尚未部署。
        case routeUnavailable(String)
        /// 搜索服务高峰期限流（对齐 `/api/site/pool` 的 `search busy` 处理）。
        case searchBusy

        var errorDescription: String? {
            switch self {
            case .http(let code, let apiCode):
                if let apiCode { return "服务返回 \(code)（\(apiCode)）" }
                return "服务返回 \(code)"
            case .unauthorized: return "需要登录"
            case .badURL: return "请求地址无法构造"
            case .routeUnavailable(let path): return "功能尚未上线（\(path) 未部署）"
            case .searchBusy: return "搜索服务正忙，稍后再试"
            }
        }
    }

    // MARK: - 帖子列表

    /// 一页帖子。热榜用 offset 分页（`nextOffset`），其余排序用 keyset（`nextCursor`），
    /// 两者必居其一；都为 nil 表示没有下一页。
    struct PostPage: Sendable {
        var posts: [ForumPost]
        var totalCount: Int?
        var nextCursor: String?
        var nextOffset: Int?
    }

    enum PostSort: String, Sendable {
        case latest, top, hot
    }

    /// GET /api/posts?sort=&tag=&limit=&cursor=|offset=
    ///
    /// `tag=<slug>` 过滤板块。**注意**（2026-10-07 实测仓库代码）：
    /// `listPublicPosts` 与 `list_hot_posts` 的 tag 过滤都是**精确 slug 命中**，
    /// 主题 slug 不会自动带上子标签的帖子 —— 与产品文档「主题命中其子标签」的描述
    /// 有出入，以仓库代码为准。手册板块接口（`resolveHandbookTagSlugs`）才有
    /// 主题 → 子标签的聚合语义。
    func posts(sort: PostSort, tag: String? = nil, cursor: String? = nil, offset: Int = 0) async throws -> PostPage {
        var query = [
            URLQueryItem(name: "sort", value: sort.rawValue),
            URLQueryItem(name: "limit", value: String(pageSize)),
        ]
        if let tag { query.append(URLQueryItem(name: "tag", value: tag)) }
        if sort == .hot {
            if offset > 0 { query.append(URLQueryItem(name: "offset", value: String(offset))) }
        } else if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }

        if sort == .hot {
            let dto: HotPostsResponseDTO = try await get("/api/posts", query: query, auth: .optional)
            return PostPage(
                posts: dto.posts.map(\.post),
                totalCount: dto.totalCount,
                nextCursor: nil,
                nextOffset: dto.nextOffset
            )
        }
        let dto: CursorPostsResponseDTO = try await get("/api/posts", query: query, auth: .optional)
        return PostPage(posts: dto.posts.map(\.post), totalCount: nil, nextCursor: dto.nextCursor, nextOffset: nil)
    }

    // MARK: - 帖子详情 / 浏览

    /// GET /api/posts/:id。登录后带 token 以拿到 `bookmarked`。
    func postDetail(id: String) async throws -> ForumPostDetail {
        let dto: PostDetailResponseDTO = try await get("/api/posts/\(id)", query: [], auth: .optional)
        return ForumPostDetail(
            post: dto.post.post,
            featured: dto.featured ?? false,
            bookmarked: dto.post.bookmarked ?? false,
            handbookArticle: dto.handbookArticle.map { HandbookArticleLink(id: $0.id, title: $0.title) }
        )
    }

    /// POST /api/posts/:id/view —— 打开详情浏览 +1。失败静默（不影响展示），
    /// 返回最新浏览数（失败为 nil，调用方不更新计数即可）。
    @discardableResult
    func incrementView(id: String) async -> Int? {
        struct ViewDTO: Decodable { let views: Int? }
        return try? await sendEmpty("/api/posts/\(id)/view", method: "POST", auth: .none, decode: ViewDTO.self).views
    }

    // MARK: - 评论

    /// GET /api/comments?target_type=post&target_id= → 评论 + 作者名片表。
    func comments(postID: String) async throws -> [ForumComment] {
        let dto: CommentsResponseDTO = try await get(
            "/api/comments",
            query: [
                URLQueryItem(name: "target_type", value: "post"),
                URLQueryItem(name: "target_id", value: postID),
            ],
            auth: .none
        )
        return dto.comments.map { $0.comment(authors: dto.authors ?? [:]) }
    }

    /// POST /api/comments。正文 ≤ 5000 字；`parentID` 实现单层楼中楼。
    @discardableResult
    func createComment(postID: String, content: String, parentID: String? = nil) async throws -> ForumComment {
        struct Body: Encodable {
            let target_type = "post"
            let target_id: String
            let content: String
            let parent_id: String?
        }
        struct CreatedDTO: Decodable { let comment: CommentDTO }
        let created: CreatedDTO = try await sendJSON(
            "/api/comments",
            method: "POST",
            body: Body(target_id: postID, content: content, parent_id: parentID),
            auth: .required
        )
        // 刚发出的评论作者就是当前用户，详情里作者名片由调用方本地补齐。
        return created.comment.comment(authors: [:])
    }

    // MARK: - 点赞 / 收藏

    /// POST /api/post-likes?post_id=（toggle，query 传参无 body）。返回最新 liked 状态。
    @discardableResult
    func togglePostLike(postID: String) async throws -> Bool {
        struct ResultDTO: Decodable { let liked: Bool }
        let dto: ResultDTO = try await sendEmpty(
            "/api/post-likes",
            method: "POST",
            query: [URLQueryItem(name: "post_id", value: postID)],
            auth: .required,
            decode: ResultDTO.self
        )
        return dto.liked
    }

    /// POST /api/bookmarks `{target_type:"post", target_id}`（toggle）。
    @discardableResult
    func toggleBookmark(postID: String) async throws -> Bool {
        struct Body: Encodable {
            let target_type = "post"
            let target_id: String
        }
        struct ResultDTO: Decodable { let bookmarked: Bool }
        let dto: ResultDTO = try await sendJSON(
            "/api/bookmarks",
            method: "POST",
            body: Body(target_id: postID),
            auth: .required
        )
        return dto.bookmarked
    }

    /// GET /api/bookmarks（需登录）：按收藏时间倒序 keyset 分页。
    func bookmarks(cursor: String? = nil) async throws -> (items: [ForumBookmarkItem], nextCursor: String?) {
        var query = [URLQueryItem(name: "limit", value: String(pageSize))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let dto: BookmarksResponseDTO = try await get("/api/bookmarks", query: query, auth: .required)
        return (dto.bookmarks.map(\.item), dto.nextCursor)
    }

    // MARK: - 发帖

    /// POST /api/posts `{title?, content≤20000, tags:[slug…≤3]}`。
    /// 返回新帖 id，供发帖成功后直接跳转。
    @discardableResult
    func createPost(title: String?, content: String, tags: [String]) async throws -> String {
        struct Body: Encodable {
            let title: String?
            let content: String
            let tags: [String]
        }
        struct CreatedDTO: Decodable {
            struct Post: Decodable { let id: String }
            let post: Post
        }
        let dto: CreatedDTO = try await sendJSON(
            "/api/posts",
            method: "POST",
            body: Body(title: title, content: content, tags: tags),
            auth: .required
        )
        return dto.post.id
    }

    // MARK: - 手册

    /// GET /api/handbook/sections → 8 主题 + 子标签 + 文章数。
    func handbookSections() async throws -> [HandbookSectionInfo] {
        let dto: HandbookSectionsResponseDTO = try await get("/api/handbook/sections", query: [], auth: .none)
        return dto.sections.map(\.info)
    }

    /// 板块详情：板块元信息 + 文章列表（主题 slug 含其子标签的文章）。
    func handbookSection(slug: String) async throws -> (section: HandbookSectionInfo, articles: [HandbookArticleSummary]) {
        let dto: HandbookSectionDetailDTO = try await get("/api/handbook/sections/\(slug)", query: [], auth: .none)
        let children = dto.section.children?.map { HandbookSectionInfo.Child(slug: $0.slug, name: $0.name, articleCount: $0.articleCount ?? 0) } ?? []
        let section = HandbookSectionInfo(
            slug: dto.section.slug,
            name: dto.section.name ?? ForumTagCatalog.name(for: dto.section.slug) ?? dto.section.slug,
            articleCount: dto.section.articleCount ?? dto.articles.count,
            children: children
        )
        return (section, dto.articles.map(\.summary))
    }

    /// 手册文章详情（`content_html` 已渲染消毒）。
    func handbookArticle(id: String) async throws -> HandbookArticle {
        let dto: HandbookArticleResponseDTO = try await get("/api/handbook/articles/\(id)", query: [], auth: .none)
        let article = dto.article
        return HandbookArticle(
            id: article.id,
            tagSlug: article.tagSlug,
            title: article.title,
            authorDisplay: article.authorDisplay,
            contentHTML: article.contentHTML ?? "",
            publishedAt: DateParser.parseForum(article.publishedAt),
            updatedAt: DateParser.parseForum(article.updatedAt),
            sourcePost: article.sourcePost.map {
                HandbookArticle.SourcePost(
                    id: $0.id,
                    title: $0.title,
                    likesCount: $0.likesCount ?? 0,
                    commentsCount: $0.commentsCount ?? 0,
                    viewsCount: $0.viewsCount ?? 0,
                    author: $0.author?.author
                )
            }
        )
    }

    // MARK: - 关注 / 关注流（阶段 2，后端并行开发中；404 时抛 routeUnavailable）

    /// GET /api/follows?target_type=tag|user。
    func follows(targetType: ForumFollow.TargetType) async throws -> [ForumFollow] {
        let dto: FollowsResponseDTO = try await get(
            "/api/follows",
            query: [URLQueryItem(name: "target_type", value: targetType.rawValue)],
            auth: .required
        )
        return dto.allFollows.compactMap { $0.follow }
    }

    /// POST /api/follows（关注）。阶段 2 契约。
    func follow(targetType: ForumFollow.TargetType, targetID: String) async throws {
        struct Body: Encodable {
            let target_type: String
            let target_id: String
        }
        struct ResultDTO: Decodable {}
        let _: ResultDTO = try await sendJSON(
            "/api/follows",
            method: "POST",
            body: Body(target_type: targetType.rawValue, target_id: targetID),
            auth: .required
        )
    }

    /// DELETE /api/follows（取关），body 同 POST。阶段 2 契约。
    func unfollow(targetType: ForumFollow.TargetType, targetID: String) async throws {
        struct Body: Encodable {
            let target_type: String
            let target_id: String
        }
        struct ResultDTO: Decodable {}
        let _: ResultDTO = try await sendJSON(
            "/api/follows",
            method: "DELETE",
            body: Body(target_type: targetType.rawValue, target_id: targetID),
            auth: .required
        )
    }

    /// GET /api/feed/following（keyset；未登录 401；无关注返回空 + suggested_tags）。
    func followingFeed(cursor: String? = nil) async throws -> (posts: [ForumPost], nextCursor: String?, suggestedTags: [String]) {
        var query = [URLQueryItem(name: "limit", value: String(pageSize))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let dto: FollowingFeedResponseDTO = try await get("/api/feed/following", query: query, auth: .required)
        return (dto.posts?.map(\.post) ?? [], dto.nextCursor, dto.suggestedTags ?? [])
    }

    // MARK: - 论坛搜索（阶段 2，后端并行开发中）

    /// 一组搜索结果（帖子或手册文章各一组），keyset 分页。
    struct ForumSearchResult: Sendable {
        var posts: [ForumPost] = []
        var postsNextCursor: String?
        var articles: [HandbookArticleSummary] = []
        var articlesNextCursor: String?
    }

    enum ForumSearchType: String, Sendable {
        case post, article, all
    }

    /// GET /api/search?q=&type=post|article|all。分两组返回，各带 items + next_cursor。
    func search(query keyword: String, type: ForumSearchType, cursor: String? = nil) async throws -> ForumSearchResult {
        var query = [
            URLQueryItem(name: "q", value: keyword),
            URLQueryItem(name: "type", value: type.rawValue),
            URLQueryItem(name: "limit", value: String(pageSize)),
        ]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let dto: ForumSearchResponseDTO = try await get("/api/search", query: query, auth: .optional)
        return ForumSearchResult(
            posts: dto.posts?.items?.map(\.post) ?? [],
            postsNextCursor: dto.posts?.nextCursor ?? nil,
            articles: dto.articles?.items?.map(\.summary) ?? [],
            articlesNextCursor: dto.articles?.nextCursor ?? nil
        )
    }

    // MARK: - 图片地址

    /// 帖子图片的 `asset_url` 是相对路径（`/api/media/...`），相对论坛 baseURL 解析。
    func resolveAssetURL(_ path: String) -> URL? {
        URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem], auth: AuthRequirement) async throws -> T {
        try await perform(path, method: "GET", query: query, body: Optional<EmptyBody>.none, auth: auth, decode: T.self)
    }

    /// 无 JSON body 的写请求（如 view、post-likes 的 query 传参）。
    private func sendEmpty<T: Decodable>(
        _ path: String,
        method: String,
        query: [URLQueryItem] = [],
        auth: AuthRequirement,
        decode: T.Type
    ) async throws -> T {
        try await perform(path, method: method, query: query, body: Optional<EmptyBody>.none, auth: auth, decode: T.self)
    }

    private func sendJSON<Body: Encodable, T: Decodable>(
        _ path: String,
        method: String,
        body: Body,
        auth: AuthRequirement
    ) async throws -> T {
        try await perform(path, method: method, query: [], body: body, auth: auth, decode: T.self)
    }

    private struct EmptyBody: Encodable {}

    private func perform<Body: Encodable, T: Decodable>(
        _ path: String,
        method: String,
        query: [URLQueryItem],
        body: Body?,
        auth: AuthRequirement,
        decode: T.Type
    ) async throws -> T {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        // 同 FeedService 的教训：必须用 percentEncodedPath，`path` 会把已编码的 % 二次转义。
        components?.percentEncodedPath = path.percentEncodedPath
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw ForumAPIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        // host 白名单：token 只发给论坛本域。components 拼出来的 URL 理论上恒等于
        // baseURL.host，但这里显式校验，将来改 baseURL 或拼路径出错时宁可 401 也不外泄。
        if auth != .none {
            guard url.host() == baseURL.host() else {
                // 要求鉴权但 host 对不上：绝不发请求。
                throw ForumAPIError.unauthorized
            }
            if let token = await tokenProvider(), !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else if auth == .required {
                throw ForumAPIError.unauthorized
            }
        }

        let (data, response) = try await session.data(for: request)
        return try decodeResponse(data: data, response: response, path: path, decode: T.self)
    }

    private func decodeResponse<T: Decodable>(data: Data, response: URLResponse, path: String, decode: T.Type) throws -> T {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 503 { throw ForumAPIError.searchBusy }
        if status == 401 { throw ForumAPIError.unauthorized }
        guard (200..<300).contains(status) else {
            // 论坛的错误模型是 {"error": "CODE"}；解不出来（比如路由未部署时
            // Next.js 回 HTML 404 页）就说明这条路由还不存在 → routeUnavailable。
            let code = (try? Self.decoder.decode(ForumErrorDTO.self, from: data))?.error
            if status == 404, code == nil { throw ForumAPIError.routeUnavailable(path) }
            throw ForumAPIError.http(statusCode: status, code: code)
        }
        do {
            // 写接口可能回 204 / 空 body（阶段 2 契约未定死），空数据按 {} 解。
            let payload = data.isEmpty ? Data("{}".utf8) : data
            return try Self.decoder.decode(T.self, from: payload)
        } catch {
            // 与 FeedService 同款：解码失败带响应头 200 字节，且绝不用 NSLog %@ 打印泛型元类型。
            let head = String(data: data.prefix(200), encoding: .utf8) ?? ""
            let info = error as NSError
            print("[ForumAPIClient] 解码 \(T.self) 失败：code=\(info.code) "
                  + "domain=\(info.domain) head=\(head)")
            throw error
        }
    }

    /// 日期解析不走 decoder 的 dateDecodingStrategy：论坛响应的时间戳是 PostgREST
    /// 序列化的 timestamptz（可能带 6 位微秒），DTO 里一律按 String 收，再用
    /// `DateParser.parseForum` 转，解析失败只是该字段为 nil，不会拖垮整页。
    nonisolated private static let decoder = JSONDecoder()
}

private struct ForumErrorDTO: Decodable {
    let error: String?
}

// MARK: - 论坛日期解析

extension DateParser {
    /// 论坛（PostgREST）时间戳：`2026-10-07T04:47:20.123456+00:00`，微秒可能 6 位。
    /// `DateFormatter` 的 `.SSS` 只认 3 位毫秒，6 位直接解析失败 —— 先截断再解析。
    static func parseForum(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let direct = parse(string) { return direct }
        let truncated = string.replacingOccurrences(
            of: #"\.(\d{3})\d+"#,
            with: ".$1",
            options: .regularExpression
        )
        return parse(truncated)
    }
}

// MARK: - DTO（只解析 app 用到的字段；多余字段忽略，字段名写错会静默变空，故关键字段在 SelfCheck 有契约断言）

/// 非 private：SelfCheck 拿真实响应片段做解码断言。
struct ForumAuthorDTO: Decodable {
    let id: String
    let displayName: String?
    let username: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case username
        case avatarUrl = "avatar_url"
    }

    var author: ForumAuthor {
        ForumAuthor(id: id, displayName: displayName, username: username, avatarURL: avatarUrl)
    }
}

struct ForumTagDTO: Decodable {
    let id: String?
    let name: String
    let slug: String

    var tag: ForumTag { ForumTag(slug: slug, name: name) }
}

/// 公开帖子（列表与详情同形；详情额外有 `bookmarked`）。
struct ForumPostDTO: Decodable {
    struct ImageDTO: Decodable {
        let id: String?
        let assetUrl: String?
        let sortOrder: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case assetUrl = "asset_url"
            case sortOrder = "sort_order"
        }
    }

    let id: String
    let title: String?
    let content: String?
    let createdAt: String?
    let likesCount: Int?
    let commentsCount: Int?
    let viewsCount: Int?
    let pinnedAt: String?
    let author: ForumAuthorDTO?
    let images: [ImageDTO]?
    let tags: [ForumTagDTO]?
    let bookmarked: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, content, author, images, tags, bookmarked
        case createdAt = "created_at"
        case likesCount = "likes_count"
        case commentsCount = "comments_count"
        case viewsCount = "views_count"
        case pinnedAt = "pinned_at"
    }

    var post: ForumPost {
        ForumPost(
            id: id,
            title: title,
            content: content ?? "",
            createdAt: DateParser.parseForum(createdAt),
            likesCount: likesCount ?? 0,
            commentsCount: commentsCount ?? 0,
            viewsCount: viewsCount ?? 0,
            pinnedAt: DateParser.parseForum(pinnedAt),
            author: author?.author,
            imagePaths: (images ?? []).compactMap(\.assetUrl),
            tags: (tags ?? []).map(\.tag)
        )
    }
}

private struct HotPostsResponseDTO: Decodable {
    let posts: [ForumPostDTO]
    let totalCount: Int?
    let nextOffset: Int?

    enum CodingKeys: String, CodingKey {
        case posts
        case totalCount = "total_count"
        case nextOffset = "next_offset"
    }
}

private struct CursorPostsResponseDTO: Decodable {
    let posts: [ForumPostDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case posts
        case nextCursor = "next_cursor"
    }
}

private struct PostDetailResponseDTO: Decodable {
    let post: ForumPostDTO
    let featured: Bool?
    let handbookArticle: HandbookArticleLinkDTO?

    enum CodingKeys: String, CodingKey {
        case post, featured
        case handbookArticle = "handbook_article"
    }
}

struct HandbookArticleLinkDTO: Decodable {
    let id: String
    let title: String
}

private struct CommentDTO: Decodable {
    let id: String
    let authorId: String?
    let content: String
    let parentId: String?
    let likesCount: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, content
        case authorId = "author_id"
        case parentId = "parent_id"
        case likesCount = "likes_count"
        case createdAt = "created_at"
    }

    func comment(authors: [String: ForumAuthorDTO]) -> ForumComment {
        ForumComment(
            id: id,
            author: authorId.flatMap { authors[$0]?.author },
            content: content,
            parentID: parentId,
            likesCount: likesCount ?? 0,
            createdAt: DateParser.parseForum(createdAt)
        )
    }
}

private struct CommentsResponseDTO: Decodable {
    let comments: [CommentDTO]
    let authors: [String: ForumAuthorDTO]?
}

private struct BookmarksResponseDTO: Decodable {
    struct BookmarkDTO: Decodable {
        struct TargetDTO: Decodable {
            let id: String
            let title: String?
            let excerpt: String?
            let createdAt: String?
            let likesCount: Int?
            let commentsCount: Int?
            let author: ForumAuthorDTO?

            enum CodingKeys: String, CodingKey {
                case id, title, excerpt, author
                case createdAt = "created_at"
                case likesCount = "likes_count"
                case commentsCount = "comments_count"
            }
        }

        let id: String
        let targetId: String
        let createdAt: String?
        let target: TargetDTO?

        enum CodingKeys: String, CodingKey {
            case id, target
            case targetId = "target_id"
            case createdAt = "created_at"
        }

        var item: ForumBookmarkItem {
            ForumBookmarkItem(
                id: id,
                postID: target?.id ?? targetId,
                title: target?.title ?? nil,
                excerpt: target?.excerpt ?? "",
                createdAt: DateParser.parseForum(createdAt),
                likesCount: target?.likesCount ?? 0,
                commentsCount: target?.commentsCount ?? 0,
                author: target?.author?.author
            )
        }
    }

    let bookmarks: [BookmarkDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case bookmarks
        case nextCursor = "next_cursor"
    }
}

private struct HandbookSectionDTO: Decodable {
    struct ChildDTO: Decodable {
        let slug: String
        let name: String
        let articleCount: Int?

        enum CodingKeys: String, CodingKey {
            case slug, name
            case articleCount = "article_count"
        }
    }

    let slug: String
    let name: String?
    let articleCount: Int?
    let children: [ChildDTO]?

    enum CodingKeys: String, CodingKey {
        case slug, name, children
        case articleCount = "article_count"
    }

    var info: HandbookSectionInfo {
        HandbookSectionInfo(
            slug: slug,
            name: name ?? ForumTagCatalog.name(for: slug) ?? slug,
            articleCount: articleCount ?? 0,
            children: (children ?? []).map {
                HandbookSectionInfo.Child(slug: $0.slug, name: $0.name, articleCount: $0.articleCount ?? 0)
            }
        )
    }
}

private struct HandbookSectionsResponseDTO: Decodable {
    let sections: [HandbookSectionDTO]
}

private struct HandbookSectionDetailDTO: Decodable {
    let section: HandbookSectionDTO
    let articles: [HandbookArticleSummaryDTO]
}

struct HandbookArticleSummaryDTO: Decodable {
    struct SourcePostRefDTO: Decodable {
        let id: String
        let title: String?
    }

    let id: String
    let tagSlug: String
    let title: String
    let authorDisplay: String?
    let publishedAt: String?
    let sourcePost: SourcePostRefDTO?

    enum CodingKeys: String, CodingKey {
        case id, title
        case tagSlug = "tag_slug"
        case authorDisplay = "author_display"
        case publishedAt = "published_at"
        case sourcePost = "source_post"
    }

    var summary: HandbookArticleSummary {
        HandbookArticleSummary(
            id: id,
            tagSlug: tagSlug,
            title: title,
            authorDisplay: authorDisplay,
            publishedAt: DateParser.parseForum(publishedAt),
            sourcePost: sourcePost.map { HandbookArticleLink(id: $0.id, title: $0.title ?? "") }
        )
    }
}

private struct HandbookArticleResponseDTO: Decodable {
    struct ArticleDTO: Decodable {
        struct SourcePostDTO: Decodable {
            let id: String
            let title: String?
            let likesCount: Int?
            let commentsCount: Int?
            let viewsCount: Int?
            let author: ForumAuthorDTO?

            enum CodingKeys: String, CodingKey {
                case id, title, author
                case likesCount = "likes_count"
                case commentsCount = "comments_count"
                case viewsCount = "views_count"
            }
        }

        let id: String
        let tagSlug: String
        let title: String
        let authorDisplay: String?
        let contentHTML: String?
        let publishedAt: String?
        let updatedAt: String?
        let sourcePost: SourcePostDTO?

        enum CodingKeys: String, CodingKey {
            case id, title
            case tagSlug = "tag_slug"
            case authorDisplay = "author_display"
            case contentHTML = "content_html"
            case publishedAt = "published_at"
            case updatedAt = "updated_at"
            case sourcePost = "source_post"
        }
    }

    let article: ArticleDTO
}

private struct FollowsResponseDTO: Decodable {
    struct FollowDTO: Decodable {
        let targetType: String?
        let targetId: String?

        enum CodingKeys: String, CodingKey {
            case targetType = "target_type"
            case targetId = "target_id"
        }

        var follow: ForumFollow? {
            guard let raw = targetType, let type = ForumFollow.TargetType(rawValue: raw),
                  let targetId, !targetId.isEmpty else { return nil }
            return ForumFollow(targetType: type, targetID: targetId)
        }
    }

    // 阶段 2 契约未定死包装键：兼容 {follows:[...]} 与 {items:[...]} 两种形态。
    let follows: [FollowDTO]?
    let items: [FollowDTO]?

    var allFollows: [FollowDTO] { follows ?? items ?? [] }
}

private struct FollowingFeedResponseDTO: Decodable {
    let posts: [ForumPostDTO]?
    let nextCursor: String?
    let suggestedTags: [String]?

    enum CodingKeys: String, CodingKey {
        case posts
        case nextCursor = "next_cursor"
        case suggestedTags = "suggested_tags"
    }
}

private struct ForumSearchResponseDTO: Decodable {
    struct PostGroupDTO: Decodable {
        let items: [ForumPostDTO]?
        let nextCursor: String?

        enum CodingKeys: String, CodingKey {
            case items
            case nextCursor = "next_cursor"
        }
    }
    struct ArticleGroupDTO: Decodable {
        let items: [HandbookArticleSummaryDTO]?
        let nextCursor: String?

        enum CodingKeys: String, CodingKey {
            case items
            case nextCursor = "next_cursor"
        }
    }

    let posts: PostGroupDTO?
    let articles: ArticleGroupDTO?
}

// MARK: - ForumStore

/// 论坛数据仓库：热门/最新/板块/关注四个信息流各自维护一页分页状态，
/// 外加手册板块、关注关系、收藏列表。竞态防护与 `FeedStore` 同模式
/// （generation 计数器 + `Paging.merge` 去重）。
@Observable
@MainActor
final class ForumStore {
    /// 信息流的一页状态。`nextCursor` 与 `nextOffset` 二选一（热榜用 offset）。
    struct PostPageState {
        var items: [ForumPost] = []
        var nextCursor: String?
        var nextOffset: Int?
        var isLoading = false
        var isLoadingMore = false
        var hasLoaded = false
        var errorMessage: String?
        /// true 表示该功能后端尚未部署（routeUnavailable），UI 显示「即将上线」。
        var unavailable = false
        /// true 表示需要登录（关注流未登录）。
        var requiresLogin = false

        var hasMore: Bool { nextCursor != nil || nextOffset != nil }
    }

    enum FeedKey: Hashable {
        case hot
        case latest
        case tag(String)
        case following
    }

    private let client: ForumAPIClient
    private var pages: [FeedKey: PostPageState] = [:]
    private var generations: [FeedKey: Int] = [:]

    /// 热榜排序在服务端的可用性。线上曾先于仓库代码部署（`sort=hot` 回
    /// `INVALID_SORT`），此时降级到 `latest` 并记在这里，避免每次刷新都白打一发。
    private(set) var hotFallbackToLatest = false

    // 关注（阶段 2）
    private(set) var followedTagSlugs: Set<String> = []
    private(set) var suggestedTags: [String] = []
    private(set) var followsLoaded = false
    private(set) var followsUnavailable = false

    // 手册
    private(set) var handbookSections: [HandbookSectionInfo]?
    private(set) var handbookError: String?
    private(set) var handbookUnavailable = false
    private var isLoadingHandbook = false

    init(client: ForumAPIClient = ForumAPIClient()) {
        self.client = client
    }

    func page(for key: FeedKey) -> PostPageState {
        pages[key] ?? PostPageState()
    }

    // MARK: - 列表加载

    func loadIfNeeded(_ key: FeedKey) async {
        guard !page(for: key).hasLoaded else { return }
        await refresh(key)
    }

    func refresh(_ key: FeedKey) async {
        guard !page(for: key).isLoading else { return }
        let generation = nextGeneration(for: key)
        pages[key, default: PostPageState()].isLoading = true
        pages[key]?.errorMessage = nil
        defer {
            if generations[key] == generation { pages[key]?.isLoading = false }
        }
        do {
            let result = try await fetch(key, cursor: nil, offset: 0)
            guard generations[key] == generation else { return }
            pages[key] = PostPageState(
                items: Paging.distinct(result.posts),
                nextCursor: result.nextCursor,
                nextOffset: result.nextOffset,
                hasLoaded: true
            )
        } catch {
            if Self.isCancellation(error) { return }
            guard generations[key] == generation else { return }
            var state = page(for: key)
            state.nextCursor = nil
            state.nextOffset = nil
            state.hasLoaded = true
            apply(error, to: &state)
            pages[key] = state
        }
    }

    /// 滚动到底加载下一页。失败静默，下次滚动到底会再试。
    func loadMore(_ key: FeedKey) async {
        let state = page(for: key)
        guard state.hasLoaded, !state.isLoading, !state.isLoadingMore, state.errorMessage == nil,
              state.hasMore else { return }

        let generation = generations[key] ?? 0
        pages[key]?.isLoadingMore = true
        defer {
            if generations[key] == generation { pages[key]?.isLoadingMore = false }
        }
        do {
            let result = try await fetch(key, cursor: state.nextCursor, offset: state.nextOffset ?? 0)
            guard generations[key] == generation else { return }
            pages[key]?.items = Paging.merge(existing: pages[key]?.items ?? [], incoming: result.posts)
            pages[key]?.nextCursor = result.nextCursor
            pages[key]?.nextOffset = result.nextOffset
        } catch {
            // 翻页失败静默：列表还有内容，不必打断用户；滚到底会自然重试。
        }
    }

    private func fetch(_ key: FeedKey, cursor: String?, offset: Int) async throws -> ForumAPIClient.PostPage {
        switch key {
        case .hot:
            if hotFallbackToLatest {
                return try await client.posts(sort: .latest, cursor: cursor)
            }
            do {
                return try await client.posts(sort: .hot, offset: offset)
            } catch let error as ForumAPIClient.ForumAPIError {
                // 线上部署先于仓库代码时 sort=hot 回 400 INVALID_SORT：
                // 降级到 latest（公开读，同样真实），并在客户端记住这次降级。
                if case .http(400, let code) = error, code == "INVALID_SORT" {
                    hotFallbackToLatest = true
                    return try await client.posts(sort: .latest, cursor: cursor)
                }
                throw error
            }
        case .latest:
            return try await client.posts(sort: .latest, cursor: cursor)
        case .tag(let slug):
            return try await client.posts(sort: .latest, tag: slug, cursor: cursor)
        case .following:
            let feed = try await client.followingFeed(cursor: cursor)
            if cursor == nil { suggestedTags = feed.suggestedTags }
            return ForumAPIClient.PostPage(
                posts: feed.posts,
                totalCount: nil,
                nextCursor: feed.nextCursor,
                nextOffset: nil
            )
        }
    }

    // MARK: - 关注（阶段 2）

    func loadFollows() async {
        do {
            let tags = try await client.follows(targetType: .tag)
            followedTagSlugs = Set(tags.map(\.targetID))
            followsLoaded = true
            followsUnavailable = false
        } catch let error as ForumAPIClient.ForumAPIError {
            if case .routeUnavailable = error {
                followsUnavailable = true
                followsLoaded = true
            } else if case .unauthorized = error {
                followsLoaded = true
            } else {
                // 其他错误不置 loaded，下次进入会重试。
            }
        } catch {
            // 网络层错误同样不置 loaded，下次进入会重试。
        }
    }

    var isFollowingTags: Bool { !followedTagSlugs.isEmpty }

    func isFollowing(tag slug: String) -> Bool { followedTagSlugs.contains(slug) }

    /// 关注/取关一个板块标签。乐观更新，失败回滚。
    func toggleFollow(tag slug: String) async {
        let wasFollowing = followedTagSlugs.contains(slug)
        if wasFollowing { followedTagSlugs.remove(slug) } else { followedTagSlugs.insert(slug) }
        do {
            if wasFollowing {
                try await client.unfollow(targetType: .tag, targetID: slug)
            } else {
                try await client.follow(targetType: .tag, targetID: slug)
            }
        } catch {
            if wasFollowing { followedTagSlugs.insert(slug) } else { followedTagSlugs.remove(slug) }
        }
    }

    // MARK: - 手册

    func loadHandbookSections() async {
        guard handbookSections == nil, !isLoadingHandbook, !handbookUnavailable else { return }
        isLoadingHandbook = true
        handbookError = nil
        defer { isLoadingHandbook = false }
        do {
            handbookSections = try await client.handbookSections()
        } catch let error as ForumAPIClient.ForumAPIError {
            if case .routeUnavailable = error {
                handbookUnavailable = true
            } else {
                handbookError = error.errorDescription
            }
        } catch {
            handbookError = error.localizedDescription
        }
    }

    /// 发帖成功后让热榜/最新失效重载。
    func invalidateFeeds() {
        for key in [FeedKey.hot, .latest] {
            pages[key] = nil
        }
    }

    // MARK: - Private

    private func nextGeneration(for key: FeedKey) -> Int {
        let next = (generations[key] ?? 0) + 1
        generations[key] = next
        return next
    }

    private func apply(_ error: Error, to state: inout PostPageState) {
        if let api = error as? ForumAPIClient.ForumAPIError {
            switch api {
            case .unauthorized:
                state.requiresLogin = true
            case .routeUnavailable:
                state.unavailable = true
            default:
                state.errorMessage = api.errorDescription
            }
        } else if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet: state.errorMessage = "当前没有网络连接"
            case .timedOut: state.errorMessage = "请求超时"
            default: state.errorMessage = url.localizedDescription
            }
        } else {
            state.errorMessage = error.localizedDescription
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }
}
