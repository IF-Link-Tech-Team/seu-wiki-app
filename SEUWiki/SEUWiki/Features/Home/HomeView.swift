import SwiftUI

struct HomeView: View {
    @Environment(UserProfile.self) private var profile
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

                    HomeFeedSection(items: Array(MockData.feedItems.filter(\.isSelected).prefix(3)))
                    HomeForumSection(posts: Array(MockData.forumPosts.prefix(3)))
                }
                .padding()
            }
            .groupedBackground()
            .navigationTitle("主页")
            .profileEntry(isPresented: $showsProfile)
            .appNavigationDestinations()
        }
    }
}

#Preview {
    HomeView()
        .environment(UserProfile())
}
