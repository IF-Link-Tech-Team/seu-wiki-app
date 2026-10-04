import SwiftUI

/// 搜索结果行（资讯通知）：分类图标 + 标题/摘要，关键词加粗。
struct SearchFeedRow: View {
    let item: FeedItem
    let keyword: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.category.systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.highlighting(keyword))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                (Text("\(item.sourceName) · ") + Text(item.summary.highlighting(keyword)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// 搜索结果行（经验论坛）：话题图标 + 标题/摘要，关键词加粗。
struct SearchForumRow: View {
    let post: ForumPost
    let keyword: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(.orange.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(post.title.highlighting(keyword))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                (Text("\(post.authorName) · ") + Text(post.excerpt.highlighting(keyword)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// 搜索结果行（生存手册）：手册图标 + 标题/摘要，关键词加粗。
struct SearchHandbookRow: View {
    let entry: HandbookEntry
    let keyword: String

    /// 摘要优先展示 subtitle；仅正文命中时展示正文片段，保证高亮可见。
    private var snippet: String {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty,
           !SearchEngine.matches(entry.title, key),
           !SearchEngine.matches(entry.subtitle, key),
           SearchEngine.matches(entry.body, key) {
            return entry.body
        }
        return entry.subtitle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(.green)
                .frame(width: 32, height: 32)
                .background(.green.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title.highlighting(keyword))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(snippet.highlighting(keyword))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
