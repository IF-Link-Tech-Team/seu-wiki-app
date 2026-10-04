import SwiftUI

/// 搜索词为空时的引导页：热门搜索 chips + 可搜信源说明。
struct SearchSuggestionsView: View {
    let onSelect: (String) -> Void

    private let hotWords = [
        "保研", "SRTP", "奖学金", "转专业", "数学建模", "秋招",
        "交换", "选课", "图书馆", "食堂", "班车", "校园卡",
    ]

    private let sourceScopes: [SearchScope] = [.feed, .forum, .handbook]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hotSearchCard
                sourcesCard
            }
            .padding()
        }
    }

    private var hotSearchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("热门搜索", systemImage: "flame.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            ChipsFlowLayout(spacing: 8) {
                ForEach(hotWords, id: \.self) { word in
                    Button {
                        onSelect(word)
                    } label: {
                        Text(word)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(.systemGroupedBackground), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle()
    }

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("搜索范围", systemImage: "square.stack.3d.up.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            ForEach(sourceScopes) { scope in
                HStack(spacing: 12) {
                    Image(systemName: scope.systemImage)
                        .font(.body.weight(.medium))
                        .foregroundStyle(scope.tint)
                        .frame(width: 32, height: 32)
                        .background(scope.tint.opacity(0.12), in: .circle)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(scope.name)
                            .font(.subheadline.weight(.medium))
                        Text(scope.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .cardStyle()
    }
}

/// 简单流式布局：子视图从左到右排列，超出可用宽度自动换行。
struct ChipsFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + size.width > maxWidth {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
