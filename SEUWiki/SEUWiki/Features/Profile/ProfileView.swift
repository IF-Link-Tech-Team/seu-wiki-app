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

/// 「我的画像」：学院 / 学段 / 年级 / 兴趣，登录与否均可编辑（对应 for-you 画像参数）。
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
            Text("画像用于「为你精选」的匹配，存在本机，未登录也可编辑。改了画像会立即重新匹配。")
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

/// 「我的收藏」：收藏的手册/经验长文。
///
/// 收藏对象从「论坛帖子 id」换成「长文 slug」：本 App 尚未接入论坛 API，
/// 收藏帖子存下来也永远点不开。现在收藏的是 `/api/site/docs/*` 的真实内容，
/// 在手册/经验详情页收藏，这里能真正打开。
private struct BookmarksSection: View {
    @Environment(UserProfile.self) private var profile
    @State private var store = ExperienceStore()

    var body: some View {
        Section {
            if profile.bookmarkedSlugs.isEmpty {
                Text("暂无收藏，在手册或经验详情页点右上角收藏后会出现在这里")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bookmarked, id: \.slug) { item in
                    NavigationLink(value: DocSearchHit(
                        slug: item.slug,
                        kind: item.kind == "experience" ? .experience : .survival,
                        title: item.title,
                        description: item.description,
                        occurredAt: item.occurredAt,
                        anchor: nil
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            if let description = item.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("我的收藏")
        }
        .task { await loadBookmarks() }
    }

    /// 收藏只存了 slug，标题要从索引里回填。手册和经验两个索引都拉一次，
    /// 命中哪个用哪个；都没命中（内容下线）就如实跳过而不是显示空白。
    @State private var bookmarked: [DocItem] = []

    private func loadBookmarks() async {
        guard !profile.bookmarkedSlugs.isEmpty else { return }
        await store.loadHandbook()
        await store.loadExperience()
        let all = (store.handbook?.parts.flatMap { $0.groups.flatMap(\.items) } ?? [])
            + (store.experience?.items ?? [])
        var seen = Set<String>()
        bookmarked = all
            .filter { profile.bookmarkedSlugs.contains($0.slug) && seen.insert($0.slug).inserted }
            .sorted { $0.title < $1.title }
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
                Text("登录服务由自部署 Logto（auth.iflink.tech）提供。\n资讯与手册内容来自 seu.wiki。")
            }

            Section("功能状态") {
                LabeledContent("资讯聚合", value: "已上线")
                LabeledContent("为你精选", value: "已上线")
                LabeledContent("东大生存手册", value: "已上线")
                LabeledContent("经验长文", value: "已上线")
                LabeledContent("提醒推送", value: "已上线")
                LabeledContent("社区（发帖/点赞/评论）", value: "开发中")
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
