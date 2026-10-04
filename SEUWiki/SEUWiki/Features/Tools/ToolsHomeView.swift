import SwiftUI

struct ToolsHomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("工具", systemImage: "square.grid.2x2", description: Text("开发中"))
                .navigationTitle("工具")
        }
    }
}

#Preview {
    ToolsHomeView()
}
