import SwiftUI

/// 经验 · 东大生存手册：板块列表（8 主题 + 子标签分组 + 文章数）。
///
/// 数据来自论坛 `GET /api/handbook/sections`（编辑团队从讨论沉淀的真实文章），
/// 不再是 seu-wiki-v2 的 `/api/site/docs/survival` 文档树。
/// 后端路由未部署时显式标注「内容准备中」。
struct HandbookHomeView: View {
    @Environment(ForumStore.self) private var store

    var body: some View {
        ScrollView {
            if store.handbookUnavailable {
                ContentUnavailableView {
                    Label("手册内容准备中", systemImage: "book.closed")
                } description: {
                    Text("东大生存手册的服务端接口即将上线。")
                }
                .padding(.top, 60)
            } else if let error = store.handbookError {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await store.loadHandbookSections() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 60)
            } else if let sections = store.handbookSections {
                if sections.isEmpty {
                    ContentUnavailableView("手册暂无板块", systemImage: "book.closed")
                        .padding(.top, 60)
                } else {
                    sectionList(sections)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            }
        }
        .groupedBackground()
        .task { await store.loadHandbookSections() }
    }

    private func sectionList(_ sections: [HandbookSectionInfo]) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(sections) { section in
                NavigationLink {
                    HandbookSectionView(slug: section.slug, fallbackName: section.name)
                } label: {
                    sectionCard(section)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private func sectionCard(_ section: HandbookSectionInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "books.vertical.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(ForumPalette.solidColor(for: section.slug), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.name)
                        .font(.headline)
                    Text("\(section.articleCount) 篇")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !section.children.isEmpty {
                Divider().padding(.leading, 60)
                ChipsFlowLayout(spacing: 8) {
                    ForEach(section.children) { child in
                        Text("\(child.name) · \(child.articleCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.tertiarySystemFill), in: .capsule)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .cardStyle(padding: 0)
    }
}

/// 手册板块页：板块元信息 + 文章列表 + 「查看该板块讨论」入口（跳到该 tag 的帖子流）。
struct HandbookSectionView: View {
    let slug: String
    /// 列表页带过来的板块名，详情请求返回前导航栏就有标题。
    var fallbackName: String = ""

    @State private var client = ForumAPIClient()
    @State private var section: HandbookSectionInfo?
    @State private var articles: [HandbookArticleSummary]?
    @State private var errorMessage: String?
    @State private var unavailable = false

    private var title: String {
        section?.name ?? (fallbackName.isEmpty ? (ForumTagCatalog.name(for: slug) ?? slug) : fallbackName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                discussionEntry

                if unavailable {
                    ContentUnavailableView {
                        Label("手册内容准备中", systemImage: "book.closed")
                    } description: {
                        Text("该板块的服务端接口即将上线。")
                    }
                    .padding(.top, 40)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("重试") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 40)
                } else if let articles {
                    if articles.isEmpty {
                        ContentUnavailableView {
                            Label("暂无文章", systemImage: "doc.text")
                        } description: {
                            Text("该板块还没有沉淀文章，去讨论区看看吧。")
                        }
                        .padding(.top, 40)
                    } else {
                        articleList(articles)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupedBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    /// 「查看该板块讨论」→ 该 tag 的帖子流。
    private var discussionEntry: some View {
        NavigationLink {
            ForumTagFeedView(tag: ForumTag(slug: slug, name: title))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12), in: .circle)
                Text("查看该板块讨论")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func articleList(_ articles: [HandbookArticleSummary]) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(articles) { article in
                NavigationLink {
                    HandbookArticleView(articleID: article.id, fallbackTitle: article.title)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(article.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if let tagName = ForumTagCatalog.name(for: article.tagSlug) {
                                Text(tagName)
                            }
                            if let author = article.authorDisplay, !author.isEmpty {
                                Text("·")
                                Text(author)
                            }
                            if let publishedAt = article.publishedAt {
                                Text("·")
                                RelativeTimeText(date: publishedAt)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            let result = try await client.handbookSection(slug: slug)
            section = result.section
            articles = result.articles
        } catch let error as ForumAPIClient.ForumAPIError {
            if case .routeUnavailable = error {
                unavailable = true
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 手册文章详情：渲染服务端消毒过的 `content_html`
/// （复用 `DocSection.split` + `HTMLRenderer` 的 HTML 管线，与长文详情同一条路径）。
/// 有 `source_post` 时底部显示「查看原帖讨论」卡片跳帖子详情。
struct HandbookArticleView: View {
    let articleID: String
    var fallbackTitle: String = ""

    @State private var client = ForumAPIClient()
    @State private var article: HandbookArticle?
    @State private var sections: [DocSection] = []
    @State private var errorMessage: String?
    @State private var unavailable = false
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                bodyContent
                if let source = article?.sourcePost {
                    sourcePostCard(source)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupedBackground()
        .navigationTitle("东大生存手册")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: articleID) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(article?.title ?? fallbackTitle)
                .font(.title2.weight(.bold))

            HStack(spacing: 6) {
                if let article, let tagName = ForumTagCatalog.name(for: article.tagSlug) {
                    Text(tagName)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: .capsule)
                }
                if let author = article?.authorDisplay, !author.isEmpty {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                }
                if let publishedAt = article?.publishedAt {
                    RelativeTimeText(date: publishedAt)
                }
            }
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if unavailable {
            ContentUnavailableView {
                Label("手册内容准备中", systemImage: "book.closed")
            } description: {
                Text("该文章的服务端接口即将上线。")
            }
        } else if let errorMessage {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.exclamationmark")
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
                        .lineSpacing(6)
                        .tint(Color.accentColor)
                }
            }
        }
    }

    /// 「查看原帖讨论」卡片：这篇文章是从哪个帖子沉淀来的。
    private func sourcePostCard(_ source: HandbookArticle.SourcePost) -> some View {
        NavigationLink {
            ForumPostDetailView(postID: source.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("查看原帖讨论")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(source.title?.isEmpty == false ? source.title! : "原帖")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text("\(forumCompactCount(source.likesCount)) 赞 · \(forumCompactCount(source.commentsCount)) 评论")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        sections = []
        defer { isLoading = false }
        do {
            let loaded = try await client.handbookArticle(id: articleID)
            article = loaded
            guard !loaded.contentHTML.isEmpty else { return }
            // 手册文章没有 outline 接口，传空集合：切分出的 section 用序号兜底 id。
            sections = await DocSection.split(html: loaded.contentHTML, outlineIDs: [])
        } catch let error as ForumAPIClient.ForumAPIError {
            if case .routeUnavailable = error {
                unavailable = true
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("手册板块") {
    NavigationStack {
        HandbookHomeView()
    }
    .environment(ForumStore())
}
