import Foundation

/// 搜索信源 provider：大小写 / 变音符号不敏感的包含匹配。
/// - 「通知」线上实现是 `FeedAPIClient.pool`（由 SearchStore 调用，防抖 + 分页），
///   这里的本地匹配仅作网络失败时的回退；
/// - 「经验」「手册」当前是 MockData 本地 provider。
enum SearchEngine {
    /// 「通知」信源的回退 provider：线上 pool 搜索失败时用 MockData 本地匹配，不阻塞 UI。
    static func searchFeedOffline(keyword: String) -> [FeedItem] {
        MockData.feedItems.filter {
            matches($0.title, keyword) || matches($0.summary, keyword)
        }
    }

    /// 「经验」信源 provider。论坛后端 seu-forum 已部署但公网 DNS 未生效，App 暂时无法访问，
    /// 当前用 MockData 本地匹配；后续替换为 seu-forum 的 `GET /api/posts`（公开只读）远程实现。
    static func searchForum(keyword: String) -> [ForumPost] {
        MockData.forumPosts.filter {
            matches($0.title, keyword) || matches($0.excerpt, keyword)
        }
    }

    /// 「手册」信源 provider：MockData 本地匹配。
    static func searchHandbook(keyword: String) -> [HandbookEntry] {
        MockData.handbookSections.flatMap(\.entries).filter {
            matches($0.title, keyword) || matches($0.subtitle, keyword) || matches($0.body, keyword)
        }
    }

    static func matches(_ text: String, _ key: String) -> Bool {
        text.range(of: key, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

extension String {
    /// 关键词命中片段加粗（strong emphasis），字号与颜色沿用外层设置。
    func highlighting(_ keyword: String) -> AttributedString {
        var attributed = AttributedString(self)
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return attributed }

        var lowerBound = startIndex
        while let match = range(of: key, options: [.caseInsensitive, .diacriticInsensitive], range: lowerBound..<endIndex) {
            if let attributedRange = Range(match, in: attributed) {
                attributed[attributedRange].inlinePresentationIntent = .stronglyEmphasized
            }
            lowerBound = match.upperBound
        }
        return attributed
    }
}
