import SwiftUI

/// 资讯详情页（占位，资讯模块完善：底部「在网页中打开」+「设定提醒」）。
struct FeedItemDetailView: View {
    let item: FeedItem

    var body: some View {
        ScrollView {
            Text(item.summary)
                .padding()
        }
        .navigationTitle(item.sourceName)
    }
}
