import SwiftUI

/// 资讯页 console 选项：精选 / 一手 / 8 个资讯分类 / 全部。
/// 与网页端 tab 行（seu-wiki-v2 2026-10-08 信息架构重构）逐一对齐：
/// 精选走 timeline，一手 / 分类 / 全部走 pool；for-you 已被网页端删除，这里同步移除。
enum FeedScope: Hashable, Identifiable {
    case featured
    case firstParty
    case all
    case category(FeedCategory)

    var id: String {
        switch self {
        case .featured: "featured"
        case .firstParty: "firstParty"
        case .all: "all"
        case .category(let category): category.rawValue
        }
    }

    var title: String {
        switch self {
        case .featured: "精选"
        case .firstParty: "一手"
        case .all: "全部"
        case .category(let category): category.name
        }
    }

    /// 顺序即 tab 行顺序：精选、一手、8 个分类、全部。
    static let scopes: [FeedScope] = [.featured, .firstParty] + FeedCategory.allCases.map { .category($0) } + [.all]
}

/// 「全部」列表的筛选条件。
///
/// ⚠️ **只有分类筛选是真实生效的。** 后端 `toFeedItemSummary` 从不下发 `campus`
/// 受众字段（学院 / 学段 / 截止时间），所以「只看我的学院」和「学段」两个条件
/// 在客户端**永远匹配不到任何东西** —— 早期版本把它们做成可用的开关，用户勾了之后
/// 列表却完全不变，还以为是自己选错了学院。
///
/// 现在的处理：这两个条件在筛选面板里明确置灰并写清原因，不做「看起来能用但没效果」
/// 的假开关；分类筛选是真能用的（`FeedItem.category` 由后端下发）。
/// 等后端补上 audience 字段，把 `matches` 里的两行去掉置灰即可。
struct FeedFilter: Hashable {
    var onlyMyCollege = false
    var degree: String?                 // nil 为全部学段
    var categories: Set<FeedCategory> = []

    /// 后端尚未下发受众字段，暂时置灰。
    static let supportsAudienceFilter = false

    var isActive: Bool { onlyMyCollege || degree != nil || !categories.isEmpty }

    func matches(_ item: FeedItem, profile: UserProfile) -> Bool {
        if Self.supportsAudienceFilter {
            if onlyMyCollege, !item.audience.colleges.isEmpty, !item.audience.colleges.contains(profile.college) { return false }
            if let degree, !item.audience.identities.isEmpty, !item.audience.identities.contains(degree) { return false }
        }
        if !categories.isEmpty, !categories.contains(item.category) { return false }
        return true
    }
}

struct FeedHomeView: View {
    @Environment(UserProfile.self) private var profile
    @Environment(FeedStore.self) private var store
    @State private var showsProfile = false
    @State private var scope: FeedScope = .featured
    @State private var filter = FeedFilter()
    @State private var showsFilter = false
    /// 点提醒通知要打开的资讯 id，由 `RootTabView` 投递、消费后清空。
    var pendingItemID: Binding<String?> = .constant(nil)
    /// 显式路径而不是纯 `NavigationLink`：通知深链要**由代码**推进，
    /// 没有可供用户点的链接。
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            // ConsoleBar 用 `.safeAreaBar(edge: .top)` 固定在导航栏下方。
            // 放在 ScrollView 的 VStack 里会随内容一起滚走 —— 资讯有 11 个 scope，
            // 用户往下翻一屏就找不到 scope 切换器了，得滚回顶部才行。
            Group {
                    switch scope {
                    case .featured:
                        FeedItemList(
                            items: store.page(for: .featured).items,
                            page: store.page(for: .featured),
                            emptyMessage: "暂无精选资讯",
                            onRefresh: { await store.refresh(scope: .featured) },
                            onLoadMore: { await store.loadMore(scope: .featured) }
                        )
                    case .firstParty:
                        FeedItemList(
                            items: store.page(for: .firstParty).items,
                            page: store.page(for: .firstParty),
                            emptyMessage: "暂无一手资讯",
                            onRefresh: { await store.refresh(scope: .firstParty) },
                            onLoadMore: { await store.loadMore(scope: .firstParty) }
                        )
                    case .all:
                        FeedItemList(
                            items: allItems,
                            page: store.page(for: .all),
                            emptyMessage: filter.isActive ? "没有符合条件的资讯，试试调整筛选条件" : "暂无资讯",
                            onRefresh: { await store.refresh(scope: .all) },
                            onLoadMore: { await store.loadMore(scope: .all) }
                        )
                    case .category(let category):
                        FeedItemList(
                            items: store.page(for: .category(category)).items,
                            page: store.page(for: .category(category)),
                            emptyMessage: "该分类暂无资讯",
                            onRefresh: { await store.refresh(scope: .category(category)) },
                            onLoadMore: { await store.loadMore(scope: .category(category)) }
                        )
                    }
                }
                .transition(.opacity)
            .safeAreaBar(edge: .top) {
                ConsoleBar(items: FeedScope.scopes, selection: $scope, title: \.title)
            }
            .groupedBackground()
            .navigationTitle("资讯")
            .trackScreen("/feed", title: "资讯")
            .toolbar {
                if case .all = scope {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("筛选", systemImage: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") {
                            showsFilter = true
                        }
                    }
                }
            }
            .profileEntry(isPresented: $showsProfile)
            .appNavigationDestinations()
            .sheet(isPresented: $showsFilter) {
                FeedFilterView(filter: $filter)
            }
            .task(id: scope) {
                await store.loadIfNeeded(scope: scope)
            }
            // `initial: true` 是必需的：冷启动点通知时，`RootTabView` 在本视图
            // **第一次求值之前**就把 id 投递过来了（它要先切 tab，本视图才被创建）。
            // 只挂 `onChange` 会永远等不到「变化」——实测就是停在列表页、推不进详情。
            .onChange(of: pendingItemID.wrappedValue, initial: true) { _, newValue in
                guard let newValue, !newValue.isEmpty else { return }
                // 已加载的分页里找得到就用完整条目（标题、来源、分类都有）；
                // 冷启动时任何 scope 都还没加载，退化成只有 id 的占位，
                // 由 `FeedItemDetailView` 拉真实标题和正文顶上。**不编造内容。**
                path.append(store.findItem(id: newValue) ?? .placeholder(id: newValue))
                pendingItemID.wrappedValue = nil
            }
        }
    }

    /// 「全部」：筛选条件在客户端应用（分类多选直接匹配，学院/学段对受众未知的线上数据不剔除）。
    private var allItems: [FeedItem] {
        store.page(for: .all).items.filter { filter.matches($0, profile: profile) }
    }
}

/// 网络失败时的提示条：如实说明并给重试，**不再**回退演示数据。
struct FeedOfflineBanner: View {
    var message: String?
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
            Text(message ?? "暂时无法连接服务器")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let onRetry {
                Button("重试", action: onRetry)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    FeedHomeView()
        .environment(UserProfile())
        .environment(FeedStore())
}
