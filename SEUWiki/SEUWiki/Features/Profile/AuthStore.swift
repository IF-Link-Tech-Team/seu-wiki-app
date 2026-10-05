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
/// - 必须请求 `openid profile email roles`，否则 UserInfo 缺声明、角色映射静默降级；
/// - 之后的后端请求一律带 `Authorization: Bearer <access_token>`，该头是权威凭证，
///   token 无效只会得到匿名/401，绝不回退 Cookie 会话。
///
/// 实现说明：
/// - `ASWebAuthenticationSession` **必须强引用**，否则 session 会立刻释放、回调永不触发；
/// - 换 token / 拉 UserInfo 走 `URLSession`，不引入任何第三方网络库（与
///   `FeedAPIClient` 一致）；
/// - UserInfo 用 `Decodable` 解，`String?` 遇到 JSON null 会得到 nil，不会退化成
///   字面量 "null"（Android 侧曾踩过这个坑，见 Kotlin 版 `stringOrNull`）。
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
            return nil
        }
    }

    func dismissError() { lastError = nil }

    /// 本地登出：清 token 与资料。Logto 端是 Cookie-only 浏览器会话，
    /// native bearer 客户端没有会话登出重定向可走，这里只清本地。
    func logout() {
        defaults.removeObject(forKey: Self.keySession)
        session = nil
        lastError = nil
    }

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
        return try JSONDecoder().decode(TokenResponse.self, from: data)
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
