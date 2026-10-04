import SwiftUI

struct ExperienceHomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("经验", systemImage: "bubble.left.and.text.bubble.right", description: Text("开发中"))
                .navigationTitle("经验")
        }
    }
}

#Preview {
    ExperienceHomeView()
}
