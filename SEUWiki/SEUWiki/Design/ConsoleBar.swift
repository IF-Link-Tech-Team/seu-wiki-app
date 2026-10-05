import SwiftUI

/// 顶部 console：横向滚动的胶囊选项，用于 Tab 页内子页面切换。
/// 选中态使用 accent 填充，未选中为二级分组底色，遵循原生分段控件语义。
struct ConsoleBar<Item: Identifiable & Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    @Namespace private var capsule

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    let isSelected = item == selection
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            selection = item
                        }
                    } label: {
                        Text(title(item))
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            // 深色模式下 accent 是亮绿，白字只有 1.83:1；accentInk 切到深绿是 7.08:1。
                            .foregroundStyle(isSelected ? Color.accentInk : .primary)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .matchedGeometryEffect(id: "capsule", in: capsule)
                                } else {
                                    Capsule()
                                        .fill(Color(.secondarySystemGroupedBackground))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: selection)
                    // 读屏必须知道「当前选中的是哪个」，否则七个胶囊会被读成一串名字。
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
