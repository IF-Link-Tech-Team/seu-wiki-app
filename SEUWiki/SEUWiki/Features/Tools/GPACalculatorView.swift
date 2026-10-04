import SwiftUI

/// 绩点计算的输入焦点：定位到某一行的某个输入框，供键盘「完成」按钮统一收起。
private enum GPAField: Hashable {
    case name(UUID)
    case credits(UUID)
    case score(UUID)
}

/// 绩点计算：录入课程成绩与学分，按五分制自动换算单课程绩点与加权平均绩点。
/// 数据通过 GPACalculatorStore 持久化到 UserDefaults，重启后保留。
struct GPACalculatorView: View {
    @State private var store = GPACalculatorStore()
    @FocusState private var focusedField: GPAField?

    var body: some View {
        content
            .animation(.smooth(duration: 0.25), value: store.courses.isEmpty)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: store.courses.count) { (old: Int, new: Int) in new > old }
            .sensoryFeedback(.impact(weight: .medium), trigger: store.courses.count) { (old: Int, new: Int) in new < old }
            .toolbar { toolbarContent }
    }

    private var content: some View {
        Group {
            if store.courses.isEmpty {
                emptyState
            } else {
                CoursesForm(store: store, focusedField: $focusedField)
            }
        }
        .groupedBackground()
        .navigationTitle("绩点计算")
        .tint(.green)
        .scrollDismissesKeyboard(.interactively)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("完成") { focusedField = nil }
        }
        if !store.courses.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有课程", systemImage: "percent")
        } description: {
            Text("添加课程的成绩与学分，自动按五分制换算绩点")
        } actions: {
            Button("添加课程") {
                withAnimation(.snappy(duration: 0.25)) {
                    store.addCourse()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// 课程表单：顶部汇总卡片，中间可增删的课程行，底部五分制换算规则与来源脚注。
private struct CoursesForm: View {
    @Bindable var store: GPACalculatorStore
    var focusedField: FocusState<GPAField?>.Binding

    var body: some View {
        Form {
            SummaryCard(summary: store.summary)

            Section("课程") {
                ForEach($store.courses) { $course in
                    CourseRow(course: $course, focusedField: focusedField)
                }
                .onDelete { offsets in
                    store.courses.remove(atOffsets: offsets)
                }

                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        store.addCourse()
                    }
                } label: {
                    Label("添加课程", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
            }

            Section {
                rulesGrid
            } header: {
                Text("五分制换算")
            } footer: {
                Text("换算规则依据 app 内手册「绩点计算规则」：90–100 为 5.0，此后每 5 分一档递减 0.5，60 以下为 0。未检索到东南大学官方公开的换算文件，此处为假设规则，实际以教务处最新规定为准。")
            }
        }
    }

    private var rulesGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            GridRow {
                rule("90–100", "5.0")
                rule("70–74", "3.0")
            }
            GridRow {
                rule("85–89", "4.5")
                rule("65–69", "2.5")
            }
            GridRow {
                rule("80–84", "4.0")
                rule("60–64", "2.0")
            }
            GridRow {
                rule("75–79", "3.5")
                rule("60 以下", "0")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func rule(_ range: String, _ point: String) -> some View {
        HStack {
            Text(range)
                .foregroundStyle(.secondary)
            Spacer()
            Text(point)
                .fontWeight(.semibold)
        }
        .font(.subheadline.monospacedDigit())
        .frame(maxWidth: .infinity)
    }
}

/// 汇总卡片：大字号加权平均绩点，下方总学分 / 加权平均分 / 计入课程三栏。
private struct SummaryCard: View {
    let summary: GPASummary

    var body: some View {
        Section {
            VStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(summary.gradePointText)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.green)
                        .contentTransition(.numericText())
                    Text("加权平均绩点")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 0) {
                    stat(title: "总学分", value: summary.totalCreditsText)
                    Divider().frame(height: 28)
                    stat(title: "加权平均分", value: summary.averageScoreText)
                    Divider().frame(height: 28)
                    stat(title: "计入课程", value: "\(summary.countedCourses) 门")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .listRowSeparator(.hidden)
        }
        .animation(.smooth(duration: 0.3), value: summary)
    }

    private func stat(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 单门课程行：课程名（选填）+ 学分 / 成绩数字输入，右侧实时显示换算出的单课程绩点。
private struct CourseRow: View {
    @Binding var course: GPACourse
    var focusedField: FocusState<GPAField?>.Binding

    private var gradePointText: String {
        course.gradePoint.map { String(format: "%.1f", $0) } ?? "—"
    }

    private var errorText: String? {
        if course.hasScoreError { return "成绩需在 0–100 之间" }
        if course.hasCreditsError { return "学分需大于 0" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("课程名称（选填）", text: $course.name)
                .focused(focusedField, equals: .name(course.id))
                .submitLabel(.done)
                .onSubmit { focusedField.wrappedValue = nil }

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("学分")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("如 3.0", text: $course.creditsText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .focused(focusedField, equals: .credits(course.id))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text("成绩")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("0 – 100", text: $course.scoreText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .focused(focusedField, equals: .score(course.id))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("绩点")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(gradePointText)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(course.gradePoint == nil ? Color.secondary : Color.green)
                        .contentTransition(.numericText())
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .animation(.snappy(duration: 0.2), value: course.gradePoint)
        .animation(.snappy(duration: 0.2), value: errorText)
    }
}

#Preview {
    NavigationStack {
        GPACalculatorView()
    }
}
