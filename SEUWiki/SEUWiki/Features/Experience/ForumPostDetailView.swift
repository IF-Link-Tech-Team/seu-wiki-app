import SwiftUI

/// 论坛帖子详情：真实评论 / 点赞 / 收藏 / 浏览计数。
///
/// 打开时 `POST /api/posts/:id/view` 浏览 +1（失败静默，不影响展示）。
/// 点赞与收藏的初始状态：收藏由详情响应的 `bookmarked` 给出（登录才准确）；
/// **「赞」没有读取接口**（仓库路由里没有 hasUserLiked 的 GET），所以进入详情时
/// 一律显示未赞，点按后以 toggle 返回的 `liked` 为准 —— 这是后端契约的限制，
/// 不是客户端遗漏。
struct ForumPostDetailView: View {
    let postID: String
    /// 列表卡片带过来的摘要，详情请求返回前先展示它，避免整页空白转圈。
    var summary: ForumPost? = nil

    @State private var client = ForumAPIClient()
    @State private var auth = AuthStore.shared
    @State private var detail: ForumPostDetail?
    @State private var errorMessage: String?
    @State private var isLoading = true

    /// 互动状态（随详情响应初始化，点按后与服务器结果对齐）。
    @State private var liked = false
    @State private var likesCount = 0
    @State private var bookmarked = false
    @State private var viewsCount = 0
    @State private var commentsCount = 0
    /// 未登录点「赞/收藏」时弹登录引导。
    @State private var showsLoginGuide = false

    @State private var comments: [ForumComment]?
    @State private var commentsError: String?
    @State private var draft = ""
    /// 楼中楼的回复目标（单层级：回复一条回复时挂到其顶层评论上）。
    @State private var replyTarget: ForumComment?
    @State private var isSending = false

    private var shownPost: ForumPost? { detail?.post ?? summary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let post = shownPost {
                    header(post)
                    contentSection(post)
                    if let link = detail?.handbookArticle {
                        handbookCard(link)
                    }
                    actionBar
                    commentSection
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("重试") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 60)
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
        .navigationTitle("帖子")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom) {
            if shownPost != nil {
                commentInputBar
            }
        }
        .sheet(isPresented: $showsLoginGuide) {
            NavigationStack {
                LoginView(auth: auth)
            }
        }
        .task { await load() }
    }

    // MARK: - 加载

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await client.postDetail(id: postID)
            detail = loaded
            likesCount = loaded.post.likesCount
            bookmarked = loaded.bookmarked
            commentsCount = loaded.post.commentsCount
            // 浏览计数：先展示详情返回的值，再尝试 +1（失败静默，保持原值）。
            viewsCount = loaded.post.viewsCount
            if let views = await client.incrementView(id: postID) {
                viewsCount = views
            }
        } catch let error as ForumAPIClient.ForumAPIError {
            self.errorMessage = error.errorDescription
        } catch {
            self.errorMessage = error.localizedDescription
        }
        await loadComments()
    }

    private func loadComments() async {
        commentsError = nil
        do {
            comments = try await client.comments(postID: postID)
        } catch {
            commentsError = "评论加载失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 头部与正文

    private func header(_ post: ForumPost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if post.isPinned {
                    Label("置顶", systemImage: "pin.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if detail?.featured == true {
                    Label("精选", systemImage: "star.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
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

            if let title = post.title, !title.isEmpty {
                Text(title)
                    .font(.title2.weight(.bold))
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                if let author = post.author {
                    ForumAvatar(name: author.name, size: 28)
                    Text(author.name)
                        .font(.subheadline.weight(.medium))
                }
                Spacer(minLength: 4)
                if let createdAt = post.createdAt {
                    RelativeTimeText(date: createdAt)
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func contentSection(_ post: ForumPost) -> some View {
        if !post.content.isEmpty {
            Text(post.content)
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !post.imagePaths.isEmpty {
            imageGrid(post.imagePaths)
        }
    }

    private func imageGrid(_ paths: [String]) -> some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(paths, id: \.self) { path in
                if let url = client.resolveAssetURL(path) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            // 图片加载失败要显式占位，不能留白让人以为这里没有内容。
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        default:
                            ProgressView()
                        }
                    }
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    /// 「已收录进东大生存手册」卡片 → 手册文章详情。
    private func handbookCard(_ link: HandbookArticleLink) -> some View {
        NavigationLink {
            HandbookArticleView(articleID: link.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "book.closed.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.green)
                    .frame(width: 32, height: 32)
                    .background(Color.green.opacity(0.12), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("已收录进东大生存手册")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(link.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
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

    // MARK: - 互动栏

    private var actionBar: some View {
        HStack(spacing: 20) {
            Button { Task { await toggleLike() } } label: {
                Label(forumCompactCount(likesCount), systemImage: liked ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(liked ? .red : .secondary)
            }
            .buttonStyle(.plain)

            Label(forumCompactCount(commentsCount), systemImage: "bubble.left")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(forumCompactCount(viewsCount), systemImage: "eye")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button { Task { await toggleBookmark() } } label: {
                Label(bookmarked ? "已收藏" : "收藏", systemImage: bookmarked ? "bookmark.fill" : "bookmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(bookmarked ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func toggleLike() async {
        guard auth.isLoggedIn else { showsLoginGuide = true; return }
        do {
            let liked = try await client.togglePostLike(postID: postID)
            self.liked = liked
            likesCount += liked ? 1 : -1
            likesCount = max(0, likesCount)
        } catch let error as ForumAPIClient.ForumAPIError {
            if case .unauthorized = error { showsLoginGuide = true }
        } catch {
            // 点赞失败静默：不打断阅读，下次进入详情会与服务器对齐。
        }
    }

    private func toggleBookmark() async {
        guard auth.isLoggedIn else { showsLoginGuide = true; return }
        do {
            bookmarked = try await client.toggleBookmark(postID: postID)
        } catch let error as ForumAPIClient.ForumAPIError {
            if case .unauthorized = error { showsLoginGuide = true }
        } catch {
            // 同上：失败静默，进入详情时重新对齐。
        }
    }

    // MARK: - 评论

    /// 顶层评论（parentID 为空），按时间正序。
    private var topLevelComments: [ForumComment] {
        (comments ?? []).filter { $0.parentID == nil }
    }

    /// 某条顶层评论下的回复：后端允许 parent_id 指向任意一条评论（含回复），
    /// 展示时统一归并到顶层评论之下（单层楼中楼）。
    private func replies(to comment: ForumComment) -> [ForumComment] {
        (comments ?? []).filter { candidate in
            guard let parent = candidate.parentID else { return false }
            if parent == comment.id { return true }
            // parent 指向本层某条回复时也算进来。
            return (comments ?? []).contains { $0.id == parent && $0.parentID == comment.id }
        }
    }

    @ViewBuilder
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("评论 \(forumCompactCount(commentsCount))")
                .font(.headline)

            if let commentsError {
                HStack(spacing: 8) {
                    Text(commentsError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("重试") { Task { await loadComments() } }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            } else if comments == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else if topLevelComments.isEmpty {
                Text("还没有评论，来说两句。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(topLevelComments) { comment in
                    commentRow(comment, depth: 0)
                    ForEach(replies(to: comment)) { reply in
                        commentRow(reply, depth: 1)
                    }
                }
            }
        }
    }

    private func commentRow(_ comment: ForumComment, depth: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ForumAvatar(name: comment.author?.name ?? "东大同学", size: depth == 0 ? 32 : 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author?.name ?? "东大同学")
                        .font(.caption.weight(.medium))
                    if let createdAt = comment.createdAt {
                        RelativeTimeText(date: createdAt, font: .caption2, color: Color(.tertiaryLabel))
                    }
                }
                Text(comment.content)
                    .font(.subheadline)
                    .textSelection(.enabled)
                Button("回复") {
                    guard auth.isLoggedIn else { showsLoginGuide = true; return }
                    replyTarget = comment
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, depth == 0 ? 0 : 36)
    }

    // MARK: - 评论输入

    private var commentInputBar: some View {
        VStack(spacing: 6) {
            if let replyTarget {
                HStack {
                    Text("回复 \(replyTarget.author?.name ?? "东大同学")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消", systemImage: "xmark.circle") {
                        self.replyTarget = nil
                    }
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
            HStack(spacing: 8) {
                TextField(auth.isLoggedIn ? "写下你的评论…" : "登录后才能评论", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12, style: .continuous))
                    .disabled(!auth.isLoggedIn || isSending)
                    .onTapGesture {
                        if !auth.isLoggedIn { showsLoginGuide = true }
                    }

                Button {
                    Task { await sendComment() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canSend ? Color.accentInk : .secondary)
                        .frame(width: 36, height: 36)
                        .background(canSend ? Color.accentColor : Color(.tertiarySystemFill), in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("发送评论")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        auth.isLoggedIn && !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendComment() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        // 后端上限 5000 字（parseCommentCreateInput），超了在客户端就拦下。
        guard content.count <= 5000 else { return }
        isSending = true
        defer { isSending = false }
        do {
            // 单层楼中楼：回复一条回复时，挂到它的顶层评论上。
            let parentID = replyTarget.flatMap { $0.parentID ?? $0.id }
            var created = try await client.createComment(postID: postID, content: content, parentID: parentID)
            if created.author == nil, auth.isLoggedIn {
                created.author = ForumAuthor(
                    id: auth.ifLinkID,
                    displayName: auth.displayName,
                    username: nil,
                    avatarURL: auth.avatarURL?.absoluteString
                )
            }
            comments = (comments ?? []) + [created]
            commentsCount += 1
            draft = ""
            replyTarget = nil
        } catch let error as ForumAPIClient.ForumAPIError {
            if case .unauthorized = error { showsLoginGuide = true }
        } catch {
            // 发送失败保留草稿，用户可再点一次发送。
        }
    }
}

#Preview {
    NavigationStack {
        ForumPostDetailView(
            postID: "00000000-0000-0000-0000-000000000000",
            summary: ForumPost(
                id: "00000000-0000-0000-0000-000000000000",
                title: "示例标题",
                content: "示例正文",
                createdAt: .now,
                likesCount: 0,
                commentsCount: 0,
                viewsCount: 0,
                pinnedAt: nil,
                author: nil,
                imagePaths: [],
                tags: []
            )
        )
    }
    .environment(ForumStore())
}
