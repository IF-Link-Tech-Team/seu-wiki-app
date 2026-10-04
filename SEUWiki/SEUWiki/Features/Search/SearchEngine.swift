import Foundation

/// 一次关键词搜索在三个信源上的命中集合。
struct SearchResults {
    var feed: [FeedItem] = []
    var forum: [ForumPost] = []
    var handbook: [HandbookEntry] = []

    var isEmpty: Bool {
        feed.isEmpty && forum.isEmpty && handbook.isEmpty
    }

    func isEmpty(for scope: SearchScope) -> Bool {
        switch scope {
        case .all: isEmpty
        case .feed: feed.isEmpty
        case .forum: forum.isEmpty
        case .handbook: handbook.isEmpty
        }
    }
}

/// 本地聚合搜索：大小写 / 变音符号不敏感的包含匹配。
enum SearchEngine {
    static func search(_ keyword: String) -> SearchResults {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return SearchResults() }

        return SearchResults(
            feed: MockData.feedItems.filter {
                matches($0.title, key) || matches($0.summary, key)
            },
            forum: MockData.forumPosts.filter {
                matches($0.title, key) || matches($0.excerpt, key)
            },
            handbook: MockData.handbookSections.flatMap(\.entries).filter {
                matches($0.title, key) || matches($0.subtitle, key) || matches($0.body, key)
            }
        )
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
