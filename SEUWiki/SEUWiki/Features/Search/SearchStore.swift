import Foundation

/// 搜索状态仓库。三个信源：
/// - **通知**：`/api/site/pool?type=feed`（seu.wiki，分页 page/pageCount）；
/// - **经验（论坛帖子）**：论坛 `/api/search?type=post`（keyset 分页）；
/// - **手册（东大生存手册文章）**：论坛 `/api/search?type=article`（keyset 分页）。
///
/// 经验与手册原先走 pool 的 `docs`（`/api/site/docs/*` 长文），已随经验长文
/// 信源移除而切换到论坛搜索 —— pool 现在只留资讯。论坛 `/api/search` 属阶段 2
/// 接口、与后端并行开发中：未部署时 `forumUnavailable = true`，UI 显式标注，
/// 通知信源不受影响。
///
/// 失败**不回退假数据**：显示错误态 + 重试按钮。
@Observable
@MainActor
final class SearchStore {
    /// 单个信源的分页状态（pool 用 page/pageCount 分页，每页 40 条）。
    struct FeedSearchState {
        var items: [FeedItem] = []
        var page = 0
        var pageCount = 0
        var total = 0
        var isLoadingMore = false

        var hasMore: Bool { page < pageCount }
    }

    /// 论坛搜索的一组结果（帖子或手册文章），keyset 分页。
    struct ForumSearchGroup<Item: Identifiable> where Item.ID: Hashable {
        var items: [Item] = []
        var nextCursor: String?
        var isLoadingMore = false
    }

    private let client: FeedAPIClient
    private let forumClient: ForumAPIClient
    private var searchTask: Task<Void, Never>?

    /// 当前生效的搜索词（已 trim）；结果行的关键词高亮由视图传入，不经由这里。
    private(set) var keyword = ""
    var feed = FeedSearchState()
    /// 论坛帖子命中（`/api/search` 的 posts 组）。
    var forum = ForumSearchGroup<ForumPost>()
    /// 手册文章命中（`/api/search` 的 articles 组）。
    var handbook = ForumSearchGroup<HandbookArticleSummary>()
    /// true 表示正在等待/进行搜索请求（含防抖），用于空态避免闪烁。
    var isSearching = false
    /// 通知信源失败的原因，`nil` 表示没有错误。UI 必须展示它，不要静默。
    var errorMessage: String?
    /// 论坛搜索未部署（404）或其他失败。与通知信源分开：论坛搜不了
    /// 不该把还能用的通知结果一起藏起来。
    var forumErrorMessage: String?
    /// 论坛搜索接口尚未部署（路由 404）。
    private(set) var forumUnavailable = false

    init(client: FeedAPIClient = FeedAPIClient(), forumClient: ForumAPIClient = ForumAPIClient()) {
        self.client = client
        self.forumClient = forumClient
    }

    var isEmpty: Bool {
        feed.items.isEmpty && forum.items.isEmpty && handbook.items.isEmpty
    }

    func isEmpty(for scope: SearchScope) -> Bool {
        switch scope {
        case .all: isEmpty
        case .feed: feed.items.isEmpty
        case .forum: forum.items.isEmpty
        case .handbook: handbook.items.isEmpty
        }
    }

    /// 某个信源是否还有更多（用于「查看更多」页翻页）。
    func hasMore(for scope: SearchScope) -> Bool {
        switch scope {
        case .all: false
        case .feed: feed.hasMore
        case .forum: forum.nextCursor != nil
        case .handbook: handbook.nextCursor != nil
        }
    }

    /// 关键词变化入口：新关键词取消旧任务，防抖 300ms 后并发请求两个线上信源。
    /// 两个信源各自成败、互不牵连 —— 论坛 404 不该把已经搜到的通知清掉。
    /// 任务被取消不算失败。
    func search(keyword newKeyword: String) {
        let key = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        keyword = key
        errorMessage = nil
        forumErrorMessage = nil
        guard !key.isEmpty else {
            feed = FeedSearchState()
            forum = ForumSearchGroup()
            handbook = ForumSearchGroup()
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return  // 防抖期被新输入取消
            }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.searchFeed(key: key) }
                group.addTask { await self.searchForum(key: key) }
            }
            if keyword == key { isSearching = false }
        }
    }

    private func searchFeed(key: String) async {
        do {
            let pool = try await client.pool(query: key, page: 1)
            guard !Task.isCancelled, keyword == key else { return }
            feed = FeedSearchState(
                items: pool.items,
                page: pool.page,
                pageCount: pool.pageCount,
                total: pool.total
            )
            errorMessage = nil
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard keyword == key else { return }
            feed = FeedSearchState()
            if let api = error as? FeedAPIClient.FeedAPIError, case .searchBusy = api {
                errorMessage = "搜索服务正忙，稍后再试"
            } else {
                errorMessage = "搜索失败：\(error.localizedDescription)"
            }
        }
    }

    private func searchForum(key: String) async {
        do {
            let result = try await forumClient.search(query: key, type: .all)
            guard !Task.isCancelled, keyword == key else { return }
            forum = ForumSearchGroup(items: Paging.distinct(result.posts), nextCursor: result.postsNextCursor)
            handbook = ForumSearchGroup(items: Paging.distinct(result.articles), nextCursor: result.articlesNextCursor)
            forumErrorMessage = nil
            forumUnavailable = false
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard keyword == key else { return }
            forum = ForumSearchGroup()
            handbook = ForumSearchGroup()
            if let api = error as? ForumAPIClient.ForumAPIError {
                switch api {
                case .routeUnavailable:
                    forumUnavailable = true
                    forumErrorMessage = "论坛搜索即将上线"
                case .unauthorized:
                    // 搜索是公开读，不该走到这里；真来了就如实展示。
                    forumErrorMessage = "论坛搜索需要登录态，请到个人页重新登录"
                default:
                    forumErrorMessage = api.errorDescription
                }
            } else {
                forumErrorMessage = "论坛搜索失败：\(error.localizedDescription)"
            }
        }
    }

    /// 滚动到底 / 「查看更多」页加载下一页。失败静默，下次触发会再试。
    func loadMore(for scope: SearchScope) async {
        let key = keyword
        guard !key.isEmpty else { return }
        switch scope {
        case .all:
            return
        case .feed:
            guard feed.hasMore, !feed.isLoadingMore, !isSearching else { return }
            feed.isLoadingMore = true
            defer { feed.isLoadingMore = false }
            do {
                let result = try await client.pool(query: key, page: feed.page + 1)
                guard keyword == key else { return }
                feed.items = Paging.merge(existing: feed.items, incoming: result.items)
                feed.page = result.page
                feed.pageCount = result.pageCount
                feed.total = result.total
            } catch {
                if let api = error as? FeedAPIClient.FeedAPIError, case .searchBusy = api {
                    errorMessage = "搜索服务正忙，稍后再试"
                }
            }
        case .forum:
            guard let cursor = forum.nextCursor, !forum.isLoadingMore, !isSearching else { return }
            forum.isLoadingMore = true
            defer { forum.isLoadingMore = false }
            do {
                let result = try await forumClient.search(query: key, type: .post, cursor: cursor)
                guard keyword == key else { return }
                forum.items = Paging.merge(existing: forum.items, incoming: result.posts)
                forum.nextCursor = result.postsNextCursor
            } catch {
                // 翻页失败静默：滚到底会自然重试。
            }
        case .handbook:
            guard let cursor = handbook.nextCursor, !handbook.isLoadingMore, !isSearching else { return }
            handbook.isLoadingMore = true
            defer { handbook.isLoadingMore = false }
            do {
                let result = try await forumClient.search(query: key, type: .article, cursor: cursor)
                guard keyword == key else { return }
                handbook.items = Paging.merge(existing: handbook.items, incoming: result.articles)
                handbook.nextCursor = result.articlesNextCursor
            } catch {
                // 同上。
            }
        }
    }
}
