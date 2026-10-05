import Foundation

/// 资讯模块的状态仓库：每个 console scope（为你精选 / 全部 / 各分类）各自维护
/// 一页 cursor 分页状态。
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
        var nextCursor: String?
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
    /// 否则旧画像的翻页结果会拼到新列表上。
    private var generations: [FeedScope: Int] = [:]
    /// for-you 当前的画像指纹。后端把画像编进 cursor，画像一变旧 cursor 立即作废。
    private var forYouFingerprint: String?

    init(client: FeedAPIClient = FeedAPIClient()) {
        self.client = client
    }

    func page(for scope: FeedScope) -> PageState {
        pages[scope] ?? PageState()
    }

    /// 首次进入某个 scope 时加载；已加载过的 scope 直接复用。
    func loadIfNeeded(scope: FeedScope, profile: UserProfile) async {
        guard !page(for: scope).hasLoaded else { return }
        await refresh(scope: scope, profile: profile)
    }

    /// 下拉刷新 / 首次加载。
    func refresh(scope: FeedScope, profile: UserProfile) async {
        guard !page(for: scope).isLoading else { return }

        // for-you 的 cursor 与画像绑定：画像变了必须丢掉旧 cursor，
        // 否则后端每次都回 400 invalid_cursor，列表会永远停在旧画像的结果上。
        if scope == .forYou {
            let fingerprint = profile.profileFingerprint
            if forYouFingerprint != fingerprint {
                forYouFingerprint = fingerprint
                pages[scope] = PageState()
            }
        }

        let generation = nextGeneration(for: scope)
        pages[scope, default: PageState()].isLoading = true
        pages[scope]?.errorMessage = nil
        defer {
            if generations[scope] == generation { pages[scope]?.isLoading = false }
        }
        do {
            let (items, nextCursor) = try await fetch(scope: scope, profile: profile, cursor: nil)
            guard generations[scope] == generation else { return }  // 已被更新的请求接管
            pages[scope] = PageState(
                items: Self.distinct(items),
                nextCursor: nextCursor,
                hasLoaded: true,
                isOffline: false,
                errorMessage: nil
            )
        } catch {
            if Self.isCancellation(error) { return }
            guard generations[scope] == generation else { return }
            var state = page(for: scope)
            state.nextCursor = nil
            state.hasLoaded = true
            state.isOffline = true
            state.errorMessage = Self.describe(error)
            pages[scope] = state
        }
    }

    /// 滚动到底加载下一页。失败静默，下次滚动到底会再试。
    func loadMore(scope: FeedScope, profile: UserProfile) async {
        let state = page(for: scope)
        guard state.hasLoaded, !state.isLoading, !state.isLoadingMore, !state.isOffline,
              let cursor = state.nextCursor else { return }

        let generation = generations[scope] ?? 0
        pages[scope]?.isLoadingMore = true
        defer {
            if generations[scope] == generation { pages[scope]?.isLoadingMore = false }
        }
        do {
            let (items, nextCursor) = try await fetch(scope: scope, profile: profile, cursor: cursor)
            // 刷新与翻页并发时，刷新已经重置了列表：这次的结果直接作废。
            guard generations[scope] == generation else { return }
            // 按 id 去重：for-you 的排序会随内容热度漂移，跨页出现重复 id 是现实场景。
            // 不去重的话 ForEach 行为未定义（Android 上会直接崩）。
            var seen = Set(pages[scope]?.items.map(\.id) ?? [])
            pages[scope]?.items.append(contentsOf: items.filter { seen.insert($0.id).inserted })
            pages[scope]?.nextCursor = nextCursor
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

    private static func distinct(_ items: [FeedItem]) -> [FeedItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
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
