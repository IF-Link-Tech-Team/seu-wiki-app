import Foundation

/// Logto OIDC 单点配置：所有端点、客户端标识集中在此，改环境只动这一处。
/// 服务端契约见 Reference/iflab-forum/docs/auth.md §2「Bearer access tokens (native app)」。
enum AuthConfig {
    /// Logto issuer（discovery 可用；端点路径固定如下，不依赖运行时发现）。
    static let issuer = URL(string: "https://auth.iflink.tech/oidc")!

    /// Logto 控制台注册的 **Native** 应用 ID（public client，无 secret）。
    /// 对应控制台应用「SEU Wiki Android」（2026-10-05 注册，Native App 类型）。
    /// 与 Android 端共用同一个应用：两端都是 native 客户端，回调 scheme 同为
    /// `tech.iflink.seuwiki`，不必再注册一个 iOS 专属应用。
    static let clientID = "yb6csafyv7tviokwbbu2w"

    /// 回调 URL。scheme 已在 Info.plist 的 CFBundleURLTypes 注册。
    static let redirectURI = "tech.iflink.seuwiki://callback"
    static let callbackScheme = "tech.iflink.seuwiki"

    /// 请求的 scope。
    ///
    /// - `openid` / `profile` / `email`：UserInfo 里拿到 sub、昵称、邮箱，这些**已经在用**。
    /// - `offline_access`：换 refresh token。**必须同时带 `prompt=consent`**，否则 Logto
    ///   按 OIDC Core §6 忽略它、不签发 refresh token，详见 `AuthStore.offlineAccessGranted`。
    /// - `roles`：**目前只是先要着，代码里一处都没用**。Logto 的 UserInfo 确实会返回
    ///   （实测 `["community_super_admin"]`），但 `UserInfo` 结构体没有这个字段、`Session`
    ///   也不存，全工程没有任何按角色分支的逻辑 —— 早期那句「否则社区角色映射静默降级」
    ///   是在描述一个不存在的功能，已删除。
    ///
    /// 保留在 scope 里是因为它不影响 token 形态、也不带来副作用，等到真要做社区/论坛的
    /// 角色化功能时就不用重新走一遍授权。**但那时要动的不只是这里**：得把 `roles` 加进
    /// `AuthStore` 的 UserInfo 解码与 `Session` 持久化，否则请求了也是白请求。
    static let scopes = ["openid", "profile", "email", "roles", "offline_access"]

    /// API resource：**留空**（nil），Logto 签发 opaque access token，后端经 UserInfo 校验。
    ///
    /// 与 IF.Link App 的生产实况一致，且 Logto 控制台的 Native 应用页本就没有该字段。
    /// 切勿改成非空：非空会让 Logto 签发 JWT，而 Android 端发的是 opaque token，
    /// 两端 token 形态不一致，后端校验路径也会分叉。
    static let resource: String? = nil

    static var authorizationEndpoint: URL { issuer.appending(path: "auth") }
    static var tokenEndpoint: URL { issuer.appending(path: "token") }
    static var userinfoEndpoint: URL { issuer.appending(path: "me") }
    static var endSessionEndpoint: URL { issuer.appending(path: "session/end") }

    /// clientID 仍为占位值时为 false：UI 据此禁用登录按钮并提示「登录服务配置中」。
    static var isConfigured: Bool {
        !clientID.isEmpty && clientID != "YOUR_LOGTO_NATIVE_APP_ID"
    }
}
