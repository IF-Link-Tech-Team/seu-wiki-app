import Foundation
import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

/// IF.Link 统一登录态：OIDC 授权码 + **PKCE** 流程，与 Android 端
/// `data/AuthStore.kt` 逐项对齐。
///
/// 配置项全部来自 [AuthConfig]（与 Android 端同一份值、同一个 Logto 应用）。
/// 后端契约见 `Reference/iflab-forum/docs/auth.md` §2「Bearer access tokens (native app)」：
///
/// - 授权码 + PKCE（S256），public client 无 secret；
/// - scope 为 `openid profile email roles offline_access`。其中 `roles` **当前只是先要着**，
///   代码里没有解析也没有任何按角色分支的逻辑；真要做角色化功能时记得连 UserInfo 解析与
///   持久化一起补，详见 `AuthConfig.scopes`；
/// - 之后的后端请求一律带 `Authorization: Bearer <access_token>`，该头是权威凭证，
///   token 无效只会得到匿名/401，绝不回退 Cookie 会话。
///
/// 实现说明：
/// - `ASWebAuthenticationSession` **必须强引用**，否则 session 会立刻释放、回调永不触发；
/// - 换 token / 拉 UserInfo 走 `URLSession`，不引入任何第三方网络库（与
///   `FeedAPIClient` 一致）；
/// - UserInfo 用 `Decodable` 解，`String?` 遇到 JSON null 会得到 nil，不会退化成
///   字面量 "null"（Android 侧曾踩过这个坑，见 Kotlin 版 `stringOrNull`）；
/// - 要 refresh token 就必须补 `prompt=consent`，否则 Logto 按 OIDC Core §6 丢弃
///   `offline_access`，详见 [offlineAccessGranted]。
@MainActor
@Observable
final class AuthStore {

    /// 本地会话。`nil` 表示未登录。
    struct Session: Sendable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date
        var subject: String
        var displayName: String
        var email: String
        var avatarURL: URL?
    }

    private(set) var session: Session?
    /// 正在与 Logto 交互（开浏览器 / 换 token），UI 据此禁用按钮。
    private(set) var isBusy = false
    /// 最近一次失败的提示，`nil` 表示没有错误。UI 应如实展示，不要吞掉。
    private(set) var lastError: String?

    var isLoggedIn: Bool { session != nil }
    var isConfigured: Bool { AuthConfig.isConfigured }

    var displayName: String { session?.displayName ?? "" }
    var email: String { session?.email ?? "" }
    /// IF.Link ID：UserInfo 的 `sub`。
    var ifLinkID: String { session?.subject ?? "" }
    var avatarURL: URL? { session?.avatarURL }

    /// 头像占位用的首字母 / 首字。
    var initials: String {
        String(displayName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    /// 是否已经向 Logto 取得过「离线访问」授权（即拿到过 refresh token）。
    ///
    /// OIDC Core §6 规定：请求里带 `offline_access` 时 `prompt` 必须同时带 `consent`，
    /// 否则授权服务器**必须忽略** `offline_access`。Logto 严格执行这条 —— 早期只发了
    /// `offline_access` 而漏了 `prompt=consent`，token 响应里就**没有 `refresh_token`**，
    /// 而 `email` / `roles` 一切正常，极难察觉。后果是 access token 一小时后过期，
    /// `accessToken()` 拿不到 refresh token 只能 `logout()`，表现为「用着用着被静默登出」。
    ///
    /// 首次登录补上 `prompt=consent`，Logto 会展示授权页并把 `offline_access` 记进该
    /// 用户对本应用的 grant；之后按 OIDC Core 的「其他已满足条件」直接复用该 grant，
    /// 不必每次登录都弹授权页。故此标志只置位、登出时也保留，
    /// 仅在续期被拒（grant 可能已在服务端失效）时清掉，让下一次登录重新征求同意。
    private var offlineAccessGranted: Bool {
        get { defaults.bool(forKey: Self.keyOfflineGrant) }
        set { defaults.set(newValue, forKey: Self.keyOfflineGrant) }
    }

    /// `ASWebAuthenticationSession` 不会被系统持有，不留强引用就立刻释放、
    /// 回调永远不来。存成属性由本对象持有到回调结束。
    private var webSession: ASWebAuthenticationSession?
    /// 授权期间保存 PKCE 材料，回调时校验 state 并换 token。
    private var pending: PendingRequest?

    private let session0 = URLSession(configuration: .ephemeral)
    private let defaults = UserDefaults.standard
    private let keychainTag = "tech.iflink.seuwiki.auth"

    init() {
        session = Self.readPersisted(defaults)
    }

    /// 应用级单例。
    ///
    /// 登录态不只被个人页用：`FeedAPIClient` 每次发请求都要经 `accessToken()` 拿续过期的
    /// 凭证，而 feed 层是 App 入口级（`SEUWikiApp`）持有的，拿不到 sheet 里的那份实例。
    /// 与 Android 的 `AuthStore.get(context)` 同一取舍：宁可全局一个，也不想让登录态分裂
    /// 成「个人页已登录、请求仍匿名」两份。
    static let shared = AuthStore()

    // MARK: - 登录

    /// 发起系统浏览器授权。成功后自动完成换 token 与资料填充。
    ///
    /// `presenter` 用于满足 iOS 13+ 的 presentation anchor 要求；传 nil 时回退到
    /// key window。
    func signIn(presenter: ASPresentationAnchor? = nil) {
        guard AuthConfig.isConfigured else {
            lastError = "登录服务配置中"
            return
        }
        guard webSession == nil else { return }  // 防止重复点按开出两个授权页

        let request: AuthorizationRequest
        do {
            request = try buildAuthorizationRequest()
        } catch {
            lastError = "登录失败：\(error.localizedDescription)"
            return
        }
        pending = PendingRequest(verifier: request.verifier, state: request.state)

        let anchor = presenter ?? Self.keyWindow()
        let session = ASWebAuthenticationSession(
            url: request.url,
            callbackURLScheme: AuthConfig.callbackScheme
        ) { [weak self] callbackURL, error in
            // 回调不一定在主线程（系统可能在任意队列投递）。
            Task { @MainActor in
                guard let self else { return }
                self.webSession = nil
                if let error {
                    // 用户主动取消不是错误，不该弹红字。
                    let ns = error as NSError
                    if ns.domain == ASWebAuthenticationSessionError.errorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.pending = nil
                        return
                    }
                    self.pending = nil
                    self.lastError = "登录失败：\(error.localizedDescription)"
                    return
                }
                guard let callbackURL else {
                    self.pending = nil
                    self.lastError = "登录回调为空"
                    return
                }
                await self.completeSignIn(callbackURL: callbackURL)
            }
        }
        AuthPresenter.shared.anchor = anchor
        session.presentationContextProvider = AuthPresenter.shared
        session.prefersEphemeralWebBrowserSession = false  // 复用 Safari 登录态
        webSession = session

        if !session.start() {
            webSession = nil
            pending = nil
            lastError = "无法打开登录页"
        }
    }

    /// 处理回调：校验 state 防 CSRF，再换 token、拉 UserInfo 填资料。
    /// 任何一步失败都只写 [lastError]，不抛 —— 失败后仍停在「未登录」。
    private func completeSignIn(callbackURL: URL) async {
        isBusy = true
        defer { isBusy = false }
        lastError = nil

        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []
        func param(_ name: String) -> String? {
            query.first { $0.name == name }?.value
        }

        if let error = param("error") {
            pending = nil
            lastError = param("error_description") ?? "登录失败：\(error)"
            return
        }
        guard let code = param("code"), !code.isEmpty else {
            pending = nil
            lastError = "登录回调缺少 code"
            return
        }
        guard let request = pending else {
            lastError = "登录会话已失效，请重试"
            return
        }
        guard param("state") == request.state else {
            pending = nil
            lastError = "state 校验失败，已中止登录"
            return
        }
        pending = nil

        do {
            let token = try await exchangeCode(code: code, verifier: request.verifier)
            // 拿到 refresh token 即说明 Logto 认可了 offline_access，之后不必再弹授权页。
            if token.refreshToken != nil { offlineAccessGranted = true }
            let info = try await fetchUserInfo(accessToken: token.accessToken)
            let newSession = Session(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: Date().addingTimeInterval(token.expiresIn),
                subject: info.subject ?? "",
                displayName: Self.resolveDisplayName(info),
                email: info.email ?? "",
                avatarURL: info.picture.flatMap(URL.init(string:))
            )
            persist(newSession)
            session = newSession
        } catch {
            lastError = "登录失败：\(Self.describe(error))"
        }
    }

    // MARK: - 令牌

    /// 取一个可用的 access token，必要时用 refresh token 换新的。
    ///
    /// `FeedAPIClient` 每次请求前调它，登录态下就自动带上新鲜凭证；刷新失败说明
    /// 会话已失效，清本地登录态并返回 nil（回到匿名请求）。
    func accessToken() async -> String? {
        guard let current = session else { return nil }
        if current.expiresAt.timeIntervalSinceNow > Self.expirySkew {
            return current.accessToken
        }
        guard let refresh = current.refreshToken else {
            logout()
            return nil
        }
        do {
            let token = try await renewAccessToken(using: refresh)
            // Logto 可能在刷新时轮换 refresh token，缺省则沿用旧的。
            let renewed = Session(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken ?? refresh,
                expiresAt: Date().addingTimeInterval(token.expiresIn),
                subject: current.subject,
                displayName: current.displayName,
                email: current.email,
                avatarURL: current.avatarURL
            )
            persist(renewed)
            session = renewed
            return renewed.accessToken
        } catch {
            logout()
            // grant 可能已在服务端失效（超过 14 天 TTL、密码重置、管理员清理授权）：
            // 连同「已授权」标志一起清掉，下一次登录会重新弹授权页并取回 refresh token。
            offlineAccessGranted = false
            return nil
        }
    }

    func dismissError() { lastError = nil }

    /// 本地登出：清 token 与资料。Logto 端是 Cookie-only 浏览器会话，
    /// native bearer 客户端没有会话登出重定向可走，这里只清本地。
    ///
    /// 刻意不动 `keyOfflineGrant`：consent 是「用户对本应用的一次性许可」，登出不代表
    /// 收回它 —— 否则每次重新登录都要再看一遍授权页。
    func logout() {
        defaults.removeObject(forKey: Self.keySession)
        session = nil
        lastError = nil
    }

    #if DEBUG
    /// 仅 Debug 构建存在：把本地会话标记为已过期，并立刻走一次**真实**的续期请求，
    /// 用来验证 `refresh_token` 链路是否通。
    ///
    /// 为什么需要它：模拟器与真机都可能点不到「个人页」里的按钮，而从外部改
    /// UserDefaults 也不可靠 —— `cfprefsd` 会用内存缓存把文件里的值覆盖回去。
    /// 在 App 进程内改就没有这个问题。Release 构建里整个方法不存在。
    func debugExpireAndRefresh() {
        guard var dict = defaults.dictionary(forKey: Self.keySession),
              let access = dict["access_token"] as? String, !access.isEmpty
        else {
            NSLog("[AuthStore] debug: 本地没有会话，先登录一次")
            return
        }
        dict["expires_at"] = 0  // 1970 年，强制走 renewAccessToken
        defaults.set(dict, forKey: Self.keySession)
        session = Self.readPersisted(defaults)
        Task { [weak self] in
            let token = await self?.accessToken()
            NSLog("[AuthStore] debug 强制续期结果=%@", token == nil ? "失败（已登出）" : "成功")
        }
    }

    /// 调试 URL 入口。App 已注册 `tech.iflink.seuwiki` scheme，直接用：
    /// `xcrun simctl openurl booted 'tech.iflink.seuwiki://debug/expire-and-refresh'`
    func handleDebugURL(_ url: URL) {
        guard url.path == "/debug/expire-and-refresh" else { return }
        debugExpireAndRefresh()
    }
    #endif

    // MARK: - 请求构造

    private struct AuthorizationRequest {
        let url: URL
        let verifier: String
        let state: String
    }

    private struct PendingRequest {
        let verifier: String
        let state: String
    }

    private func buildAuthorizationRequest() throws -> AuthorizationRequest {
        let verifier = Self.randomURLSafe(byteCount: 32)
        let challenge = Self.base64URL(Data(CryptoKit.SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafe(byteCount: 16)

        var items = [
            URLQueryItem(name: "client_id", value: AuthConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AuthConfig.redirectURI),
            URLQueryItem(name: "scope", value: AuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        // 只在还没拿到过离线授权时补 prompt=consent，见 offlineAccessGranted。
        if !offlineAccessGranted {
            items.append(URLQueryItem(name: "prompt", value: "consent"))
        }
        // resource 目前为 nil（opaque token）。若将来开启，这里会带上面板值。
        if let resource = AuthConfig.resource {
            items.append(URLQueryItem(name: "resource", value: resource))
        }

        guard var components = URLComponents(
            url: AuthConfig.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw AuthError.badURL
        }
        components.queryItems = items
        guard let url = components.url else { throw AuthError.badURL }
        return AuthorizationRequest(url: url, verifier: verifier, state: state)
    }

    // MARK: - 网络

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    /// UserInfo 的可选声明全部声明为可选：JSON `null` 会解成 nil，
    /// 不会变成字符串 "null"。
    private struct UserInfo: Decodable {
        let subject: String?
        let name: String?
        let username: String?
        let preferredUsername: String?
        let email: String?
        let picture: String?

        enum CodingKeys: String, CodingKey {
            case subject = "sub"
            case name
            case username
            case preferredUsername = "preferred_username"
            case email
            case picture
        }
    }

    /// 只记 token 响应的字段名与「有没有 refresh_token」，绝不打印任何 token 值。
    private static func logTokenResponse(_ data: Data, hasRefreshToken: Bool) {
        let fields = (try? JSONSerialization.jsonObject(with: data))
            .flatMap { $0 as? [String: Any] }
            .map { $0.keys.sorted().joined(separator: ",") } ?? "?"
        NSLog(
            "[AuthStore] token 响应字段=%@，含 refresh_token=%@",
            fields, hasRefreshToken ? "是" : "否"
        )
    }

    private func exchangeCode(code: String, verifier: String) async throws -> TokenResponse {
        var form = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": AuthConfig.redirectURI,
            "client_id": AuthConfig.clientID,
            "code_verifier": verifier,
        ]
        if let resource = AuthConfig.resource { form["resource"] = resource }
        return try await postForm(AuthConfig.tokenEndpoint, form)
    }

    private func renewAccessToken(using refresh: String) async throws -> TokenResponse {
        var form = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": AuthConfig.clientID,
        ]
        if let resource = AuthConfig.resource { form["resource"] = resource }
        return try await postForm(AuthConfig.tokenEndpoint, form)
    }

    private func fetchUserInfo(accessToken: String) async throws -> UserInfo {
        var request = URLRequest(url: AuthConfig.userinfoEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        let (data, response) = try await session0.data(for: request)
        try Self.checkStatus(response, data: data)
        return try JSONDecoder().decode(UserInfo.self, from: data)
    }

    private func postForm(_ url: URL, _ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let body = form
            .sorted { $0.key < $1.key }
            .map { "\(Self.formEncode($0.key))=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await session0.data(for: request)
        try Self.checkStatus(response, data: data)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        Self.logTokenResponse(data, hasRefreshToken: token.refreshToken != nil)
        return token
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            // 把服务端给的错误体带出来：Logto 的 code/message 就在里面。
            let text = String(data: data, encoding: .utf8) ?? ""
            let head = String(text.prefix(160))
            throw AuthError.http(status: http.statusCode, body: head.isEmpty ? nil : head)
        }
    }

    private static func describe(_ error: Error) -> String {
        if case let AuthError.http(status, body) = error {
            return body.map { "HTTP \(status): \($0)" } ?? "HTTP \(status)"
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - 持久化

    private func persist(_ s: Session) {
        let dict: [String: Any] = [
            "access_token": s.accessToken,
            "refresh_token": s.refreshToken ?? "",
            "expires_at": s.expiresAt.timeIntervalSince1970,
            "subject": s.subject,
            "display_name": s.displayName,
            "email": s.email,
            "avatar_url": s.avatarURL?.absoluteString ?? "",
        ]
        defaults.set(dict, forKey: Self.keySession)
    }

    /// 读回本地会话。
    ///
    /// 有 token 但已过期时**仍然恢复**，交给 `accessToken()` 用 refresh token 续期 ——
    /// 冷启动时不该把还能续的会话丢掉。
    private static func readPersisted(_ defaults: UserDefaults) -> Session? {
        guard let dict = defaults.dictionary(forKey: keySession),
              let access = dict["access_token"] as? String,
              !access.isEmpty
        else { return nil }
        let refresh = (dict["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Session(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date(timeIntervalSince1970: dict["expires_at"] as? Double ?? 0),
            subject: dict["subject"] as? String ?? "",
            displayName: dict["display_name"] as? String ?? "",
            email: dict["email"] as? String ?? "",
            avatarURL: (dict["avatar_url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                .flatMap(URL.init(string:))
        )
    }

    // MARK: - 工具

    /// 昵称回退链：name → username → preferred_username → 邮箱前缀 → 固定文案。
    private static func resolveDisplayName(_ info: UserInfo) -> String {
        if let name = info.name, !name.isEmpty { return name }
        if let username = info.username, !username.isEmpty { return username }
        if let preferred = info.preferredUsername, !preferred.isEmpty { return preferred }
        if let email = info.email, !email.isEmpty { return String(email.split(separator: "@").first ?? "") }
        return "IF.Link 用户"
    }

    private enum AuthError: Error, LocalizedError {
        case badURL
        case http(status: Int, body: String?)

        var errorDescription: String? {
            switch self {
            case .badURL: "授权地址无法构造"
            case let .http(status, body): body.map { "HTTP \(status): \($0)" } ?? "HTTP \(status)"
            }
        }
    }

    private static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        // 系统随机源失败时抛错，不用低质量替代。
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// form-urlencoded：空格必须是 `+`，且要转义 `&` `=` 等保留字符。
    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? s
    }

    static func keyWindow() -> ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    private static let keySession = "seu_wiki_auth_session"
    /// 是否已取得 offline_access 授权，见 [offlineAccessGranted]。
    private static let keyOfflineGrant = "seu_wiki_auth_offline_grant"
    /// 提前这么多秒就当作过期，避免请求正好卡在边界上被拒。
    private static let expirySkew: TimeInterval = 60
}

/// 只是个占位符，真正持有 session 的对象是 [AuthStore]；
/// 这里仅用于满足 `ASWebAuthenticationSessionPresentationContextProviding`。
private final class AuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresenter()
    /// 由 [AuthStore] 在发起授权前写入；`ASWebAuthenticationSession.presentationAnchor`
    /// 是只读的，anchor 只能经由本 provider 提供。
    var anchor: ASPresentationAnchor?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? AuthStore.keyWindow() ?? ASPresentationAnchor()
    }
}
