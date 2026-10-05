import Foundation

/// 资讯模块的状态仓库：每个 console scope（为你精选 / 全部 / 各分类）各自维护一页
/// cursor 分页状态。网络失败时回退 MockData 并标记离线，不阻塞 UI。
@Observable
@MainActor
final class FeedStore {
    struct PageState {
        var items: [FeedItem] = []
        var nextCursor: String?
        var isLoading = false
        var isLoadingMore = false
        var hasLoaded = false
        /// true 表示当前数据是网络失败后的 MockData 回退。
        var isOffline = false
    }

    private let client: FeedAPIClient
    /// Preview 用：永远使用 MockData，不发起网络请求。
    private let mockOnly: Bool
    private var pages: [FeedScope: PageState] = [:]
    private var detailCache: [String: FeedItemDetail] = [:]

    init(client: FeedAPIClient = FeedAPIClient(), mockOnly: Bool = false) {
        self.client = client
        self.mockOnly = mockOnly
    }

    func page(for scope: FeedScope) -> PageState {
        pages[scope] ?? PageState()
    }

    /// 首次进入某个 scope 时加载；已加载过的 scope 直接复用。
    func loadIfNeeded(scope: FeedScope, profile: UserProfile) async {
        guard !page(for: scope).hasLoaded else { return }
        await refresh(scope: scope, profile: profile)
    }

    /// 下拉刷新 / 首次加载：成功后重置分页，失败回退 MockData。
    func refresh(scope: FeedScope, profile: UserProfile) async {
        guard !page(for: scope).isLoading else { return }
        if mockOnly {
            var state = PageState()
            state.items = Self.mockItems(for: scope)
            state.hasLoaded = true
            pages[scope] = state
            return
        }
        pages[scope, default: PageState()].isLoading = true
        defer { pages[scope]?.isLoading = false }
        do {
            let (items, nextCursor) = try await fetch(scope: scope, profile: profile, cursor: nil)
            pages[scope] = PageState(items: items, nextCursor: nextCursor, hasLoaded: true)
        } catch {
            // 任务被取消（如快速切换 scope）：不算失败，下次进入时重新加载。
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            var state = page(for: scope)
            if state.items.isEmpty {
                state.items = Self.mockItems(for: scope)
            }
            state.nextCursor = nil
            state.hasLoaded = true
            state.isOffline = true
            pages[scope] = state
        }
    }

    /// 滚动到底加载下一页。失败静默，下次滚动到底会再试。
    func loadMore(scope: FeedScope, profile: UserProfile) async {
        let state = page(for: scope)
        guard !mockOnly, state.hasLoaded, !state.isLoading, !state.isLoadingMore, !state.isOffline,
              let cursor = state.nextCursor else { return }
        pages[scope]?.isLoadingMore = true
        defer { pages[scope]?.isLoadingMore = false }
        do {
            let (items, nextCursor) = try await fetch(scope: scope, profile: profile, cursor: cursor)
            pages[scope]?.items.append(contentsOf: items)
            pages[scope]?.nextCursor = nextCursor
        } catch {}
    }

    /// 资讯详情（body / originalURL 等）。结果按 id 缓存；失败时调用方回退展示 FeedItem 摘要。
    func detail(for item: FeedItem) async throws -> FeedItemDetail {
        if let cached = detailCache[item.id] { return cached }
        if mockOnly {
            return FeedItemDetail(summary: item.summary, originalURL: item.originalURL)
        }
        let detail = try await client.itemDetail(id: item.id)
        detailCache[item.id] = detail
        return detail
    }

    // MARK: - Private

    private func fetch(scope: FeedScope, profile: UserProfile, cursor: String?) async throws -> (items: [FeedItem], nextCursor: String?) {
        switch scope {
        case .forYou:
            try await client.forYou(profile: profile, cursor: cursor)
        case .all:
            try await client.timeline(cursor: cursor)
        case .category(let category):
            try await client.timeline(category: category, cursor: cursor)
        }
    }

    /// 离线 / Preview 兜底：排序规则与线上语义对齐（为你精选按命中理由优先，其余按时间倒序）。
    private static func mockItems(for scope: FeedScope) -> [FeedItem] {
        switch scope {
        case .forYou:
            PreviewSample.feedItems.sorted { lhs, rhs in
                if !lhs.matchReasons.isEmpty != !rhs.matchReasons.isEmpty {
                    return !lhs.matchReasons.isEmpty
                }
                return lhs.publishedAt > rhs.publishedAt
            }
        case .all:
            PreviewSample.feedItems.sorted { $0.publishedAt > $1.publishedAt }
        case .category(let category):
            PreviewSample.feedItems
                .filter { $0.category == category }
                .sorted { $0.publishedAt > $1.publishedAt }
        }
    }
}
