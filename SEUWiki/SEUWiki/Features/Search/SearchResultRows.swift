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
                // `Text(a) + Text(b)` 在 iOS 26 已弃用，改成先拼字符串再整体高亮。
                HighlightedText(text: "\(item.sourceName) · \(item.summary)", keyword: keyword, lineLimit: 1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 搜索结果行（论坛经验帖）：标题（无标题时正文节选）+ 节选 + 作者/互动计数。
struct SearchPostRow: View {
    let post: ForumPost
    let keyword: String

    private var metaLine: String {
        var parts: [String] = []
        if let author = post.author?.name, !author.isEmpty {
            parts.append(author)
        }
        parts.append("\(forumCompactCount(post.likesCount)) 赞")
        parts.append("\(forumCompactCount(post.commentsCount)) 评论")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.body.weight(.medium))
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(Color.orange.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(post.headline.highlighting(keyword))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if let title = post.title, !title.isEmpty, !post.excerpt.isEmpty {
                    // 有标题时再补一行正文节选；无标题时主行已经是节选了。
                    Text(post.excerpt.highlighting(keyword))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(metaLine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// 搜索结果行（东大生存手册文章）：标题 + 标签/作者。
struct SearchHandbookArticleRow: View {
    let article: HandbookArticleSummary
    let keyword: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(.green)
                .frame(width: 32, height: 32)
                .background(Color.green.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(article.title.highlighting(keyword))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                let meta = [
                    ForumTagCatalog.name(for: article.tagSlug),
                    article.authorDisplay,
                ]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
