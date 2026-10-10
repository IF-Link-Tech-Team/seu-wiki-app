import SwiftUI

/// Debug 专用：`-uipicker college|degree|grade` 冷启动直接进对应的选择器。
///
/// 本机没有合成点击能力（`Simulator.app` 不在 Xcode 包内、无 idb），个人页又是
/// sheet 而不是 tab，没法像 `-uitab` 那样直达。学院选择器这次加了搜索框，
/// 不截图就没法验收它到底出没出来。
enum PersonaPickerField: String, Hashable, Identifiable {
    case college, degree, grade

    var id: String { rawValue }

    static func fromLaunchArguments() -> PersonaPickerField? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-uipicker"), index + 1 < args.count else { return nil }
        return PersonaPickerField(rawValue: args[index + 1])
        #else
        return nil
        #endif
    }
}

/// 个人页面与设置：以 sheet 从各 Tab 右上角弹出。
/// 登录走 IF.Link 生态自部署 Logto（auth.iflink.tech），OIDC 授权码 + PKCE。
///
/// **本地功能不再藏在登录门后**（I-9）：提醒、收藏、画像、设置都是本地数据，
/// 未登录也能设提醒 —— 早期版本把它们放在 `if auth.isLoggedIn` 里，用户能设却看不到、
/// 更删不掉。需要登录的只有账号区本身和「退出登录」。
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserProfile.self) private var profile

    /// 用 `AuthStore.shared`（不是每次新建）：feed 层发请求时要经 `accessToken()` 取凭证，
    /// 拿的必须是个人页这一份，否则登录态会被分裂成两份。
    @State private var auth = AuthStore.shared
    @State private var showsLogin = false
    @State private var debugPicker = PersonaPickerField.fromLaunchArguments()

    var body: some View {
        NavigationStack {
            Form {
                if auth.isLoggedIn {
                    AccountHeaderSection(auth: auth)
                } else {
                    LoginPromptSection(showsLogin: $showsLogin)
                }

                if let error = auth.lastError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    } header: {
                        Text("登录失败")
                    }
                }

                PersonaSection()
                RemindersSection()
                BookmarksSection()
                SettingsSection()

                if auth.isLoggedIn {
                    Section {
                        Button(role: .destructive) {
                            confirmsLogout = true
                        } label: {
                            Text("退出登录")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("我的")
            .trackScreen("/profile", title: "个人中心")
            .navigationDestination(isPresented: $showsLogin) {
                // 显式传 auth，不靠 environment 传播（原因见 LoginView 的注释）。
                LoginView(auth: auth)
            }
            .navigationDestination(item: $debugPicker) { field in
                DebugPickerDestination(field: field)
            }
            .appNavigationDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            // 危险操作必须确认：登出会吊销 refresh token，误触的代价不小。
            .confirmationDialog("确定退出登录？", isPresented: $confirmsLogout, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    withAnimation(.smooth) { auth.logout() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会清除本机登录状态。收藏、提醒与画像都存在本机，不会丢失。")
            }
        }
    }

    @State private var confirmsLogout = false
}

/// 未登录态顶部的登录引导卡。
private struct LoginPromptSection: View {
    @Binding var showsLogin: Bool

    var body: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("未登录")
                        .font(.headline)
                    Text("登录 IF.Link 账号后，社区发帖、关注与云端同步将可用。提醒、收藏与画像现在就能用。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            Button {
                showsLogin = true
            } label: {
                Label("登录 IF.Link 账号", systemImage: "link")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .listRowBackground(Color.clear)
        }
    }
}

/// 已登录态的头部资料行。
private struct AccountHeaderSection: View {
    let auth: AuthStore

    var body: some View {
        Section {
            HStack(spacing: 14) {
                Text(auth.initials)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor.gradient, in: .circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.displayName)
                        .font(.headline)
                    Text(auth.email)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            LabeledContent("IF.Link ID", value: auth.ifLinkID)
                .font(.footnote)
        }
    }
}

/// `-uipicker` 的落点。复用真实的 [ProfileSinglePicker]，不另写一份，
/// 否则截图验的就不是线上那段代码了。
private struct DebugPickerDestination: View {
    let field: PersonaPickerField
    @Environment(UserProfile.self) private var profile

    var body: some View {
        @Bindable var profile = profile
        switch field {
        case .college:
            ProfileSinglePicker(title: "学院", options: PersonaOptions.colleges, selection: $profile.college)
        case .degree:
            ProfileSinglePicker(title: "学段", options: PersonaOptions.degrees, selection: $profile.degree)
        case .grade:
            ProfileSinglePicker(title: "年级", options: PersonaOptions.grades, selection: $profile.grade)
        }
    }
}

/// 「我的画像」：学院 / 学段 / 年级 / 兴趣，登录与否均可编辑。
/// （网页端 for-you 个性化已下线，资讯流暂不使用画像；画像数据保留在本机。）
private struct PersonaSection: View {    @Environment(UserProfile.self) private var profile

    var body: some View {
        @Bindable var profile = profile

        Section {
            NavigationLink {
                ProfileSinglePicker(title: "学院", options: PersonaOptions.colleges, selection: $profile.college)
            } label: {
                LabeledContent("学院", value: profile.college)
            }
            NavigationLink {
                ProfileSinglePicker(title: "学段", options: PersonaOptions.degrees, selection: $profile.degree)
            } label: {
                LabeledContent("学段", value: profile.degree)
            }
            NavigationLink {
                ProfileSinglePicker(title: "年级", options: PersonaOptions.grades, selection: $profile.grade)
            } label: {
                LabeledContent("年级", value: profile.grade)
            }
            NavigationLink {
                ProfileMultiPicker(title: "兴趣", options: PersonaOptions.interests, selection: $profile.interests)
            } label: {
                LabeledContent("兴趣", value: profile.interests.joined(separator: "、"))
            }
        } header: {
            Text("我的画像")
        } footer: {
            Text("画像存在本机，未登录也可编辑。资讯流暂不使用画像匹配。")
        }
    }
}

/// 「我的提醒」：profile.reminders 列表，可左滑删除。
private struct RemindersSection: View {
    @Environment(UserProfile.self) private var profile

    var body: some View {
        Section {
            if profile.reminders.isEmpty {
                Text("暂无提醒，可在资讯详情页设定")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profile.reminders) { reminder in
                    ReminderRow(reminder: reminder)
                }
                .onDelete { offsets in
                    // 删除提醒必须同步取消已排程的系统通知，否则用户删了还会被弹醒。
                    for index in offsets {
                        ReminderScheduler.shared.cancel(id: profile.reminders[index].notificationID)
                    }
                    profile.reminders.remove(atOffsets: offsets)
                }
            }
        } header: {
            Text("我的提醒")
        } footer: {
            if !profile.reminders.isEmpty {
                Text("提醒会通过系统通知在截止前发出。删除提醒会同时取消对应的通知。")
            }
        }
    }
}

private struct ReminderRow: View {
    let reminder: CampusReminder

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.isExpired ? "bell.slash" : "bell.fill")
                .foregroundStyle(reminder.isExpired ? Color.secondary : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.subheadline.weight(.medium))
                Text("\(TimeFormat.deadline(reminder.dueDate)) 截止 · 提前 \(reminder.advanceDays) 天提醒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // 过期的不能再显示「今天」—— 那是明显错误的主张。
            Text(badge)
                .font(.caption.weight(.semibold))
                .foregroundStyle(reminder.isExpired ? Color.secondary : (reminder.daysRemaining <= 2 ? Color.red : Color.secondary))
        }
    }

    private var badge: String {
        if reminder.isExpired { return "已过期" }
        if reminder.daysRemaining == 0 { return "今天" }
        if reminder.daysRemaining == 1 { return "明天" }
        return "剩 \(reminder.daysRemaining) 天"
    }
}

/// 「我的收藏」：两个来源。
/// - **帖子收藏**：论坛服务端 `/api/bookmarks`（需登录，401 显示登录引导而不是错误）；
/// - **长文收藏（本机）**：`profile.bookmarkedSlugs` 里的 `/api/site/docs/*` slug，
///   在长文详情页收藏，仍在本地保存。
private struct BookmarksSection: View {
    @Environment(UserProfile.self) private var profile
    @State private var auth = AuthStore.shared

    var body: some View {
        ForumBookmarksSection(auth: auth)
        LocalDocBookmarksSection()
    }
}

/// 帖子收藏（服务端）。每次回到个人页拉第一页；失败显示重试行，不静默。
private struct ForumBookmarksSection: View {
    let auth: AuthStore

    @State private var client = ForumAPIClient()
    @State private var items: [ForumBookmarkItem]?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if !auth.isLoggedIn {
                Text("登录后可查看收藏的帖子")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let errorMessage {
                HStack {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("重试") { Task { await load() } }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            } else if let items {
                if items.isEmpty {
                    Text("暂无帖子收藏，在帖子详情页点收藏后会出现在这里")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        NavigationLink {
                            ForumPostDetailView(postID: item.postID)
                        } label: {
                            ForumBookmarkRow(item: item)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        } header: {
            Text("帖子收藏")
        }
        .task(id: auth.isLoggedIn) {
            guard auth.isLoggedIn else { return }
            await load()
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            items = try await client.bookmarks().items
        } catch let error as ForumAPIClient.ForumAPIError {
            // 401 在 AuthStore 换 token 失败时才会发生：如实提示重新登录，不显示成接口故障。
            if case .unauthorized = error {
                errorMessage = "登录态已失效，请退出后重新登录"
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ForumBookmarkRow: View {
    let item: ForumBookmarkItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title?.isEmpty == false ? item.title! : item.excerpt)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 6) {
                if let name = item.author?.name, !name.isEmpty {
                    Text(name)
                }
                Text("\(forumCompactCount(item.likesCount)) 赞")
                Text("\(forumCompactCount(item.commentsCount)) 评论")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// 长文收藏（本机 slug）。收藏时只存了 slug，行标题用 slug 末段兜底
/// （索引接口已随经验长文信源移除，不再做标题回填）。
private struct LocalDocBookmarksSection: View {
    @Environment(UserProfile.self) private var profile

    var body: some View {
        Section {
            if profile.bookmarkedSlugs.isEmpty {
                Text("暂无长文收藏")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profile.bookmarkedSlugs.sorted(), id: \.self) { slug in
                    NavigationLink(value: DocSearchHit(
                        slug: slug,
                        kind: .survival,
                        title: Self.displayTitle(for: slug),
                        description: nil,
                        occurredAt: nil,
                        anchor: nil
                    )) {
                        Text(Self.displayTitle(for: slug))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                    }
                }
            }
        } header: {
            Text("长文收藏（本机）")
        }
    }

    static func displayTitle(for slug: String) -> String {
        let last = slug.split(separator: "/").last.map(String.init) ?? slug
        return last.isEmpty ? slug : last
    }
}

/// 「设置」：通知开关、外观偏好、关于。
private struct SettingsSection: View {
    @AppStorage("settings.notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("settings.appearance") private var appearance: AppAppearance = .system

    var body: some View {
        Section("设置") {
            Toggle("接收通知", systemImage: "bell.badge", isOn: $notificationsEnabled)
                .onChange(of: notificationsEnabled) { _, enabled in
                    // 开关要真的生效：关掉时把已排程的通知全部撤掉。
                    ReminderScheduler.shared.setGloballyEnabled(enabled)
                }
            Picker(selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.name).tag(option)
                }
            } label: {
                Label("外观", systemImage: "circle.lefthalf.filled")
            }
            NavigationLink {
                AboutView()
            } label: {
                Label("关于 SEU.wiki", systemImage: "info.circle")
            }
        }
    }
}

/// 外观偏好。由 `SEUWikiApp` 读取并应用到 `preferredColorScheme` —— 早期版本
/// 这里只存不使用，开关拨了没有任何反应。
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 设置 → 关于页。
private struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "graduationcap.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor)
                    Text("SEU.wiki")
                        .font(.title3.weight(.bold))
                    Text("东南大学校园资讯与经验社区")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("版本", value: "0.1.0")
                LabeledContent("构建", value: "本地开发版")
                LabeledContent("生态", value: "IF.Link")
            } footer: {
                Text("登录服务由自部署 Logto（auth.iflink.tech）提供。\n资讯内容来自 seu.wiki；社区与东大生存手册内容来自 forum.seu.wiki。")
            }

            Section("功能状态") {
                LabeledContent("资讯聚合", value: "已上线")
                LabeledContent("社区（发帖/点赞/评论/收藏）", value: "已上线")
                LabeledContent("东大生存手册", value: "接口部署中")
                LabeledContent("提醒推送", value: "已上线")
                LabeledContent("课表与绩点", value: "本机记录")
            }
        }
        .navigationTitle("关于")
    }
}

#Preview {
    ProfileView()
        .environment(UserProfile())
}
