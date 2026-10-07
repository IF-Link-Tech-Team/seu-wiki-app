import SwiftUI

/// 各 Tab 页右上角统一的个人入口按钮（个人页面与设置）。
struct ProfileToolbarItem: ToolbarContent {
    @Binding var isPresented: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("个人主页", systemImage: "person.crop.circle") {
                isPresented = true
            }
        }
    }
}

extension View {
    /// 附加右上角个人入口与对应 sheet。
    func profileEntry(isPresented: Binding<Bool>) -> some View {
        self
            .toolbar {
                ProfileToolbarItem(isPresented: isPresented)
            }
            .sheet(isPresented: isPresented) {
                ProfileView()
            }
            .onAppear {
                // Debug 专用：`-uipicker college` 冷启动直接弹个人页并进选择器；
                // `-uiprofile` 只弹个人页。个人页是 sheet，本机又没有合成点击能力，
                // 不这么做就验不到。
                #if DEBUG
                if PersonaPickerField.fromLaunchArguments() != nil
                    || ProcessInfo.processInfo.arguments.contains("-uiprofile") {
                    isPresented.wrappedValue = true
                }
                #endif
            }
    }
}
