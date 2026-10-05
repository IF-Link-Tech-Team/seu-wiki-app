import SwiftUI

/// 搜索主页：一次搜索聚合「通知 / 经验 / 手册」三个信源。
/// - 关键词为空：热门搜索与搜索范围引导。
/// - scope 为「全部」：按信源分区的聚合卡片（每区最多 3 条 + 查看更多）。
/// - scope 为具体信源：直接显示该信源的完整结果列表（不分区）。
/// 「通知」信源来自线上 pool 搜索（SearchStore 负责防抖 / 取消 / 失败回退 MockData）。
struct SearchHomeView: View {
    @State private var keyword = ""
    @State private var scope: SearchScope = .all
    @State private var store: SearchStore

    init(store: SearchStore = SearchStore()) {
        _store = State(initialValue: store)
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
            // `HandbookEntry`，与根视图的 `appNavigationDestinations()` 重复。
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
        } else if let message = store.errorMessage {
            // 搜索失败要**如实告诉用户**并给重试，绝不悄悄换成假结果。
            ContentUnavailableView {
                Label("搜索失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { store.search(keyword: trimmedKeyword) }
                    .buttonStyle(.borderedProminent)
            }
        } else if store.isEmpty {
            // 线上搜索进行中先显示加载中，避免空态闪烁。
            if store.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView.search(text: trimmedKeyword)
            }
        } else if scope == .all {
            aggregatedResults
        } else if store.isEmpty(for: scope) {
            ContentUnavailableView.search(text: trimmedKeyword)
        } else {
            SearchSourceListView(scope: scope, keyword: trimmedKeyword, store: store, title: "搜索")
        }
    }

    /// 「全部」scope：三个信源各自一张分区卡片，无命中的信源不显示。
    private var aggregatedResults: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !store.feed.items.isEmpty {
                    feedSection
                }
                if !store.forum.isEmpty {
                    forumSection
                }
                if !store.handbook.isEmpty {
                    handbookSection
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
            count: store.forum.count,
            destination: SearchSourceListView(scope: .forum, keyword: trimmedKeyword, store: store)
        ) {
            sectionRows(Array(store.forum.prefix(3))) { hit in
                NavigationLink(value: hit) {
                    SearchDocRow(hit: hit, keyword: trimmedKeyword)
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
            count: store.handbook.count,
            destination: SearchSourceListView(scope: .handbook, keyword: trimmedKeyword, store: store)
        ) {
            sectionRows(Array(store.handbook.prefix(3))) { hit in
                NavigationLink(value: hit) {
                    SearchDocRow(hit: hit, keyword: trimmedKeyword)
                        .padding(14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
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
