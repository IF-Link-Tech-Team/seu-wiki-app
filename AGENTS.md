# AGENTS.md — SEU.wiki iOS

SwiftUI 原生客户端。本文件记录**必须遵守**的工程规则，改动前先读。

## 账号体系（登录态单一事实源）

与 Android 端同一套约定（见 `seu-wiki-android/AGENTS.md`，2026-10 账号重构）。
历史教训：Android 曾因 UI 拿服务端投影（`viewer`）当登录门禁导致发帖死循环，
两端共用以下铁律。

1. **登录态只有一份**：`AuthStore.shared.session`。判断「是否已登录」一律用
   `AuthStore.isLoggedIn`，功能模块不得自建第二份登录状态。
2. **门禁只看 `isLoggedIn`**：发帖/点赞/收藏/评论等写操作的入口判断只读
   `isLoggedIn`（现状：`guard auth.isLoggedIn else { showsLoginGuide = true }`）。
   **禁止**拿服务端投影当门禁——它可能没拉过、可能是上个账号的残留。
3. **401 是校正信号，不是登录指令**：请求 401 → 对应 state 置
   `requiresLogin`/`needsLogin`，UI 显示登录引导；绝不因一次 401 直接跳登录
   （token 续期由 `AuthStore.accessToken()` 内部完成）。
4. **token 只有一个来源**：所有需要鉴权的客户端通过
   `tokenProvider = { await AuthStore.shared.accessToken() }` 注入。禁止在功能
   模块里另起 OIDC 流程或缓存自己的 token。
5. **功能 store 必须实现登录态钩子**：`onSignedOut()` 清空本模块**全部**用户态
   数据（关注关系、关注流、缓存里的「上个账号视角」字段），防换账号串数据。
   统一在 `SEUWikiApp` 的 `.onChange(of: auth.isLoggedIn)` 里注册调用，禁止分散
   到各页面自己监听登出。与用户数据无关的 store 不实现钩子。
6. **新功能接入账号的三步**：① 客户端注入 tokenProvider；② 需要用户态的 store
   实现 `onSignedOut` 并在 `SEUWikiApp` 注册；③ UI 门禁只看 `isLoggedIn`。

## 构建与自检

- 打开 `SEUWiki/SEUWiki.xcodeproj`；模拟器构建：
  `xcodebuild -project SEUWiki/SEUWiki.xcodeproj -scheme SEUWiki -destination 'platform=iOS Simulator,name=iPhone 16' build`
- `SelfCheck.runAll()`（`Services/SelfCheck.swift`）在 DEBUG 启动时自动跑，
  与 Android `SelfCheckTest` **逐条对齐**；新增关键纯逻辑必须两端各补一条断言，
  失败会弹断言——改坏了另一端也该知道。
- 本机有 iOS 模拟器（device hub），可实机回归。

## 代码结构速览

- `Features/Profile/AuthStore.swift` — Logto 会话、token 续期、登录/登出。
- `Services/ForumService.swift` — 论坛 HTTP 客户端 + `ForumStore`（含 `onSignedOut`）。
- `Services/AnalyticsService.swift` — Umami 统计（`umami.iflink.tech`）：payload 纯函数 +
  `.trackScreen` 埋点，DEBUG 不上报，契约断言在 SelfCheck（与 Android 同语义）。
- `App/SEUWikiApp.swift` — store 装配 + 登录态统一接线（`.onChange`）。
- `Features/Experience/` — 论坛各页面（信息流/详情/发帖/手册）。
