import SwiftUI

/// 主页「与我有关的通知」：基于画像的精选，最多 3 条，可进入完整列表。
struct HomeFeedSection: View {
    let items: [FeedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(title: "与我有关的通知", destination: HomeFeedListView(items: MockData.feedItems))

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item) {
                        HomeFeedRow(item: item)
                    }
                    .buttonStyle(.plain)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .cardStyle(padding: 0)
        }
    }
}

private struct HomeFeedRow: View {
    let item: FeedItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.category.systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.sourceName)
                    if let first = item.matchReasons.first {
                        Text("·")
                        Text(first)
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Text(item.publishedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .contentShape(.rect)
    }
}

/// 「与我有关的通知」完整列表页。
struct HomeFeedListView: View {
    let items: [FeedItem]

    var body: some View {
        List(items) { item in
            NavigationLink(value: item) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.subheadline.weight(.medium))
                    Text("\(item.sourceName) · \(item.publishedAt, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("与我有关")
        .appNavigationDestinations()
    }
}
