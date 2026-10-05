import Foundation
import SwiftUI
import UIKit

/// seu.wiki 线上只读 API（`/api/site/*`，契约见 seu-wiki-v2 `packages/contracts/src/site.ts`）。
///
/// **不带任何鉴权头。** `/api/site` 这一组接口后端**明确不读** `Authorization`
/// （见 `apps/api/src/lib/server.ts` 的挂载与 `apps/api/src/routes/site.ts` 全部 GET），
/// 所以挂 token 有两个纯粹的坏处：白白扩大凭证暴露面，且每刷一次 feed 都会把
/// 续期链路（并发合并、错误分类）拽进来，凭空多出一堆能把自己登出���的路径。
/// 个性化**不依赖登录** —— for-you 的画像参数直接来自本地 `UserProfile`。
/// 等 forum 接通、那边真的要 Bearer 时，再单独给 forum 客户端挂 token 并加 host 白名单。
///
/// 缓存：timeline/for-you 由服务端发 ETag，走 `URLCache`（见 `makeSession`）。
struct FeedAPIClient: Sendable {
    var baseURL = URL(string: "https://seu.wiki")!
    var session: URLSession = .shared
    var pageSize = 20

    init(
        baseURL: URL = URL(string: "https://seu.wiki")!,
        session: URLSession = .shared,
        pageSize: Int = 20
    ) {
        self.baseURL = baseURL
        self.session = session
        self.pageSize = pageSize
    }

    enum FeedAPIError: Error, LocalizedError {
        case http(statusCode: Int)
        case badURL
        /// 搜索服务在高峰期会主动回 503（`search busy`），这是**正常状态**，
        /// 不是故障。UI 要区别于网络错误来展示「稍后再试」。
        case searchBusy

        var errorDescription: String? {
            switch self {
            case .http(let code): "服务返回 \(code)"
            case .badURL: "请求地址无法构造"
            case .searchBusy: "搜索服务正忙，稍后再试"
            }
        }
    }

    // MARK: - 资讯

    /// GET /api/site/timeline?channel=all&category=&cursor=&limit=
    func timeline(category: FeedCategory? = nil, cursor: String? = nil) async throws -> (items: [FeedItem], nextCursor: String?) {
        var query = [
            URLQueryItem(name: "channel", value: "all"),
            URLQueryItem(name: "limit", value: String(pageSize)),
        ]
        if let category { query.append(URLQueryItem(name: "category", value: category.rawValue)) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let response: TimelineResponseDTO = try await get("/api/site/timeline", query: query)
        return (response.cards.map { $0.item.feedItem() }, response.nextCursor)
    }

    /// GET /api/site/for-you?college=&degree=&grade=&interests=&cursor=&limit=
    /// 画像参数直接透传 UserProfile；interests 逗号分隔，URLQueryItem 自动编码中文。
    ///
    /// ⚠️ **cursor 绑定画像**：后端把画像摘要编进 cursor（`foryou.ts`），改了学院/
    /// 学段/年级/兴趣之后再用旧 cursor 会被判为 `invalid_cursor` 返回 400。
    /// 调用方（`FeedStore`）必须在这四种参数任一变化时丢掉旧 cursor。
    func forYou(profile: UserProfile, cursor: String? = nil) async throws -> (items: [FeedItem], nextCursor: String?) {
        var query = [URLQueryItem(name: "limit", value: String(pageSize))]
        for (key, value) in profile.forYouParams {
            query.append(URLQueryItem(name: key, value: value))
        }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let response: ForYouResponseDTO = try await get("/api/site/for-you", query: query)
        return (response.items.map { $0.feedItem() }, response.nextCursor)
    }

    /// GET /api/site/items/:id → 详情（含 body 与 links.original）。
    func itemDetail(id: String) async throws -> FeedItemDetail {
        let dto: ItemDetailDTO = try await get("/api/site/items/\(id)", query: [])
        // 纯英文条目 `body.zh` 为 null，此时回退原文，否则正文整块空白。
        let html = dto.body?.zh ?? dto.body?.original
        return FeedItemDetail(
            originalTitle: dto.originalTitle,
            summary: dto.summary,
            reason: dto.reason,
            bodyHTML: html,
            originalURL: dto.links?.original.flatMap(URL.init(string:))
        )
    }

    // MARK: - 手册 / 经验长文

    /// GET /api/site/docs/survival → 生存手册目录（「篇 → 组 → 条」的真实文档树）。
    func survivalIndex() async throws -> HandbookIndex {
        let dto: SurvivalIndexDTO = try await get("/api/site/docs/survival", query: [])
        return dto.index
    }

    /// GET /api/site/docs/experience?category=&grade=&college= → 经验长文索引 + 分面筛选项。
    func experienceIndex(
        categories: [String] = [],
        grades: [String] = [],
        colleges: [String] = []
    ) async throws -> ExperienceIndex {
        var query: [URLQueryItem] = []
        if !categories.isEmpty { query.append(URLQueryItem(name: "category", value: categories.joined(separator: ","))) }
        if !grades.isEmpty { query.append(URLQueryItem(name: "grade", value: grades.joined(separator: ","))) }
        if !colleges.isEmpty { query.append(URLQueryItem(name: "college", value: colleges.joined(separator: ","))) }
        let dto: ExperienceIndexDTO = try await get("/api/site/docs/experience", query: query)
        return ExperienceIndex(
            filters: dto.filters.map { ExperienceIndex.Facet(key: $0.key, label: $0.label, values: $0.values) },
            items: dto.items.map(\.item)
        )
    }

    /// GET /api/site/docs/{slug} → 手册/经验条目详情，含正文与目录（outline）。
    ///
    /// slug 形如 `survival/观点篇/1-认识`：含中文与 `/`。后端路由是通配 `/api/site/docs/*`，
    /// **必须只编码非 ASCII，斜杠保留字面量** —— 把 `/` 也编掉会 404。
    func docDetail(slug: String) async throws -> DocDetail {
        let dto: DocDetailDTO = try await get("/api/site/docs/\(slug.percentEncodedPath)", query: [])
        return DocDetail(
            slug: dto.slug,
            kind: dto.kind,
            title: dto.title,
            description: dto.description,
            author: dto.author,
            occurredAt: dto.occurredAt,
            category: dto.category,
            grade: dto.grade,
            college: dto.college,
            html: dto.html,
            outline: dto.outline.map { DocDetail.Outline(id: $0.id, text: $0.text, level: $0.level) }
        )
    }

    // MARK: - 统一搜索

    /// GET /api/site/pool?q=&type= → 一次搜三类信源。
    ///
    /// `type=all`（默认）时后端同时返回 `items`（资讯动态）与 `docs`
    /// （手册 survival + 经验 experience 长文命中）。两端都**必须**用上 `docs`：
    /// 只取 `items` 的话，「经验」和「手册」两栏就只能拿本地假数据填。
    func pool(query: String, type: PoolSearchType = .all, page: Int = 1) async throws -> PoolResult {
        let response: PoolResponseDTO = try await get("/api/site/pool", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: type.rawValue),
            URLQueryItem(name: "page", value: String(page)),
        ])
        return PoolResult(
            items: response.items.map { $0.feedItem() },
            docs: response.mappedDocs,
            page: response.page,
            pageCount: response.pageCount,
            total: response.total
        )
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw FeedAPIError.badURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 503 { throw FeedAPIError.searchBusy }
        guard (200..<300).contains(status) else { throw FeedAPIError.http(statusCode: status) }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            // 解码失败时把前 200 字节带上：排查线上字段变动时省去反复抓包。
            let head = String(data: data.prefix(200), encoding: .utf8) ?? ""
            NSLog("[FeedAPIClient] 解码 %@ 失败：%@ / %@", String(describing: T.self), (error as NSError).code, head)
            throw error
        }
    }

    /// 共享解码器。`ISO8601FormatStyle` 是值类型、线程安全，**不要**再每次解码
    /// 新建 `ISO8601DateFormatter`（那是 `NSDateFormatter` 子类，实例开销大）。
    nonisolated private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = DateParser.parse(string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "无法解析日期: \(string)"
            )
        }
        return decoder
    }()
}

/// 搜索时的信源范围，对应后端 `pool` 的 `type` 参数。
enum PoolSearchType: String, CaseIterable, Sendable {
    case all, feed, survival, experience
}

// MARK: - 搜索与文档模型

struct PoolResult: Sendable {
    var items: [FeedItem]
    var docs: [DocSearchHit]
    var page: Int
    var pageCount: Int
    var total: Int

    var experienceHits: [DocSearchHit] { docs.filter { $0.kind == .experience } }
    var survivalHits: [DocSearchHit] { docs.filter { $0.kind == .survival } }
}

/// 搜索命中的长文（手册或经验）。`anchor` 非空表示命中的是正文里的某个小节，
/// 详情页应滚动定位过去。
struct DocSearchHit: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case survival, experience }

    var id: String { "\(kind.rawValue):\(slug)" }
    var slug: String
    var kind: Kind
    var title: String
    var description: String?
    var occurredAt: String?
    var anchor: Anchor?

    struct Anchor: Hashable, Sendable {
        var id: String
        var text: String
    }
}

/// 生存手册目录树。
struct HandbookIndex: Sendable {
    struct Part: Identifiable, Hashable, Sendable {
        var id: String { key }
        var key: String
        var label: String
        var groups: [Group]
    }
    struct Group: Identifiable, Hashable, Sendable {
        var id: String { "\(key)-\(items.map(\.slug).joined(separator: ","))" }
        var key: String
        var items: [DocItem]
    }
    var parts: [Part]
}

/// 经验长文索引 + 可选筛选项。
struct ExperienceIndex: Sendable {
    struct Facet: Identifiable, Hashable, Sendable {
        var id: String { key }
        var key: String
        var label: String
        var values: [String]
    }
    var filters: [Facet]
    var items: [DocItem]
}

/// 手册/经验条目在索引里的形态。
struct DocItem: Identifiable, Hashable, Sendable {
    var id: String { slug }
    var slug: String
    var kind: String
    var title: String
    var description: String?
    var author: String?
    var occurredAt: String?
    var category: String?
    var grade: String?
    var college: String?
    var part: String?
    var position: Int?
}

/// 条目详情（含正文与目录）。
struct DocDetail: Sendable {
    /// 目录条目。`id` 直接用后端给的锚点 id，它在同一篇文档内唯一。
    struct Outline: Identifiable, Hashable, Sendable {
        var id: String
        var text: String
        var level: Int
    }
    var slug: String
    var kind: String
    var title: String
    var description: String?
    var author: String?
    var occurredAt: String?
    var category: String?
    var grade: String?
    var college: String?
    var html: String?
    var outline: [Outline]
}

/// 资讯详情（`/api/site/items/:id`），加载失败时详情页回退展示列表传入的 FeedItem 摘要。
struct FeedItemDetail {
    var originalTitle: String?
    var summary: String?
    var reason: String?
    /// 服务端白名单 HTML，由 `HTMLRenderer` 异步转成 `AttributedString`。
    var bodyHTML: String?
    var originalURL: URL?
}

extension String {
    /// 只对非 ASCII 做 percent-encoding，保留 `/`。
    ///
    /// 后端 `/api/site/docs/*` 是通配路由，slug 里的 `/` 是**路径分隔符**而不是数据，
    /// 编码掉就匹配不上（实测 404）。`addingPercentEncoding` 用一个保留 `/` 的
    /// 字符集即可，不必自己分段。
    var percentEncodedPath: String {
        addingPercentEncoding(withAllowedCharacters: .seuWikiPath) ?? self
    }
}

extension CharacterSet {
    /// URL 路径里允许**原样出现**的字符：ASCII 字母数字 + `-._~` + `/`。
    ///
    /// ⚠️ **不能用 `CharacterSet.alphanumerics`**：它是 Unicode 感知的，会把中文
    /// 汉字当成「字母」直接放行，于是 slug 完全没被编码，后端按字面量去查表必然 404。
    /// （自检里那条 `slug/中文已编码` 就是防这个的。）
    static let seuWikiPath: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        set.insert(charactersIn: "0123456789")
        set.insert(charactersIn: "-._~/")
        return set
    }()
}

// MARK: - 日期解析

/// 集中管理日期格式。**不要**在解码路径里现建 `DateFormatter`。
///
/// `DateFormatter` 的构造开销不小（每次都要读 locale/calendar），而解码是逐条目的热路径。
/// 这里预先建好并复用：Foundation 保证 `DateFormatter` 在**未被修改**的前提下
/// 并发解析是安全的（iOS 7+），所以用 `nonisolated(unsafe)` 放行静态隔离检查。
enum DateParser {
    /// 带时区的 ISO8601，兼容有无毫秒（实测 `"2026-10-04T04:47:20.333Z"`）。
    nonisolated(unsafe) static let iso8601: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return f
    }()

    /// 不带毫秒的 ISO8601，作为上一条的降级。
    nonisolated(unsafe) static let iso8601NoFraction: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f
    }()

    /// 只有日期的格式。后端 `analyze.ts` 的 `deadline` 产出 `YYYY-MM-DD`
    /// （截止日没有时刻），ISO8601 解析器解不了，缺它会**整页**解码失败。
    nonisolated(unsafe) static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 依次尝试三种格式。全失败返回 nil。
    static func parse(_ string: String) -> Date? {
        if let d = iso8601.date(from: string) { return d }
        if let d = iso8601NoFraction.date(from: string) { return d }
        return dateOnly.date(from: string)
    }
}

// MARK: - DTO（只解析 app 用到的字段，多余字段忽略）

private struct SourceDTO: Decodable {
    let name: String
}

/// 列表/详情均可能携带的 campus 受众。**后端当前从不输出这些字段**
/// （`toFeedItemSummary` 源码里没有 campus），全部可空容错。
private struct CampusDTO: Decodable {
    let identities: [String]?
    let colleges: [String]?
    let grades: [String]?
    let deadline: String?
    let valueTier: String?

    func audience() -> CampusAudience {
        CampusAudience(
            identities: identities ?? [],
            colleges: colleges ?? [],
            grades: grades ?? [],
            // deadline 是 `YYYY-MM-DD`，走 dateOnly 而不是 ISO8601。
            deadline: deadline.flatMap { DateParser.dateOnly.date(from: $0) },
            valueTier: CampusAudience.ValueTier(rawValue: valueTier ?? "") ?? .news
        )
    }
}

/// 对应 `FeedItemSummary`；for-you 额外有 matchReasons / rankScore（见 `ForYouItem`）。
private struct FeedItemSummaryDTO: Decodable {
    let id: String
    let title: String
    let summary: String?
    let reason: String?
    let source: SourceDTO
    let publishedAt: Date?
    let timelineAt: Date
    let category: String?
    let tags: [String]
    let score: Int?
    let selected: Bool
    let campus: CampusDTO?
    let matchReasons: [String]?
    let rankScore: Double?

    func feedItem() -> FeedItem {
        FeedItem(
            id: id,
            title: title,
            summary: summary ?? reason ?? "",
            sourceName: source.name,
            category: FeedCategory(rawValue: category ?? "") ?? .news,
            tags: tags,
            publishedAt: publishedAt ?? timelineAt,
            originalURL: nil, // 列表响应不含 links，进入详情时由 itemDetail 补齐
            score: score ?? 0,
            isSelected: selected,
            audience: campus?.audience() ?? CampusAudience(),
            matchReasons: matchReasons ?? []
        )
    }
}

private struct TimelineResponseDTO: Decodable {
    struct Card: Decodable {
        let item: FeedItemSummaryDTO
    }
    let cards: [Card]
    let nextCursor: String?
}

private struct ForYouResponseDTO: Decodable {
    let items: [FeedItemSummaryDTO]
    let nextCursor: String?
}

private struct PoolResponseDTO: Decodable {
    let items: [FeedItemSummaryDTO]
    let docs: [DocHitDTO]?
    let page: Int
    let pageCount: Int
    let total: Int
}

private struct DocHitDTO: Decodable {
    struct AnchorDTO: Decodable {
        let id: String
        let text: String
    }
    let slug: String
    let kind: String
    let title: String
    let description: String?
    let occurredAt: String?
    let anchor: AnchorDTO?

    var hit: DocSearchHit {
        DocSearchHit(
            slug: slug,
            kind: DocSearchHit.Kind(rawValue: kind) ?? .survival,
            title: title,
            description: description,
            occurredAt: occurredAt,
            anchor: anchor.map { DocSearchHit.Anchor(id: $0.id, text: $0.text) }
        )
    }
}

extension PoolResponseDTO {
    /// `docs` 的便捷映射，交给调用方时已转成模型。
    var mappedDocs: [DocSearchHit] { (docs ?? []).map(\.hit) }
}

private struct ItemDetailDTO: Decodable {
    struct Links: Decodable {
        let original: String?
    }
    struct Body: Decodable {
        let zh: String?
        /// 纯英文条目的回退正文。
        let original: String?
    }
    let originalTitle: String?
    let summary: String?
    let reason: String?
    let links: Links?
    let body: Body?
}

// MARK: - 手册 / 经验索引 DTO

private struct DocItemDTO: Decodable {
    let slug: String
    let kind: String
    let title: String
    let description: String?
    let author: String?
    let occurredAt: String?
    let category: String?
    let grade: String?
    let college: String?
    let part: String?
    let position: Int?

    var item: DocItem {
        DocItem(
            slug: slug, kind: kind, title: title, description: description,
            author: author, occurredAt: occurredAt, category: category,
            grade: grade, college: college, part: part, position: position
        )
    }
}

private struct SurvivalIndexDTO: Decodable {
    struct GroupDTO: Decodable {
        let key: String
        let items: [DocItemDTO]
    }
    struct PartDTO: Decodable {
        let key: String
        let label: String
        let groups: [GroupDTO]
    }
    let parts: [PartDTO]
}

private struct ExperienceIndexDTO: Decodable {
    struct FacetDTO: Decodable {
        let key: String
        let label: String
        let values: [String]
    }
    let filters: [FacetDTO]
    let items: [DocItemDTO]
}

private struct DocDetailDTO: Decodable {
    struct OutlineDTO: Decodable {
        let id: String
        let text: String
        let level: Int
    }
    let slug: String
    let kind: String
    let title: String
    let description: String?
    let author: String?
    let occurredAt: String?
    let category: String?
    let grade: String?
    let college: String?
    let html: String?
    let outline: [OutlineDTO]
}

private extension SurvivalIndexDTO {
    var index: HandbookIndex {
        HandbookIndex(parts: parts.map { part in
            HandbookIndex.Part(
                key: part.key,
                label: part.label,
                groups: part.groups.map { group in
                    HandbookIndex.Group(key: group.key, items: group.items.map(\.item))
                }
            )
        })
    }
}

// MARK: - 白名单 HTML → AttributedString

/// 服务端下发的正文是白名单 HTML（p/span/strong/a/img 等）。解析有两处必须处理：
///
/// 1. **不能放主线程。** 工程开了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，
///    `NSAttributedString(.html:)` 走 WebKit 的导入器，遇到 `<img>` 还会**同步**去拉图片，
///    表现为打开详情页时先卡一下。
/// 2. **`<img>` 应该在解析前剥掉。** App 的正文样式里没有图片位，保留只会白白发请求；
///    而且图片 URL 若指向内网/失效地址，同步拉取会拖长甚至挂住整个解析。
///
/// 解析后统一把字体换成系统正文的**动态字体**（保留粗体等 trait），
/// 顺便把暗色模式下「HTML 自带黑色前景色导致看不清」的问题一并解决：
/// 正文颜色交给 SwiftUI 的 `.foregroundStyle` 决定，HTML 里的颜色一律丢弃。
enum HTMLRenderer {
    /// 在后台线程完成 HTML 解析，返回 `AttributedString`（值类型、可跨 actor 传递）。
    static func render(_ html: String) async -> AttributedString? {
        let stripped = stripImages(html)
        guard let data = stripped.data(using: .utf8), !data.isEmpty else { return nil }

        return await Task.detached(priority: .userInitiated) {
            guard let parsed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            ) else { return nil }
            return restyle(parsed)
        }.value
    }

    private static func stripImages(_ html: String) -> String {
        // 保守地只删 img 标签本身（含属性），保留锚文本内容。
        html.replacingOccurrences(
            of: "<img[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// 换成系统正文字体并抹掉 HTML 自带的前景色。
    private nonisolated static func restyle(_ parsed: NSAttributedString) -> AttributedString {
        let mutable = NSMutableAttributedString(attributedString: parsed)
        let full = NSRange(location: 0, length: mutable.length)

        // 前景色：交给 SwiftUI 决定。HTML 常带 `color: #000000`，暗色模式下会黑字黑底。
        mutable.removeAttribute(.foregroundColor, range: full)
        mutable.removeAttribute(.backgroundColor, range: full)

        let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        mutable.enumerateAttribute(.font, in: full) { value, range, _ in
            let isBold = (value as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
            let isItalic = (value as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false
            var traits: UIFontDescriptor.SymbolicTraits = []
            if isBold { traits.insert(.traitBold) }
            if isItalic { traits.insert(.traitItalic) }
            var descriptor = base
            if !traits.isEmpty, let withTraits = descriptor.withSymbolicTraits(traits) {
                descriptor = withTraits
            }
            mutable.addAttribute(.font, value: UIFont(descriptor: descriptor, size: 0), range: range)
        }
        // 让行距跟随 Dynamic Type，AX 字号下不至于挤成一团。
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        mutable.addAttribute(.paragraphStyle, value: paragraph, range: full)
        return AttributedString(mutable)
    }
}
