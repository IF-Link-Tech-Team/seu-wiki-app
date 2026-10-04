import SwiftUI

/// 本地评论 mock：parentID 指向同帖另一条评论，支持一层楼中楼。
struct PostComment: Identifiable, Hashable {
    let id: String
    var postID: String
    var authorName: String
    var authorHeadline: String
    var text: String
    var likesCount: Int
    var createdAt: Date
    var parentID: String?
}

extension PostComment {
    /// 开发用样例评论：按 postID 派生稳定 id，含两条楼中楼回复。
    static func samples(for postID: String) -> [PostComment] {
        func make(_ suffix: String, _ author: String, _ headline: String, _ text: String, _ likes: Int, _ age: TimeInterval, parent: String? = nil) -> PostComment {
            PostComment(
                id: "\(postID)-\(suffix)",
                postID: postID,
                authorName: author,
                authorHeadline: headline,
                text: text,
                likesCount: likes,
                createdAt: .now.addingTimeInterval(-age),
                parentID: parent
            )
        }
        return [
            make("c1", "顾之遥", "21 级 · 考研上岸本校", "写得太实在了，尤其是时间线那一段。对照着看发现自己正好落后了一个月，赶紧补上。", 214, 3600 * 5),
            make("c2", "江浸月", "22 级 · 数模国一", "补充一个信息差：学院教务老师那边的消息往往比官网快半天，建议大家多留意。", 156, 3600 * 9),
            make("c3", "温知夏", "23 级 · 梅园食堂品鉴大师", "请问楼主可以分享一下文中提到的材料模板吗？万分感谢！", 32, 86400),
            make("c4", "林晚舟", "20 级 · 保研至清华大学", "模板我整理好了，放在这条的回复里，需要自取。记得按自己学院的要求改抬头。", 98, 3600 * 20, parent: "\(postID)-c3"),
            make("c5", "温知夏", "23 级 · 梅园食堂品鉴大师", "收到！已保存，太感谢了。", 12, 3600 * 18, parent: "\(postID)-c3"),
            make("c6", "陆停云", "20 级 · 转至计算机学院", "去年照着楼主前一篇帖子准备的，亲测有效。评论区高手们的补充也很全，建议一起看。", 76, 86400 * 1.5),
        ]
    }
}

/// 论坛帖子详情页：作者行、正文、标签、互动条与楼中楼评论区。
struct ForumPostDetailView: View {
    @Environment(UserProfile.self) private var profile

    let post: ForumPost

    @State private var isLiked = false
    @State private var isFollowingAuthor = false
    @State private var comments: [PostComment]
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    init(post: ForumPost) {
        self.post = post
        _comments = State(initialValue: PostComment.samples(for: post.id))
    }

    private var isBookmarked: Bool {
        profile.bookmarkedPostIDs.contains(post.id)
    }

    /// 正文 mock：excerpt 扩写为完整长帖。
    private var bodyParagraphs: [String] {
        [
            post.excerpt,
            "先说结论：这件事的核心不是天赋，而是信息差和节奏感。越早把关键节点排进自己的日历，后面的每一步就越从容。我把自己踩过的坑按顺序列在下面，大家可以对照自己的进度查漏补缺。",
            "第一，前期准备比想象中更重要。材料、信息渠道、时间节点这三件事，建议单独建一个备忘录，每周固定时间更新一次。很多看起来「运气好」的人，只是把该盯的信息都盯住了。",
            "第二，找到两三个可以请教的学长学姐。大部分问题他们都经历过，一杯奶茶能换来几个小时的弯路。提问时带上自己的现状和已经做过的功课，得到的回答会具体得多。",
            "第三，给自己留缓冲。计划永远赶不上变化，无论是材料截止、考试安排还是临时通知，预留一到两周的机动时间，能让你在出意外时不至于全盘打乱。",
            "最后，这篇帖子会持续更新。评论区欢迎提问和补充，我看到都会回复；如果内容有过时的地方，也欢迎留言指正，我会一并修订。",
        ]
    }

    private var topLevelComments: [PostComment] {
        comments
            .filter { $0.parentID == nil }
            .sorted { $0.likesCount > $1.likesCount }
    }

    private func replies(to comment: PostComment) -> [PostComment] {
        comments
            .filter { $0.parentID == comment.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func authorName(of commentID: String?) -> String? {
        comments.first { $0.id == commentID }?.authorName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                authorRow
                titleBlock
                bodyBlock
                tagChips
                interactionBar
                commentsSection
            }
            .padding()
        }
        .groupedBackground()
        .navigationTitle("帖子")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            composer
        }
    }

    private var authorRow: some View {
        HStack(spacing: 10) {
            ForumAvatar(name: post.authorName, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorName)
                    .font(.subheadline.weight(.semibold))
                Text(post.authorHeadline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    isFollowingAuthor.toggle()
                }
            } label: {
                Text(isFollowingAuthor ? "已关注" : "关注")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .foregroundStyle(isFollowingAuthor ? Color.secondary : .white)
                    .background(isFollowingAuthor ? Color(.tertiarySystemFill) : Color.accentColor, in: .capsule)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: isFollowingAuthor)
        }
        .padding(.horizontal, 4)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if post.isFeatured {
                    Text("精选")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(Color.accentColor)
                        .background(Color.accentColor.opacity(0.12), in: .capsule)
                }
                Text("\(post.createdAt, style: .relative) · \(forumCompactCount(post.viewsCount)) 次浏览")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(post.title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var bodyBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(bodyParagraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.body)
                    .lineSpacing(5)
            }
        }
        .padding(.horizontal, 4)
    }

    private var tagChips: some View {
        HStack(spacing: 8) {
            ForEach(post.tags, id: \.self) { slug in
                Text("# \(forumTopicName(for: slug) ?? slug)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(Color.accentColor)
                    .background(Color.accentColor.opacity(0.1), in: .capsule)
            }
        }
        .padding(.horizontal, 4)
    }

    private var interactionBar: some View {
        HStack(spacing: 0) {
            likeButton
                .frame(maxWidth: .infinity)
            commentButton
                .frame(maxWidth: .infinity)
            bookmarkButton
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .cardStyle(padding: 0)
    }

    private var likeButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                isLiked.toggle()
            }
        } label: {
            Label(forumCompactCount(post.likesCount + (isLiked ? 1 : 0)), systemImage: isLiked ? "heart.fill" : "heart")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isLiked ? .red : .secondary)
                .contentTransition(.numericText())
                .symbolEffect(.bounce, value: isLiked)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: isLiked)
    }

    private var commentButton: some View {
        Button {
            composerFocused = true
        } label: {
            Label(forumCompactCount(post.commentsCount), systemImage: "bubble.right")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var bookmarkButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                if isBookmarked {
                    profile.bookmarkedPostIDs.remove(post.id)
                } else {
                    profile.bookmarkedPostIDs.insert(post.id)
                }
            }
        } label: {
            Label(isBookmarked ? "已收藏" : "收藏", systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isBookmarked ? Color.accentColor : .secondary)
                .symbolEffect(.bounce, value: isBookmarked)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: isBookmarked)
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("评论 \(post.commentsCount)")
                .font(.title3.weight(.bold))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(topLevelComments.enumerated()), id: \.element.id) { index, comment in
                    VStack(spacing: 0) {
                        CommentRow(comment: comment)
                        ForEach(replies(to: comment)) { reply in
                            CommentRow(comment: reply, parentAuthor: authorName(of: reply.parentID))
                                .padding(.leading, 40)
                        }
                    }
                    if index < topLevelComments.count - 1 {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
            .cardStyle(padding: 0)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("写下你的评论…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
                .focused($composerFocused)

            Button {
                sendComment()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: comments.count)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func sendComment() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let comment = PostComment(
            id: UUID().uuidString,
            postID: post.id,
            authorName: "我",
            authorHeadline: "\(profile.grade) · \(profile.college)",
            text: text,
            likesCount: 0,
            createdAt: .now
        )
        withAnimation(.snappy) {
            comments.append(comment)
        }
        draft = ""
        composerFocused = false
    }
}

private struct CommentRow: View {
    let comment: PostComment
    var parentAuthor: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForumAvatar(name: comment.authorName, size: comment.parentID == nil ? 32 : 26)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.caption.weight(.semibold))
                    Text(comment.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let parentAuthor {
                    Text("回复 @\(parentAuthor)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }

                Text(comment.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                Label("\(comment.likesCount)", systemImage: "heart")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

#Preview {
    NavigationStack {
        ForumPostDetailView(post: MockData.forumPosts[0])
    }
    .environment(UserProfile())
}
