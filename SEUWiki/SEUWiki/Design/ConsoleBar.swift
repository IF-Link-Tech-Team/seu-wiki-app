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
                            .foregroundStyle(isSelected ? .white : .primary)
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
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
