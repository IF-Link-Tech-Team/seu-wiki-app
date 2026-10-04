import SwiftUI

struct SearchHomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("搜索", systemImage: "magnifyingglass", description: Text("开发中"))
                .navigationTitle("搜索")
        }
    }
}

#Preview {
    SearchHomeView()
}
