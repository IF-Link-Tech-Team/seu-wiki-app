import Foundation
import SwiftUI

/// 论坛/手册共用的确定式配色：同一 key 恒定同色。
enum ForumPalette {
    static let colors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .mint]

    /// 高饱和实体色：手册板块图标底色（对齐 Apple 播客分类页）。
    static let solidColors: [Color] = [
        Color(red: 0.62, green: 0.66, blue: 0.22),
        Color(red: 0.86, green: 0.24, blue: 0.32),
        Color(red: 0.93, green: 0.49, blue: 0.16),
        Color(red: 0.88, green: 0.30, blue: 0.47),
        Color(red: 0.36, green: 0.68, blue: 0.26),
        Color(red: 0.18, green: 0.62, blue: 0.58),
        Color(red: 0.24, green: 0.52, blue: 0.89),
        Color(red: 0.50, green: 0.36, blue: 0.83),
        Color(red: 0.86, green: 0.28, blue: 0.62),
        Color(red: 0.94, green: 0.62, blue: 0.14),
    ]

    static func color(for key: String) -> Color {
        let sum = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[sum % colors.count]
    }

    static func solidColor(for key: String) -> Color {
        let sum = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return solidColors[sum % solidColors.count]
    }
}

/// 圆形 initials 头像。
struct ForumAvatar: View {
    let name: String
    var size: CGFloat = 36

    private var tint: Color {
        ForumPalette.color(for: name)
    }

    var body: some View {
        Text(name.prefix(1))
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: - 帖子卡片

/// 「图标 + 计数」的紧凑 label 样式（系统 iconOnly 会把数字扔掉，titleOnly 又只剩数字）。
private struct CountLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

/// 帖子卡：置顶标记、标题（无标题时用正文节选）、板块标签、正文节选、
/// 作者与相对时间、浏览/赞/评计数。数据来自论坛真实接口。
struct ForumPostCard: View {
    let post: ForumPost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if post.isPinned {
                    Label("置顶", systemImage: "pin.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12), in: .capsule)
                }
                ForEach(post.tags) { tag in
                    Text(tag.name)
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: .capsule)
                }
            }

            Text(post.headline)
                .font(.headline)
                .multilineTextAlignment(.leading)

            if post.title != nil, !post.excerpt.isEmpty {
                Text(post.excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: 8) {
                if let author = post.author {
                    ForumAvatar(name: author.name, size: 20)
                    Text(author.name)
                        .lineLimit(1)
                } else {
                    Text("东大同学")
                }
                Spacer(minLength: 4)
                if let createdAt = post.createdAt {
                    RelativeTimeText(date: createdAt)
                        .fixedSize()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label(forumCompactCount(post.viewsCount), systemImage: "eye")
                Label(forumCompactCount(post.likesCount), systemImage: "heart")
                Label(forumCompactCount(post.commentsCount), systemImage: "bubble.left")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .labelStyle(CountLabelStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - 通用帖子信息流

/// 一个信息流 key（热门 / 最新 / 板块 / 关注）的通用列表：
/// 加载中 / 错误 / 未部署 / 空态 / 卡片流 + 滚动翻页 + 下拉刷新。
struct ForumPostListView: View {
    @Environment(ForumStore.self) private var store
    let feedKey: ForumStore.FeedKey
    var emptyTitle = "暂无帖子"
    var emptyDescription = "这个板块还没有帖子，来发第一帖吧。"

    private var page: ForumStore.PostPageState { store.page(for: feedKey) }

    var body: some View {
        ScrollView {
            if page.isLoading && page.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            } else if page.unavailable {
                ContentUnavailableView {
                    Label("功能即将上线", systemImage: "person.2.badge.gearshape")
                } description: {
                    Text("该功能的服务端接口正在开发中，上线后即可使用。")
                }
                .padding(.top, 60)
            } else if page.requiresLogin {
                ForumLoginGuide()
                    .padding(.top, 60)
            } else if let error = page.errorMessage, page.items.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await store.refresh(feedKey) } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 60)
            } else if page.items.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "bubble.left.and.text.bubble.right")
                } description: {
                    Text(emptyDescription)
                }
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(page.items) { post in
                        NavigationLink {
                            ForumPostDetailView(postID: post.id, summary: post)
                        } label: {
                            ForumPostCard(post: post)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if post.id == page.items.last?.id {
                                Task { await store.loadMore(feedKey) }
                            }
                        }
                    }
                    if page.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
        }
        .groupedBackground()
        .refreshable { await store.refresh(feedKey) }
        .task { await store.loadIfNeeded(feedKey) }
    }
}

/// 经验 · 热门：论坛热榜（`sort=hot`，置顶帖优先）。
/// 线上尚未部署热榜排序时自动降级到最新（见 `ForumStore.hotFallbackToLatest`）。
struct ForumHotFeedView: View {
    @Environment(ForumStore.self) private var store

    var body: some View {
        ForumPostListView(
            feedKey: .hot,
            emptyTitle: "还没有热门帖子",
            emptyDescription: "论坛刚开张，点右上角「发帖」写下第一篇经验。"
        )
    }
}

/// 某个板块标签的帖子流（手册板块页「查看该板块讨论」的落点）。
struct ForumTagFeedView: View {
    let tag: ForumTag

    var body: some View {
        ForumPostListView(
            feedKey: .tag(tag.slug),
            emptyTitle: "「\(tag.name)」还没有帖子",
            emptyDescription: "成为第一个在这个板块分享经验的人。"
        )
        .navigationTitle(tag.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 关注

/// 登录引导卡片：401 / 未登录时的统一展示（不是错误态）。
struct ForumLoginGuide: View {
    @State private var auth = AuthStore.shared
    var message = "登录 IF.Link 账号后，可以使用关注、发帖、点赞、评论与收藏。"

    var body: some View {
        ContentUnavailableView {
            Label("需要登录", systemImage: "person.crop.circle")
        } description: {
            Text(message)
        } actions: {
            Button {
                auth.signIn()
            } label: {
                Label("登录 IF.Link 账号", systemImage: "link")
            }
            .buttonStyle(.borderedProminent)
            .disabled(auth.isBusy || !auth.isConfigured)
        }
    }
}

/// 经验 · 关注：已关注板块/作者的新帖信息流。
///
/// 阶段 2 接口（`/api/follows`、`/api/feed/following`）与后端并行开发中：
/// 未部署时显式标注「即将上线」；已登录无关注时用 `suggested_tags`
/// （接口未下发时回退到内嵌目录的主题列表）做板块推荐，可直接点关注。
struct ForumFollowingFeedView: View {
    @Environment(ForumStore.self) private var store
    @State private var auth = AuthStore.shared
    let onBrowseHot: () -> Void

    var body: some View {
        Group {
            if !auth.isLoggedIn {
                ScrollView {
                    ForumLoginGuide(message: "登录后关注感兴趣的板块与作者，他们的新帖会出现在这里。")
                        .padding(.top, 80)
                }
            } else if store.followsUnavailable {
                ScrollView {
                    ContentUnavailableView {
                        Label("关注功能即将上线", systemImage: "person.2.badge.gearshape")
                    } description: {
                        Text("关注板块/作者与服务端信息流接口正在开发中。现在可以先去「热门」看看。")
                    } actions: {
                        Button("浏览热门", action: onBrowseHot)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 60)
                }
            } else if !store.isFollowingTags {
                suggestionList
            } else {
                followingContent
            }
        }
        .groupedBackground()
        .task {
            guard auth.isLoggedIn else { return }
            await store.loadFollows()
            await store.loadIfNeeded(.following)
        }
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            guard loggedIn else { return }
            Task {
                await store.loadFollows()
                await store.refresh(.following)
            }
        }
    }

    /// 已登录、有关注：关注流 + 已关注板块管理。
    private var followingContent: some View {
        let page = store.page(for: .following)
        return ScrollView {
            LazyVStack(spacing: 12) {
                followedTagsCard

                if page.unavailable {
                    ContentUnavailableView {
                        Label("关注流即将上线", systemImage: "person.2.badge.gearshape")
                    } description: {
                        Text("信息流接口正在开发中；你关注的板块已保存，上线后自动生效。")
                    }
                    .padding(.top, 24)
                } else if page.isLoading && page.items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if page.items.isEmpty {
                    ContentUnavailableView {
                        Label("还没有新帖", systemImage: "bubble.left.and.text.bubble.right")
                    } description: {
                        Text("你关注的板块最近没有新帖。")
                    }
                    .padding(.top, 24)
                } else {
                    ForEach(page.items) { post in
                        NavigationLink {
                            ForumPostDetailView(postID: post.id, summary: post)
                        } label: {
                            ForumPostCard(post: post)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if post.id == page.items.last?.id {
                                Task { await store.loadMore(.following) }
                            }
                        }
                    }
                    if page.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await store.loadFollows()
            await store.refresh(.following)
        }
    }

    /// 已关注板块横排 chips（可点取关）。
    private var followedTagsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("我关注的板块")
                .font(.subheadline.weight(.semibold))
            ChipsFlowLayout(spacing: 8) {
                ForEach(store.followedTagSlugs.sorted(), id: \.self) { slug in
                    Button {
                        Task { await store.toggleFollow(tag: slug) }
                    } label: {
                        Label(ForumTagCatalog.name(for: slug) ?? slug, systemImage: "checkmark")
                            .font(.footnote)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.14), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("取消关注")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// 已登录、无关注：板块推荐引导（可直接点关注）。
    private var suggestionList: some View {
        // suggested_tags 由接口下发；接口还没给（或阶段 2 未部署）时
        // 回退到内嵌目录的 8 个主题 —— 这是固定目录，不是编造内容。
        let suggestions = store.suggestedTags.isEmpty
            ? ForumTagCatalog.topics.map(\.slug)
            : store.suggestedTags
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ContentUnavailableView {
                    Label("还没有关注任何板块", systemImage: "tag")
                } description: {
                    Text("关注感兴趣的板块，相关新帖会聚合到这里。")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("推荐板块")
                        .font(.subheadline.weight(.semibold))
                    ForEach(ForumTagCatalog.topics.filter { suggestions.contains($0.slug) }) { topic in
                        HStack(spacing: 10) {
                            Image(systemName: "tag")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28, height: 28)
                                .background(Color.accentColor.opacity(0.12), in: .circle)
                            Text(topic.name)
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            FollowButton(slug: topic.slug)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                }
                .cardStyle(padding: 0)
                .padding(.bottom)
            }
            .padding()
        }
    }
}

/// 关注/取关按钮（板块标签）。未登录时点按触发登录。
struct FollowButton: View {
    @Environment(ForumStore.self) private var store
    @State private var auth = AuthStore.shared
    @State private var isPending = false
    let slug: String

    var body: some View {
        Button {
            guard auth.isLoggedIn else {
                auth.signIn()
                return
            }
            isPending = true
            Task {
                await store.toggleFollow(tag: slug)
                isPending = false
            }
        } label: {
            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 44)
            } else {
                Text(store.isFollowing(tag: slug) ? "已关注" : "关注")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        store.isFollowing(tag: slug)
                            ? AnyShapeStyle(Color(.tertiarySystemFill))
                            : AnyShapeStyle(Color.accentColor),
                        in: .capsule
                    )
                    .foregroundStyle(store.isFollowing(tag: slug) ? Color.primary : Color.accentInk)
            }
        }
        .buttonStyle(.plain)
        .disabled(isPending)
    }
}

#Preview("热门") {
    NavigationStack {
        ForumHotFeedView()
    }
    .environment(ForumStore())
}
