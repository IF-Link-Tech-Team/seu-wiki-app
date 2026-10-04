import SwiftUI

/// 全局共享的 value-based 导航目的地：任何 Tab 的 NavigationStack 内
/// 都可以直接 `NavigationLink(value:)` 到资讯或帖子详情。
extension View {
    func appNavigationDestinations() -> some View {
        self
            .navigationDestination(for: FeedItem.self) { item in
                FeedItemDetailView(item: item)
            }
            .navigationDestination(for: ForumPost.self) { post in
                ForumPostDetailView(post: post)
            }
    }
}
