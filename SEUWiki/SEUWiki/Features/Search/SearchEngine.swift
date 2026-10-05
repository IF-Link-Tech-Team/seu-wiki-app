import SwiftUI

/// 搜索的本地工具只剩「关键词高亮」了 —— 三个信源的数据都来自线上
/// `/api/site/pool`（`items` + `docs`），不再有本地 provider，也不再有 Mock 回退。
///
/// 早期版本这里的 `searchForum` / `searchHandbook` 拿 `MockData` 本地匹配，
/// 表现是「搜什么都出同一批编造的帖子和手册」；`searchFeedOffline` 更糟 ——
/// 线上失败时**静默**换成本地假数据，用户以为搜到了，其实看到的是编造内容。
enum SearchEngine {
    static func matches(_ text: String, _ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        return text.range(of: key, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

extension String {
    /// 关键词命中片段加粗（strong emphasis），字号与颜色沿用外层设置。
    func highlighting(_ keyword: String) -> AttributedString {
        var attributed = AttributedString(self)
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return attributed }

        var lowerBound = startIndex
        while let match = range(of: key, options: [.caseInsensitive, .diacriticInsensitive], range: lowerBound..<endIndex) {
            if let attributedRange = Range(match, in: attributed) {
                attributed[attributedRange].inlinePresentationIntent = .stronglyEmphasized
            }
            lowerBound = match.upperBound
        }
        return attributed
    }
}

/// 带关键词高亮的文本。
///
/// 单独抽一个组件是因为 `Text(a) + Text(b)` 拼接之后得到的是 `Text` 而不是
/// `AttributedString`，没法再回头做高亮；而 `Text + Text` 在 iOS 26 已弃用。
struct HighlightedText: View {
    let text: String
    let keyword: String
    var lineLimit: Int? = nil

    var body: some View {
        Text(text.highlighting(keyword))
            .lineLimit(lineLimit)
    }
}
