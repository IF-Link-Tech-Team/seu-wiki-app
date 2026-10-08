import SwiftUI

/// 通知列表（`GET /api/notifications`，需登录）。
///
/// 未读高亮的寿命只有「进入这一屏」一次：进入时先快照未读 id，再调
/// `store.markAllNotificationsRead()` 把本地 readAt 全部改写 —— 所以高亮
/// 判断看的是快照，不是条目当前的 readAt。下次再进，那批通知已是旧闻。
/// 与 Android `ForumNotificationsScreen` 同语义。
struct ForumNotificationsView: View {
    @Environment(ForumStore.self) private var store
    @State private var auth = AuthStore.shared
    /// 进入本页时的未读快照：nil = 还没拍过（首屏未加载完）。
    @State private var unreadAtEntry: Set<String>?

    private var page: ForumStore.NotificationPageState { store.notifications }

    var body: some View {
        ScrollView {
            if !auth.isLoggedIn || page.requiresLogin {
                ForumLoginGuide(message: "登录 IF.Link 账号后，帖子收到评论、回复或点赞时会提醒你。")
                    .padding(.top, 60)
            } else if page.isLoading && page.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            } else if let error = page.errorMessage, page.items.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await store.refreshNotifications() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 60)
            } else if page.items.isEmpty {
                ContentUnavailableView {
                    Label("还没有通知", systemImage: "bell")
                } description: {
                    Text("帖子收到评论、回复或点赞时会提醒你。")
                }
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(page.items) { notification in
                        row(for: notification)
                            .onAppear {
                                if notification.id == page.items.last?.id {
                                    Task { await store.loadMoreNotifications() }
                                }
                            }
                    }
                    if page.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
        }
        .groupedBackground()
        .navigationTitle("通知")
        .trackScreen("/forum/notifications", title: "论坛通知")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refreshNotifications() }
        .task(id: auth.isLoggedIn) {
            guard auth.isLoggedIn else { return }
            await store.refreshNotifications()
            if unreadAtEntry == nil {
                unreadAtEntry = Set(store.notifications.items.filter(\.isUnread).map(\.id))
                await store.markAllNotificationsRead()
            }
        }
    }

    /// 一条通知。post 为 nil（帖子已删/不可见）时不可点击，摘要让位给「相关内容已删除」。
    @ViewBuilder
    private func row(for notification: ForumNotification) -> some View {
        let highlight = unreadAtEntry?.contains(notification.id) ?? false
        if let post = notification.post {
            NavigationLink {
                ForumPostDetailView(postID: post.id)
            } label: {
                NotificationRow(notification: notification, highlightUnread: highlight)
            }
            .buttonStyle(.plain)
        } else {
            NotificationRow(notification: notification, highlightUnread: highlight)
        }
    }
}

private struct NotificationRow: View {
    let notification: ForumNotification
    let highlightUnread: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForumAvatar(name: notification.actor?.name ?? "东大同学", size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(notification.actor?.name ?? "东大同学")
                        .foregroundStyle(.primary)
                    Text(notification.actionText)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .lineLimit(1)

                Text(notification.post.flatMap { post in
                    if let title = post.title, !title.isEmpty { return title }
                    return post.excerpt
                } ?? "相关内容已删除")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let createdAt = notification.createdAt {
                    RelativeTimeText(date: createdAt)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 4)
            if highlightUnread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

#Preview {
    NavigationStack {
        ForumNotificationsView()
            .environment(ForumStore())
    }
}
