import Foundation

/// 资讯模块的状态仓库：每个 console scope（精选 / 一手 / 各分类 / 全部）各自维护
/// 一份分页状态。精选走 timeline 的 cursor 分页，一手 / 分类 / 全部走 pool 的
/// page 分页（与网页端 2026-10-08 信息架构重构对齐），两种分页在同一份
/// `PageState` 里并存（`nextCursor` 与 `nextPage` 只会有一个非空）。
///
/// 网络失败时**不再回退演示数据** —— 早期版本失败就塞 `PreviewSample` 并标
/// `isOffline`，用户会以为看到了真内容。资讯是这个 App 的核心，编造的条目比
/// 一个错误态糟糕得多。现在失败就是失败：`isOffline` + `errorMessage`，
/// UI 给重试。
@Observable
@MainActor
final class FeedStore {
    struct PageState {
        var items: [FeedItem] = []
        /// timeline（精选）的下一页游标。
        var nextCursor: String?
        /// pool（一手 / 分类 / 全部）的下一页页码（1 起）。
        var nextPage: Int?
        var isLoading = false
        var isLoadingMore = false
        var hasLoaded = false
        /// true 表示最近一次请求失败、内容是旧的。
        var isOffline = false
        /// 最近一次失败的原因，UI 应如实展示。
        var errorMessage: String?
    }

    private let client: FeedAPIClient
    private var pages: [FeedScope: PageState] = [:]
    private var detailCache: [String: FeedItemDetail] = [:]
    /// 每个 scope 的请求代号。刷新与翻页并发时，返回值要核对代号 ——
    /// 否则旧请求的翻页结果会拼到新列表上。
    private var generations: [FeedScope: Int] = [:]

    init(client: FeedAPIClient = FeedAPIClient()) {
        self.client = client
    }

    func page(for scope: FeedScope) -> PageState {
        pages[scope] ?? PageState()
    }

    /// 按 id 在**已加载**的分页里找一条资讯。
    ///
    /// 通知深链进来时 App 可能刚冷启动，任何 scope 都还没加载过，这时返回 nil，
    /// 调用方退化成 [FeedItem.placeholder(id:)]，由详情页去拉真实内容。
    /// 找不到不是错误 —— 所以这里不去碰网络。
    func findItem(id: String) -> FeedItem? {
        for page in pages.values {
            if let hit = page.items.first(where: { $0.id == id }) { return hit }
        }
        return nil
    }

    /// 首次进入某个 scope 时加载；已加载过的 scope 直接复用。
    func loadIfNeeded(scope: FeedScope) async {
        guard !page(for: scope).hasLoaded else { return }
        await refresh(scope: scope)
    }

    /// 下拉刷新 / 首次加载。
    func refresh(scope: FeedScope) async {
        guard !page(for: scope).isLoading else { return }

        let generation = nextGeneration(for: scope)
        pages[scope, default: PageState()].isLoading = true
        pages[scope]?.errorMessage = nil
        defer {
            if generations[scope] == generation { pages[scope]?.isLoading = false }
        }
        do {
            let result = try await fetch(scope: scope, cursor: nil, page: 1)
            guard generations[scope] == generation else { return }  // 已被更新的请求接管
            pages[scope] = PageState(
                items: Self.distinct(result.items),
                nextCursor: result.nextCursor,
                nextPage: result.nextPage,
                hasLoaded: true,
                isOffline: false,
                errorMessage: nil
            )
        } catch {
            if Self.isCancellation(error) { return }
            guard generations[scope] == generation else { return }
            var state = page(for: scope)
            state.nextCursor = nil
            state.nextPage = nil
            state.hasLoaded = true
            state.isOffline = true
            state.errorMessage = Self.describe(error)
            pages[scope] = state
        }
    }

    /// 滚动到底加载下一页。失败静默，下次滚动到底会再试。
    func loadMore(scope: FeedScope) async {
        let state = page(for: scope)
        guard state.hasLoaded, !state.isLoading, !state.isLoadingMore, !state.isOffline else { return }
        // 两种分页只会有一个 token 非空；都没有就是到底了。
        guard state.nextCursor != nil || state.nextPage != nil else { return }

        let generation = generations[scope] ?? 0
        pages[scope]?.isLoadingMore = true
        defer {
            if generations[scope] == generation { pages[scope]?.isLoadingMore = false }
        }
        do {
            let result = try await fetch(scope: scope, cursor: state.nextCursor, page: state.nextPage ?? 1)
            // 刷新与翻页并发时，刷新已经重置了列表：这次的结果直接作废。
            guard generations[scope] == generation else { return }
            // 按 id 去重（实现见 `Paging.merge`，被 `SelfCheck` 覆盖）。
            pages[scope]?.items = Paging.merge(existing: pages[scope]?.items ?? [], incoming: result.items)
            pages[scope]?.nextCursor = result.nextCursor
            pages[scope]?.nextPage = result.nextPage
        } catch {
            // 翻页失败静默：列表还有内容，不必打断用户；滚到底会自然重试。
        }
    }

    /// 资讯详情（body / originalURL 等）。结果按 id 缓存；失败时调用方回退展示 FeedItem 摘要。
    func detail(for item: FeedItem) async throws -> FeedItemDetail {
        if let cached = detailCache[item.id] { return cached }
        let detail = try await client.itemDetail(id: item.id)
        detailCache[item.id] = detail
        return detail
    }

    // MARK: - Private

    private func nextGeneration(for scope: FeedScope) -> Int {
        let next = (generations[scope] ?? 0) + 1
        generations[scope] = next
        return next
    }

    /// scope → 端点路由（与网页端 tab 一一对应）：
    /// 精选 → timeline（cursor 分页）；一手 / 分类 / 全部 → pool（page 分页，
    /// `hasMore = page < pageCount`）。
    private func fetch(scope: FeedScope, cursor: String?, page: Int) async throws -> (items: [FeedItem], nextCursor: String?, nextPage: Int?) {
        switch scope {
        case .featured:
            let result = try await client.timeline(cursor: cursor)
            return (result.items, result.nextCursor, nil)
        case .firstParty:
            let result = try await client.pool(channel: "firstParty", page: page)
            return (result.items, nil, result.hasMore ? result.page + 1 : nil)
        case .category(let category):
            let result = try await client.pool(category: category, page: page)
            return (result.items, nil, result.hasMore ? result.page + 1 : nil)
        case .all:
            let result = try await client.pool(page: page)
            return (result.items, nil, result.hasMore ? result.page + 1 : nil)
        }
    }

    private static func distinct(_ items: [FeedItem]) -> [FeedItem] {
        Paging.distinct(items)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    private static func describe(_ error: Error) -> String {
        if let api = error as? FeedAPIClient.FeedAPIError {
            return api.errorDescription ?? "请求失败"
        }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet: return "当前没有网络连接"
            case .timedOut: return "请求超时"
            default: return url.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
