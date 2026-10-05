import Foundation

/// 搜索状态仓库。**三个信源全部走线上**。
///
/// 关键事实：`/api/site/pool` 一个接口同时返回三类命中 ——
/// `items`（通知动态）与 `docs`（`kind` 为 `survival` 的手册条目 / `experience` 的经验长文）。
/// 早期版本只取 `items`、把 `docs` 扔掉，然后用本地假数据填「经验」和「手册」两栏，
/// 表现为「搜什么都出同一批编造内容」。现在三栏都来自真实数据。
///
/// 失败**不再回退假数据**：显示错误态 + 重试按钮。搜索结果里混进假内容比搜不到更糟。
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

    private let client: FeedAPIClient
    private var searchTask: Task<Void, Never>?

    /// 当前生效的搜索词（已 trim）；结果行的关键词高亮由视图传入，不经由这里。
    private(set) var keyword = ""
    var feed = FeedSearchState()
    /// 经验长文命中（`docs` 中 kind == experience）。
    var forum: [DocSearchHit] = []
    /// 生存手册命中（`docs` 中 kind == survival）。
    var handbook: [DocSearchHit] = []
    /// true 表示正在等待/进行 pool 请求（含防抖），用于空态避免闪烁。
    var isSearching = false
    /// 搜索失败的原因，`nil` 表示没有错误。UI 必须展示它，不要静默。
    var errorMessage: String?
    /// 单信源列表页（`SearchSourceListView`）当前在翻的页。
    private var sourcePage: [SearchScope: Int] = [:]

    init(client: FeedAPIClient = FeedAPIClient()) {
        self.client = client
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

    /// 某个信源是否还有更多（用于「查看更多」页翻页）。
    func hasMore(for scope: SearchScope) -> Bool {
        switch scope {
        case .all, .forum, .handbook: false   // docs 一次性返回，不分页
        case .feed: feed.hasMore
        }
    }

    /// 关键词变化入口：新关键词取消旧任务，防抖 300ms 后请求线上 pool。
    /// 任务被取消不算失败。
    func search(keyword newKeyword: String) {
        let key = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        keyword = key
        errorMessage = nil
        sourcePage = [:]
        guard !key.isEmpty else {
            feed = FeedSearchState()
            forum = []
            handbook = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                let result = try await client.pool(query: key, type: .all, page: 1)
                // 请求期间关键词已变：结果作废，交给新搜索自己落地。
                guard !Task.isCancelled, keyword == key else { return }
                apply(result)
            } catch {
                // 任务被取消（快速连续输入）：不算失败，交给新任务接管。
                if Task.isCancelled || error is CancellationError { return }
                if let api = error as? FeedAPIClient.FeedAPIError, case .searchBusy = api {
                    errorMessage = "搜索服务正忙，稍后再试"
                } else {
                    errorMessage = "搜索失败：\(error.localizedDescription)"
                }
                feed = FeedSearchState()
                forum = []
                handbook = []
            }
            if keyword == key { isSearching = false }
        }
    }

    private func apply(_ result: PoolResult) {
        feed = FeedSearchState(
            items: result.items,
            page: result.page,
            pageCount: result.pageCount,
            total: result.total
        )
        forum = result.experienceHits
        handbook = result.survivalHits
        errorMessage = nil
    }

    /// 「通知」列表滚动到底加载下一页。失败静默，下次滚到底会再试。
    func loadMoreFeed() async {
        let key = keyword
        guard !key.isEmpty, feed.hasMore, !feed.isLoadingMore, !isSearching else { return }
        feed.isLoadingMore = true
        defer { feed.isLoadingMore = false }
        do {
            let result = try await client.pool(query: key, type: .all, page: feed.page + 1)
            guard keyword == key else { return }
            // 按 id 去重：pool 的排序会随内容热度漂移，跨页出现重复 id 是现实场景。
            // 不去重会让 ForEach 行为未定义。
            var seen = Set(feed.items.map(\.id))
            feed.items.append(contentsOf: result.items.filter { seen.insert($0.id).inserted })
            feed.page = result.page
            feed.pageCount = result.pageCount
            feed.total = result.total
        } catch {
            if let api = error as? FeedAPIClient.FeedAPIError, case .searchBusy = api {
                errorMessage = "搜索服务正忙，稍后再试"
            }
        }
    }

    /// 「查看更多」页的翻页：只追加当前信源的去重结果。
    ///
    /// `docs`（经验/手册）由后端一次性返回、不分页，所以这两个 scope 直接返回 false。
    func loadMore(for scope: SearchScope) async {
        guard scope == .feed else { return }
        await loadMoreFeed()
    }
}
