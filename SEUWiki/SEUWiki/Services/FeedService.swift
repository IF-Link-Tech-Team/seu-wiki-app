import Foundation
import UIKit

/// seu.wiki 线上只读 API（/api/site/*，契约见 seu-wiki-v2 `packages/contracts/src/site.ts`）。
/// 匿名访问；timeline 带 ETag（URLSession 默认缓存策略自动发 If-None-Match、处理 304），
/// for-you 响应是 `private, no-store`，因人而异不缓存。
struct FeedAPIClient: Sendable {
    var baseURL = URL(string: "https://seu.wiki")!
    var session: URLSession = .shared
    var pageSize = 20

    enum FeedAPIError: Error {
        case http(statusCode: Int)
    }

    // MARK: - Endpoints

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
    func forYou(profile: UserProfile, cursor: String? = nil) async throws -> (items: [FeedItem], nextCursor: String?) {
        var query = [URLQueryItem(name: "limit", value: String(pageSize))]
        if !profile.college.isEmpty { query.append(URLQueryItem(name: "college", value: profile.college)) }
        if !profile.degree.isEmpty { query.append(URLQueryItem(name: "degree", value: profile.degree)) }
        if !profile.grade.isEmpty { query.append(URLQueryItem(name: "grade", value: profile.grade)) }
        if !profile.interests.isEmpty { query.append(URLQueryItem(name: "interests", value: profile.interests.joined(separator: ","))) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let response: ForYouResponseDTO = try await get("/api/site/for-you", query: query)
        return (response.items.map { $0.feedItem() }, response.nextCursor)
    }

    /// GET /api/site/items/:id → 详情（含 body.zh 白名单 HTML 与 links.original）。
    func itemDetail(id: String) async throws -> FeedItemDetail {
        let dto: ItemDetailDTO = try await get("/api/site/items/\(id)", query: [])
        return FeedItemDetail(
            originalTitle: dto.originalTitle,
            summary: dto.summary,
            reason: dto.reason,
            body: dto.body?.zh.flatMap { AttributedString(campusHTML: $0) },
            originalURL: dto.links?.original.flatMap { URL(string: $0) }
        )
    }

    /// GET /api/site/pool?q=&page= → 全站搜索。items 结构与 timeline 相同，
    /// 走同一套 DTO 映射；分页用 page/pageCount（每页 40 条），docs（手册/经验命中）暂不使用。
    func pool(query: String, page: Int = 1) async throws -> (items: [FeedItem], page: Int, pageCount: Int, total: Int) {
        let response: PoolResponseDTO = try await get("/api/site/pool", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
        ])
        return (response.items.map { $0.feedItem() }, response.page, response.pageCount, response.total)
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else { throw FeedAPIError.http(statusCode: status) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // 实测为带毫秒的 ISO8601（"2026-10-04T04:47:20.333Z"），兼容不带毫秒。
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: string) { return date }
            if let date = ISO8601DateFormatter().date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解析日期: \(string)")
        }
        return try decoder.decode(T.self, from: data)
    }
}

/// 资讯详情（/api/site/items/:id），加载失败时详情页回退展示列表传入的 FeedItem 摘要。
struct FeedItemDetail {
    var originalTitle: String?
    var summary: String?
    var reason: String?
    var body: AttributedString?
    var originalURL: URL?
}

// MARK: - DTO（只解析 app 用到的字段，多余字段忽略）

private struct SourceDTO: Decodable {
    let name: String
}

/// 列表/详情均可能携带的 campus 受众（契约里有，但当前线上未输出；全部可空容错）。
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
            deadline: deadline.flatMap { ISO8601DateFormatter().date(from: $0) },
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

/// 对应 `PoolResponse`，只取 items 与分页字段（filters / docs / freshness 等暂不使用）。
private struct PoolResponseDTO: Decodable {
    let items: [FeedItemSummaryDTO]
    let page: Int
    let pageCount: Int
    let total: Int
}

private struct ItemDetailDTO: Decodable {
    struct Links: Decodable {
        let original: String?
    }
    struct Body: Decodable {
        let zh: String?
    }
    let originalTitle: String?
    let summary: String?
    let reason: String?
    let links: Links?
    let body: Body?
}

// MARK: - 白名单 HTML → AttributedString

extension AttributedString {
    /// body.zh 是服务端白名单 HTML（p/span/strong/a/img 等）。HTML 解析的默认字体偏小，
    /// 统一替换为系统正文动态字体，只保留粗体等 trait。
    init?(campusHTML html: String) {
        guard let data = html.data(using: .utf8),
              let parsed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              ) else { return nil }
        let restyled = NSMutableAttributedString(attributedString: parsed)
        restyled.enumerateAttribute(.font, in: NSRange(location: 0, length: restyled.length)) { value, range, _ in
            let bold = (value as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
            var descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            if bold, let withBold = descriptor.withSymbolicTraits(.traitBold) {
                descriptor = withBold
            }
            restyled.addAttribute(.font, value: UIFont(descriptor: descriptor, size: 0), range: range)
        }
        self.init(restyled)
    }
}
