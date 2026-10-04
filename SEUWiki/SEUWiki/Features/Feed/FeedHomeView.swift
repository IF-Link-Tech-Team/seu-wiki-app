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
        if onlyMyCollege, !item.audience.colleges.contains(profile.college) { return false }
        if let degree, !item.audience.identities.isEmpty, !item.audience.identities.contains(degree) { return false }
        if !categories.isEmpty, !categories.contains(item.category) { return false }
        return true
    }
}

struct FeedHomeView: View {
    @Environment(UserProfile.self) private var profile
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
                        ForYouFeedList(items: forYouItems)
                    case .all:
                        FeedItemList(
                            items: allItems,
                            emptyMessage: filter.isActive ? "没有符合条件的资讯，试试调整筛选条件" : "暂无资讯"
                        )
                    case .category(let category):
                        FeedItemList(items: items(in: category), emptyMessage: "该分类暂无资讯")
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
        }
    }

    /// 为你精选：有命中理由的排前面，组内按发布时间倒序。
    private var forYouItems: [FeedItem] {
        MockData.feedItems.sorted { lhs, rhs in
            if !lhs.matchReasons.isEmpty != !rhs.matchReasons.isEmpty {
                return !lhs.matchReasons.isEmpty
            }
            return lhs.publishedAt > rhs.publishedAt
        }
    }

    /// 「全部」：应用筛选条件，按发布时间倒序。
    private var allItems: [FeedItem] {
        MockData.feedItems
            .filter { filter.matches($0, profile: profile) }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    private func items(in category: FeedCategory) -> [FeedItem] {
        MockData.feedItems
            .filter { $0.category == category }
            .sorted { $0.publishedAt > $1.publishedAt }
    }
}

/// 「为你精选」：个性化卡片流，命中理由显示为 accent 色 chip。
private struct ForYouFeedList: View {
    let items: [FeedItem]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        ForYouCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
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
                Text(item.publishedAt, style: .relative)

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
}
