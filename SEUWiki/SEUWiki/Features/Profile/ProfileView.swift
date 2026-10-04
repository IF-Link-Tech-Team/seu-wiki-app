import SwiftUI

/// 个人页面与设置（占位，后续接入 IF.Link Logto 登录）。
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView("个人页面", systemImage: "person.crop.circle", description: Text("登录与设置开发中"))
                .navigationTitle("我的")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }
}

#Preview {
    ProfileView()
}
