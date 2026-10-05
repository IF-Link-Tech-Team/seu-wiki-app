import SwiftUI

/// 单一信源的完整搜索结果列表：分区卡片「查看更多」的目的地；
/// ConsoleBar 选定具体信源时也内联复用（此时保留「搜索」大标题）。
/// 「通知」scope 跟随 SearchStore 分页：滚动到底自动加载下一页 pool 结果。
/// 「经验」「手册」是 `pool` 的 `docs` 命中，后端一次性返回、不分页。
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
                            Task { await store.loadMore(for: .feed) }
                        }
                }
            case .forum:
                ForEach(store.forum) { hit in
                    NavigationLink(value: hit) {
                        SearchDocRow(hit: hit, keyword: keyword)
                    }
                }
            case .handbook:
                ForEach(store.handbook) { hit in
                    NavigationLink(value: hit) {
                        SearchDocRow(hit: hit, keyword: keyword)
                    }
                }
            }
        }
        .navigationTitle(title ?? scope.name)
        // 不在这里注册 destination：这个视图既被 push 使用、也被内联在搜索根页里，
        // 重复注册会和根视图的 `appNavigationDestinations()` 打架。
    }
}
