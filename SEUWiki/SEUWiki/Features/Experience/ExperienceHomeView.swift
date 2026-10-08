import SwiftUI

/// 「经验」主页：热门 / 关注 / 东大生存手册三个子页，
/// ConsoleBar 与可侧滑的 page TabView 双向绑定。
///
/// 数据全部来自论坛后端 `https://forum.seu.wiki`（seu-wiki-forum，真实内容）。
/// 「热门」是论坛热榜（`GET /api/posts?sort=hot`，置顶帖优先）；
/// 「关注」是关注板块/作者后的信息流（阶段 2 接口，未部署时显式标注）；
/// 「东大生存手册」是编辑团队从讨论沉淀的手册文章（`/api/handbook/*`）。
/// 早期版本的「热门」是 `/api/site/docs/experience` 的经验长文、「话题」是其分面筛选，
/// 两者已随经验长文信源一并移除。
struct ExperienceHomeView: View {
    @Environment(ForumStore.self) private var store
    @State private var auth = AuthStore.shared
    @State private var showsProfile = false
    @State private var showsComposer = false
    @State private var tab: ForumFeedTab

    /// `initialTab` 与 `initiallyShowComposer` 只被 DEBUG 启动参数使用
    /// （`-uiconsole following` / `-uicomposer`，见 `RootTabView.launchExperienceConsole`）：
    /// 本机无合成点击能力，console 切换与发帖 sheet 不这样就截不到图验收。
    init(initialTab: ForumFeedTab = .hot, initiallyShowComposer: Bool = false) {
        _tab = State(initialValue: initialTab)
        _showsComposer = State(initialValue: initiallyShowComposer)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $tab) {
                ForumHotFeedView()
                    .tag(ForumFeedTab.hot)
                ForumFollowingFeedView(onBrowseHot: { select(.hot) })
                    .tag(ForumFeedTab.following)
                HandbookHomeView()
                    .tag(ForumFeedTab.handbook)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // 固定在导航栏下方，不随内容滚走。
            .safeAreaBar(edge: .top) {
                ConsoleBar(items: ForumFeedTab.allCases, selection: $tab) { $0.name }
            }
            .groupedBackground()
            .navigationTitle("经验")
            .toolbar {
                // 通知入口：纯登录态功能，未登录不渲染（门禁只看 isLoggedIn，见 AGENTS.md）。
                if auth.isLoggedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            ForumNotificationsView()
                        } label: {
                            Image(systemName: "bell")
                                .overlay(alignment: .topTrailing) {
                                    if store.unreadNotificationCount > 0 {
                                        Text(store.unreadNotificationCount > 99 ? "99+" : "\(store.unreadNotificationCount)")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.accentColor, in: .capsule)
                                            .offset(x: 10, y: -6)
                                    }
                                }
                                .accessibilityLabel("通知")
                        }
                    }
                }
                // 发帖入口（登录后在编辑器内完成鉴权检查）。
                ToolbarItem(placement: .topBarTrailing) {
                    Button("发帖", systemImage: "square.and.pencil") {
                        showsComposer = true
                    }
                }
            }
            // 登录态变化（含冷启动已登录）→ 刷一次未读角标；失败静默（store 内部吞掉）。
            .task(id: auth.isLoggedIn) {
                guard auth.isLoggedIn else { return }
                await store.refreshUnreadNotificationCount()
            }
            .profileEntry(isPresented: $showsProfile)
            .appNavigationDestinations()
            .sheet(isPresented: $showsComposer) {
                ForumComposerView {
                    store.invalidateFeeds()
                }
            }
        }
    }

    private func select(_ tab: ForumFeedTab) {
        withAnimation(.smooth(duration: 0.35)) {
            self.tab = tab
        }
    }
}

#Preview {
    ExperienceHomeView()
        .environment(UserProfile())
        .environment(ForumStore())
}
