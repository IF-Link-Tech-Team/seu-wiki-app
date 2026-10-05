import Foundation

/// Logto OIDC 单点配置：所有端点、客户端标识集中在此，改环境只动这一处。
/// 服务端契约见 Reference/iflab-forum/docs/auth.md §2「Bearer access tokens (native app)」。
struct AuthConfig: Sendable {
    /// Logto issuer（discovery 可用；端点路径固定如下，不依赖运行时发现）。
    var issuer = URL(string: "https://auth.iflink.tech/oidc")!

    /// Logto 控制台注册的 **Native** 应用 ID（public client，无 secret）。
    /// 对应控制台应用「SEU Wiki Android」（2026-10-05 注册，Native App 类型）。
    /// 与 Android 端共用同一个应用：两端都是 native 客户端，回调 scheme 同为
    /// `tech.iflink.seuwiki`，不必再注册一个 iOS 专属应用。
    var clientID = "yb6csafyv7tviokwbbu2w"

    /// 回调 URL。scheme 已在 Info.plist 的 CFBundleURLTypes 注册。
    var redirectURI = "tech.iflink.seuwiki://callback"
    var callbackScheme = "tech.iflink.seuwiki"

    /// 必须请求的 scope：与 Cookie 客户端一致（否则 UserInfo 缺 email / roles 声明，
    /// 社区角色映射静默降级）；`offline_access` 换取 refresh token。
    var scopes = ["openid", "profile", "email", "roles", "offline_access"]

    /// API resource：**留空**（nil），Logto 签发 opaque access token，后端经 UserInfo 校验。
    ///
    /// 与 IF.Link App 的生产实况一致，且 Logto 控制台的 Native 应用页本就没有该字段。
    /// 切勿改成非空：非空会让 Logto 签发 JWT，而 Android 端发的是 opaque token，
    /// 两端 token 形态不一致，后端校验路径也会分叉。
    var resource: String? = nil

    var authorizationEndpoint: URL { issuer.appending(path: "auth") }
    var tokenEndpoint: URL { issuer.appending(path: "token") }
    var userinfoEndpoint: URL { issuer.appending(path: "me") }
    var endSessionEndpoint: URL { issuer.appending(path: "session/end") }

    /// clientID 仍为占位值时为 false：UI 据此禁用登录按钮并提示「登录服务配置中」。
    var isConfigured: Bool {
        !clientID.isEmpty && clientID != "YOUR_LOGTO_NATIVE_APP_ID"
    }
}
