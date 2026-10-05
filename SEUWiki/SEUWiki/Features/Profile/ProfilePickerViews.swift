import SwiftUI

/// 「我的画像」各字段的可选项（MockData 未提供，自定义；兴趣对齐资讯 / 论坛常见标签）。
enum PersonaOptions {
    /// 常见 SEU 学院。
    static let colleges = [
        "建筑学院", "机械工程学院", "能源与环境学院", "信息科学与工程学院",
        "土木工程学院", "电子科学与工程学院", "数学学院", "自动化学院",
        "计算机科学与工程学院", "软件学院", "集成电路学院", "网络空间安全学院",
        "物理学院", "化学化工学院", "经济管理学院", "电气工程学院",
        "外国语学院", "交通学院", "仪器科学与工程学院", "材料科学与工程学院",
        "生物科学与医学工程学院", "生命科学与技术学院", "医学院", "公共卫生学院",
        "法学院", "人文学院", "艺术学院", "体育系",
    ]

    static let degrees = ["本科", "硕士", "博士"]

    static let grades = [
        "大一", "大二", "大三", "大四", "大五",
        "研一", "研二", "研三",
        "博一", "博二", "博三", "博四", "博五",
    ]

    static let interests = [
        "保研", "考研", "留学", "SRTP", "机器学习", "数学建模",
        "学科竞赛", "实习就业", "转专业", "交换项目", "奖学金", "校园生活",
    ]
}

/// 单选选择页（学院 / 学段 / 年级）：checkmark 标记当前项，选中后自动返回。
struct ProfileSinglePicker: View {
    let title: String
    let options: [String]
    @Binding var selection: String

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// 超过这个数量才给搜索框。
    ///
    /// HIG 建议长列表配搜索，但学段只有 3 项、年级 13 项 —— 给它们挂搜索框只会
    /// 凭空多一个用不上的控件。学院 28 项才是真正需要搜索的那一个。
    private static let searchThreshold = 20

    private var isSearchable: Bool { options.count >= Self.searchThreshold }

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard isSearchable, !q.isEmpty else { return options }
        return options.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List(filtered, id: \.self) { option in
            Button {
                selection = option
                dismiss()
            } label: {
                HStack {
                    Text(option)
                        .foregroundStyle(.primary)
                    Spacer()
                    if option == selection {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(title)
        // 搜索结果为空时给一句说明，别让用户对着一张白列表怀疑 App 坏了。
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .modifier(SearchableIf(enabled: isSearchable, text: $query))
    }
}

/// 只在需要时挂 `.searchable`。
///
/// 这个修饰符不能简单地写成 `if` 包在 body 里 —— `.searchable` 要作用在导航容器
/// 的内容上，条件化之后得靠 ViewModifier 把它送到正确的位置。
private struct SearchableIf: ViewModifier {
    let enabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, prompt: "搜索")
        } else {
            content
        }
    }
}

/// 多选选择页（兴趣）：checkmark 切换，不自动返回。
struct ProfileMultiPicker: View {
    let title: String
    let options: [String]
    @Binding var selection: [String]

    var body: some View {
        List(options, id: \.self) { option in
            let isSelected = selection.contains(option)
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    if isSelected {
                        selection.removeAll { $0 == option }
                    } else {
                        selection.append(option)
                    }
                }
            } label: {
                HStack {
                    Text(option)
                        .foregroundStyle(.primary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .transition(.opacity)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(title)
    }
}
