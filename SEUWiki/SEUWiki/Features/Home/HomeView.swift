import SwiftUI

struct HomeView: View {
    @Environment(UserProfile.self) private var profile
    @Environment(FeedStore.self) private var store
    @State private var showsProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        ReminderCard(reminder: profile.reminders.min { $0.dueDate < $1.dueDate })
                        NextCourseCard(course: profile.nextCourse)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    HomeFeedSection(items: feedItems)
                    HomeForumSection(posts: Array(MockData.forumPosts.prefix(3)))
                }
                .padding()
            }
            .groupedBackground()
            .navigationTitle("主页")
            .profileEntry(isPresented: $showsProfile)
            .appNavigationDestinations()
            .task {
                await store.loadIfNeeded(scope: .forYou, profile: profile)
            }
        }
    }

    /// 首页通知区用「为你精选」第一页；未加载时（含 Preview）回退 Mock 精选，加载失败时
    /// store 本身已回退 Mock，此处总是有内容。
    private var feedItems: [FeedItem] {
        let items = store.page(for: .forYou).items
        return items.isEmpty ? MockData.feedItems.filter(\.isSelected) : items
    }
}

#Preview {
    HomeView()
        .environment(UserProfile())
        .environment(FeedStore(mockOnly: true))
}
