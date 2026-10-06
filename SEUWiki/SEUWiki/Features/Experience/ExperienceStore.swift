import Foundation

/// 「经验」模块的数据仓库：生存手册目录 + 经验长文索引。
///
/// 两个信源都来自 `seu-wiki-v2` 的 `/api/site/docs/*`（真实内容）。
/// 论坛 UGC（发帖、点赞、评论、关注）**尚未接通** —— `seu-wiki-forum` 已有完整
/// HTTP API（34 个路由）并已部署到 iflink-prod，但本 App 还没有论坛客户端：
/// 公网域名与 Logto 应用注册未完成，「经验」模块当前接的是 seu-wiki-v2 的
/// 文档接口。相关入口一律显示「即将上线」并去掉占位数字，不做假内容。
@Observable
@MainActor
final class ExperienceStore {
    private let client: FeedAPIClient

    var handbook: HandbookIndex?
    var experience: ExperienceIndex?

    var isLoadingHandbook = false
    var isLoadingExperience = false
    var handbookError: String?
    var experienceError: String?

    /// 话题广场选中的分面：`category` / `grade` / `college` → 选中的值。
    var selectedFacets: [String: Set<String>] = [:]

    init(client: FeedAPIClient = FeedAPIClient()) {
        self.client = client
    }

    // MARK: - 生存手册

    func loadHandbook() async {
        guard handbook == nil, !isLoadingHandbook else { return }
        isLoadingHandbook = true
        handbookError = nil
        defer { isLoadingHandbook = false }
        do {
            handbook = try await client.survivalIndex()
        } catch {
            handbookError = "手册加载失败：\(error.localizedDescription)"
        }
    }

    /// 手册条目总数，用于分类行的「N 篇」。
    func entryCount(of part: HandbookIndex.Part) -> Int {
        part.groups.reduce(0) { $0 + $1.items.count }
    }

    // MARK: - 经验长文

    func loadExperience() async {
        guard experience == nil, !isLoadingExperience else { return }
        isLoadingExperience = true
        experienceError = nil
        defer { isLoadingExperience = false }
        await fetchExperience()
    }

    /// 分面变化后重新拉取（后端支持按 category/grade/college 过滤）。
    func reloadExperience() async {
        isLoadingExperience = true
        experienceError = nil
        await fetchExperience()
    }

    private func fetchExperience() async {
        defer { isLoadingExperience = false }
        do {
            experience = try await client.experienceIndex(
                categories: values(for: "category"),
                grades: values(for: "grade"),
                colleges: values(for: "college")
            )
        } catch {
            experienceError = "经验加载失败：\(error.localizedDescription)"
        }
    }

    private func values(for key: String) -> [String] {
        (selectedFacets[key] ?? []).sorted()
    }

    func toggle(_ value: String, inFacet key: String) {
        var current = selectedFacets[key] ?? []
        if current.contains(value) { current.remove(value) } else { current.insert(value) }
        selectedFacets[key] = current.isEmpty ? nil : current
    }

    func isSelected(_ value: String, inFacet key: String) -> Bool {
        selectedFacets[key]?.contains(value) == true
    }

    var hasActiveFacets: Bool {
        selectedFacets.values.contains { !$0.isEmpty }
    }

    func clearFacets() {
        selectedFacets = [:]
    }
}
