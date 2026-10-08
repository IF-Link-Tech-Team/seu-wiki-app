import SwiftUI

/// 课表：顶部周一~周日胶囊行（默认今天），下方当天课程按时间段竖向排列。
/// 数据与主页「下一节课」共用 UserProfile.courses。
struct TimetableView: View {
    /// 一周中的一天，供星期胶囊行使用。id 与 Course.weekday 对齐：1 = 周一 … 7 = 周日。
    struct Weekday: Identifiable, Hashable {
        let id: Int
        let title: String

        static let all: [Weekday] = [
            Weekday(id: 1, title: "周一"),
            Weekday(id: 2, title: "周二"),
            Weekday(id: 3, title: "周三"),
            Weekday(id: 4, title: "周四"),
            Weekday(id: 5, title: "周五"),
            Weekday(id: 6, title: "周六"),
            Weekday(id: 7, title: "周日"),
        ]

        /// 今天是周几（Calendar.weekday 的 1 = 周日映射为 7）。
        static var today: Int {
            let weekday = Calendar.current.component(.weekday, from: .now)
            return weekday == 1 ? 7 : weekday - 1
        }
    }

    @Environment(UserProfile.self) private var profile
    @State private var selectedWeekday = Weekday.today
    /// 非 nil 时弹出编辑表单（新增时是新 `Course`，编辑时是已有课程）。
    @State private var editing: Course?

    private var selection: Binding<Weekday> {
        Binding(
            get: { Weekday.all[selectedWeekday - 1] },
            set: { selectedWeekday = $0.id }
        )
    }

    private var dayCourses: [Course] {
        profile.courses
            .filter { $0.weekday == selectedWeekday }
            .sorted {
                ($0.startTime.hour ?? 0) * 60 + ($0.startTime.minute ?? 0)
                    < ($1.startTime.hour ?? 0) * 60 + ($1.startTime.minute ?? 0)
            }
    }

    /// 所选星期在本周对应的日期。
    private var selectedDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: selectedWeekday - Weekday.today,
            to: Calendar.current.startOfDay(for: .now)
        ) ?? .now
    }

    /// 「10月4日 · 周日」——与界面其余硬编码中文文案保持一致，不随系统语言变化。
    private var selectedDateText: String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: selectedDate)
        let day = calendar.component(.day, from: selectedDate)
        return "\(month)月\(day)日 · \(Weekday.all[selectedWeekday - 1].title)"
    }

    var body: some View {
        VStack(spacing: 0) {
            WeekdayBar(selection: selection)

            ScrollView {
                if dayCourses.isEmpty {
                    ContentUnavailableView {
                        Label(
                            profile.courses.isEmpty ? "还没有添加课程" : (selectedWeekday == Weekday.today ? "今天没课" : "这天没课"),
                            systemImage: "calendar.badge.checkmark"
                        )
                    } description: {
                        Text(profile.courses.isEmpty
                             ? "点右上角「添加」把本学期的课录进来，主页的「下一节课」会同步更新。"
                             : "好好休息，或切换到其他日期查看")
                    } actions: {
                        if profile.courses.isEmpty {
                            Button("添加课程") { editing = Course() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    LazyVStack(spacing: 12) {
                        HStack {
                            Text(selectedDateText)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(dayCourses.count) 节课")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        ForEach(dayCourses) { course in
                            Button {
                                editing = course
                            } label: {
                                CourseCard(course: course)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .animation(.smooth(duration: 0.25), value: dayCourses)
                }
            }
        }
        .groupedBackground()
        .navigationTitle("课表")
        .trackScreen("/tools/timetable", title: "课表")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加", systemImage: "plus") {
                    editing = Course(weekday: selectedWeekday)
                }
            }
            if selectedWeekday != Weekday.today {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("回到今天") {
                        withAnimation(.snappy) {
                            selectedWeekday = Weekday.today
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { course in
            CourseEditView(course: course) { saved in
                apply(saved)
            }
        }
    }

    /// 新增或覆盖保存。`Course` 的 `id` 决定是新增还是更新。
    private func apply(_ course: Course) {
        if let index = profile.courses.firstIndex(where: { $0.id == course.id }) {
            profile.courses[index] = course
        } else {
            profile.courses.append(course)
        }
    }
}

/// 课程新增/编辑表单。
///
/// 课表此前是**只读**的：数据来自演示样例，用户既不能加也不能改，
/// 「与主页联动」实际上只是在展示一份假数据。现在可以正常录入并落盘。
struct CourseEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserProfile.self) private var profile

    @State private var draft: Course
    private let onSave: (Course) -> Void

    init(course: Course, onSave: @escaping (Course) -> Void) {
        _draft = State(initialValue: course)
        self.onSave = onSave
    }

    private var isNew: Bool {
        !profile.courses.contains { $0.id == draft.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("课程信息") {
                    TextField("课程名", text: $draft.name)
                    TextField("教师", text: $draft.teacher)
                    TextField("地点", text: $draft.location)
                }

                Section("时间") {
                    Picker("星期", selection: $draft.weekday) {
                        ForEach(TimetableView.Weekday.all) { day in
                            Text(day.title).tag(day.id)
                        }
                    }
                    DatePicker("开始", selection: startBinding, displayedComponents: .hourAndMinute)
                    DatePicker("结束", selection: endBinding, displayedComponents: .hourAndMinute)
                }

                if !isNew {
                    Section {
                        Button("删除这门课", systemImage: "trash", role: .destructive) {
                            confirmsDelete = true
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "添加课程" : "编辑课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("删除这门课？", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    profile.courses.removeAll { $0.id == draft.id }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    @State private var confirmsDelete = false

    /// `Course` 存的是 `DateComponents`（只有时分），编辑时借 `Date` 与原生
    /// DatePicker 互通。用当天 2001-01-01 作基准，避免真的跑到别的日期。
    private var baseDay: Date {
        var c = DateComponents()
        c.year = 2001; c.month = 1; c.day = 1; c.hour = 0; c.minute = 0
        return Calendar.current.date(from: c) ?? .now
    }

    private func date(from components: DateComponents) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: baseDay)
        c.hour = components.hour ?? 8
        c.minute = components.minute ?? 0
        return Calendar.current.date(from: c) ?? baseDay
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { date(from: draft.startTime) },
            set: { draft.startTime = Calendar.current.dateComponents([.hour, .minute], from: $0) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { date(from: draft.endTime) },
            set: { draft.endTime = Calendar.current.dateComponents([.hour, .minute], from: $0) }
        )
    }
}

/// 星期胶囊行：样式与 Design/ConsoleBar 一致，额外支持滚动居中到选中的星期。
private struct WeekdayBar: View {
    @Binding var selection: TimetableView.Weekday

    @Namespace private var capsule

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TimetableView.Weekday.all) { day in
                        let isSelected = day == selection
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                selection = day
                            }
                        } label: {
                            Text(day.title)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .foregroundStyle(isSelected ? Color.accentInk : .primary)
                                .background {
                                    if isSelected {
                                        Capsule()
                                            .fill(Color.accentColor)
                                            .matchedGeometryEffect(id: "capsule", in: capsule)
                                    } else {
                                        Capsule()
                                            .fill(Color(.secondarySystemGroupedBackground))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: selection)
                        .id(day.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onAppear {
                proxy.scrollTo(selection.id, anchor: .center)
            }
            .onChange(of: selection) { _, newValue in
                withAnimation(.snappy) {
                    proxy.scrollTo(newValue.id, anchor: .center)
                }
            }
        }
    }
}

/// 单节课卡片：左侧时间区间竖向排列，右侧课程名、教师、地点。
private struct CourseCard: View {
    let course: Course

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(Self.timeText(course.startTime))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                RoundedRectangle(cornerRadius: 1)
                    .fill(.quaternary)
                    .frame(width: 2, height: 14)
                Text(Self.timeText(course.endTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text(course.name)
                    .font(.headline)
                HStack(spacing: 12) {
                    Label(course.teacher, systemImage: "person")
                    Label(course.location, systemImage: "mappin")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private static func timeText(_ components: DateComponents) -> String {
        String(format: "%d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

#Preview {
    NavigationStack {
        TimetableView()
    }
    .environment(UserProfile())
}
