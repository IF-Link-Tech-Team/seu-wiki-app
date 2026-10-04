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

    var body: some View {
        List(options, id: \.self) { option in
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
