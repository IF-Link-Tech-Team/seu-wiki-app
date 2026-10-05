import SwiftUI

/// 工具聚合页：双列卡片网格，布局参考「快捷指令」资料库。
struct ToolsHomeView: View {
    @Environment(UserProfile.self) private var profile
    @State private var showsProfile = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ToolCatalog.all) { tool in
                        NavigationLink(value: tool) {
                            ToolCard(tool: tool, subtitle: liveSubtitle(for: tool))
                        }
                        .buttonStyle(ToolCardButtonStyle())
                    }
                }
                .padding()
            }
            .groupedBackground()
            .navigationTitle("工具")
            .profileEntry(isPresented: $showsProfile)
            .navigationDestination(for: ToolItem.self) { tool in
                switch tool.id {
                case "timetable":
                    TimetableView()
                case "gpa":
                    GPACalculatorView()
                default:
                    ToolPlaceholderView(tool: tool)
                }
            }
        }
    }

    /// 课表卡片的副标题与 UserProfile.courses 联动（同主页「下一节课」），其余工具沿用 mock 文案。
    private func liveSubtitle(for tool: ToolItem) -> String? {
        guard tool.id == "timetable" else { return nil }
        let count = profile.courses.filter { $0.weekday == TimetableView.Weekday.today }.count
        return count > 0 ? "今日 \(count) 节课" : "今日无课"
    }
}

#Preview {
    ToolsHomeView()
        .environment(UserProfile())
}
