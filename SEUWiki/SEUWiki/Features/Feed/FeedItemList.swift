import SwiftUI

/// 「全部」与分类页共用的资讯卡片列表。
struct FeedItemList: View {
    let items: [FeedItem]
    var emptyMessage: String = "暂无资讯"

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView("暂无资讯", systemImage: "newspaper", description: Text(emptyMessage))
                    .padding(.top, 80)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            FeedItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
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
