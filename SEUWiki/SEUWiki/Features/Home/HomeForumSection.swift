import SwiftUI

/// 主页「精选经验」：来自 `/api/site/docs/experience` 的真实长文。
///
/// 这里原来叫「论坛新帖」，内容是 `MockData.forumPosts` —— 虚构作者「林晚舟 ·
/// 保研至清华大学」、虚构的 1893 赞 / 342 评论，界面上没有任何标记说明是编造的。
/// 论坛后端 `seu-wiki-forum` 有完整 HTTP API，但本 App 还没有论坛客户端，
/// 拿不到真实帖子，
/// 所以把这一块换成**真实可用的经验长文**，并如实标注社区功能的状态。
struct HomeForumSection: View {
    @Environment(ExperienceStore.self) private var store: ExperienceStore?
    /// 最多展示 3 条，bento 布局不铺满。
    let limit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(title: "精选经验", destination: ExperienceListView())

            VStack(spacing: 0) {
                if let items = store?.experience?.items, !items.isEmpty {
                    ForEach(Array(items.prefix(limit).enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item.navigationValue) {
                            HomeExperienceRow(item: item)
                        }
                        .buttonStyle(.plain)
                        if index < min(items.count, limit) - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                } else {
                    communityComingSoon
                }
            }
            .cardStyle(padding: 0)
        }
        .task { await store?.loadExperience() }
    }

    /// 经验长文还没加载出来（或加载失败）时，如实说明社区状态，不编内容。
    private var communityComingSoon: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("社区功能即将上线", systemImage: "person.2.badge.gearshape")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
            Text("发帖、点赞、评论、关注话题正在开发中。先看看来自学长学姐的经验长文与东大生存手册。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

private struct HomeExperienceRow: View {
    let item: DocItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(.orange.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let author = item.author, !author.isEmpty {
                        Text(author)
                    }
                    if let category = item.category, !category.isEmpty {
                        Text("·")
                        Text(category)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .contentShape(.rect)
    }
}

/// 「精选经验」完整列表页。
struct ExperienceListView: View {
    @Environment(ExperienceStore.self) private var store: ExperienceStore?

    var body: some View {
        Group {
            if let items = store?.experience?.items, !items.isEmpty {
                List(items) { item in
                    NavigationLink(value: item.navigationValue) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                            if let description = item.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                ContentUnavailableView("暂无经验内容", systemImage: "text.book.closed")
            }
        }
        .navigationTitle("精选经验")
        .task { await store?.loadExperience() }
    }
}
