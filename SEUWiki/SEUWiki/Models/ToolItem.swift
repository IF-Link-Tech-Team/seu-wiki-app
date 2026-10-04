import SwiftUI

/// 工具页入口卡片。
struct ToolItem: Identifiable, Hashable {
    let id: String
    var name: String
    var systemImage: String
    var tint: Color
    var subtitle: String
}
