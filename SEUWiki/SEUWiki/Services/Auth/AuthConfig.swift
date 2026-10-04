import Foundation

/// Logto OIDC 单点配置：所有端点、客户端标识集中在此，改环境只动这一处。
/// 服务端契约见 Reference/iflab-forum/docs/auth.md §2「Bearer access tokens (native app)」。
struct AuthConfig: Sendable {
    /// Logto issuer（discovery 可用；端点路径固定如下，不依赖运行时发现）。
    var issuer = URL(string: "https://auth.iflink.tech/oidc")!

    /// Logto 控制台注册的 **Native** 应用 ID（public client，无 secret）。
    /// 尚未注册，占位期间 `isConfigured == false`，登录入口优雅降级。
    var clientID = "YOUR_LOGTO_NATIVE_APP_ID"

    /// 回调 URL。scheme 已在 Info.plist 的 CFBundleURLTypes 注册。
    var redirectURI = "tech.iflink.seuwiki://callback"
    var callbackScheme = "tech.iflink.seuwiki"

    /// 必须请求的 scope：与 Cookie 客户端一致（否则 UserInfo 缺 email / roles 声明，
    /// 社区角色映射静默降级）；`offline_access` 换取 refresh token。
    var scopes = ["openid", "profile", "email", "roles", "offline_access"]

    /// API resource：配置后 Logto 签发 JWT access token（后端 JWKS 本地校验）；
    /// 置 nil 则签发 opaque token（后端走 UserInfo 校验）。两种后端都接受。
    var resource: String? = "https://accounts.iflink.tech/api"

    var authorizationEndpoint: URL { issuer.appending(path: "auth") }
    var tokenEndpoint: URL { issuer.appending(path: "token") }
    var userinfoEndpoint: URL { issuer.appending(path: "me") }
    var endSessionEndpoint: URL { issuer.appending(path: "session/end") }

    /// clientID 仍为占位值时为 false：UI 据此禁用登录按钮并提示「登录服务配置中」。
    var isConfigured: Bool {
        !clientID.isEmpty && clientID != "YOUR_LOGTO_NATIVE_APP_ID"
    }
}
