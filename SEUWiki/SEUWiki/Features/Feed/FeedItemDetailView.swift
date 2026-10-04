import SwiftUI

/// 资讯详情页：正文 + 底部「在网页中打开 / 设定提醒」操作条。
struct FeedItemDetailView: View {
    @Environment(\.openURL) private var openURL
    @State private var showsReminderEditor = false

    let item: FeedItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    categoryChip
                    Text(item.sourceName)
                    Text("·")
                    Text(item.publishedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(item.title)
                    .font(.title2.weight(.bold))

                if let deadline = item.audience.deadline {
                    deadlineRow(deadline)
                }

                Text(item.summary)
                    .font(.body)
                    .lineSpacing(6)

                if !item.tags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(item.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.tertiarySystemFill), in: .capsule)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupedBackground()
        .navigationTitle(item.category.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .sheet(isPresented: $showsReminderEditor) {
            ReminderEditView(item: item)
        }
    }

    private var categoryChip: some View {
        Label(item.category.name, systemImage: item.category.systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12), in: .capsule)
    }

    private func deadlineRow(_ deadline: Date) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("截止时间")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(deadline.formatted(date: .long, time: .shortened))
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            Text(deadline, style: .relative)
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                if let url = item.originalURL {
                    openURL(url)
                }
            } label: {
                Label("在网页中打开", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(item.originalURL == nil)

            Button {
                showsReminderEditor = true
            } label: {
                Label("设定提醒", systemImage: "bell.badge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// 简单横向流式布局，用于标签 chips 自动换行。
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(width: proposal.width ?? .infinity, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            height += row.height + (index == 0 ? 0 : spacing)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func computeRows(width maxWidth: CGFloat, subviews: Subviews) -> [(indices: [Int], height: CGFloat)] {
        var rows: [(indices: [Int], height: CGFloat)] = [([], 0)]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rows.append(([], 0))
                x = 0
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += size.width + spacing
        }
        return rows
    }
}

#Preview {
    NavigationStack {
        FeedItemDetailView(item: MockData.feedItems[0])
    }
    .environment(UserProfile())
}
