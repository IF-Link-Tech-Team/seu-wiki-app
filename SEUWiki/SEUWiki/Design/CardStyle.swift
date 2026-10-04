import SwiftUI

/// bento / 卡片通用样式：浅色分组背景上的浮起卡片。
extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
    }
}

/// 页面内容底色（卡片浮在上面）。
extension View {
    func groupedBackground() -> some View {
        self.background(Color(.systemGroupedBackground))
    }
}
