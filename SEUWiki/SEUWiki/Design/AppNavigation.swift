import SwiftUI

/// 全局共享的 value-based 导航目的地：任何 Tab 的 NavigationStack 内
/// 都可以直接 `NavigationLink(value:)` 到资讯、帖子或手册/经验长文详情。
///
/// **只在每个 Tab 的根部注册一次。** 早期版本在 `SearchSourceListView`、
/// `HomeFeedSection`、`HomeForumSection` 里又各注册了一遍，既重复又在被内联复用时
/// 会和根部注册互相覆盖。
extension View {
    func appNavigationDestinations() -> some View {
        self
            .navigationDestination(for: FeedItem.self) { item in
                FeedItemDetailView(item: item)
            }
            .navigationDestination(for: ForumPost.self) { post in
                ForumPostDetailView(post: post)
            }
            .navigationDestination(for: DocSearchHit.self) { hit in
                DocDetailView(slug: hit.slug, kind: hit.kind, highlightAnchor: hit.anchor?.id)
            }
    }
}
