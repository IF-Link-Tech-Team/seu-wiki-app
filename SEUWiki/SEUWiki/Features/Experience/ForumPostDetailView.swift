import SwiftUI

/// 论坛帖子详情页（占位，经验模块完善）。
struct ForumPostDetailView: View {
    let post: ForumPost

    var body: some View {
        ScrollView {
            Text(post.excerpt)
                .padding()
        }
        .navigationTitle(post.title)
    }
}
