import SwiftUI

/// 「全部」与分类页共用的资讯卡片列表。
/// page / onRefresh / onLoadMore 缺省时退化为纯静态列表（Preview 与 Mock 用法）。
struct FeedItemList: View {
    let items: [FeedItem]
    var page: FeedStore.PageState?
    var emptyMessage: String = "暂无资讯"
    var onRefresh: (() async -> Void)? = nil
    var onLoadMore: (() async -> Void)? = nil

    var body: some View {
        ScrollView {
            if let page, page.isLoading, items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            } else if items.isEmpty {
                ContentUnavailableView("暂无资讯", systemImage: "newspaper", description: Text(emptyMessage))
                    .padding(.top, 80)
            } else {
                LazyVStack(spacing: 12) {
                    if page?.isOffline == true {
                        FeedOfflineBanner()
                    }
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            FeedItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if item.id == items.last?.id {
                                Task { await onLoadMore?() }
                            }
                        }
                    }
                    if page?.isLoadingMore == true {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
        }
        .refreshableIfSupported(onRefresh)
    }
}

private extension View {
    @ViewBuilder
    func refreshableIfSupported(_ action: (() async -> Void)?) -> some View {
        if let action {
            self.refreshable { await action() }
        } else {
            self
        }
    }
}

private struct FeedItemRow: View {
    let item: FeedItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.category.systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.sourceName)
                    Text("·")
                    Text(item.publishedAt, style: .relative)
                    if item.isSelected {
                        Text("·")
                        Label("精选", systemImage: "star.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .cardStyle(padding: 14)
    }
}

#Preview {
    NavigationStack {
        FeedItemList(items: MockData.feedItems)
            .groupedBackground()
            .appNavigationDestinations()
    }
}
