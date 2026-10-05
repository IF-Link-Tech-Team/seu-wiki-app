import SwiftUI

struct HomeView: View {
    @Environment(UserProfile.self) private var profile
    @Environment(FeedStore.self) private var feedStore
    @State private var experienceStore = ExperienceStore()
    @State private var showsProfile = false

    /// 跨 tab 跳转：由 `RootTabView` 注入。
    var onShowTimetable: () -> Void = {}
    var onShowReminders: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 提醒卡 / 课程卡并排；大字号下自动改竖排，避免 AX 字号被截断。
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
            .refreshable {
                await feedStore.refresh(scope: .forYou, profile: profile)
            }
            .task(id: profile.profileFingerprint) {
                // 画像一变就重新拉「为你精选」：后端 cursor 与画像绑定，
                // 沿用旧结果既不匹配也会让翻页一直失败。
                await feedStore.refresh(scope: .forYou, profile: profile)
            }
        }
        .environment(experienceStore)
    }

    private var reminderCard: some View {
        ReminderCard(reminder: profile.nextPendingReminder, onTap: onShowReminders)
    }

    private var nextCourseCard: some View {
        NextCourseCard(course: profile.nextCourse, onTap: onShowTimetable)
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
