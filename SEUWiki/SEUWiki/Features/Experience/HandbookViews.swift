import SwiftUI

/// 经验 · 生存手册：从 `/api/site/docs/survival` 拉真实的「篇 → 组 → 条」文档树。
///
/// 形态按需求做成 **list 形式的文档结构**（早期版本是两列卡片网格 + 6 条硬编码假条目）。
struct HandbookHomeView: View {
    @Environment(ExperienceStore.self) private var store: ExperienceStore?

    var body: some View {
        ScrollView {
            if let store {
                if store.isLoadingHandbook && store.handbook == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let error = store.handbookError {
                    errorState(error)
                } else if let parts = store.handbook?.parts, !parts.isEmpty {
                    partList(parts, store: store)
                } else {
                    ContentUnavailableView("手册暂无内容", systemImage: "book.closed")
                }
            }
        }
        .groupedBackground()
        .task { await store?.loadHandbook() }
    }

    /// 真实文档树：每个「篇」一张卡，篇内按「组」分组列出条目。
    private func partList(_ parts: [HandbookIndex.Part], store: ExperienceStore) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(parts) { part in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "books.vertical.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(ForumPalette.solidColor(for: part.key), in: .circle)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.label)
                                .font(.headline)
                            Text("\(store.entryCount(of: part)) 篇")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    Divider().padding(.leading, 60)

                    ForEach(part.groups) { group in
                        groupRows(group, in: part)
                    }
                }
                .cardStyle(padding: 0)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func groupRows(_ group: HandbookIndex.Group, in part: HandbookIndex.Part) -> some View {
        // 组标题只在有名字且不是默认空 key 时显示（后端第一组的 key 可能是空串）。
        if !group.key.isEmpty {
            Text(group.key)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        ForEach(group.items) { item in
            NavigationLink(value: DocSearchHit(
                slug: item.slug,
                kind: .survival,
                title: item.title,
                description: item.description,
                occurredAt: item.occurredAt,
                anchor: nil
            )) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        if let description = item.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 38)
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("手册加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") { Task { await store?.loadHandbook() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
