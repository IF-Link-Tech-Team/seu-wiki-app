import SwiftUI

/// 「经验」主页：热门 / 话题 / 关注 / 生存手册四个子页，
/// ConsoleBar 与可侧滑的 page TabView 双向绑定。
///
/// 数据全部来自 `seu-wiki-v2` 的 `/api/site/docs/*`（真实内容）。
/// 论坛 UGC 未接通，「关注」页如实说明，不放编造帖子。
struct ExperienceHomeView: View {
    @State private var showsProfile = false
    @State private var tab: ForumFeedTab = .hot
    @State private var store = ExperienceStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ConsoleBar(items: ForumFeedTab.allCases, selection: $tab) { $0.name }

                TabView(selection: $tab) {
                    ForumHotFeedView()
                        .tag(ForumFeedTab.hot)
                    ForumTopicsSquareView()
                        .tag(ForumFeedTab.topics)
                    ForumFollowingFeedView(onBrowseTopics: { select(.topics) })
                        .tag(ForumFeedTab.following)
                    HandbookHomeView()
                        .tag(ForumFeedTab.handbook)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .groupedBackground()
            .navigationTitle("经验")
            .profileEntry(isPresented: $showsProfile)
            .appNavigationDestinations()
        }
        .environment(store)
    }

    private func select(_ tab: ForumFeedTab) {
        withAnimation(.smooth(duration: 0.35)) {
            self.tab = tab
        }
    }
}

#Preview {
    ExperienceHomeView()
        .environment(UserProfile())
}
