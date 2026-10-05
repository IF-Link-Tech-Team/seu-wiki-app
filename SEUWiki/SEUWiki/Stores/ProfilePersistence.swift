import Foundation

/// UserProfile 的轻量持久化层：UserDefaults(.standard) + JSONEncoder/Decoder。
/// 数据量小（画像、提醒、课表、两个 ID 集合），直接同步写即可。
enum ProfileStorage {
    /// 首次启动后写入的初始化标记；存在则表示已从默认值过渡到用户态。
    static let initializedKey = "profile.initialized"

    enum Key: String, CaseIterable {
        case college = "profile.college"
        case degree = "profile.degree"
        case grade = "profile.grade"
        case interests = "profile.interests"
        case reminders = "profile.reminders"
        case courses = "profile.courses"
        case followedTopicIDs = "profile.followedTopicIDs"
        case bookmarkedSlugs = "profile.bookmarkedSlugs"
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    static func isInitialized(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: initializedKey)
    }

    static func markInitialized(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: initializedKey)
    }

    static func save(_ value: some Encodable, for key: Key, defaults: UserDefaults = .standard) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key.rawValue)
    }

    static func load<T: Decodable>(_ type: T.Type, for key: Key, defaults: UserDefaults = .standard) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    /// 清空所有 profile 相关 key（含初始化标记）。
    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: initializedKey)
        for key in Key.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    #if DEBUG
    /// 往返编码自检：用独立 suite 验证 UUID/Date/DateComponents/Set<String> 无损。
    /// 返回 true 表示全部通过；失败项会 print 到控制台。
    @discardableResult
    static func runPersistenceSelfTest() -> Bool {
        guard let suite = UserDefaults(suiteName: "ProfilePersistenceSelfTest") else {
            print("[ProfileStorage] self-test: failed to create suite")
            return false
        }
        defer {
            suite.removePersistentDomain(forName: "ProfilePersistenceSelfTest")
        }

        var ok = true
        func check(_ label: String, _ condition: Bool) {
            if !condition {
                ok = false
                print("[ProfileStorage] self-test FAILED: \(label)")
            }
        }

        // CampusReminder：UUID + Date + Optional<String>
        let reminder = CampusReminder(title: "自测提醒", dueDate: Date(timeIntervalSince1970: 1_800_000_000.5), advanceDays: 2, note: "n", relatedItemID: "f1")
        save([reminder], for: .reminders, defaults: suite)
        let loadedReminders = load([CampusReminder].self, for: .reminders, defaults: suite)
        check("reminder round-trip", loadedReminders == [reminder])

        // Course：UUID + DateComponents(hour/minute)
        let course = Course(name: "自测课", teacher: "t", location: "l", weekday: 3, startHour: 8, startMinute: 30, endHour: 10, endMinute: 10)
        save([course], for: .courses, defaults: suite)
        let loadedCourses = load([Course].self, for: .courses, defaults: suite)
        check("course round-trip", loadedCourses == [course])

        // Set<String>
        let ids: Set<String> = ["baoyan", "srtp", "竞赛"]
        save(ids, for: .followedTopicIDs, defaults: suite)
        let loadedIDs = load(Set<String>.self, for: .followedTopicIDs, defaults: suite)
        check("set round-trip", loadedIDs == ids)

        // 空数组/空集合边界
        let empty: Set<String> = []
        save(empty, for: .bookmarkedSlugs, defaults: suite)
        check("empty set round-trip", load(Set<String>.self, for: .bookmarkedSlugs, defaults: suite) == empty)

        // reset 清空
        ProfileStorage.reset(defaults: suite)
        check("reset clears keys", load(Set<String>.self, for: .followedTopicIDs, defaults: suite) == nil)

        print("[ProfileStorage] self-test \(ok ? "passed" : "FAILED")")
        return ok
    }
    #endif
}
