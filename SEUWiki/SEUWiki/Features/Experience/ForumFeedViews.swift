import Foundation
import SwiftUI

/// 数字紧凑格式：过万显示「x.x万」。
func forumCompactCount(_ value: Int) -> String {
    if value >= 10000 {
        String(format: "%.1f万", Double(value) / 10000)
    } else {
        "\(value)"
    }
}

/// 话题 slug → 显示名。
func forumTopicName(for slug: String) -> String? {
    MockData.topics.first { $0.id == slug }?.name
}

/// 论坛/手册共用的确定式配色：同一 key 恒定同色。
enum ForumPalette {
    static let colors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .mint]

    /// 高饱和实体色：话题卡片底色与手册分类图标（对齐 Apple 播客分类页）。
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
    }
}

/// 帖子卡片：标题、两行摘要、作者行与互动数据，精选帖带 accent 标记。
struct ForumPostCard: View {
    let post: ForumPost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if post.isFeatured {
                    Text("精选")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(Color.accentColor)
                        .background(Color.accentColor.opacity(0.12), in: .capsule)
                }
                if let slug = post.tags.first, let topicName = forumTopicName(for: slug) {
                    Text(topicName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Text(post.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(post.title)
                .font(.headline)
                .lineLimit(2)

            Text(post.excerpt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                ForumAvatar(name: post.authorName, size: 22)
                Text(post.authorName)
                    .font(.caption.weight(.medium))
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(post.authorHeadline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 14) {
                Label(forumCompactCount(post.likesCount), systemImage: "heart")
                Label(forumCompactCount(post.commentsCount), systemImage: "bubble.right")
                Label(forumCompactCount(post.viewsCount), systemImage: "eye")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

/// 经验 · 热门：按点赞数排序的帖子卡片流。
struct ForumHotFeedView: View {
    private var posts: [ForumPost] {
        MockData.forumPosts.sorted { $0.likesCount > $1.likesCount }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(posts) { post in
                    NavigationLink(value: post) {
                        ForumPostCard(post: post)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .groupedBackground()
    }
}

/// 经验 · 关注：已关注话题下的最新帖子；空态引导去话题广场。
struct ForumFollowingFeedView: View {
    @Environment(UserProfile.self) private var profile
    let onBrowseTopics: () -> Void

    private var posts: [ForumPost] {
        MockData.forumPosts
            .filter { post in post.tags.contains { profile.followedTopicIDs.contains($0) } }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ScrollView {
            if posts.isEmpty {
                ContentUnavailableView {
                    Label("还没有关注的话题", systemImage: "star")
                } description: {
                    Text("去话题广场关注感兴趣的话题，相关新帖会出现在这里。")
                } actions: {
                    Button("浏览话题广场", action: onBrowseTopics)
                        .buttonStyle(.borderedProminent)
                }
                .containerRelativeFrame(.vertical)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(posts) { post in
                        NavigationLink(value: post) {
                            ForumPostCard(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .groupedBackground()
    }
}

#Preview("热门") {
    NavigationStack {
        ForumHotFeedView()
            .appNavigationDestinations()
    }
    .environment(UserProfile())
}

#Preview("关注") {
    NavigationStack {
        ForumFollowingFeedView(onBrowseTopics: {})
    }
    .environment(UserProfile())
}
