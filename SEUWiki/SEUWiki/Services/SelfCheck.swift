import Foundation
import SwiftUI
import UIKit

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
        checkReminderNotification()
        checkReminderFireDate()
        checkSFSymbols()
        checkForumTagCatalog()
        checkForumDateParsing()
        checkForumPostContract()
        checkPersistence()
        let snapshot = results
        let failed = snapshot.filter { !$0.passed }
        if failed.isEmpty {
            NSLog("[SelfCheck] 全部 %d 项通过", snapshot.count)
        } else {
            NSLog("[SelfCheck] %d/%d 项失败：%@", failed.count, snapshot.count,
                  failed.map(\.name).joined(separator: ", "))
        }
        writeReport(snapshot)
        return snapshot
    }

    /// 自检报告落盘。
    ///
    /// `NSLog` 在模拟器上取不出来：`log show` 匹配不到，`simctl launch --console-pty`
    /// 也接不到（这个工程的构建产物走的是索引目录，`console-pty` 那条路在这里是断的）。
    /// 于是「自检到底跑了没有、过了几条」只能靠肉眼看控制台，等于没法验证。
    /// 写到 Documents 下，宿主侧直接读文件就能确认。
    private static func writeReport(_ snapshot: [Result]) {
        let failed = snapshot.filter { !$0.passed }
        var lines = ["\(snapshot.count - failed.count)/\(snapshot.count) 通过"]
        lines += snapshot.map { r in
            r.passed ? "PASS  \(r.name)" : "FAIL  \(r.name) — \(r.detail ?? "")"
        }
        write(lines.joined(separator: "\n"))
    }

    private static func write(_ text: String) {
        guard let dir = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask).first else { return }
        try? text.write(to: dir.appendingPathComponent("selfcheck.txt"),
                        atomically: true, encoding: .utf8)
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

    // MARK: - 通知深链

    /// 提醒通知的 `userInfo` 与占位条目。
    ///
    /// 这条链路上出错的代价全是**静默**的：key 拼错 → 点了通知什么都不发生；
    /// 占位条目编了标题 → 通知深链进来显示一条内容对不上的假资讯。
    /// 两者编译期都查不出来，只能靠自检。
    private static func checkReminderNotification() {
        let key = NotificationCenterDelegate.feedItemIDKey

        // 有关联资讯时必须带上，且值要原样对上。
        let linked = ReminderScheduler.userInfo(id: "seuwiki-reminder-ABC", relatedItemID: "item-42")
        expect("通知/userInfo 带关联资讯 id", (linked[key] as? String) == "item-42", "实际 \(linked)")
        expect("通知/userInfo 保留 reminder id", (linked["reminderID"] as? String) == "seuwiki-reminder-ABC")

        // 没有关联资讯时不要塞空串 —— 排查时要能区分「本来就没有」和「关联丢了」。
        let unlinked = ReminderScheduler.userInfo(id: "seuwiki-reminder-XYZ", relatedItemID: nil)
        expect("通知/无关联时不塞空 key", unlinked[key] == nil, "实际 \(unlinked)")
        expect("通知/空串关联视为无关联",
               ReminderScheduler.userInfo(id: "r", relatedItemID: "")[key] == nil)

        // 空 id / 全空白 id 都必须被挡掉：空 id 会让详情页拿空串去请求接口。
        expect("通知/空白 id 不放行",
               NotificationCenterDelegate.feedItemID(from: [key: "   "]) == nil)
        expect("通知/缺失 id 不放行",
               NotificationCenterDelegate.feedItemID(from: ["reminderID": "r"]) == nil)
        expect("通知/带空白 id 正常解析",
               NotificationCenterDelegate.feedItemID(from: [key: " item-42 "]) == "item-42")

        // 前台必须有横幅。返回 `[]` 或只有 `.badge` 正是本 bug 的成因，
        // 没有任何编译期或运行期错误提示，只能靠自检锁住。
        expect("通知/前台弹横幅",
               NotificationCenterDelegate.foregroundPresentation.contains(.banner))
        expect("通知/前台有声",
               NotificationCenterDelegate.foregroundPresentation.contains(.sound))

        // 占位条目：id 正确，且**不编造**任何用户可见内容。
        let placeholder = FeedItem.placeholder(id: "item-42")
        expect("通知/占位条目 id 正确", placeholder.id == "item-42")
        expect("通知/占位条目不编造标题", placeholder.title.isEmpty)
        expect("通知/占位条目不编造摘要", placeholder.summary.isEmpty)
        expect("通知/占位条目不编造来源", placeholder.sourceName.isEmpty)
    }

    /// 提醒触发时刻的算法。
    ///
    /// 盯的是两件容易回归的事：提醒时间必须是 09:00（不是截止时刻本身），
    /// 以及往前推天数必须走日历而不是减 86400 秒（夏令时那天会差一小时）。
    private static func checkReminderFireDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        func parts(_ date: Date) -> (Int, Int, Int, Int, Int) {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            return (c.year!, c.month!, c.day!, c.hour!, c.minute!)
        }

        // 2026-10-20 14:30 截止，提前 3 天 → 2026-10-17 09:00。
        let deadline = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 14, minute: 30))!
        let three = ReminderScheduler.fireDate(deadline: deadline, advanceDays: 3, calendar: calendar)!
        expect("提醒时刻/提前 3 天", parts(three) == (2026, 10, 17, 9, 0), "实际 \(parts(three))")

        // 提前 0 天 = 截止当天 09:00，而不是截止时刻 14:30。
        let sameDay = ReminderScheduler.fireDate(deadline: deadline, advanceDays: 0, calendar: calendar)!
        expect("提醒时刻/当天 9 点而非截止时刻", parts(sameDay) == (2026, 10, 20, 9, 0), "实际 \(parts(sameDay))")

        // 负数提前量当成 0，绝不往截止日之后排。
        let negative = ReminderScheduler.fireDate(deadline: deadline, advanceDays: -5, calendar: calendar)!
        expect("提醒时刻/负提前量夹到 0", parts(negative) == (2026, 10, 20, 9, 0), "实际 \(parts(negative))")

        // 夏令时回归：America/New_York 2026-11-01 夏令时结束（凌晨回拨一小时）。
        // 截止 2026-11-01 09:00，提前 1 天必须是 2026-10-31 **09:00**；
        // 「减 86400 秒」会算成 08:00，提醒就早一小时。
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let dstDeadline = ny.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!
        let dstFire = ReminderScheduler.fireDate(deadline: dstDeadline, advanceDays: 1, calendar: ny)!
        let nyParts = ny.dateComponents([.year, .month, .day, .hour], from: dstFire)
        expect("提醒时刻/跨夏令时仍是 9 点",
               nyParts.year == 2026 && nyParts.month == 10 && nyParts.day == 31 && nyParts.hour == 9,
               "实际 \(nyParts)")
    }

    // MARK: - SF Symbol 有效性

    /// 工程里用到的**全部** SF Symbol 名。
    ///
    /// 这份清单是照着源码全量扫出来的（`systemName:` / `systemImage:` 字面量，
    /// 加上三元表达式里的两个分支）。**新增图标时要往这里加一行**，
    /// 否则自检验不到 —— 这是刻意的：让「加了图标忘了验」变成一件看得见的事。
    private static let usedSFSymbols = [
        "airplane", "arrow.triangle.branch", "bell", "bell.badge", "bell.fill", "bell.slash",
        "book", "book.closed", "book.closed.fill", "bookmark", "bookmark.fill",
        "books.vertical", "books.vertical.fill", "briefcase", "bubble.left",
        "bubble.left.and.text.bubble.right", "building.2", "bus",
        "calendar.badge.checkmark", "calendar.day.timeline.left", "checklist", "checkmark",
        "chevron.right", "circle.lefthalf.filled", "clock.badge.exclamationmark", "creditcard",
        "doc.text", "exclamationmark.triangle", "eye", "figure.walk.arrival", "flame.fill", "flask",
        "graduationcap", "graduationcap.circle", "graduationcap.circle.fill", "graduationcap.fill",
        "heart", "heart.fill", "house", "info.circle", "leaf",
        "line.3.horizontal.decrease.circle", "line.3.horizontal.decrease.circle.fill",
        "link", "link.circle.fill", "list.bullet.indent", "lock.shield", "map", "mappin",
        "newspaper", "paperplane.fill", "pencil.and.list.clipboard", "percent", "person",
        "person.2.badge.gearshape", "person.crop.circle", "person.crop.circle.fill",
        "photo", "pin.fill", "plus", "plus.circle.fill", "safari",
        "square.and.pencil", "square.grid.2x2", "square.stack.3d.up.fill",
        "star.fill", "tag", "text.book.closed", "tram", "trash", "trophy",
        "wifi.exclamationmark", "wifi.slash", "xmark.circle", "yensign.circle",
    ]

    private static func checkSFSymbols() {
        // `Image(systemName:)` 拿到不认识的名字**不报错**，只是画一个空白 —— 没有
        // 编译错误、没有运行时异常，构建照样全绿。SF Symbols 又是随系统版本增补的，
        // 在低版本上写高版本的符号名尤其容易中招。
        //
        // 安卓端对应的那条断言是在模拟器截图里发现「收藏按钮渲染成九宫格」之后补的
        // （`SeuIcons` 兜底成了一个语义完全不相干的图形）。iOS 这边兜底是空白，
        // 一样只有肉眼能发现，所以在这里用 `UIImage(systemName:)` 直接验一遍。
        //
        // 这里刻意**不去扫源码目录**：早先试过从 `#file` 反推源码根再遍历，结果
        // `#file` 在这套构建配置下是相对路径，删两级退化成 `/`，自检就在
        // `App.init` 里遍历整个文件系统 —— App 直接白屏起不来。模拟器里的 App
        // 本来也不该去读开发机的源码树。
        expect("SF Symbol/清单非空", !usedSFSymbols.isEmpty)
        for name in usedSFSymbols {
            expect("SF Symbol/\(name)", UIImage(systemName: name) != nil,
                   "在当前系统（iOS \(ProcessInfo.processInfo.operatingSystemVersionString)）上不存在，会渲染成空白")
        }
    }

    // MARK: - 论坛标签目录

    /// 发帖与板块筛选的标签来自这份内嵌目录，它与论坛后端
    /// `src/lib/tags/catalog.mjs` 是**同一份数据的两份拷贝**：后端目录变了而这里
    /// 没跟上，用户就会发出一个后端拒收的标签（400）。结构完整性在这里钉住，
    /// 与后端逐 slug 的对账只能人工做（目录变动频率很低）。
    private static func checkForumTagCatalog() {
        let topics = ForumTagCatalog.topics
        expect("论坛标签/8 个主题", topics.count == 8, "实际 \(topics.count)")
        let children = topics.flatMap(\.children)
        expect("论坛标签/29 个子标签", children.count == 29, "实际 \(children.count)")

        let allSlugs = ForumTagCatalog.allTags.map(\.slug)
        expect("论坛标签/37 个 slug", allSlugs.count == 37, "实际 \(allSlugs.count)")
        expect("论坛标签/slug 无重复", Set(allSlugs).count == allSlugs.count,
               "重复：\(allSlugs.filter { s in allSlugs.filter { $0 == s }.count > 1 })")

        // slug 会进 URL query 与后端校验正则，形态必须稳定。
        let pattern = #"^[a-z0-9][a-z0-9-]{0,39}$"#
        let invalid = allSlugs.filter { $0.range(of: pattern, options: .regularExpression) == nil }
        expect("论坛标签/slug 形态合法", invalid.isEmpty, "非法：\(invalid)")

        expect("论坛标签/中文名非空", ForumTagCatalog.allTags.allSatisfy { !$0.name.isEmpty })
        expect("论坛标签/名称可查", ForumTagCatalog.name(for: "baoyan") == "保研")
        expect("论坛标签/未知 slug 返回 nil", ForumTagCatalog.name(for: "not-a-tag") == nil)
        expect("论坛标签/每帖上限 3", ForumTagCatalog.maxPostTags == 3)
    }

    // MARK: - 论坛日期解析

    private static func checkForumDateParsing() {
        // 论坛时间戳是 PostgREST 序列化的 timestamptz：**6 位微秒 + 数字时区**。
        // DateFormatter 的 `.SSS` 只认 3 位毫秒，直接解析必失败 → 帖子的
        // 时间与置顶标记会静默变 nil。`parseForum` 先截断再解析。
        let micros = DateParser.parseForum("2026-10-07T04:47:20.123456+00:00")
        expect("论坛日期/6 位微秒可解析", micros != nil)
        expect("论坛日期/3 位毫秒可解析", DateParser.parseForum("2026-10-07T04:47:20.123+00:00") != nil)
        expect("论坛日期/Z 结尾可解析", DateParser.parseForum("2026-10-07T04:47:20Z") != nil)
        expect("论坛日期/nil 输入返回 nil", DateParser.parseForum(nil) == nil)
        expect("论坛日期/非法输入返回 nil", DateParser.parseForum("not-a-date") == nil)
    }

    // MARK: - 论坛字段契约

    /// 与 `checkDocDetailContract` 同理由：论坛 DTO 全是 snake_case + CodingKeys，
    /// 字段名写错**不会报错**，只会静默解成 nil（作者名消失、计数归零）。
    /// 这里拿一段按仓库路由代码构造的真实形态响应做解码断言。
    private static func checkForumPostContract() {
        let json = """
        {
          "id": "5f2c0a2e-0000-4000-8000-000000000001",
          "title": "保研时间线复盘",
          "content": "正文",
          "post_type": "normal",
          "created_at": "2026-10-07T04:47:20.123456+00:00",
          "likes_count": 12,
          "comments_count": 3,
          "views_count": 45,
          "pinned_at": "2026-10-07T05:00:00+00:00",
          "author": {
            "id": "u1",
            "display_name": "林同学",
            "username": "lin",
            "avatar_url": "https://forum.seu.wiki/api/media/a.png"
          },
          "images": [{ "id": "i1", "asset_url": "/api/media/x.png", "mime_type": "image/png", "sort_order": 0 }],
          "tags": [{ "id": "t1", "name": "保研", "slug": "baoyan" }],
          "bookmarked": false
        }
        """
        guard let data = json.data(using: .utf8),
              let dto = try? JSONDecoder().decode(ForumPostDTO.self, from: data)
        else {
            expect("契约/forumPost 可解码", false, "字段名与后端不匹配")
            return
        }
        let post = dto.post
        expect("契约/帖子计数已解析", post.likesCount == 12 && post.commentsCount == 3 && post.viewsCount == 45,
               "实际 \(post.likesCount)/\(post.commentsCount)/\(post.viewsCount)")
        expect("契约/帖子作者已解析", post.author?.displayName == "林同学",
               "实际 \(String(describing: post.author?.displayName))")
        expect("契约/帖子图片相对路径已解析", post.imagePaths == ["/api/media/x.png"],
               "实际 \(post.imagePaths)")
        expect("契约/帖子标签已解析", post.tags.map(\.slug) == ["baoyan"])
        expect("契约/帖子置顶时间已解析", post.isPinned)
        expect("契约/帖子创建时间已解析（微秒）", post.createdAt != nil)
        expect("契约/书签标记已解析", dto.bookmarked == false)

        // 无标题是合法形态（后端 title 可空），卡片用正文节选兜底。
        let noTitleJSON = """
        { "id": "p2", "title": null, "content": "只有正文的帖子" }
        """
        if let data2 = noTitleJSON.data(using: .utf8),
           let dto2 = try? JSONDecoder().decode(ForumPostDTO.self, from: data2) {
            expect("契约/无标题帖子 headline 回退正文", dto2.post.headline == "只有正文的帖子",
                   "实际 \(dto2.post.headline)")
        } else {
            expect("契约/无标题帖子可解码", false)
        }

        // 手册文章摘要的契约（板块列表与搜索命中共用）。
        let articleJSON = """
        {
          "id": "a1",
          "tag_slug": "baoyan",
          "title": "推免政策解读",
          "author_display": "编辑部",
          "published_at": "2026-10-07T04:47:20.123456+00:00",
          "source_post": { "id": "p1", "title": "原帖" }
        }
        """
        guard let articleData = articleJSON.data(using: .utf8),
              let articleDTO = try? JSONDecoder().decode(HandbookArticleSummaryDTO.self, from: articleData)
        else {
            expect("契约/手册文章摘要可解码", false, "字段名与后端不匹配")
            return
        }
        let article = articleDTO.summary
        expect("契约/手册文章字段已解析",
               article.tagSlug == "baoyan" && article.authorDisplay == "编辑部" && article.sourcePost?.id == "p1",
               "实际 \(article.tagSlug)/\(String(describing: article.authorDisplay))")
        expect("契约/手册文章时间已解析（微秒）", article.publishedAt != nil)
    }

    // MARK: - 持久化

    private static func checkPersistence() {
        expect("持久化/往返自检", ProfileStorage.runPersistenceSelfTest())
        expect("持久化/schema 版本已写入", ProfileStorage.storedVersion(for: .courses) >= 1)
    }
}
#endif
