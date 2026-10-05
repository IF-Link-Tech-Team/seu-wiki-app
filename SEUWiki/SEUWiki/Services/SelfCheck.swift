import Foundation
import SwiftUI

/// 关键纯逻辑的断言套件。
///
/// 存在的理由：两端此前都是**零测试**，而这几处正是历次线上事故的高发区 ——
/// 日期解析（后端混用带时刻与只有日期两种格式）、分页合并去重、绩点换算、
/// 颜色对比度、持久化往返。
///
/// 运行方式：
/// - Debug 启动 App 时自动跑一遍（`SEUWikiApp.init`），结果打日志；
/// - 或用 `xcrun simctl launch` 后在控制台看 `[SelfCheck]` 开头的结果。
///
/// 之所以做成 DEBUG 自检而不是 XCTest target：这个工程没有测试 target，
/// 手工往 `project.pbxproj` 里加 target + TEST_HOST 的风险高于收益；
/// 自检跑在真机/模拟器的真实运行环境里，反而能覆盖 `Calendar.current`、
/// 时区、locale 这些最容易出错的系统依赖。
///
/// 整个类型包在 `#if DEBUG` 里：它只在 `SEUWikiApp.init` 被调用，且依赖若干同样
/// 只在 DEBUG 存在的 API（如 `ProfileStorage.runPersistenceSelfTest`）。不隔离的话
/// **Release 构建会直接失败**——自检是调试设施，不该进发布二进制。
#if DEBUG
enum SelfCheck {
    struct Result {
        var name: String
        var passed: Bool
        var detail: String?
    }

    /// 跑全部检查。
    static func runAll() -> [Result] {
        results = []
        checkDateParsing()
        checkRelativeTime()
        checkGPA()
        checkPaginationDedup()
        checkSlugEncoding()
        checkDocDetailContract()
        checkProfileFingerprint()
        checkContrast()
        checkReminderBadge()
        checkPersistence()
        let snapshot = results
        let failed = snapshot.filter { !$0.passed }
        if failed.isEmpty {
            NSLog("[SelfCheck] 全部 %d 项通过", snapshot.count)
        } else {
            NSLog("[SelfCheck] %d/%d 项失败：%@", failed.count, snapshot.count,
                  failed.map(\.name).joined(separator: ", "))
        }
        return snapshot
    }

    private static var results: [Result] = []

    private static func expect(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        results.append(Result(name: name, passed: condition, detail: condition ? nil : detail()))
    }

    // MARK: - 日期解析

    private static func checkDateParsing() {
        // 后端 `timelineAt` 是带毫秒的 ISO8601。
        let withFraction = DateParser.parse("2026-10-04T04:47:20.333Z")
        expect("日期解析/带毫秒 ISO8601", withFraction != nil)

        // 不带毫秒的也要能解。
        expect("日期解析/无毫秒 ISO8601", DateParser.parse("2026-10-04T04:47:20Z") != nil)

        // ⚠️ `deadline` 是 `YYYY-MM-DD`（只有日期）。早期版本只有 ISO8601 解析器，
        // 这一种直接抛异常，进而让**整页** feed 解码失败并回退到演示数据。
        let dateOnly = DateParser.parse("2026-10-05")
        expect("日期解析/只有日期 YYYY-MM-DD", dateOnly != nil, "后端 deadline 就是这个格式")
        if let dateOnly {
            let c = Calendar(identifier: .gregorian)
            let parts = c.dateComponents([.year, .month, .day], from: dateOnly)
            expect("日期解析/年月日正确", parts.year == 2026 && parts.month == 10 && parts.day == 5,
                   "实际 \(parts.year)-\(parts.month)-\(parts.day)")
        }

        // 完全无法识别的串要返回 nil 而不是崩。
        expect("日期解析/非法输入返回 nil", DateParser.parse("not-a-date") == nil)
    }

    // MARK: - 相对时间

    private static func checkRelativeTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar.current
        func date(offsetDays: Int) -> Date {
            calendar.date(byAdding: .day, value: offsetDays, to: now)!
        }
        expect("相对时间/刚刚", TimeFormat.relative(date(offsetDays: 0), now: now).contains("分钟前")
               || TimeFormat.relative(date(offsetDays: 0), now: now) == "刚刚")
        expect("相对时间/N 天前", TimeFormat.relative(date(offsetDays: -3), now: now) == "3 天前",
               "实际 \(TimeFormat.relative(date(offsetDays: -3), now: now))")
        // 超过 7 天走绝对日期，不能再显示「8 天前」这种越来越长的相对表述。
        let tenDays = TimeFormat.relative(date(offsetDays: -10), now: now)
        expect("相对时间/超过 7 天用绝对日期", !tenDays.contains("天前"), "实际 \(tenDays)")
        // 未来时间不能显示「还有 x」。
        let future = TimeFormat.relative(date(offsetDays: 3), now: now)
        expect("相对时间/未来时间不显示天前", !future.contains("天前"), "实际 \(future)")
    }

    // MARK: - 绩点

    private static func checkGPA() {
        // 五分制：90–100 为 5.0，此后每 5 分降 0.5，60 以下为 0。
        expect("绩点/95 分 = 5.0", GPAGradingScale.point(for: 95) == 5.0)
        expect("绩点/90 分 = 5.0", GPAGradingScale.point(for: 90) == 5.0)
        expect("绩点/89 分 = 4.5", GPAGradingScale.point(for: 89) == 4.5)
        expect("绩点/85 分 = 4.5", GPAGradingScale.point(for: 85) == 4.5)
        expect("绩点/60 分 = 2.0", GPAGradingScale.point(for: 60) == 2.0)
        expect("绩点/59 分 = 0", GPAGradingScale.point(for: 59) == 0)
        // 输入侧：非法输入必须被判无效，不能让 NaN 混进加权平均。
        let bad = GPACourse(creditsText: "inf", scoreText: "108")
        expect("绩点/inf 学分判无效", bad.credits == nil)
        expect("绩点/越界成绩判无效", bad.score == nil)
        expect("绩点/越界成绩有行内错误", bad.hasScoreError)
        let ok = GPACourse(creditsText: "3", scoreText: "90")
        expect("绩点/正常输入可换算", ok.gradePoint == 5.0)
    }

    // MARK: - 分页去重

    private static func checkPaginationDedup() {
        // for-you 的排序会随内容热度漂移，跨页出现重复 id 是现实场景。
        // 不去重时 ForEach 行为未定义，Android 上会直接抛 key 重复崩溃。
        let a = FeedItem(id: "1", title: "a", summary: "", sourceName: "s", category: .news,
                         tags: [], publishedAt: .now, originalURL: nil, score: 0,
                         isSelected: false, audience: CampusAudience())
        let b = FeedItem(id: "2", title: "b", summary: "", sourceName: "s", category: .news,
                         tags: [], publishedAt: .now, originalURL: nil, score: 0,
                         isSelected: false, audience: CampusAudience())
        let merged = Paging.merge(existing: [a, b], incoming: [b, a])
        expect("分页/追加去重", merged.count == 2, "实际 \(merged.count)")
        expect("分页/去重后顺序稳定", merged.map(\.id) == ["1", "2"])
    }

    // MARK: - slug 编码

    private static func checkSlugEncoding() {
        // 后端 `/api/site/docs/*` 是通配路由，slug 里的 `/` 是路径分隔符，
        // 编码掉会 404；中文必须编码。
        let slug = "survival/观点篇/1-认识"
        let encoded = slug.percentEncodedPath
        expect("slug/斜杠保留", encoded.contains("/"), "实际 \(encoded)")
        expect("slug/中文已编码", !encoded.contains("观"), "实际 \(encoded)")
        expect("slug/无空格等保留字符", !encoded.contains(" "))
        checkURLAssembly(encoded: encoded)
    }

    /// 防回归：曾经用 `URLComponents.path` 拼已编码的 slug，`%` 被二次转义成
    /// `%25`，**每一个**中文文档详情都 404，而且只在真机/模拟器点进去才看得见。
    /// 这里断言最终 URL 恰好编码一次。
    private static func checkURLAssembly(encoded: String) {
        let path = "/api/site/docs/\(encoded)"
        guard let base = URL(string: "https://seu.wiki") else { return }

        // 复现 FeedService.get 的正确写法。
        var good = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        good.percentEncodedPath = path
        // 对照：错误写法。
        var bad = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        bad.path = path

        let goodURL = good.url?.absoluteString ?? ""
        let badURL = bad.url?.absoluteString ?? ""
        expect("URL/中文恰好编码一次", goodURL.contains("%E8%A7%82"), "实际 \(goodURL)")
        expect("URL/无 %25 双重编码", !goodURL.contains("%25"), "实际 \(goodURL)")
        expect("URL/斜杠仍分段", goodURL.contains("/docs/survival/"), "实际 \(goodURL)")
        // 把错误写法的形态也钉住：万一有人「修回去」，这条会先炸。
        expect("URL/错误写法确实双重编码", badURL.contains("%25E8"), "实际 \(badURL)")
    }

    // MARK: - 后端字段契约

    /// 防回归：`DocDetailDTO` 一度写成 `outline`/`level`，而后端真实字段是
    /// **`headings`/`depth`**。字段名写错**不会抛错**——JSONDecoder 只是解成 nil，
    /// 于是目录永远空白，还查不出原因。这里拿一段真实响应做解码断言。
    private static func checkDocDetailContract() {
        // 取自 `GET /api/site/docs/survival/观点篇/1-认识` 的真实响应（截取相关字段）。
        let json = """
        {
          "slug": "survival/观点篇/1-认识",
          "kind": "survival",
          "title": "1 认识",
          "html": "<h2 id=\\"11-大学的定义\\">1.1 大学的定义</h2><p>正文</p>",
          "headings": [
            { "id": "11-大学的定义", "text": "1.1 大学的定义", "depth": 2 },
            { "text": "1.2 没有 `id` 的标题", "depth": 3 }
          ]
        }
        """
        guard let data = json.data(using: .utf8),
              let dto = try? JSONDecoder().decode(DocDetailDTO.self, from: data)
        else {
            expect("契约/docDetail 可解码", false, "字段名与后端不匹配")
            return
        }
        expect("契约/headings 非空", !dto.headings.isEmpty, "目录会是空的")
        expect("契约/depth 已解析", dto.headings.first?.depth == 2, "实际 \(String(describing: dto.headings.first?.depth))")
        expect("契约/id 已解析", dto.headings.first?.id == "11-大学的定义")
        // 缺 `id` / `depth` 的条目不能把整页拖崩。
        expect("契约/缺 id 仍能解码", dto.headings.count == 2, "实际 \(dto.headings.count)")
    }

    // MARK: - 画像指纹

    private static func checkProfileFingerprint() {
        let suite = "SelfCheckProfile"
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defer { defaults.removePersistentDomain(forName: suite) }

        let a = UserProfile(defaults: defaults)
        let before = a.profileFingerprint
        a.grade = "大四"
        let after = a.profileFingerprint
        // 后端把画像编进 for-you 的 cursor，画像一变指纹就必须变，
        // 否则旧 cursor 会被当成有效游标一直用下去，永远 400。
        expect("画像指纹/变化后不同", before != after)
        expect("画像指纹/相同画像稳定", a.profileFingerprint == after)
        expect("画像指纹/含学段", a.profileFingerprint.contains("grade="))
    }

    // MARK: - 对比度

    private static func checkContrast() {
        // 深色模式 accent 是 #34D6AB，早先在上面压白字只有 1.83:1（远低于 4.5:1）。
        let accent = (0x34 / 255.0, 0xD6 / 255.0, 0xAB / 255.0)
        let white = Color.WCAG.ratio(red1: 1, green1: 1, blue1: 1,
                                     red2: accent.0, green2: accent.1, blue2: accent.2)
        let darkInk = Color.WCAG.ratio(red1: 0, green1: 0x38 / 255.0, blue1: 0x2B / 255.0,
                                      red2: accent.0, green2: accent.1, blue2: accent.2)
        expect("对比度/白字压亮绿不达标（这正是原缺陷）", white < 4.5, "实测 \(String(format: "%.2f", white)):1")
        expect("对比度/深绿压亮绿达标", darkInk >= 4.5, "实测 \(String(format: "%.2f", darkInk)):1")

        // 亮色模式品牌色 #0E5A46 配白字必须达标。
        let brand = (0x0E / 255.0, 0x5A / 255.0, 0x46 / 255.0)
        let brandWhite = Color.WCAG.ratio(red1: 1, green1: 1, blue1: 1,
                                          red2: brand.0, green2: brand.1, blue2: brand.2)
        expect("对比度/白字压品牌绿达标", brandWhite >= 4.5, "实测 \(String(format: "%.2f", brandWhite)):1")
    }

    // MARK: - 提醒文案

    private static func checkReminderBadge() {
        let calendar = Calendar.current
        let now = Date.now
        func reminder(days: Int) -> CampusReminder {
            CampusReminder(
                title: "t",
                dueDate: calendar.date(byAdding: .day, value: days, to: now)!,
                advanceDays: 1
            )
        }
        // 过期提醒绝不能显示「今天」—— 那是明显错误的主张。
        expect("提醒/过期判定", reminder(days: -3).isExpired)
        expect("提醒/未过期判定", !reminder(days: 3).isExpired)
        // 只取未过期的那条。
        let profile = UserProfile(defaults: UserDefaults(suiteName: "SelfCheckReminders") ?? .standard)
        profile.reminders = [reminder(days: -5), reminder(days: 4), reminder(days: 2)]
        let next = profile.nextPendingReminder
        expect("提醒/主页取最近未过期", next?.dueDate == reminder(days: 2).dueDate)
        expect("提醒/过期条数正确", profile.expiredReminders.count == 1)
    }

    // MARK: - 持久化

    private static func checkPersistence() {
        expect("持久化/往返自检", ProfileStorage.runPersistenceSelfTest())
        expect("持久化/schema 版本已写入", ProfileStorage.storedVersion(for: .courses) >= 1)
    }
}
#endif
