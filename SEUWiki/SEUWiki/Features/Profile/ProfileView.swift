import SwiftUI

/// 个人页面与设置：以 sheet 从各 Tab 右上角弹出。
/// 登录走 IF.Link 生态自部署 Logto（auth.iflink.tech），OIDC 授权码 + PKCE。
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserProfile.self) private var profile

    /// 用 `AuthStore.shared`（不是每次新建）：feed 层发请求时要经 `accessToken()` 取凭证，
    /// 拿的必须是个人页这一份，否则登录态会被分裂成两份。
    @State private var auth = AuthStore.shared
    @State private var showsLogin = false

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

                if auth.isLoggedIn {
                    RemindersSection()
                    BookmarksSection()
                    FollowedTopicsSection()
                    SettingsSection()

                    Section {
                        Button(role: .destructive) {
                            withAnimation(.smooth) { auth.logout() }
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
            .appNavigationDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
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
                    Text("登录 IF.Link 账号，同步收藏、提醒与关注的话题")
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

/// 「我的画像」：学院 / 学段 / 年级 / 兴趣，登录与否均可编辑（对应 for-you 画像参数）。
private struct PersonaSection: View {
    @Environment(UserProfile.self) private var profile

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
            Text("画像用于主页「为你推荐」匹配，未登录也可编辑。")
        }
    }
}

/// 「我的提醒」：profile.reminders 列表，可左滑删除。
private struct RemindersSection: View {
    @Environment(UserProfile.self) private var profile

    var body: some View {
        Section("我的提醒") {
            if profile.reminders.isEmpty {
                Text("暂无提醒，可在资讯详情页设定")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profile.reminders) { reminder in
                    HStack(spacing: 12) {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title)
                                .font(.subheadline.weight(.medium))
                            Text("\(reminder.dueDate, style: .date) 截止 · 提前 \(reminder.advanceDays) 天提醒")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(reminder.daysRemaining > 0 ? "剩 \(reminder.daysRemaining) 天" : "今天")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(reminder.daysRemaining <= 2 ? .red : .secondary)
                    }
                }
                .onDelete { offsets in
                    profile.reminders.remove(atOffsets: offsets)
                }
            }
        }
    }
}

/// 「我的收藏」：bookmarkedPostIDs 对应的经验帖，跳转帖子详情。
private struct BookmarksSection: View {
    @Environment(UserProfile.self) private var profile

    private var bookmarkedPosts: [ForumPost] {
        MockData.forumPosts.filter { profile.bookmarkedPostIDs.contains($0.id) }
    }

    var body: some View {
        Section("我的收藏") {
            if bookmarkedPosts.isEmpty {
                Text("暂无收藏，在经验帖详情页收藏后显示在这里")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bookmarkedPosts) { post in
                    NavigationLink(value: post) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(post.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            Text("\(post.authorName) · \(post.createdAt, style: .relative)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

/// 「关注的话题」：followedTopicIDs 对应的话题。
private struct FollowedTopicsSection: View {
    @Environment(UserProfile.self) private var profile

    private var followedTopics: [ForumTopic] {
        MockData.topics.filter { profile.followedTopicIDs.contains($0.id) }
    }

    var body: some View {
        Section("关注的话题") {
            if followedTopics.isEmpty {
                Text("暂无关注，去论坛话题页看看")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(followedTopics) { topic in
                    Label {
                        Text(topic.name)
                    } icon: {
                        Image(systemName: topic.systemImage)
                            .foregroundStyle(.orange)
                    }
                    .badge(topic.postCount)
                }
            }
        }
    }
}

/// 「设置」：通知开关、外观偏好、关于。
private struct SettingsSection: View {
    @AppStorage("settings.notificationsEnabled") private var notificationsEnabled = true
    /// 外观偏好仅存本地；后续在 App 根视图读取并应用 `preferredColorScheme`。
    @AppStorage("settings.appearance") private var appearance: AppAppearance = .system

    var body: some View {
        Section("设置") {
            Toggle("接收通知", systemImage: "bell.badge", isOn: $notificationsEnabled)
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

/// 外观偏好（本地存储，后续由 App 根视图应用到 preferredColorScheme）。
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
                Text("登录服务由自部署 Logto（auth.iflink.tech）提供。")
            }
        }
        .navigationTitle("关于")
    }
}

#Preview {
    ProfileView()
        .environment(UserProfile())
}
