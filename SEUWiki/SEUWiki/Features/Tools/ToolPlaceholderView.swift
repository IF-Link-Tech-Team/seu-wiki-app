import SwiftUI

/// 尚未实现工具的占位详情页：大号工具图标 + 名称 + 「功能开发中」说明。
struct ToolPlaceholderView: View {
    let tool: ToolItem

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 18) {
                ToolIconSquare(tool: tool, size: 88)
                Text(tool.name)
                    .font(.title2.weight(.bold))
            }
        } description: {
            Text("\(tool.subtitle) · 功能开发中，敬请期待")
        }
        .groupedBackground()
        .navigationTitle(tool.name)
    }
}

#Preview {
    NavigationStack {
        ToolPlaceholderView(tool: ToolCatalog.all[1])
    }
}
