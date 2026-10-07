import SwiftUI

/// 主页「社区热议」：论坛热榜前 3 条（`GET /api/posts?sort=hot`，置顶优先）。
///
/// 这里原来叫「论坛新帖」，内容是 `MockData.forumPosts` —— 虚构作者、虚构的
/// 上千赞。后来换成经验长文索引（`/api/site/docs/experience`）；经验 tab 论坛化后
/// 该索引信源已移除，这一块回到它本来的名字，展示论坛的真实帖子。
/// 加载失败/空列表时如实显示状态文案，不编内容。
struct HomeForumSection: View {
    @Environment(ForumStore.self) private var store
    /// 最多展示 3 条，bento 布局不铺满。
    let limit = 3

    private var page: ForumStore.PostPageState { store.page(for: .hot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(title: "社区热议", destination: HomeForumFeedView())

            VStack(spacing: 0) {
                if page.unavailable {
                    statusRow(icon: "person.2.badge.gearshape", tint: .orange,
                              title: "社区功能即将上线",
                              detail: "发帖、点赞、评论的服务端接口正在开发中。")
                } else if let error = page.errorMessage, page.items.isEmpty {
                    statusRow(icon: "wifi.exclamationmark", tint: .secondary,
                              title: "社区内容加载失败", detail: error)
                } else if page.items.isEmpty {
                    if page.hasLoaded {
                        statusRow(icon: "bubble.left.and.text.bubble.right", tint: .secondary,
                                  title: "论坛刚开张",
                                  detail: "还没有帖子，去「经验」页写下第一篇分享。")
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在加载社区热议…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                } else {
                    ForEach(Array(page.items.prefix(limit).enumerated()), id: \.element.id) { index, post in
                        NavigationLink {
                            ForumPostDetailView(postID: post.id, summary: post)
                        } label: {
                            HomePostRow(post: post)
                        }
                        .buttonStyle(.plain)
                        if index < min(page.items.count, limit) - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
            .cardStyle(padding: 0)
        }
        .task { await store.loadIfNeeded(.hot) }
    }

    private func statusRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

private struct HomePostRow: View {
    let post: ForumPost

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: post.isPinned ? "pin.fill" : "bubble.left.and.text.bubble.right")
                .font(.body.weight(.medium))
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(.orange.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(post.headline)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let name = post.author?.name, !name.isEmpty {
                        Text(name)
                    }
                    Text("\(forumCompactCount(post.likesCount)) 赞")
                    Text("\(forumCompactCount(post.commentsCount)) 评论")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .contentShape(.rect)
    }
}

/// 「社区热议」查看全部的落点：完整热榜信息流。
private struct HomeForumFeedView: View {
    var body: some View {
        ForumPostListView(
            feedKey: .hot,
            emptyTitle: "还没有热门帖子",
            emptyDescription: "论坛刚开张，去「经验」页写下第一篇分享。"
        )
        .navigationTitle("社区热议")
        .navigationBarTitleDisplayMode(.inline)
    }
}
