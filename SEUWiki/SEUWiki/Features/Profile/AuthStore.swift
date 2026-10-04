import SwiftUI

/// 本地登录态（stub）：仅保存状态并在 login()/logout() 间切换，不发任何网络请求。
///
/// 后续接入 IF.Link 生态自部署 Logto（https://auth.iflink.tech），要点
/// （后端契约见 Reference/iflab-forum/docs/auth.md §2「Bearer access tokens (native app)」）：
/// - 在 Logto 控制台注册 **Native** 应用（public client，无 secret），
///   回调 scheme 形如 `com.iflink.app://callback`；
/// - 走 OIDC 授权码 + **PKCE** 流程换取 access_token；
/// - 必须请求 scope `openid profile email roles`（与 Cookie 客户端一致，
///   否则 UserInfo 缺少 email / roles 声明，社区角色映射会静默降级）；
/// - 之后的后端请求一律携带 `Authorization: Bearer <access_token>`；
///   该头是权威凭证：token 无效只会得到匿名/401，绝不回退 Cookie 会话；
/// - Logto 默认签发 opaque token，由后端经 UserInfo（`/oidc/me`）校验；
///   配置 API resource 后签发 JWT，由后端 JWKS 本地校验且要求 sub 与 UserInfo 一致。
@Observable
final class AuthStore {
    var isLoggedIn = false

    /// 登录时输入的用户名（stub 保留用于展示，正式版不本地留存凭证）。
    private(set) var username = ""
    /// 昵称（后续来自 Logto profile 的 name）。
    private(set) var displayName = ""
    /// 邮箱（后续来自 UserInfo 的 email）。
    private(set) var email = ""
    /// IF.Link ID（后续来自 UserInfo 的 sub，经 Accounts 解析为稳定 UUID）。
    private(set) var ifLinkID = ""

    /// 头像占位用的首字母 / 首字。
    var initials: String {
        displayName.prefix(1).uppercased()
    }

    /// 本地 stub：仅切换登录态并伪造资料。
    /// 接 Logto 后替换为 OIDC 授权码 + PKCE 流程，在回调里用 UserInfo 填充资料；
    /// password 参数届时移除（原生页表单也将替换为系统浏览器授权）。
    func login(username: String, password: String) {
        let name = username.split(separator: "@").first.map(String.init) ?? username
        self.username = username
        displayName = name
        email = username.contains("@") ? username : "\(username)@iflink.tech"
        ifLinkID = "ifl_local_" + name.lowercased().filter { $0.isLetter || $0.isNumber }
        isLoggedIn = true
    }

    /// 本地 stub：清空登录态。
    /// 接 Logto 后需同时清除本地 token；Logto 端会话为 Cookie-only 浏览器流程，
    /// native bearer 客户端无会话登出重定向。
    func logout() {
        username = ""
        displayName = ""
        email = ""
        ifLinkID = ""
        isLoggedIn = false
    }
}
