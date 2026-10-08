import Foundation
import SwiftUI
import UIKit

/// Umami 统计（自建实例 https://umami.iflink.tech，v3.2.0）。
///
/// 协议：`POST /api/send`，body `{"type":"event","payload":{website, hostname,
/// language, screen, url, title, referrer, name?, data?}}`。服务端靠 **IP + User-Agent**
/// 生成会话并解析设备/OS，所以 UA 必须带 `iPhone; CPU iPhone OS …` 形态，
/// 否则 Realtime 面板里全部归成 unknown。
///
/// 设计约束：
/// - **fire-and-forget**：离线、超时、非 2xx 一律静默吞掉，不重试、不阻塞 UI、
///   绝不影响任何用户可见路径。统计丢了就丢了，App 不能为它付出任何代价。
/// - **DEBUG 不上报**（`isEnabled`）：开发与自检都在 DEBUG 跑，上报会污染统计。
///   payload 构造（`screenViewPayload`）是纯函数、与发送解耦，契约由
///   `SelfCheck.checkUmamiContract` 断言，与 Android 端同语义
///   （website id / hostname / type / url / title 逐字段对齐）。
enum UmamiAnalytics {
    static let endpoint = URL(string: "https://umami.iflink.tech/api/send")!
    /// Umami 后台站点「SEU Wiki APP」的 website_id。
    static let websiteID = "97ce2a8e-3118-478e-81e3-ea76c9f73f35"
    static let hostname = "app.seu.wiki"

    /// DEBUG 构建不上报，Release 才发。
    static var isEnabled: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    /// 上一屏路径，作为下一屏的 `referrer`（Umami 会话内页面流转就靠它）。
    private static var lastScreenPath = ""

    /// 屏幕出现即上报一次 screen view。重复出现（切回 tab、pop 回来）算新的一次浏览。
    static func trackScreen(_ path: String, title: String) {
        let body = screenViewPayload(
            url: path,
            title: title,
            referrer: lastScreenPath,
            screen: currentScreenSize(),
            language: currentLanguage()
        )
        lastScreenPath = path
        guard isEnabled, let request = makeRequest(body) else { return }
        // detached：发送不挂调用方（视图 onAppear）的 actor 与取消域，
        // 页面销毁不该取消上报，网络等待也不占主 actor。
        Task.detached(priority: .utility) {
            // 一切失败静默吞掉：统计请求没有重试的价值，更没有崩 App 的资格。
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// 构造 `/api/send` 请求体。**纯函数**，不读任何全局状态，
    /// 便于 SelfCheck 逐字段断言契约。
    static func screenViewPayload(
        url: String,
        title: String,
        referrer: String = "",
        screen: String,
        language: String,
        eventName: String? = nil,
        data: [String: Any]? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "website": websiteID,
            "hostname": hostname,
            "language": language,
            "screen": screen,
            "url": url,
            "title": title,
            "referrer": referrer,
        ]
        // 自定义事件才带 name/data；纯页面浏览不带（Umami 据此区分）。
        if let eventName { payload["name"] = eventName }
        if let data { payload["data"] = data }
        return ["type": "event", "payload": payload]
    }

    /// 由请求体构造 POST 请求；body 无法序列化时返回 nil（调用方静默跳过）。
    static func makeRequest(_ body: [String: Any]) -> URLRequest? {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = data
        return request
    }

    /// 让 Umami 能解析出 iOS 设备/OS 的 UA（形态对齐移动端 Safari）。
    static var userAgent: String {
        let device = UIDevice.current
        let os = device.systemVersion.replacingOccurrences(of: ".", with: "_")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        if device.userInterfaceIdiom == .pad {
            return "Mozilla/5.0 (iPad; CPU OS \(os) like Mac OS X) SEUWiki/\(version)"
        }
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(os) like Mac OS X) SEUWiki/\(version)"
    }

    /// 物理像素（如 1170x2532），与网页端 window.screen 语义一致。
    private static func currentScreenSize() -> String {
        let bounds = UIScreen.main.nativeBounds
        return "\(Int(bounds.width))x\(Int(bounds.height))"
    }

    private static func currentLanguage() -> String {
        Locale.preferredLanguages.first ?? "zh-CN"
    }
}

extension View {
    /// 屏幕浏览埋点：视图每次出现（含切回 tab、pop 返回）上报一次 Umami screen view。
    /// 挂在各顶层页面与详情页的根容器上（紧邻 `navigationTitle`）。
    func trackScreen(_ path: String, title: String) -> some View {
        onAppear { UmamiAnalytics.trackScreen(path, title: title) }
    }
}
