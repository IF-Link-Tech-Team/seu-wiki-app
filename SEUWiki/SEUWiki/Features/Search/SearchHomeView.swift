import SwiftUI

/// 搜索主页：一次搜索聚合「通知 / 经验 / 手册」三个信源。
/// - 关键词为空：热门搜索与搜索范围引导。
/// - scope 为「全部」：按信源分区的聚合卡片（每区最多 3 条 + 查看更多）。
/// - scope 为具体信源：直接显示该信源的完整结果列表（不分区）。
struct SearchHomeView: View {
    @State private var keyword = ""
    @State private var scope: SearchScope = .all

    private var trimmedKeyword: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: SearchResults {
        SearchEngine.search(trimmedKeyword)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ConsoleBar(items: SearchScope.allCases, selection: $scope) { $0.name }
                content
            }
            .groupedBackground()
            .navigationTitle("搜索")
            .searchable(
                text: $keyword,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索通知、经验、手册"
            )
            .appNavigationDestinations()
            .navigationDestination(for: HandbookEntry.self) { entry in
                SearchHandbookEntryView(entry: entry)
            }
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
        } else if results.isEmpty {
            ContentUnavailableView.search(text: trimmedKeyword)
        } else if scope == .all {
            aggregatedResults
        } else if results.isEmpty(for: scope) {
            ContentUnavailableView.search(text: trimmedKeyword)
        } else {
            SearchSourceListView(scope: scope, keyword: trimmedKeyword, results: results, title: "搜索")
        }
    }

    /// 「全部」scope：三个信源各自一张分区卡片，无命中的信源不显示。
    private var aggregatedResults: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !results.feed.isEmpty {
                    feedSection
                }
                if !results.forum.isEmpty {
                    forumSection
                }
                if !results.handbook.isEmpty {
                    handbookSection
                }
            }
            .padding()
        }
    }

    private var feedSection: some View {
        SearchSectionCard(
            scope: .feed,
            count: results.feed.count,
            destination: SearchSourceListView(scope: .feed, keyword: trimmedKeyword, results: results)
        ) {
            sectionRows(Array(results.feed.prefix(3))) { item in
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
            count: results.forum.count,
            destination: SearchSourceListView(scope: .forum, keyword: trimmedKeyword, results: results)
        ) {
            sectionRows(Array(results.forum.prefix(3))) { post in
                NavigationLink(value: post) {
                    SearchForumRow(post: post, keyword: trimmedKeyword)
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
            count: results.handbook.count,
            destination: SearchSourceListView(scope: .handbook, keyword: trimmedKeyword, results: results)
        ) {
            sectionRows(Array(results.handbook.prefix(3))) { entry in
                NavigationLink(value: entry) {
                    SearchHandbookRow(entry: entry, keyword: trimmedKeyword)
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
