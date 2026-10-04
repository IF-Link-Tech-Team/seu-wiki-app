import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("主页", systemImage: "house") {
                HomeView()
            }
            Tab("资讯", systemImage: "newspaper") {
                FeedHomeView()
            }
            Tab("经验", systemImage: "bubble.left.and.text.bubble.right") {
                ExperienceHomeView()
            }
            Tab("工具", systemImage: "square.grid.2x2") {
                ToolsHomeView()
            }
            Tab(role: .search) {
                SearchHomeView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview {
    RootTabView()
}
