import SwiftUI

/// 搜索主页：一次搜索聚合「通知 / 经验 / 手册」三个信源。
/// - 关键词为空：热门搜索与搜索范围引导。
/// - scope 为「全部」：按信源分区的聚合卡片（每区最多 3 条 + 查看更多）。
/// - scope 为具体信源：直接显示该信源的完整结果列表（不分区）。
/// 「通知」信源来自线上 pool 搜索；「经验」「手册」来自论坛 `/api/search`
/// （SearchStore 负责防抖 / 取消，两个信源各自成败互不牵连，均不回退假数据）。
struct SearchHomeView: View {
    @State private var keyword = ""
    @State private var scope: SearchScope = .all
    @State private var store: SearchStore

    init(store: SearchStore = SearchStore()) {
        _store = State(initialValue: store)
        // Debug 专用：`-uisearch 保研` 冷启动直接带关键词搜索。
        // 本机无合成输入能力，没有这个开关就截不到聚合结果页做验收。
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-uisearch"), index + 1 < args.count {
            _keyword = State(initialValue: args[index + 1])
        }
        #endif
    }

    private var trimmedKeyword: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            content
                .safeAreaBar(edge: .top) {
                    // 固定在导航栏下方：搜索结果可能很长，scope 切换器不该跟着滚走。
                    ConsoleBar(items: SearchScope.allCases, selection: $scope) { $0.name }
                }
                .groupedBackground()
            .navigationTitle("搜索")
            .trackScreen("/search", title: "搜索")
            // `displayMode: .always` 是**故意**保留的。
            //
            // 既有审查（I-3）建议去掉 placement，理由是「钉在顶部会失去 tab 栏的变形动画」。
            // 实测否掉了这条建议：在 iOS 27（当前模拟器系统版本，工程目标仍是 26.0）上，
            // 不指定 placement 时系统会把搜索框收进抽屉，**进入搜索 tab 只看到大标题和
            // scope 行，搜索框完全不可见**，必须下拉才拉出来。对一个独立的搜索 tab 来说
            // 「看不见搜索框」是功能问题，「少一个动效」是观感问题，取舍很清楚。
            // `.searchPresentationToolbarBehavior(.avoidHidingContent)` 则让搜索时
            // tab 栏不消失，保住那部分体验。
            .searchable(
                text: $keyword,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索通知、经验、手册"
            )
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .onChange(of: trimmedKeyword, initial: true) { _, newValue in
                store.search(keyword: newValue)
            }
            // 只在根部注册一次 destination。早期版本在这里又注册了一遍
            // 手册条目，与根视图的 `appNavigationDestinations()` 重复。
            .appNavigationDestinations()
        }
    }

    @ViewBuilder
    private var content: some View {
        if trimmedKeyword.isEmpty {
            SearchSuggestionsView { word in
                withAnimation(.smooth) {
                    keyword = word
                }
            }
        } else if scope == .all {
            aggregatedResults
        } else {
            scopedResult(scope)
        }
    }

    /// 具体信源 scope：论坛两个信源要先处理「接口未部署 / 失败」，
    /// 再落入通用的空态与列表。
    @ViewBuilder
    private func scopedResult(_ scope: SearchScope) -> some View {
        if scope != .feed, store.forumUnavailable {
            forumUnavailableCard
        } else if scope != .feed, let message = store.forumErrorMessage {
            errorCard(title: "论坛搜索失败", message: message)
        } else if scope == .feed, let message = store.errorMessage, store.feed.items.isEmpty {
            errorCard(title: "搜索失败", message: message)
        } else if store.isEmpty(for: scope) {
            if store.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView.search(text: trimmedKeyword)
            }
        } else {
            SearchSourceListView(scope: scope, keyword: trimmedKeyword, store: store, title: "搜索")
        }
    }

    // MARK: - 「全部」聚合

    /// 「全部」scope：三个信源各自一张分区卡片；无命中的信源不显示，
    /// 失败/未部署的信源显示如实的状态卡，不拖垮还能用的信源。
    private var aggregatedResults: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !store.feed.items.isEmpty {
                    feedSection
                } else if let message = store.errorMessage {
                    noticeCard(scope: .feed, title: "通知搜索失败", message: message)
                }

                if store.forumUnavailable {
                    noticeCard(scope: .forum, title: "论坛搜索即将上线", message: "经验帖与手册文章的搜索接口还在部署中。")
                } else {
                    if !store.forum.items.isEmpty {
                        forumSection
                    }
                    if !store.handbook.items.isEmpty {
                        handbookSection
                    }
                    if store.forum.items.isEmpty, store.handbook.items.isEmpty, let message = store.forumErrorMessage {
                        noticeCard(scope: .forum, title: "论坛搜索失败", message: message)
                    }
                }

                if store.isEmpty, store.errorMessage == nil, store.forumErrorMessage == nil, !store.forumUnavailable {
                    if store.isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        ContentUnavailableView.search(text: trimmedKeyword)
                    }
                }
            }
            .padding()
        }
    }

    private var feedSection: some View {
        SearchSectionCard(
            scope: .feed,
            count: store.feed.total,
            destination: SearchSourceListView(scope: .feed, keyword: trimmedKeyword, store: store)
        ) {
            sectionRows(Array(store.feed.items.prefix(3))) { item in
                NavigationLink(value: item) {
                    SearchFeedRow(item: item, keyword: trimmedKeyword)
                        .padding(14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var forumSection: some View {
        SearchSectionCard(
            scope: .forum,
            count: store.forum.items.count,
            destination: SearchSourceListView(scope: .forum, keyword: trimmedKeyword, store: store)
        ) {
            sectionRows(Array(store.forum.items.prefix(3))) { post in
                NavigationLink {
                    ForumPostDetailView(postID: post.id, summary: post)
                } label: {
                    SearchPostRow(post: post, keyword: trimmedKeyword)
                        .padding(14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var handbookSection: some View {
        SearchSectionCard(
            scope: .handbook,
            count: store.handbook.items.count,
            destination: SearchSourceListView(scope: .handbook, keyword: trimmedKeyword, store: store)
        ) {
            sectionRows(Array(store.handbook.items.prefix(3))) { article in
                NavigationLink {
                    HandbookArticleView(articleID: article.id, fallbackTitle: article.title)
                } label: {
                    SearchHandbookArticleRow(article: article, keyword: trimmedKeyword)
                        .padding(14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 状态卡

    /// 论坛 `/api/search` 尚未部署时的显式标注（不是错误，不给重试）。
    private var forumUnavailableCard: some View {
        ContentUnavailableView {
            Label("论坛搜索即将上线", systemImage: "bubble.left.and.text.bubble.right")
        } description: {
            Text("经验帖与手册文章的搜索接口还在部署中，通知搜索不受影响。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 聚合视图里的单信源状态卡（失败/未部署），不打断其他信源的结果。
    private func noticeCard(scope: SearchScope, title: String, message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: scope.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(scope.tint)
                .frame(width: 30, height: 30)
                .background(scope.tint.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 0)
    }

    private func errorCard(title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") { store.search(keyword: trimmedKeyword) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 分区卡片内的结果行列表：行间分隔线与 Home 分区一致。
    private func sectionRows<Item: Identifiable, Row: View>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                if index < items.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
    }
}

#Preview {
    SearchHomeView()
}
