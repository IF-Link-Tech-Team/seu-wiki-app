import Foundation

/// 搜索模块的状态仓库：「通知」走线上 pool 搜索（300ms 防抖、失败回退 MockData、page 分页），
/// 「经验」「手册」由 SearchEngine 的本地 provider 即时给出。
@Observable
@MainActor
final class SearchStore {
    /// 「通知」信源的分页状态（pool 用 page/pageCount 分页，每页 40 条）。
    struct FeedSearchState {
        var items: [FeedItem] = []
        var page = 0
        var pageCount = 0
        var total = 0
        var isLoadingMore = false
        /// true 表示当前数据是网络失败后的 MockData 回退。
        var isOffline = false

        var hasMore: Bool { !isOffline && page < pageCount }
    }

    private let client: FeedAPIClient
    /// Preview 用：永远使用本地 provider，不发起网络请求。
    private let mockOnly: Bool
    private var searchTask: Task<Void, Never>?

    /// 当前生效的搜索词（已 trim）；结果行的关键词高亮由视图传入，不经由这里。
    private(set) var keyword = ""
    var feed = FeedSearchState()
    var forum: [ForumPost] = []
    var handbook: [HandbookEntry] = []
    /// true 表示正在等待/进行 pool 请求（含防抖），用于空态避免闪烁。
    var isSearching = false

    init(client: FeedAPIClient = FeedAPIClient(), mockOnly: Bool = false) {
        self.client = client
        self.mockOnly = mockOnly
    }

    var isEmpty: Bool {
        feed.items.isEmpty && forum.isEmpty && handbook.isEmpty
    }

    func isEmpty(for scope: SearchScope) -> Bool {
        switch scope {
        case .all: isEmpty
        case .feed: feed.items.isEmpty
        case .forum: forum.isEmpty
        case .handbook: handbook.isEmpty
        }
    }

    /// 关键词变化入口（手动输入与热门搜索 chips 相同）：新关键词取消旧任务，
    /// 防抖 300ms 后请求线上 pool；任务被取消不算失败。
    func search(keyword newKeyword: String) {
        let key = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        keyword = key
        guard !key.isEmpty else {
            feed = FeedSearchState()
            forum = []
            handbook = []
            isSearching = false
            return
        }
        // 「经验」「手册」本地 provider 即时出结果；「通知」走线上。
        forum = SearchEngine.searchForum(keyword: key)
        handbook = SearchEngine.searchHandbook(keyword: key)
        if mockOnly {
            let items = SearchEngine.searchFeedOffline(keyword: key)
            feed = FeedSearchState(items: items, total: items.count, isOffline: true)
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                let (items, page, pageCount, total) = try await client.pool(query: key, page: 1)
                feed = FeedSearchState(items: items, page: page, pageCount: pageCount, total: total)
            } catch {
                // 任务被取消（快速连续输入）：不算失败，交给新任务接管。
                if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
                // 网络失败回退 MockData 本地匹配（现状行为），不阻塞。
                let items = SearchEngine.searchFeedOffline(keyword: key)
                feed = FeedSearchState(items: items, total: items.count, isOffline: true)
            }
            isSearching = false
        }
    }

    /// 「通知」完整列表页滚动到底加载下一页；失败静默，下次滚动到底会再试。
    func loadMoreFeed() async {
        let key = keyword
        guard !mockOnly, !key.isEmpty, feed.hasMore, !feed.isLoadingMore, !isSearching else { return }
        feed.isLoadingMore = true
        defer { feed.isLoadingMore = false }
        do {
            let (items, page, pageCount, total) = try await client.pool(query: key, page: feed.page + 1)
            // 请求期间关键词已变化：结果作废，交给新搜索自己落地。
            guard keyword == key else { return }
            feed.items.append(contentsOf: items)
            feed.page = page
            feed.pageCount = pageCount
            feed.total = total
        } catch {}
    }
}
