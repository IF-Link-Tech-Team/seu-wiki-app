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

/// 搜索结果行（经验长文 / 生存手册）。
///
/// 两个信源在后端是同一份 `DocSearchHit`（`/api/site/pool` 的 `docs` 数组，
/// 靠 `kind` 区分），所以共用一个行组件，只是图标与配色不同 —— 这样「经验」和
/// 「手册」两栏展示的信息层次天然一致。
struct SearchDocRow: View {
    let hit: DocSearchHit
    let keyword: String

    private var tint: Color { hit.kind == .experience ? .orange : .green }
    private var icon: String {
        hit.kind == .experience ? "graduationcap.fill" : "book.closed.fill"
    }

    /// 摘要优先用 `description`；命中的是正文某个小节时展示锚点文字，
    /// 让用户知道「命中在文章的哪一段」，点进去能直接定位。
    private var snippet: String? {
        if let anchor = hit.anchor, !anchor.text.isEmpty { return anchor.text }
        if let description = hit.description, !description.isEmpty { return description }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(hit.title.highlighting(keyword))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if let snippet {
                    Text(snippet.highlighting(keyword))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
