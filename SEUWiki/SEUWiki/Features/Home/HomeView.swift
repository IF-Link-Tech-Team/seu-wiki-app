import SwiftUI

struct HomeView: View {
    @Environment(UserProfile.self) private var profile
    @Environment(FeedStore.self) private var feedStore
    @State private var experienceStore = ExperienceStore()
    @State private var showsProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 提醒卡 / 课程卡并排；大字号下改为竖排（AX1 以上两列会挤到截断）。
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            reminderCard
                            nextCourseCard
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 12) {
                            reminderCard
                            nextCourseCard
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    HomeFeedSection(items: feedItems)
                    HomeForumSection()
                }
                .padding()
            }
            .groupedBackground()
            .navigationTitle("主页")
            .profileEntry(isPresented: $showsProfile)
            .appNavigationDestinations()
            .task {
                await feedStore.loadIfNeeded(scope: .forYou, profile: profile)
            }
        }
        .environment(experienceStore)
    }

    private var reminderCard: some View {
        ReminderCard(reminder: profile.nextPendingReminder)
    }

    private var nextCourseCard: some View {
        NextCourseCard(course: profile.nextCourse)
    }

    /// 首页通知区用「为你精选」第一页。
    ///
    /// 加载失败时**不**用样例数据兜底 —— 首页是用户对 App 的第一印象，
    /// 拿编造的通知填满首屏比显示一个错误态糟糕得多。`FeedStore` 失败时会置
    /// `isOffline`，由 `HomeFeedSection` 展示错误态与重试。
    private var feedItems: [FeedItem] {
        feedStore.page(for: .forYou).items
    }
}

#Preview {
    HomeView()
        .environment(UserProfile())
        .environment(FeedStore())
}
