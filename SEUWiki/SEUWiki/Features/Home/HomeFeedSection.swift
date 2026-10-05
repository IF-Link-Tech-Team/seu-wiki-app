import SwiftUI

/// 主页「与我有关的通知」：基于画像的精选，最多 3 条，可进入完整列表。
struct HomeFeedSection: View {
    let items: [FeedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(title: "与我有关的通知", destination: HomeFeedListView(items: items))

            VStack(spacing: 0) {
                let shown = Array(items.prefix(3))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item) {
                        HomeFeedRow(item: item)
                    }
                    .buttonStyle(.plain)
                    if index < shown.count - 1 {
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
                    metaLabel
                    Spacer(minLength: 4)
                    RelativeTimeText(date: item.publishedAt)
                        .fixedSize()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .contentShape(.rect)
    }

    /// 来源与命中理由常常是同一句话的不同长度版本
    /// （来源名多为「学院名 + 部门名」，命中理由就是学院名），两个都显示会挤成两行。
    /// 这里只保留信息量更大的那个，另一个完全不出现。
    @ViewBuilder
    private var metaLabel: some View {
        let reason = item.matchReasons.first
        if let reason, !reason.isEmpty {
            if item.sourceName.contains(reason) {
                Text(reason)
                    .lineLimit(1)
                    .foregroundStyle(Color.accentColor)
            } else if reason.contains(item.sourceName) {
                Text(reason)
                    .lineLimit(1)
                    .foregroundStyle(Color.accentColor)
            } else {
                Text(item.sourceName)
                    .lineLimit(1)
                Text("·")
                Text(reason)
                    .lineLimit(1)
                    .foregroundStyle(Color.accentColor)
            }
        } else {
            Text(item.sourceName)
                .lineLimit(1)
        }
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
                    HighlightedText(text: "\(item.sourceName) · \(TimeFormat.relative(item.publishedAt))", keyword: "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("与我有关")
    }
}
