import SwiftUI

/// 聚合搜索的单信源分区卡片（参考飞书搜索的聚合卡片形态）：
/// 头部 = SF 图标 + 信源名 + 命中数，中间最多 3 条结果行，底部「查看更多」。
struct SearchSectionCard<Destination: View, Content: View>: View {
    let scope: SearchScope
    let count: Int
    private let destination: Destination
    private let content: Content

    init(scope: SearchScope, count: Int, destination: Destination, @ViewBuilder content: () -> Content) {
        self.scope = scope
        self.count = count
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: scope.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(scope.tint)
                    .frame(width: 30, height: 30)
                    .background(scope.tint.opacity(0.12), in: .circle)

                Text(scope.name)
                    .font(.headline)

                Spacer()

                Text("\(count) 条结果")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()
                .padding(.leading, 14)

            content

            Divider()
                .padding(.leading, 14)

            NavigationLink {
                destination
            } label: {
                Text("查看更多")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .cardStyle(padding: 0)
    }
}
