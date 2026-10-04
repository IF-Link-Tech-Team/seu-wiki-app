import SwiftUI

/// 「经验」主页：热门 / 关注 / 话题 / 生存手册四个子页，
/// ConsoleBar 与可侧滑的 page TabView 双向绑定。
struct ExperienceHomeView: View {
    @State private var showsProfile = false
    @State private var tab: ForumFeedTab = .hot

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ConsoleBar(items: ForumFeedTab.allCases, selection: $tab) { $0.name }

                TabView(selection: $tab) {
                    ForumHotFeedView()
                        .tag(ForumFeedTab.hot)
                    ForumFollowingFeedView(onBrowseTopics: { select(.topics) })
                        .tag(ForumFeedTab.following)
                    ForumTopicsSquareView()
                        .tag(ForumFeedTab.topics)
                    HandbookHomeView()
                        .tag(ForumFeedTab.handbook)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .groupedBackground()
            .navigationTitle("经验")
            .profileEntry(isPresented: $showsProfile)
            .appNavigationDestinations()
            .navigationDestination(for: ForumTopic.self) { topic in
                ForumTopicDetailView(topic: topic)
            }
            .navigationDestination(for: HandbookSection.self) { section in
                HandbookSectionView(section: section)
            }
        }
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
