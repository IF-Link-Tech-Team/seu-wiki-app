import SwiftUI

/// 5 个一级页面。
///
/// 搜索是**独立的 tab**（`Tab(role: .search)`），不是某个 tab 上的搜索框 ——
/// 这样用户在任何页面都能一键进入搜索，符合系统对独立搜索 tab 的预期。
enum AppTab: Hashable {
    case home, feed, experience, tools, search
}

/// 根 TabView。
///
/// 绑定了 `selection` 才能支持**跨 tab 跳转**：主页的「下一节课」卡要跳到工具页的
/// 课表、「提醒」卡要跳到个人页。早期版本没有 selection，两张卡也点不动。
struct RootTabView: View {
    @State private var selection: AppTab = .home
    /// 跨 tab 跳转的待办目标。各 tab 根部用 `.onChange` 消费它并清空。
    @State private var pendingToolsRoute: ToolRoute?
    @State private var showsProfile = false
    @State private var showsReminders = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("主页", systemImage: "house", value: .home) {
                HomeView(
                    onShowTimetable: {
                        selection = .tools
                        pendingToolsRoute = .timetable
                    },
                    onShowReminders: {
                        selection = .home
                        showsReminders = true
                    }
                )
            }
            Tab("资讯", systemImage: "newspaper", value: .feed) {
                FeedHomeView()
            }
            Tab("经验", systemImage: "bubble.left.and.text.bubble.right", value: .experience) {
                ExperienceHomeView()
            }
            Tab("工具", systemImage: "square.grid.2x2", value: .tools) {
                ToolsHomeView(route: $pendingToolsRoute)
            }
            Tab(value: .search, role: .search) {
                SearchHomeView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $showsReminders) {
            // 继承 App 根上注入的 `UserProfile`（sheet 内容会继承环境）。
            MyRemindersView()
        }
    }
}

/// 「我的提醒」独立页：主页提醒卡的落点。
///
/// 单独抽出来是因为提醒是本地数据、不该藏在个人页的登录门后面（I-9）：
/// 用户能设提醒，就必须找得到、看得到、删得掉。
struct MyRemindersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserProfile.self) private var profile

    var body: some View {
        NavigationStack {
            Group {
                if profile.reminders.isEmpty {
                    ContentUnavailableView {
                        Label("暂无提醒", systemImage: "bell")
                    } description: {
                        Text("在资讯详情页点「设定提醒」，到期前会收到系统通知。")
                    }
                } else {
                    List {
                        ForEach(profile.reminders) { reminder in
                            reminderRow(reminder)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                ReminderScheduler.shared.cancel(id: profile.reminders[index].notificationID)
                            }
                            profile.reminders.remove(atOffsets: offsets)
                        }
                    }
                }
            }
            .navigationTitle("我的提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func reminderRow(_ reminder: CampusReminder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.isExpired ? "bell.slash" : "bell.fill")
                .foregroundStyle(reminder.isExpired ? Color.secondary : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.subheadline.weight(.medium))
                Text("\(TimeFormat.deadline(reminder.dueDate)) 截止 · 提前 \(reminder.advanceDays) 天提醒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !reminder.note.isEmpty {
                    Text(reminder.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(badge(for: reminder))
                .font(.caption.weight(.semibold))
                .foregroundStyle(reminder.isExpired ? Color.secondary : (reminder.daysRemaining <= 2 ? Color.red : Color.secondary))
        }
    }

    private func badge(for reminder: CampusReminder) -> String {
        if reminder.isExpired { return "已过期" }
        if reminder.daysRemaining == 0 { return "今天" }
        if reminder.daysRemaining == 1 { return "明天" }
        return "剩 \(reminder.daysRemaining) 天"
    }
}

#Preview {
    RootTabView()
        .environment(UserProfile())
        .environment(FeedStore())
}
