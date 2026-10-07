import SwiftUI

/// 单一信源的完整搜索结果列表：分区卡片「查看更多」的目的地；
/// ConsoleBar 选定具体信源时也内联复用（此时保留「搜索」大标题）。
/// 「通知」走 pool 的 page 分页；「经验」「手册」走论坛 `/api/search` 的
/// keyset 分页 —— 三个 scope 滚动到底都会自动加载下一页。
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
                loadMoreRow(for: .feed)
            case .forum:
                ForEach(store.forum.items) { post in
                    NavigationLink {
                        ForumPostDetailView(postID: post.id, summary: post)
                    } label: {
                        SearchPostRow(post: post, keyword: keyword)
                    }
                }
                loadMoreRow(for: .forum)
            case .handbook:
                ForEach(store.handbook.items) { article in
                    NavigationLink {
                        HandbookArticleView(articleID: article.id, fallbackTitle: article.title)
                    } label: {
                        SearchHandbookArticleRow(article: article, keyword: keyword)
                    }
                }
                loadMoreRow(for: .handbook)
            }
        }
        .navigationTitle(title ?? scope.name)
        // 不在这里注册 destination：这个视图既被 push 使用、也被内联在搜索根页里，
        // 重复注册会和根视图的 `appNavigationDestinations()` 打架。
    }

    @ViewBuilder
    private func loadMoreRow(for scope: SearchScope) -> some View {
        if store.hasMore(for: scope) {
            ProgressView()
                .frame(maxWidth: .infinity)
                .onAppear {
                    Task { await store.loadMore(for: scope) }
                }
        }
    }
}
