import SwiftUI

/// 资讯页 console 选项：为你精选 / 全部 / 8 个资讯分类。
enum FeedScope: Hashable, Identifiable {
    case forYou
    case all
    case category(FeedCategory)

    var id: String {
        switch self {
        case .forYou: "forYou"
        case .all: "all"
        case .category(let category): category.rawValue
        }
    }

    var title: String {
        switch self {
        case .forYou: "为你精选"
        case .all: "全部"
        case .category(let category): category.name
        }
    }

    static let scopes: [FeedScope] = [.forYou, .all] + FeedCategory.allCases.map { .category($0) }
}

/// 「全部」列表的筛选条件：学院开关、学段、分类多选。
struct FeedFilter: Hashable {
    var onlyMyCollege = false
    var degree: String?                 // nil 为全部学段，否则如「本科生」
    var categories: Set<FeedCategory> = []

    var isActive: Bool { onlyMyCollege || degree != nil || !categories.isEmpty }

    func matches(_ item: FeedItem, profile: UserProfile) -> Bool {
        // 线上接口不下发 campus 受众字段：受众未知（空数组）时视为中性不剔除，
        // 只有明确知道受众且不匹配时才过滤（Mock 数据行为不变）。
        if onlyMyCollege, !item.audience.colleges.isEmpty, !item.audience.colleges.contains(profile.college) { return false }
        if let degree, !item.audience.identities.isEmpty, !item.audience.identities.contains(degree) { return false }
        if !categories.isEmpty, !categories.contains(item.category) { return false }
        return true
    }
}

struct FeedHomeView: View {
    @Environment(UserProfile.self) private var profile
    @Environment(FeedStore.self) private var store
    @State private var showsProfile = false
    @State private var scope: FeedScope = .forYou
    @State private var filter = FeedFilter()
    @State private var showsFilter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ConsoleBar(items: FeedScope.scopes, selection: $scope, title: \.title)

                Group {
                    switch scope {
                    case .forYou:
                        ForYouFeedList(
                            page: store.page(for: .forYou),
                            onRefresh: { await store.refresh(scope: .forYou, profile: profile) },
                            onLoadMore: { await store.loadMore(scope: .forYou, profile: profile) }
                        )
                    case .all:
                        FeedItemList(
                            items: allItems,
                            page: store.page(for: .all),
                            emptyMessage: filter.isActive ? "没有符合条件的资讯，试试调整筛选条件" : "暂无资讯",
                            onRefresh: { await store.refresh(scope: .all, profile: profile) },
                            onLoadMore: { await store.loadMore(scope: .all, profile: profile) }
                        )
                    case .category(let category):
                        FeedItemList(
                            items: store.page(for: .category(category)).items,
                            page: store.page(for: .category(category)),
                            emptyMessage: "该分类暂无资讯",
                            onRefresh: { await store.refresh(scope: .category(category), profile: profile) },
                            onLoadMore: { await store.loadMore(scope: .category(category), profile: profile) }
                        )
                    }
                }
                .transition(.opacity)
            }
            .groupedBackground()
            .navigationTitle("资讯")
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
                await store.loadIfNeeded(scope: scope, profile: profile)
            }
        }
    }

    /// 「全部」：筛选条件在客户端应用（分类多选直接匹配，学院/学段对受众未知的线上数据不剔除）。
    private var allItems: [FeedItem] {
        store.page(for: .all).items.filter { filter.matches($0, profile: profile) }
    }
}

/// 「为你精选」：个性化卡片流，命中理由显示为 accent 色 chip。
private struct ForYouFeedList: View {
    let page: FeedStore.PageState
    var onRefresh: () async -> Void
    var onLoadMore: () async -> Void

    var body: some View {
        ScrollView {
            if page.isLoading, page.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            } else if page.items.isEmpty {
                if page.isOffline {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(page.errorMessage ?? "暂时无法连接服务器")
                    } actions: {
                        Button("重试") { Task { await onRefresh() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 60)
                } else {
                    ContentUnavailableView("暂无资讯", systemImage: "newspaper", description: Text("暂时没有为你精选的资讯"))
                        .padding(.top, 80)
                }
            } else {
                LazyVStack(spacing: 12) {
                    if page.isOffline {
                        FeedOfflineBanner(message: page.errorMessage) {
                            Task { await onRefresh() }
                        }
                    }
                    ForEach(page.items) { item in
                        NavigationLink(value: item) {
                            ForYouCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if item.id == page.items.last?.id {
                                Task { await onLoadMore() }
                            }
                        }
                    }
                    if page.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
        }
        .refreshable { await onRefresh() }
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

private struct ForYouCard: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: item.category.systemImage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.12), in: .circle)

                Text(item.sourceName)
                Text("·")
                RelativeTimeText(date: item.publishedAt)

                Spacer(minLength: 4)

                if item.isSelected {
                    Label("精选", systemImage: "star.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(item.title)
                .font(.headline)
                .lineLimit(2)

            Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !item.matchReasons.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.matchReasons, id: \.self) { reason in
                        Text(reason)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: .capsule)
                    }
                }
            }
        }
        .cardStyle()
    }
}

#Preview {
    FeedHomeView()
        .environment(UserProfile())
        .environment(FeedStore())
}
