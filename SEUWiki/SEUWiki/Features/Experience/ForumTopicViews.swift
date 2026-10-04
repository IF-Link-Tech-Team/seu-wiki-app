import SwiftUI

/// 经验 · 话题广场：双列话题卡片（参考 Apple 播客分类页）。
struct ForumTopicsSquareView: View {
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(MockData.topics) { topic in
                    NavigationLink(value: topic) {
                        TopicCard(topic: topic)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .groupedBackground()
    }
}

/// 播客分类风格卡片：饱和纯色底，左下白色加粗话题名，
/// 右侧大尺寸半透明白色装饰图标（略微出血裁切）。
private struct TopicCard: View {
    let topic: ForumTopic

    private var tint: Color {
        ForumPalette.solidColor(for: topic.id)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            tint

            Image(systemName: topic.systemImage)
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(x: 16, y: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(forumCompactCount(topic.postCount)) 篇帖子")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text(topic.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 116)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect)
    }
}

/// 话题详情：关注按钮 + 子标签筛选 + 该话题帖子列表。
struct ForumTopicDetailView: View {
    @Environment(UserProfile.self) private var profile

    let topic: ForumTopic

    /// nil 表示「全部」。
    @State private var selectedSubtag: String?

    private var tint: Color {
        ForumPalette.solidColor(for: topic.id)
    }

    private var isFollowed: Bool {
        profile.followedTopicIDs.contains(topic.id)
    }

    private var posts: [ForumPost] {
        MockData.forumPosts
            .filter { post in
                guard post.tags.contains(topic.id) else { return false }
                if let selectedSubtag {
                    return post.tags.contains(selectedSubtag)
                }
                return true
            }
            .sorted { $0.likesCount > $1.likesCount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                    .padding(.horizontal)
                subtagChips
                postsSection
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .groupedBackground()
        .navigationTitle(topic.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: topic.systemImage)
                .font(.title.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(topic.name)
                    .font(.title2.weight(.bold))
                Text("\(forumCompactCount(topic.postCount)) 篇帖子")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    if isFollowed {
                        profile.followedTopicIDs.remove(topic.id)
                    } else {
                        profile.followedTopicIDs.insert(topic.id)
                    }
                }
            } label: {
                Text(isFollowed ? "已关注" : "关注")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(isFollowed ? Color.secondary : .white)
                    .background(isFollowed ? Color(.tertiarySystemFill) : Color.accentColor, in: .capsule)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: isFollowed)
        }
        .cardStyle()
    }

    private var subtagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", isSelected: selectedSubtag == nil) {
                    selectedSubtag = nil
                }
                ForEach(topic.subtags, id: \.self) { subtag in
                    chip(subtag, isSelected: selectedSubtag == subtag) {
                        selectedSubtag = subtag
                    }
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                action()
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var postsSection: some View {
        LazyVStack(spacing: 12) {
            if posts.isEmpty {
                ContentUnavailableView {
                    Label("暂无帖子", systemImage: "tray")
                } description: {
                    Text("「\(selectedSubtag ?? topic.name)」下还没有帖子，欢迎来发第一篇。")
                }
                .padding(.top, 32)
            } else {
                ForEach(posts) { post in
                    NavigationLink(value: post) {
                        ForumPostCard(post: post)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ForumTopicsSquareView()
    }
    .environment(UserProfile())
}
