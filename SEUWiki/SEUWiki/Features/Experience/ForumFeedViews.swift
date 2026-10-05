import Foundation
import SwiftUI

/// 数字紧凑格式：过万显示「x.x万」。
func forumCompactCount(_ value: Int) -> String {
    if value >= 10000 {
        String(format: "%.1f万", Double(value) / 10000)
    } else {
        "\(value)"
    }
}

/// 论坛/手册共用的确定式配色：同一 key 恒定同色。
enum ForumPalette {
    static let colors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .mint]

    /// 高饱和实体色：话题卡片底色与手册分类图标（对齐 Apple 播客分类页）。
    static let solidColors: [Color] = [
        Color(red: 0.62, green: 0.66, blue: 0.22),
        Color(red: 0.86, green: 0.24, blue: 0.32),
        Color(red: 0.93, green: 0.49, blue: 0.16),
        Color(red: 0.88, green: 0.30, blue: 0.47),
        Color(red: 0.36, green: 0.68, blue: 0.26),
        Color(red: 0.18, green: 0.62, blue: 0.58),
        Color(red: 0.24, green: 0.52, blue: 0.89),
        Color(red: 0.50, green: 0.36, blue: 0.83),
        Color(red: 0.86, green: 0.28, blue: 0.62),
        Color(red: 0.94, green: 0.62, blue: 0.14),
    ]

    static func color(for key: String) -> Color {
        let sum = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[sum % colors.count]
    }

    static func solidColor(for key: String) -> Color {
        let sum = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return solidColors[sum % solidColors.count]
    }
}

/// 圆形 initials 头像。
struct ForumAvatar: View {
    let name: String
    var size: CGFloat = 36

    private var tint: Color {
        ForumPalette.color(for: name)
    }

    var body: some View {
        Text(name.prefix(1))
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: .circle)
            .accessibilityHidden(true)
    }
}

extension DocItem {
    /// 供 `NavigationLink(value:)` 使用的目标值。
    var navigationValue: DocSearchHit {
        DocSearchHit(
            slug: slug,
            kind: .experience,
            title: title,
            description: description,
            occurredAt: occurredAt,
            anchor: nil
        )
    }
}

/// 经验长文卡片：标题 + 摘要 + 作者/分类 + 所属信源。
///
/// 数据来自 `/api/site/docs/experience`，是**真实内容**。早期版本这里是编造的帖子
/// （虚构作者「林晚舟」、编造的 1893 赞 / 342 评论），界面上没有任何标记。
struct ExperienceDocCard: View {
    let item: DocItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.headline)
                .multilineTextAlignment(.leading)

            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: 6) {
                ForEach(metaChips, id: \.self) { chip in
                    Text(chip)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var metaChips: [String] {
        var chips: [String] = []
        if let author = item.author, !author.isEmpty { chips.append(author) }
        if let category = item.category, !category.isEmpty { chips.append(category) }
        if let grade = item.grade, !grade.isEmpty, grade != "全年级" { chips.append(grade) }
        if let college = item.college, !college.isEmpty, college != "通用" { chips.append(college) }
        if let occurred = item.occurredAt, !occurred.isEmpty { chips.append(occurred) }
        return chips
    }
}

/// 经验 · 热门：经验长文列表（真实数据）。
struct ForumHotFeedView: View {
    @Environment(ExperienceStore.self) private var store: ExperienceStore?

    var body: some View {
        ScrollView {
            if let store {
                if store.isLoadingExperience && store.experience == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let error = store.experienceError {
                    errorState(error)
                } else if let items = store.experience?.items, !items.isEmpty {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink(value: item.navigationValue) {
                                ExperienceDocCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                } else {
                    ContentUnavailableView("暂无经验内容", systemImage: "text.book.closed")
                }
            }
        }
        .groupedBackground()
        .task { await store?.loadExperience() }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") { Task { await store?.loadExperience() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// 经验 · 话题：用后端下发的**真实分面**（场景 / 年级 / 学院）做话题广场。
///
/// 早期版本用本地硬编码的 9 个话题 slug，且子话题筛选拿中文名去匹配 slug，
/// 结果永远为空（I-7）。
struct ForumTopicsSquareView: View {
    @Environment(ExperienceStore.self) private var store: ExperienceStore?

    var body: some View {
        ScrollView {
            if let store {
                if store.isLoadingExperience && store.experience == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let error = store.experienceError {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") { Task { await store.loadExperience() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    facets(store)
                    resultList(store)
                }
            }
        }
        .groupedBackground()
        .task { await store?.loadExperience() }
    }

    @ViewBuilder
    private func facets(_ store: ExperienceStore) -> some View {
        let filters = store.experience?.filters ?? []
        if !filters.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(filters) { facet in
                    facetRow(facet, store: store)
                }
                if store.hasActiveFacets {
                    Button("清除筛选", systemImage: "xmark.circle") {
                        store.clearFacets()
                        Task { await store.reloadExperience() }
                    }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                }
            }
            .padding()
        }
    }

    private func facetRow(_ facet: ExperienceIndex.Facet, store: ExperienceStore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(facet.label)
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(facet.values, id: \.self) { value in
                        let selected = store.isSelected(value, inFacet: facet.key)
                        Button {
                            store.toggle(value, inFacet: facet.key)
                            Task { await store.reloadExperience() }
                        } label: {
                            Text(value)
                                .font(.footnote)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiarySystemFill)),
                                    in: .capsule
                                )
                                .foregroundStyle(selected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func resultList(_ store: ExperienceStore) -> some View {
        let items = store.experience?.items ?? []
        if items.isEmpty {
            ContentUnavailableView("没有符合条件的内容", systemImage: "line.3.horizontal.decrease.circle")
                .padding(.top, 20)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(items) { item in
                    NavigationLink(value: item.navigationValue) {
                        ExperienceDocCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}

/// 经验 · 关注：论坛 UGC 尚未接通，如实说明而不是编造帖子。
///
/// `seu-wiki-forum` 仓库里只有 Supabase migration，没有任何可供客户端调用的 HTTP 路由，
/// 所以「关注的话题的新帖」在服务端根本不存在。宁可空着并说清楚，也不要拿假帖子填。
struct ForumFollowingFeedView: View {
    @Environment(UserProfile.self) private var profile
    let onBrowseTopics: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView {
                    Label("社区功能即将上线", systemImage: "person.2.badge.gearshape")
                } description: {
                    Text("关注话题、订阅作者、发帖与互动正在开发中。\n现在可以先看看经验长文与东大生存手册。")
                } actions: {
                    Button("浏览经验内容", action: onBrowseTopics)
                        .buttonStyle(.borderedProminent)
                }

                if !profile.followedTopicIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("你关注的话题")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(profile.followedTopicIDs.sorted().joined(separator: "、"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
            }
            .padding()
        }
        .groupedBackground()
    }
}

#Preview("热门") {
    NavigationStack {
        ForumHotFeedView()
            .appNavigationDestinations()
    }
    .environment(UserProfile())
    .environment(ExperienceStore())
}

#Preview("关注") {
    NavigationStack {
        ForumFollowingFeedView(onBrowseTopics: {})
    }
    .environment(UserProfile())
    .environment(ExperienceStore())
}
