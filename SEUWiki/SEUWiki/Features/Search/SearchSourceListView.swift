import SwiftUI

/// 单一信源的完整搜索结果列表：分区卡片「查看更多」的目的地；
/// ConsoleBar 选定具体信源时也内联复用（此时保留「搜索」大标题）。
/// 「通知」scope 跟随 SearchStore 分页：滚动到底自动加载下一页 pool 结果。
struct SearchSourceListView: View {
    let scope: SearchScope
    let keyword: String
    let store: SearchStore
    var title: String? = nil

    var body: some View {
        List {
            switch scope {
            case .all, .feed:
                ForEach(store.feed.items) { item in
                    NavigationLink(value: item) {
                        SearchFeedRow(item: item, keyword: keyword)
                    }
                }
                if store.feed.hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            Task { await store.loadMoreFeed() }
                        }
                }
            case .forum:
                ForEach(store.forum) { post in
                    NavigationLink(value: post) {
                        SearchForumRow(post: post, keyword: keyword)
                    }
                }
            case .handbook:
                ForEach(store.handbook) { entry in
                    NavigationLink(value: entry) {
                        SearchHandbookRow(entry: entry, keyword: keyword)
                    }
                }
            }
        }
        .navigationTitle(title ?? scope.name)
        .appNavigationDestinations()
        .navigationDestination(for: HandbookEntry.self) { entry in
            SearchHandbookEntryView(entry: entry)
        }
    }
}
