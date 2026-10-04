import SwiftUI

/// 工具图标：tool.tint 渐变圆角方块内的白色 SF Symbol。
/// 网格卡片与占位详情页共用，尺寸随 size 等比缩放。
struct ToolIconSquare: View {
    let tool: ToolItem
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: tool.systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [tool.tint, tool.tint.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: size * 0.27, style: .continuous)
            )
    }
}

/// 「快捷指令」资料库风格卡片：图标方块 + 工具名 + 副标题，
/// 底色为二级分组底色上叠一层 tool.tint 浅色调，深浅色模式各自协调。
struct ToolCard: View {
    let tool: ToolItem
    var subtitle: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToolIconSquare(tool: tool)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle ?? tool.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(tool.tint.opacity(colorScheme == .dark ? 0.24 : 0.12))
                }
        }
    }
}

/// 卡片按压反馈：按下时轻微缩放与淡出。
struct ToolCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: configuration.isPressed) { _, isPressed in
                isPressed
            }
    }
}
