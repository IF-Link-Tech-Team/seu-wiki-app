import SwiftUI

/// 主页「论坛新帖」：经验论坛的最新帖子，最多 3 条。
struct HomeForumSection: View {
    let posts: [ForumPost]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(title: "论坛新帖", destination: HomeForumListView(posts: MockData.forumPosts))

            VStack(spacing: 0) {
                ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                    NavigationLink(value: post) {
                        HomeForumRow(post: post)
                    }
                    .buttonStyle(.plain)
                    if index < posts.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .cardStyle(padding: 0)
        }
    }
}

private struct HomeForumRow: View {
    let post: ForumPost

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(.orange.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(post.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(post.authorName)
                    Text("·")
                    Label("\(post.likesCount)", systemImage: "heart")
                    Label("\(post.commentsCount)", systemImage: "bubble.right")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .contentShape(.rect)
    }
}

/// 「论坛新帖」完整列表页。
struct HomeForumListView: View {
    let posts: [ForumPost]

    var body: some View {
        List(posts) { post in
            NavigationLink(value: post) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.title).font(.subheadline.weight(.medium))
                    Text("\(post.authorName) · \(post.createdAt, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("论坛新帖")
        .appNavigationDestinations()
    }
}
