import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("主页", systemImage: "house", description: Text("开发中"))
                .navigationTitle("主页")
        }
    }
}

#Preview {
    HomeView()
}
