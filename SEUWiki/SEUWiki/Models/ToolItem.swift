import SwiftUI

/// 工具页入口卡片。
///
/// `isAvailable` 用来区分**已实现**和**占位**：早期版本 8 个工具里 6 个只是界面，
/// 副标题却写得像已经能用（「借阅与研讨间」「余额与流水」），用户点进去才发现是空页。
/// 现在占位工具会显式带「即将推出」标识，副标题也改成说明它将做什么。
struct ToolItem: Identifiable, Hashable {
    let id: String
    var name: String
    var systemImage: String
    var tint: Color
    /// 已实现时写实际能力（如「五分制换算」）；占位时写规划中的能力。
    var subtitle: String
    /// false 时界面必须标注「即将推出」，且不可点进。
    var isAvailable: Bool = true
}

/// 工具目录：App 自身的静态配置，不是演示数据。
///
/// 这里曾经是 `PreviewSample.tools`。工具入口是产品定义、不是「假内容」，但混在
/// `MockData` 里会让人分不清哪些是演示数据 —— 而且 CI 的红线是「release 构建里
/// 出现 MockData 引用就失败」，所以必须搬出来。
enum ToolCatalog {
    static let all: [ToolItem] = [
        ToolItem(id: "timetable", name: "课表", systemImage: "calendar.day.timeline.left",
                 tint: .blue, subtitle: "周视图与课程编辑", isAvailable: true),
        ToolItem(id: "gpa", name: "绩点计算", systemImage: "percent",
                 tint: .green, subtitle: "五分制换算", isAvailable: true),
        ToolItem(id: "exam", name: "考试安排", systemImage: "pencil.and.list.clipboard",
                 tint: .orange, subtitle: "接入教务后展示期末与补考安排", isAvailable: false),
        ToolItem(id: "library", name: "图书馆", systemImage: "books.vertical",
                 tint: .purple, subtitle: "借阅记录与研讨间预约", isAvailable: false),
        ToolItem(id: "card", name: "校园卡", systemImage: "creditcard",
                 tint: .pink, subtitle: "卡余额与消费流水", isAvailable: false),
        ToolItem(id: "bus", name: "班车时刻", systemImage: "bus",
                 tint: .teal, subtitle: "四牌楼 · 四江院 · 九龙湖班车", isAvailable: false),
        ToolItem(id: "map", name: "校园地图", systemImage: "map",
                 tint: .mint, subtitle: "教学楼与场馆导航", isAvailable: false),
        ToolItem(id: "elective", name: "选课助手", systemImage: "checklist",
                 tint: .indigo, subtitle: "课程评价与避雷参考", isAvailable: false),
    ]
}
