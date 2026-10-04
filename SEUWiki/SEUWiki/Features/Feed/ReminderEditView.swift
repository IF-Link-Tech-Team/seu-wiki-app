import SwiftUI

/// 参考 Apple 提醒事项的提醒编辑表单，在资讯详情页弹出。
struct ReminderEditView: View {
    @Environment(UserProfile.self) private var profile
    @Environment(\.dismiss) private var dismiss

    let item: FeedItem

    @State private var title: String
    @State private var dueDate: Date
    @State private var advanceDays: Int
    @State private var note = ""
    @State private var saved = false

    init(item: FeedItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _dueDate = State(initialValue: item.audience.deadline ?? .now.addingTimeInterval(86400))
        _advanceDays = State(initialValue: 1)
    }

    private static let advanceOptions: [(days: Int, label: String)] = [
        (0, "当天"),
        (1, "提前 1 天"),
        (2, "提前 2 天"),
        (3, "提前 3 天"),
        (7, "提前 1 周"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题", text: $title)
                }

                Section {
                    DatePicker("截止时间", selection: $dueDate)
                    Picker("提前提醒", selection: $advanceDays) {
                        ForEach(Self.advanceOptions, id: \.days) { option in
                            Text(option.label).tag(option.days)
                        }
                    }
                }

                Section {
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("设定提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sensoryFeedback(.success, trigger: saved)
        }
    }

    private func save() {
        let reminder = CampusReminder(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: dueDate,
            advanceDays: advanceDays,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            relatedItemID: item.id
        )
        profile.reminders.append(reminder)
        saved.toggle()
        dismiss()
    }
}

#Preview {
    ReminderEditView(item: MockData.feedItems[0])
        .environment(UserProfile())
}
