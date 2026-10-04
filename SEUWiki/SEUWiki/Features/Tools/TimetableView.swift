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
                    ContentUnavailableView(
                        selectedWeekday == Weekday.today ? "今天没课" : "这天没课",
                        systemImage: "calendar.badge.checkmark",
                        description: Text("好好休息，或切换到其他日期查看")
                    )
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
                            CourseCard(course: course)
                        }
                    }
                    .padding()
                    .animation(.smooth(duration: 0.25), value: dayCourses)
                }
            }
        }
        .groupedBackground()
        .navigationTitle("课表")
        .toolbar {
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
                                .foregroundStyle(isSelected ? .white : .primary)
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
