import Foundation

/// **只用于 SwiftUI Preview 与 Debug 的开发样例数据。**
///
/// 结构对齐 seu-wiki-v2 与 iflab-forum 的真实 API，但内容全是编造的
/// （虚构作者「林晚舟」、虚构的 1893 赞 / 342 评论等）。
///
/// 生产路径**不允许**引用本类型：它以前叫 `MockData`，而且被当成了真实数据直接
/// 展示给用户 —— 首次启动就把编造的提醒和课表写进了 UserDefaults，搜索失败时
/// 静默回退到它。现在真数据全部走 `/api/site/*`，这里只服务预览。
/// 验收方式：`grep -rn "PreviewSample" --include=*.swift . | grep -v "#Preview"`
/// 应当只在注释里命中。
enum PreviewSample {

    static let feedItems: [FeedItem] = [
        FeedItem(
            id: "f1",
            title: "2026 年推荐优秀应届本科毕业生免试攻读研究生工作启动",
            summary: "各学院推免名额已下达，10 月 12 日前完成个人申请与材料提交，教务处将组织校级审核与公示。",
            sourceName: "教务处",
            category: .academic,
            tags: ["保研", "推免"],
            publishedAt: .now.addingTimeInterval(-3600 * 3),
            originalURL: URL(string: "https://jwc.seu.edu.cn"),
            score: 92,
            isSelected: true,
            audience: CampusAudience(identities: ["本科生"], colleges: ["全校"], grades: ["大四"], deadline: .now.addingTimeInterval(86400 * 8), valueTier: .action),
            matchReasons: ["你的学段", "即将截止"]
        ),
        FeedItem(
            id: "f2",
            title: "信息科学与工程学院 SRTP 项目中期检查安排",
            summary: "2025 年立项的校级以上 SRTP 项目须于 10 月 20 日前提交中期报告，学院将组织分组答辩。",
            sourceName: "信息科学与工程学院",
            category: .competition,
            tags: ["SRTP", "科研训练"],
            publishedAt: .now.addingTimeInterval(-3600 * 7),
            originalURL: URL(string: "https://radio.seu.edu.cn"),
            score: 85,
            isSelected: true,
            audience: CampusAudience(identities: ["本科生"], colleges: ["信息科学与工程学院"], grades: ["大二", "大三"], deadline: .now.addingTimeInterval(86400 * 16), valueTier: .action),
            matchReasons: ["你的学院", "你的兴趣"]
        ),
        FeedItem(
            id: "f3",
            title: "2026 年春季学期校级交换生项目（第一批）报名通知",
            summary: "覆盖加州伯克利、慕尼黑工大等 23 所合作院校，雅思 6.5 / 托福 90 以上可申报，11 月 3 日截止。",
            sourceName: "国际合作处",
            category: .exchange,
            tags: ["交换", "留学"],
            publishedAt: .now.addingTimeInterval(-86400),
            originalURL: URL(string: "https://cie.seu.edu.cn"),
            score: 78,
            isSelected: true,
            audience: CampusAudience(identities: ["本科生", "硕士生"], colleges: ["全校"], grades: [], deadline: .now.addingTimeInterval(86400 * 30), valueTier: .opportunity),
            matchReasons: ["你的兴趣"]
        ),
        FeedItem(
            id: "f4",
            title: "国家奖学金、校长奖学金评审结果公示",
            summary: "2025—2026 学年国家奖学金拟获奖名单公示，公示期 5 个工作日，异议请实名向学生处反映。",
            sourceName: "学生处",
            category: .aid,
            tags: ["奖学金", "公示"],
            publishedAt: .now.addingTimeInterval(-86400 * 1.5),
            originalURL: URL(string: "https://xsc.seu.edu.cn"),
            score: 70,
            isSelected: false,
            audience: CampusAudience(identities: [], colleges: ["全校"], grades: [], deadline: nil, valueTier: .news)
        ),
        FeedItem(
            id: "f5",
            title: "九龙湖校区体育馆羽毛球场地预约规则调整",
            summary: "10 月 9 日起预约开放时间由提前 3 天调整为提前 7 天，每日 12:00 统一放号。",
            sourceName: "体育系",
            category: .life,
            tags: ["场馆预约"],
            publishedAt: .now.addingTimeInterval(-86400 * 2),
            originalURL: URL(string: "https://tyx.seu.edu.cn"),
            score: 55,
            isSelected: false,
            audience: CampusAudience(identities: [], colleges: ["全校"], grades: [], deadline: nil, valueTier: .news)
        ),
        FeedItem(
            id: "f6",
            title: "「挑战杯」全国大学生课外学术科技作品竞赛校内选拔赛启动",
            summary: "校赛设自然科学类、科技发明制作类、哲学社会科学类三条赛道，10 月 30 日前完成院级推荐。",
            sourceName: "校团委",
            category: .competition,
            tags: ["挑战杯", "竞赛"],
            publishedAt: .now.addingTimeInterval(-86400 * 2.5),
            originalURL: URL(string: "https://tw.seu.edu.cn"),
            score: 80,
            isSelected: true,
            audience: CampusAudience(identities: ["本科生"], colleges: ["全校"], grades: [], deadline: .now.addingTimeInterval(86400 * 26), valueTier: .opportunity),
            matchReasons: ["你的兴趣"]
        ),
        FeedItem(
            id: "f7",
            title: "图书馆研讨间系统升级，新增静音舱预约",
            summary: "李文正图书馆 4 层新增 12 个静音舱，支持线上面试场景，每次最长可约 2 小时。",
            sourceName: "图书馆",
            category: .life,
            tags: ["图书馆"],
            publishedAt: .now.addingTimeInterval(-86400 * 3),
            originalURL: URL(string: "https://lib.seu.edu.cn"),
            score: 62,
            isSelected: false,
            audience: CampusAudience(identities: [], colleges: ["全校"], grades: [], deadline: nil, valueTier: .news)
        ),
        FeedItem(
            id: "f8",
            title: "2026 届毕业生秋季校园招聘会（信息技术专场）参会单位名单",
            summary: "华为、中兴、中国电科等 86 家单位参会，10 月 15 日九龙湖校区焦廷标馆，需提前报名入场。",
            sourceName: "就业指导中心",
            category: .career,
            tags: ["秋招", "招聘会"],
            publishedAt: .now.addingTimeInterval(-86400 * 3.5),
            originalURL: URL(string: "https://job.seu.edu.cn"),
            score: 76,
            isSelected: true,
            audience: CampusAudience(identities: ["本科生", "硕士生"], colleges: [], grades: ["大四"], deadline: .now.addingTimeInterval(86400 * 11), valueTier: .opportunity),
            matchReasons: ["你的学段"]
        ),
        FeedItem(
            id: "f9",
            title: "研究生数学建模竞赛颁奖暨经验分享会",
            summary: "全国一等奖团队「无线通信小分队」将分享选题与论文写作经验，10 月 11 日晚 19:00 四牌楼校区。",
            sourceName: "研究生院",
            category: .club,
            tags: ["数学建模", "讲座"],
            publishedAt: .now.addingTimeInterval(-86400 * 4),
            originalURL: URL(string: "https://gs.seu.edu.cn"),
            score: 58,
            isSelected: false,
            audience: CampusAudience(identities: [], colleges: ["全校"], grades: [], deadline: nil, valueTier: .news)
        ),
        FeedItem(
            id: "f10",
            title: "关于 2025 级新生大学英语分级考试成绩查询的通知",
            summary: "分级考试成绩已发布，考生可登录教务系统查询，免修申请同步开放至 10 月 10 日。",
            sourceName: "外国语学院",
            category: .academic,
            tags: ["考试", "成绩查询"],
            publishedAt: .now.addingTimeInterval(-86400 * 5),
            originalURL: URL(string: "https://flc.seu.edu.cn"),
            score: 66,
            isSelected: false,
            audience: CampusAudience(identities: ["本科生"], colleges: ["全校"], grades: ["大一"], deadline: .now.addingTimeInterval(86400 * 6), valueTier: .action)
        ),
    ]

    static let reminders: [CampusReminder] = [
        CampusReminder(title: "推免申请材料提交截止", dueDate: .now.addingTimeInterval(86400 * 8), advanceDays: 2, note: "成绩单、排名证明、科研成果复印件各两份", relatedItemID: "f1"),
        CampusReminder(title: "SRTP 中期报告提交", dueDate: .now.addingTimeInterval(86400 * 16), advanceDays: 3, note: "", relatedItemID: "f2"),
    ]

    static let courses: [Course] = [
        Course(name: "信号与系统", teacher: "张教授", location: "教二-203", weekday: 7, startHour: 10, startMinute: 0, endHour: 11, endMinute: 40),
        Course(name: "数字信号处理", teacher: "李教授", location: "教四-105", weekday: 7, startHour: 14, startMinute: 0, endHour: 15, endMinute: 40),
        Course(name: "机器学习导论", teacher: "王教授", location: "计软楼-301", weekday: 1, startHour: 8, startMinute: 0, endHour: 9, endMinute: 40),
    ]

}
