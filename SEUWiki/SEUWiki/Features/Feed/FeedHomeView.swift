import SwiftUI

struct FeedHomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("资讯", systemImage: "newspaper", description: Text("开发中"))
                .navigationTitle("资讯")
        }
    }
}

#Preview {
    FeedHomeView()
}
