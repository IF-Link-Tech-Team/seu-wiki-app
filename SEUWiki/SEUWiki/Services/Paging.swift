import Foundation

/// 分页合并的公共逻辑。
///
/// 抽出来是为了两件事共用同一份实现，并且可被 `SelfCheck` 直接验证：
/// 1. `FeedStore` 追加下一页时按 id 去重；
/// 2. `SearchStore` 追加搜索结果时按 id 去重。
///
/// **为什么必须去重**：timeline 与 pool 的排序都会随内容热度、时间衰减漂移，
/// 同一条内容出现在相邻两页是现实场景。不去重时，SwiftUI 的 `ForEach` 行为未定义；
/// 同样的数据在 Android 的 `LazyColumn` 上会抛 `Key was already used` 直接崩溃。
enum Paging {
    /// 把 `incoming` 追加到 `existing` 之后，跳过 id 已存在的条目。
    /// 保持既有顺序不变。
    static func merge<Item: Identifiable>(existing: [Item], incoming: [Item]) -> [Item] where Item.ID: Hashable {
        var seen = Set(existing.map(\.id))
        return existing + incoming.filter { seen.insert($0.id).inserted }
    }

    /// 对一个序列整体去重（保留首次出现）。
    static func distinct<Item: Identifiable>(_ items: [Item]) -> [Item] where Item.ID: Hashable {
        var seen = Set<Item.ID>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
