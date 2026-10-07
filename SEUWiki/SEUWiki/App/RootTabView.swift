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
    /// 通知点击的下一步去向。传进来而不是内部取单例，是为了让整条链路可注入、可预览。
    let notifications: NotificationCenterDelegate
    @State private var selection: AppTab
    /// 跨 tab 跳转的待办目标。各 tab 根部用 `.onChange` 消费它并清空。
    @State private var pendingToolsRoute: ToolRoute?
    /// 点提醒通知要打开的资讯 id。由资讯 tab 消费。
    @State private var pendingFeedItemID: String?
    @State private var showsProfile = false
    @State private var showsReminders = false

    /// Debug 专用：`-uitab search` 之类的启动参数可以把 App 直接开在指定 tab。
    ///
    /// 存在的理由是**验收**：模拟器是无头跑的，合成点击不可用，没有这个开关就没法
    /// 截到非首页的界面做逐屏核对（深浅色、无障碍、布局都靠它）。Release 构建里
    /// 整个分支不存在。
    init(
        initialTab: AppTab = .home,
        deepLinkDoc: DocSearchHit? = nil,
        notifications: NotificationCenterDelegate = .shared
    ) {
        _selection = State(initialValue: initialTab)
        _deepLinkDoc = State(initialValue: deepLinkDoc)
        self.notifications = notifications
    }

    @State private var deepLinkDoc: DocSearchHit?

    /// Debug 专用：解析 `-uidoc <slug>`。
    static var launchDoc: DocSearchHit? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-uidoc"), index + 1 < args.count else { return nil }
        let slug = args[index + 1]
        return DocSearchHit(
            slug: slug,
            kind: slug.hasPrefix("experience/") ? .experience : .survival,
            title: slug,
            description: nil,
            occurredAt: nil,
            anchor: nil
        )
        #else
        return nil
        #endif
    }

    static var launchTab: AppTab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-uitab"), index + 1 < args.count else { return .home }
        switch args[index + 1] {
        case "feed": return .feed
        case "experience": return .experience
        case "tools": return .tools
        case "search": return .search
        default: return .home
        }
        #else
        return .home
        #endif
    }

    /// Debug 专用：`-uiconsole following|handbook` 把经验 tab 直接开在指定 console。
    static var launchExperienceConsole: ForumFeedTab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-uiconsole"), index + 1 < args.count else { return .hot }
        return ForumFeedTab(rawValue: args[index + 1]) ?? .hot
        #else
        return .hot
        #endif
    }

    /// Debug 专用：`-uicomposer` 冷启动直接弹发帖编辑器（未登录时是登录引导）。
    static var launchShowsComposer: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uicomposer")
        #else
        false
        #endif
    }

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
                FeedHomeView(pendingItemID: $pendingFeedItemID)
            }
            Tab("经验", systemImage: "bubble.left.and.text.bubble.right", value: .experience) {
                ExperienceHomeView(
                    initialTab: RootTabView.launchExperienceConsole,
                    initiallyShowComposer: RootTabView.launchShowsComposer
                )
            }
            Tab("工具", systemImage: "square.grid.2x2", value: .tools) {
                ToolsHomeView(route: $pendingToolsRoute)
            }
            Tab(value: .search, role: .search) {
                SearchHomeView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // 点提醒通知 → 落到对应那条资讯。
        //
        // `initial: true` 是必需的：冷启动点通知时 delegate 收到点击早于本视图
        // 第一次求值，只挂 `onChange` 会永远等不到「变化」而丢掉这次点击。
        //
        // 消费后立刻把来源清空，否则视图重建会重复触发 `initial:`
        // 之外的路径、把用户反复拽回同一个详情页。
        .onChange(of: notifications.pendingFeedItemID, initial: true) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            selection = .feed
            pendingFeedItemID = newValue
            notifications.consumePendingFeedItemID()
        }
        // Debug 深链：`-uidoc <slug>` 直接打开某个手册/经验条目详情。
        // DocDetailView 是全新实现（HTML 按标题切分、目录跳转、锚点定位），
        // 无头模拟器点不进去，必须有个直达入口才能验收。
        .overlay {
            if let deepLinkDoc {
                NavigationStack {
                    DocDetailView(slug: deepLinkDoc.slug, kind: deepLinkDoc.kind,
                                  highlightAnchor: deepLinkDoc.anchor?.id)
                }
                .background(.regularMaterial)
            }
        }
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
        .environment(ForumStore())
}
