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

/// 「快捷指令」资料库风格卡片：整张卡片为 tool.tint 饱和纯色
/// （上下轻微渐变增加层次），图标在左上角、名称在左下角，全部白色。
/// 深浅色模式保持同样的彩色卡片。
struct ToolCard: View {
    let tool: ToolItem
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: tool.systemImage)
                .font(.title2.weight(.semibold))

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.headline.weight(.bold))
                Text(subtitle ?? tool.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    tool.tint.mix(with: .white, by: 0.08),
                    tool.tint.mix(with: .black, by: 0.1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 20, style: .continuous)
        )
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
