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
///   `offline_access`，详见 [buildAuthorizationRequest]。
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

    /// 退出登录后置位：下次授权带上 `prompt=login`，强制 Logto 弹出账号选择。
    ///
    /// 为什么需要：Logto 的浏览器会话是 Cookie-only 的，native 端「登出」只是清本地。
    /// 不吊销 refresh token、不强制重新选号的话，用户再点登录会被浏览器里还活着的
    /// Cookie 静默送回**上一个账号** —— 表现为「怎么登出去又登回来了、还换不了号」。
    /// 登出时先吊销（RFC 7009），这里再补一道账号选择的保险。
    private var forceAccountPicker: Bool {
        get { defaults.bool(forKey: Self.keyForceAccountPicker) }
        set { defaults.set(newValue, forKey: Self.keyForceAccountPicker) }
    }

    /// `ASWebAuthenticationSession` 不会被系统持有，不留强引用就立刻释放、
    /// 回调永远不来。存成属性由本对象持有到回调结束。
    private var webSession: ASWebAuthenticationSession?
    /// 授权期间保存 PKCE 材料，回调时校验 state 并换 token。
    private var pending: PendingRequest?

    /// 正在飞行的续期任务。**所有**调用方 await 同一个任务，避免同一个 refresh token
    /// 被并发使用（Logto 开了 Rotate refresh token，第二个请求会拿到已作废的 token）。
    private var refreshTask: Task<Session?, Never>?
    /// 会话代号。登出或换号时自增，用来识别「续期还在路上，用户已经登出了」这种竞态。
    private var sessionGeneration: Int = 0

    private let session0 = URLSession(configuration: .ephemeral)
    private let defaults = UserDefaults.standard
    private let keychainTag = "tech.iflink.seuwiki.auth"

    init() {
        session = Self.readPersisted(defaults: defaults, keychainTag: keychainTag)
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
            forceAccountPicker = false
            lastError = token.refreshToken == nil
                ? "登录成功，但 Logto 未签发 refresh token，约一小时后会需要重新登录"
                : nil
        } catch {
            lastError = "登录失败：\(Self.describe(error))"
        }
    }

    // MARK: - 令牌

    /// 取一个可用的 access token，必要时用 refresh token 换新的。
    ///
    /// 资讯客户端当前**不消费**这个返回值（seu.wiki 的 `/api/site` 不校验鉴权，
    /// 见 `FeedService` 的说明），保留它是为了 forum 接入后能直接复用。
    ///
    /// 续期失败时**不一律登出**：只有 Logto 明确判定 refresh token 失效
    /// （400 `invalid_grant` / 401）才清会话；断网、超时、任务取消、服务端 5xx
    /// 一律保留登录态，本次调用退回匿名。早期版本在这里无条件 `logout()`，
    /// 叠加 `FeedHomeView` 切换 scope 时 `.task(id:)` 的取消行为，用户在切 tab
    /// 或搜索框敲字的过程中会被静默登出。
    func accessToken() async -> String? {
        guard let current = session else { return nil }
        if current.expiresAt.timeIntervalSinceNow > Self.expirySkew {
            return current.accessToken
        }
        guard let refresh = current.refreshToken else {
            // 没有 refresh token 说明 `offline_access` 从未获批，这个会话无法自愈。
            invalidateLocalSession()
            return nil
        }
        let renewed = await refreshOnce(refresh: refresh, base: current)
        return renewed?.accessToken
    }

    /// 合并并发续期：已有在飞行的任务就复用它，而不是再拿同一个 refresh token 发一次。
    ///
    /// Logto 开了 Rotate refresh token —— 同一个 refresh token 并发使用，第一个成功
    /// 就会让第二个手里的那份作废，第二个拿到 `invalid_grant`，进而把用户登出。
    /// 这里让全 App 的调用方 await 同一个 `Task`，从根上消除并发。
    private func refreshOnce(refresh: String, base: Session) async -> Session? {
        if let existing = refreshTask { return await existing.value }

        let generation = sessionGeneration
        // 刻意用非结构化 `Task`：它**不继承调用方的取消**。`.task(id:)` 被取消时
        // （切 scope、下拉刷新重来）续期仍会跑完并落盘，不会半途而废。
        let task = Task<Session?, Never> { [weak self] in
            guard let self else { return nil }
            defer { self.refreshTask = nil }
            do {
                let token = try await self.renewAccessToken(using: refresh)
                let renewed = Session(
                    accessToken: token.accessToken,
                    // Logto 会在刷新时轮换 refresh token，缺省则沿用旧的。
                    refreshToken: token.refreshToken ?? refresh,
                    expiresAt: Date().addingTimeInterval(token.expiresIn),
                    subject: base.subject,
                    displayName: base.displayName,
                    email: base.email,
                    avatarURL: base.avatarURL
                )
                // 续期在途时用户可能已登出或换号。代号对不上就丢弃结果，
                // 绝不能把已退出的会话「复活」回来。
                guard self.sessionGeneration == generation else { return nil }
                self.persist(renewed)
                self.session = renewed
                return renewed
            } catch {
                if Self.invalidatesSession(error) {
                    self.invalidateLocalSession()
                }
                return nil
            }
        }
        refreshTask = task
        return await task.value
    }

    /// 只有「服务端明确拒绝了这个 refresh token」才允许清会话。
    ///
    /// - 400 且错误体含 `invalid_grant`：RFC 6749 §5.2 规定该值表示 refresh token
    ///   无效、过期、已被吊销或已被轮换 —— 会话确实救不回来了。
    /// - 401：同样代表凭证被拒。
    /// - 403 / 429 / 5xx / 断网 / 超时 / 取消：都**不代表** token 失效，
    ///   此时登出等于把用户的网络抖动变成「账号被踢」。
    private static func invalidatesSession(_ error: Error) -> Bool {
        guard case let AuthError.http(status, body) = error else { return false }
        if status == 401 { return true }
        return status == 400 && (body?.contains("invalid_grant") == true)
    }

    func dismissError() { lastError = nil }

    /// 退出登录：清本地会话 + 作废在途续期 + 异步吊销 refresh token。
    ///
    /// 吊销走 RFC 7009。不吊销的话该 token 在服务端最长还有 14 天有效，
    /// 配合浏览器里仍存活的 Logto Cookie，用户再登录会被静默送回原账号。
    /// 吊销是网络请求，**不阻塞**本地登出：吊销失败也只是服务端多留一个无效 token，
    /// 不该让用户对着转圈等。
    func logout() {
        let token = session?.refreshToken
        invalidateLocalSession()
        forceAccountPicker = true
        if let token, !token.isEmpty {
            // 先把 token 拷出来再清：invalidateLocalSession 之后 session 已是 nil。
            Task.detached { await Self.revokeRefreshToken(token) }
        }
    }

    /// 只清本地：代号自增让在途续期作废、取消在飞任务、清存储。
    private func invalidateLocalSession() {
        sessionGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        Self.clearStoredSession(defaults: defaults, keychainTag: keychainTag)
        session = nil
        lastError = nil
    }

    /// 吊销 refresh token（RFC 7009）。失败只记日志，不影响登出流程。
    nonisolated private static func revokeRefreshToken(_ token: String) async {
        var request = URLRequest(url: AuthConfig.revocationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        let body = [
            "token=\(formEncode(token))",
            "client_id=\(formEncode(AuthConfig.clientID))",
            "token_type_hint=refresh_token",
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            NSLog("[AuthStore] 吊销 refresh token 返回 HTTP %d", code)
        } catch {
            NSLog("[AuthStore] 吊销 refresh token 失败：%@", (error as NSError).code)
        }
    }

    #if DEBUG
    /// 仅 Debug 构建存在：把本地会话标记为已过期，并立刻走一次**真实**的续期请求，
    /// 用来验证 `refresh_token` 链路是否通。
    ///
    /// 为什么需要它：模拟器与真机都可能点不到「个人页」里的按钮，而从外部改
    /// UserDefaults 也不可靠 —— `cfprefsd` 会用内存缓存把文件里的值覆盖回去。
    /// 在 App 进程内改就没有这个问题。Release 构建里整个方法不存在。
    func debugExpireAndRefresh() {
        guard var stored = Keychain.read(tag: keychainTag)
            .flatMap({ try? JSONDecoder().decode(StoredSession.self, from: $0) }),
              !stored.accessToken.isEmpty
        else {
            NSLog("[AuthStore] debug: 本地没有会话，先登录一次")
            return
        }
        let dict = StoredSession(
            version: AuthStore.payloadVersion,
            accessToken: stored.accessToken,
            refreshToken: stored.refreshToken,
            expiresAt: 0,  // 1970 年，强制走 renewAccessToken
            subject: stored.subject,
            displayName: stored.displayName,
            email: stored.email,
            avatarURL: stored.avatarURL
        )
        stored = dict
        if let data = try? JSONEncoder().encode(dict) { try? Keychain.write(data, tag: keychainTag) }
        session = dict.session
        Task { [weak self] in
            let token = await self?.accessToken()
            NSLog("[AuthStore] debug 强制续期结果=%@", token == nil ? "失败" : "成功")
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
        let verifier = try Self.randomURLSafe(byteCount: 32)
        let challenge = Self.base64URL(Data(CryptoKit.SHA256.hash(data: Data(verifier.utf8))))
        let state = try Self.randomURLSafe(byteCount: 16)

        var items = [
            URLQueryItem(name: "client_id", value: AuthConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AuthConfig.redirectURI),
            URLQueryItem(name: "scope", value: AuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        // OIDC Core §6：请求带 `offline_access` 时 `prompt` 必须同时带 `consent`，
        // 否则授权服务器**必须忽略** offline_access、不签发 refresh token。Logto 严格执行，
        // 漏掉时表现是「登录一切正常，但一小时后必然掉线」，极难察觉。
        //
        // **始终带**，不做「首次才带」的优化：Logto 的 first-party 应用在已获授权时
        // 直接复用 grant，不会重复弹授权页；而一旦某次漏带，那个「已授权」标志就再也
        // 自愈不回来（早期版本用 `offlineAccessGranted` 只置位不复位，还不分用户，
        // 结果一次失败导致之后所有登录都拿不到 refresh token）。
        items.append(URLQueryItem(name: "prompt", value: "consent"))
        // 登出过：强制 Logto 重新选号，否则浏览器里活着的 Cookie 会把人静默送回上一个账号。
        if forceAccountPicker {
            items.append(URLQueryItem(name: "prompt", value: "login"))
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

    /// 落盘载荷。带 `version` 是为了以后加字段时能平滑升级 —— 早期版本直接存字典，
    /// 模型一改、解析失败就静默丢会话，用户还得重新走一遍浏览器授权。
    private struct StoredSession: Codable {
        let version: Int
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Double
        let subject: String
        let displayName: String
        let email: String
        let avatarURL: String?

        init(session: Session) {
            version = AuthStore.payloadVersion
            accessToken = session.accessToken
            refreshToken = session.refreshToken
            expiresAt = session.expiresAt.timeIntervalSince1970
            subject = session.subject
            displayName = session.displayName
            email = session.email
            avatarURL = session.avatarURL?.absoluteString
        }

        /// 结构体一旦声明了自定义 init，编译器就不再合成 memberwise init；显式写出来。
        init(
            version: Int,
            accessToken: String,
            refreshToken: String?,
            expiresAt: Double,
            subject: String,
            displayName: String,
            email: String,
            avatarURL: String?
        ) {
            self.version = version
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
            self.subject = subject
            self.displayName = displayName
            self.email = email
            self.avatarURL = avatarURL
        }

        var session: Session {
            Session(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: Date(timeIntervalSince1970: expiresAt),
                subject: subject,
                displayName: displayName,
                email: email,
                avatarURL: avatarURL.flatMap(URL.init(string:))
            )
        }
    }

    private func persist(_ s: Session) {
        guard let data = try? JSONEncoder().encode(StoredSession(session: s)) else { return }
        do {
            try Keychain.write(data, tag: keychainTag)
        } catch {
            NSLog("[AuthStore] Keychain 写入失败：%@", (error as NSError).code)
        }
    }

    private static func clearStoredSession(defaults: UserDefaults, keychainTag: String) {
        Keychain.delete(tag: keychainTag)
        // 旧版本明文残留一并清掉，避免升级后 Keychain 与 UserDefaults 同时有会话。
        defaults.removeObject(forKey: keySession)
    }

    /// 读回本地会话。优先 Keychain；发现旧版 UserDefaults 里的明文会话则**迁移**过来。
    ///
    /// 有 token 但已过期时**仍然恢复**，交给 `accessToken()` 用 refresh token 续期 ——
    /// 冷启动时不该把还能续的会话丢掉。
    private static func readPersisted(defaults: UserDefaults, keychainTag: String) -> Session? {
        if let data = Keychain.read(tag: keychainTag),
           let stored = try? JSONDecoder().decode(StoredSession.self, from: data),
           !stored.accessToken.isEmpty {
            defaults.removeObject(forKey: keySession)  // 迁移完成后清掉旧明文
            return stored.session
        }

        // 一次性迁移：≤ 1.4 版本把 token 明文存在 UserDefaults。
        guard let legacy = defaults.dictionary(forKey: keySession),
              let access = legacy["access_token"] as? String, !access.isEmpty
        else { return nil }
        let refresh = (legacy["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let migrated = Session(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date(timeIntervalSince1970: legacy["expires_at"] as? Double ?? 0),
            subject: legacy["subject"] as? String ?? "",
            displayName: legacy["display_name"] as? String ?? "",
            email: legacy["email"] as? String ?? "",
            avatarURL: (legacy["avatar_url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                .flatMap(URL.init(string:))
        )
        if let data = try? JSONEncoder().encode(StoredSession(session: migrated)) {
            try? Keychain.write(data, tag: keychainTag)
        }
        defaults.removeObject(forKey: keySession)
        NSLog("[AuthStore] 已把 UserDefaults 里的旧会话迁移到 Keychain")
        return migrated
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
        case randomSourceUnavailable

        var errorDescription: String? {
            switch self {
            case .badURL: "授权地址无法构造"
            case .randomSourceUnavailable: "系统随机源不可用，已中止登录"
            case let .http(status, body): body.map { "HTTP \(status): \($0)" } ?? "HTTP \(status)"
            }
        }
    }

    /// 生成 URL-safe 随机串。系统随机源失败时**抛错**，不用低质量随机替代 ——
    /// PKCE 的 verifier 和 state 一旦可预测，整个授权码流程就失去意义。
    /// （旧实现丢弃了 `SecRandomCopyBytes` 的返回值，失败时会静默发出一段全零。）
    private static func randomURLSafe(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw AuthError.randomSourceUnavailable
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// form-urlencoded：空格必须是 `+`，且要转义 `&` `=` 等保留字符。
    /// `nonisolated` 是因为 [revokeRefreshToken] 在脱离主 actor 的上下文里用它。
    nonisolated private static func formEncode(_ s: String) -> String {
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
    /// 登出后置位，下次授权带 `prompt=login` 强制选号，见 [forceAccountPicker]。
    private static let keyForceAccountPicker = "seu_wiki_auth_force_account_picker"
    /// 落盘载荷版本。字段只增不改时不需要动它；改动语义时 +1 并在解码处分支。
    private static let payloadVersion = 2
    /// 提前这么多秒就当作过期，避免请求正好卡在边界上被拒。
    private static let expirySkew: TimeInterval = 60
}

/// 会话载荷的 Keychain 存取。
///
/// token 是 bearer 凭证，**不能**放 UserDefaults：那里的明文会进 iTunes/Finder 备份、
/// 也能被 `defaults read` 直接读出来。`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// 的含义是「首次解锁后可用、且不随备份迁移到别的设备」—— 换机时用户重新登录一次，
/// 比把一个能直接调用 IF.Link API 的 token 复制过去安全。
private enum Keychain {
    private static let service = "tech.iflink.seuwiki"

    static func write(_ data: Data, tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    static func read(tag: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func delete(tag: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error { case status(OSStatus) }
}

/// 只是个占位符，真正持有 session 的对象是 [AuthStore]；
/// 这里仅用于满足 `ASWebAuthenticationSessionPresentationContextProviding`。
private final class AuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresenter()
    /// 由 [AuthStore] 在发起授权前写入；`ASWebAuthenticationSession.presentationAnchor`
    /// 是只读的，anchor 只能经由本 provider 提供。
    var anchor: ASPresentationAnchor?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let anchor { return anchor }
        if let key = AuthStore.keyWindow() { return key }
        // 理论到不了这里：signIn() 开窗前就拿到并写入了 anchor，App 没有 key window 时
        // 根本不在前台。iOS 26 起 `UIWindow()` 无参 init 已废弃，只能带 windowScene；
        // 真的一个 scene 都没有时没有别的造法，保留这一行作最后的兜底。
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            return ASPresentationAnchor(windowScene: scene)
        }
        return ASPresentationAnchor()
    }
}
