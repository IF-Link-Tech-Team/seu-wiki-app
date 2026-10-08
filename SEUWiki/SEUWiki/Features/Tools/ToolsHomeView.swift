import SwiftUI

/// 工具页可被跨 tab 跳转的落点。主页「下一节课」卡点进来要直达课表，
/// 而不是停在工具列表让用户再点一次。
enum ToolRoute: Equatable {
    case timetable
    case gpa
}

/// 工具聚合页：卡片网格，布局参考「快捷指令」资料库。
struct ToolsHomeView: View {
    @Environment(UserProfile.self) private var profile
    @State private var showsProfile = false

    /// 跨 tab 跳转用的待办路由，由 `RootTabView` 写入。
    @Binding var route: ToolRoute?

    /// 网格自适应：写死两列在 iPad 上会拉得很宽很空。
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    init(route: Binding<ToolRoute?> = .constant(nil)) {
        _route = route
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ToolCatalog.all) { tool in
                        NavigationLink(value: tool) {
                            ToolCard(tool: tool, subtitle: liveSubtitle(for: tool))
                        }
                        .buttonStyle(ToolCardButtonStyle())
                        // 占位工具不可点进去：点开只有一句「开发中」，不如明确不可用。
                        .disabled(!tool.isAvailable)
                    }
                }
                .padding()
            }
            .groupedBackground()
            .navigationTitle("工具")
            .trackScreen("/tools", title: "工具")
            .profileEntry(isPresented: $showsProfile)
            .navigationDestination(for: ToolItem.self) { tool in
                toolDestination(tool)
            }
            .navigationDestination(item: $route) { target in
                switch target {
                case .timetable: TimetableView()
                case .gpa: GPACalculatorView()
                }
            }
        }
    }

    @ViewBuilder
    private func toolDestination(_ tool: ToolItem) -> some View {
        switch tool.id {
        case "timetable": TimetableView()
        case "gpa": GPACalculatorView()
        default: ToolPlaceholderView(tool: tool)
        }
    }

    /// 课表卡片的副标题与 `UserProfile.courses` 联动（同主页「下一节课」）。
    private func liveSubtitle(for tool: ToolItem) -> String? {
        guard tool.id == "timetable" else { return nil }
        let count = profile.courses.filter { $0.weekday == TimetableView.Weekday.today }.count
        if profile.courses.isEmpty { return "点此添加课程" }
        return count > 0 ? "今日 \(count) 节课" : "今日无课"
    }
}

#Preview {
    ToolsHomeView()
        .environment(UserProfile())
}
