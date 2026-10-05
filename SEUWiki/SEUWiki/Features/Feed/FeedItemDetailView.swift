import SwiftUI

/// 资讯详情页：正文 + 底部「在网页中打开 / 设定提醒」操作条。
/// 进入时按 id 拉取线上详情（body / 原文链接）；失败静默回退展示传入的列表摘要。
struct FeedItemDetailView: View {
    @Environment(\.openURL) private var openURL
    @Environment(FeedStore.self) private var store: FeedStore?
    @State private var showsReminderEditor = false
    @State private var detail: FeedItemDetail?
    @State private var isLoadingDetail = false
    /// 正文由 `HTMLRenderer` 在后台线程解析成 `AttributedString`。
    /// 不再在 body 里同步解析 —— 那会卡住首帧。
    @State private var renderedBody: AttributedString?

    let item: FeedItem

    /// 原文链接优先用详情接口下发的 links.original（列表响应不含 links）。
    private var originalURL: URL? {
        detail?.originalURL ?? item.originalURL
    }

    /// 通知深链冷启动进来时 [FeedItem.placeholder] 的标题是空的，
    /// 这时用详情接口下发的原文标题顶上，而不是留一个空标题页。
    private var displayTitle: String {
        item.title.isEmpty ? (detail?.originalTitle ?? "") : item.title
    }

    /// 占位条目没有来源与发布时间，别渲染出「··」这种空行。
    private var showsMetaRow: Bool {
        !item.sourceName.isEmpty
    }

    /// 只有 id 的占位条目（通知深链冷启动）。它的 `category` 是占位值 `.news`，
    /// 拿「校园新闻」当标签展示等于凭空断言这条资讯的分类。
    private var isDeepLinkPlaceholder: Bool {
        item.title.isEmpty && item.sourceName.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsMetaRow {
                    HStack(spacing: 8) {
                        categoryChip
                        Text(item.sourceName)
                        Text("·")
                        Text(item.publishedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Text(displayTitle)
                    .font(.title2.weight(.bold))

                // 占位条目没有自己的标题，也就无所谓「原文标题」了 —— 别重复显示。
                if let originalTitle = detail?.originalTitle,
                   !item.title.isEmpty,
                   originalTitle != item.title {
                    Text("原文标题：\(originalTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let deadline = item.audience.deadline {
                    deadlineRow(deadline)
                }

                if let renderedBody {
                    Text(renderedBody)
                        .lineSpacing(6)
                        .tint(Color.accentColor)
                } else {
                    Text(detail?.summary ?? item.summary)
                        .font(.body)
                        .lineSpacing(6)
                }

                if isLoadingDetail {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

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
        // 占位条目的 category 是占位值 `.news`，拿它当导航标题等于凭空断言
        // 「这条属于校园新闻」。这种情况下用中性的栏目名。
        .navigationTitle(isDeepLinkPlaceholder ? "资讯" : item.category.name)
        .navigationBarTitleDisplayMode(.inline)
        // iOS 26 起 `.safeAreaBar` 才是正确的底部条写法：系统自动处理材质、圆角与
        // 和 tab 栏的层级关系。早期的 `.safeAreaInset` + `.background(.bar)` 是手绘伪材质，
        // 在 iOS 26 上会和 tab 栏叠成两层。
        .safeAreaBar(edge: .bottom) {
            actionBar
        }
        .sheet(isPresented: $showsReminderEditor) {
            ReminderEditView(item: item)
        }
        .task(id: item.id) {
            guard let store, detail == nil else { return }
            isLoadingDetail = true
            defer { isLoadingDetail = false }
            guard let loaded = try? await store.detail(for: item) else { return }
            detail = loaded
            if let html = loaded.bodyHTML {
                renderedBody = await HTMLRenderer.render(html)
            }
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
                Text(TimeFormat.deadline(deadline))
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            RelativeTimeText(date: deadline, font: .caption.weight(.medium), color: .orange)
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                if let url = originalURL {
                    openURL(url)
                }
            } label: {
                Label("在网页中打开", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(originalURL == nil)

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
        // 材质由 `.safeAreaBar` 提供，这里不再自己画一层 `.background(.bar)`，
        // 否则会与系统底栏叠成两层灰。
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
        FeedItemDetailView(item: PreviewSample.feedItems[0])
    }
    .environment(UserProfile())
}
