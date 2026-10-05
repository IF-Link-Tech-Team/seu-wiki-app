import SwiftUI

/// 手册 / 经验长文详情页。
///
/// 数据来自 `/api/site/docs/{slug}`（真实内容，不是本地假数据）：
/// 正文 `html` + 目录 `outline`。目录可点击跳转，搜索命中带 `anchor` 时自动定位到对应小节。
///
/// 正文按 `<h2>/<h3>` 切分成小节渲染，而不是整篇一个 `Text` —— 整篇一个文本没法
/// 定位，`outline` 也就形同虚设。
struct DocDetailView: View {
    let slug: String
    let kind: DocSearchHit.Kind
    /// 搜索命中的锚点 id，进入后自动滚到该小节。
    var highlightAnchor: String? = nil

    @State private var detail: DocDetail?
    @State private var sections: [DocSection] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(UserProfile.self) private var profile
    @State private var isBookmarked = false

    private var isHandbook: Bool { kind == .survival }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if detail?.outline.isEmpty == false {
                        outlineList { id in
                            currentOutlineID = id
                            withAnimation(.easeInOut) { proxy.scrollTo(id, anchor: .top) }
                        }
                    }
                    bodyContent
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .groupedBackground()
            .navigationTitle(isHandbook ? "东大生存手册" : "经验分享")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleBookmark()
                    } label: {
                        Label(
                            isBookmarked ? "取消收藏" : "收藏",
                            systemImage: isBookmarked ? "bookmark.fill" : "bookmark"
                        )
                    }
                    // 触控区不小于 44pt，图标本身只有 17pt。
                    .labelStyle(.iconOnly)
                }
            }
            .task(id: slug) { await load() }
            .task(id: highlightAnchor) {
                // 等正文渲染出来再滚，否则目标还不存在。
                guard let anchor = highlightAnchor, !sections.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeInOut) { proxy.scrollTo(anchor, anchor: .top) }
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail?.title ?? "加载中")
                .font(.title2.weight(.bold))

            if let description = detail?.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(metaChips, id: \.self) { chip in
                    Text(chip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                }
            }
        }
    }

    private var metaChips: [String] {
        guard let detail else { return [] }
        var chips: [String] = []
        if let author = detail.author, !author.isEmpty { chips.append(author) }
        if let occurred = detail.occurredAt, !occurred.isEmpty { chips.append(occurred) }
        if let category = detail.category, !category.isEmpty { chips.append(category) }
        if let grade = detail.grade, !grade.isEmpty { chips.append(grade) }
        if let college = detail.college, !college.isEmpty, college != "通用" { chips.append(college) }
        return chips
    }

    // MARK: - 目录

    private func outlineList(onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("目录", systemImage: "list.bullet.indent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(detail?.outline ?? []) { entry in
                    OutlineRow(entry: entry, isCurrent: entry.id == currentOutlineID)
                        .onTapGesture { onSelect(entry.id) }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
    }

    /// 目录行的点击由外层 `ScrollViewReader` 处理；这里只负责样式与高亮。
    private struct OutlineRow: View {
        let entry: DocDetail.Outline
        let isCurrent: Bool

        var body: some View {
            HStack(spacing: 6) {
                if entry.level > 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 2, height: 14)
                }
                Text(entry.text)
                    .font(entry.level > 1 ? .caption : .subheadline)
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 触控区不小于 44pt。
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
    }

    @State private var currentOutlineID: String?

    // MARK: - 正文

    @ViewBuilder
    private var bodyContent: some View {
        if let errorMessage {
            ContentUnavailableView {
                Label("加载失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重试") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if sections.isEmpty {
            ContentUnavailableView("暂无正文", systemImage: "doc.text")
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sections) { section in
                    Text(section.rendered)
                        .id(section.id)
                        .lineSpacing(6)
                        .tint(Color.accentColor)
                }
            }
        }
    }

    // MARK: - 加载

    private func load() async {
        isLoading = true
        errorMessage = nil
        sections = []
        currentOutlineID = highlightAnchor
        isBookmarked = profile.bookmarkedSlugs.contains(slug)
        defer { isLoading = false }
        do {
            let loaded = try await FeedAPIClient().docDetail(slug: slug)
            detail = loaded
            guard let html = loaded.html, !html.isEmpty else { return }
            sections = await DocSection.split(html: html, outlineIDs: Set(loaded.outline.map(\.id)))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleBookmark() {
        if profile.bookmarkedSlugs.contains(slug) {
            profile.bookmarkedSlugs.remove(slug)
        } else {
            profile.bookmarkedSlugs.insert(slug)
        }
        isBookmarked = profile.bookmarkedSlugs.contains(slug)
    }
}

/// 正文按标题切出的小节。`id` 优先取标题标签上的 `id`（与后端 `outline` 对齐），
/// 取不到就用序号兜底。
struct DocSection: Identifiable {
    let id: String
    let html: String
    var rendered: AttributedString = AttributedString()

    /// 把整篇 HTML 按 `<h1>/<h2>/<h3>` 切开。
    ///
    /// 必须在切分**之后**再逐节做 HTML 解析：一次 `NSAttributedString(.html:)`
    /// 会把整篇合成一个不可分的文本，没法给每一节挂 `.id()`，目录跳转就成了摆设。
    static func split(html: String, outlineIDs: Set<String>) async -> [DocSection] {
        let chunks = splitRaw(html: html)
        var result: [DocSection] = []
        for (index, chunk) in chunks.enumerated() {
            var id = chunk.id ?? "section-\(index)"
            if outlineIDs.isEmpty, let existing = result.first(where: { $0.id == id }) {
                id = "\(id)-\(index)"   // 标题没带 id 时保证唯一，ForEach 不崩
            }
            var section = DocSection(id: id, html: chunk.html)
            section.rendered = await HTMLRenderer.render(chunk.html) ?? AttributedString(chunk.html)
            result.append(section)
        }
        return result
    }

    private static func splitRaw(html: String) -> [(id: String?, html: String)] {
        // 匹配 `<h1..h3 ...>` 开标签，记录标题的 id，并按它切分。
        let pattern = "<h([1-3])([^>]*)>"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return [(nil, html)] }

        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [(nil, html)] }

        var chunks: [(id: String?, html: String)] = []
        // 第一个标题之前的内容（通常是前言/引子）单独成节。
        if matches[0].range.location > 0 {
            chunks.append((nil, ns.substring(to: matches[0].range.location)))
        }
        for (index, match) in matches.enumerated() {
            let start = match.range.location
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let slice = ns.substring(with: NSRange(location: start, length: end - start))
            // 从开标签属性里抠出 id="..."。
            var id: String?
            let attrs = ns.substring(with: match.range(at: 2))
            if let idRange = attrs.range(of: "id\\s*=\\s*[\"']([^\"']+)[\"']", options: .regularExpression) {
                id = String(attrs[idRange])
                    .replacingOccurrences(of: "id\\s*=\\s*[\"']", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "[\"']", with: "", options: .regularExpression)
            }
            chunks.append((id, slice))
        }
        return chunks
    }
}
