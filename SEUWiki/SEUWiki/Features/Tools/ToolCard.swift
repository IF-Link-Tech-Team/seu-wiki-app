import SwiftUI

/// 工具图标：tool.tint 渐变圆角方块内的 SF Symbol。
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

/// 「快捷指令」资料库风格卡片：整张卡片为 tool.tint 饱和纯色，图标在左上角、
/// 名称在左下角。
///
/// 两处按 UI/UX 对齐方案 §4.1 修正：
/// 1. **文字颜色按对比度自动选**。原先一律白字，而工具卡的配色里有几个
///    （`mint`、`teal`、偏黄的绿）白字对比度不足 4.5:1，亮色模式下尤其明显。
/// 2. **占位工具带「即将推出」标识**。8 个工具里 6 个还没实现，副标题却写得像能用。
struct ToolCard: View {
    let tool: ToolItem
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: tool.systemImage)
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 0)
                if !tool.isAvailable {
                    Text("即将推出")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.22), in: .capsule)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.headline.weight(.bold))
                Text(subtitle ?? tool.subtitle)
                    .font(.caption)
                    .opacity(0.85)
            }
            .lineLimit(2)
        }
        .foregroundStyle(Contrast.foreground(on: tool.tint))
        .padding(14)
        // 用 minHeight 而不是固定 maxHeight：固定 118pt 在 200% 字号下会裁掉副标题。
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tool.isAvailable ? tool.name : "\(tool.name)，即将推出")
    }
}

/// 文字与背景色的对比度工具。
///
/// 卡片背景是品牌彩色 + 渐变，文字颜色只能二选一（白或近黑），
/// 所以按 WCAG 相对亮度公式算一遍，选对比度更高且达标的那个。
enum Contrast {
    /// 在给定背景上选一个达标的文字色。
    static func foreground(on color: Color) -> Color {
        let (r, g, b) = resolve(color)
        let onLight = Color.WCAG.ratio(red1: 1, green1: 1, blue1: 1, red2: r, green2: g, blue2: b)
        let onDark = Color.WCAG.ratio(red1: 0.06, green1: 0.08, blue1: 0.07, red2: r, green2: g, blue2: b)
        return onLight > onDark ? .white : Color(red: 0.06, green: 0.08, blue: 0.07)
    }

    /// 把 SwiftUI Color 拆成 sRGB 分量（0...1）。
    static func resolve(_ color: Color) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return (0, 0, 0) }
        return (Double(r), Double(g), Double(b))
    }
}

/// 卡片按压反馈：按下时轻微缩放与淡出（UI/UX 对齐方案 §4.5）。
struct ToolCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: configuration.isPressed) { _, isPressed in
                isPressed
            }
    }
}
