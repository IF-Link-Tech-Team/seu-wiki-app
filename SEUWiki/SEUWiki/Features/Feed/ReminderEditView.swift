import SwiftUI

/// 参考 Apple 提醒事项的提醒编辑表单，在资讯详情页弹出。
///
/// 保存时**同时**写入本机列表和系统通知排程 —— 早期版本只写列表，
/// `advanceDays` 仅用于显示文字，到期不会有任何通知（工程里当时一行
/// `UserNotifications` 代码都没有）。
struct ReminderEditView: View {
    @Environment(UserProfile.self) private var profile
    @Environment(\.dismiss) private var dismiss

    let item: FeedItem

    @State private var title: String
    @State private var dueDate: Date
    @State private var advanceDays: Int
    @State private var note = ""
    @State private var saved = false
    /// 同一个资讯已有提醒时，直接编辑那一条而不是再叠一条。
    private var existing: CampusReminder? {
        profile.reminders.first { $0.relatedItemID == item.id }
    }

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
                } footer: {
                    Text("提醒会在截止日往前推的天数当天的 9:00 由系统通知发出。")
                }

                Section {
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let existing {
                    Section {
                        Button("删除这条提醒", systemImage: "trash", role: .destructive) {
                            Task { await delete(existing) }
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "设定提醒" : "编辑提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(existing == nil ? "添加" : "保存") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sensoryFeedback(.success, trigger: saved)
        }
    }

    private func save() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if var existing {
            existing.title = trimmed
            existing.dueDate = dueDate
            existing.advanceDays = advanceDays
            existing.note = trimmedNote
            if let index = profile.reminders.firstIndex(where: { $0.id == existing.id }) {
                profile.reminders[index] = existing
            }
            await ReminderScheduler.shared.schedule(
                id: existing.notificationID, title: trimmed,
                deadline: dueDate, advanceDays: advanceDays
            )
        } else {
            let reminder = CampusReminder(
                title: trimmed,
                dueDate: dueDate,
                advanceDays: advanceDays,
                note: trimmedNote,
                relatedItemID: item.id
            )
            profile.reminders.append(reminder)
            await ReminderScheduler.shared.schedule(
                id: reminder.notificationID, title: trimmed,
                deadline: dueDate, advanceDays: advanceDays
            )
        }
        saved.toggle()
        dismiss()
    }

    private func delete(_ reminder: CampusReminder) async {
        ReminderScheduler.shared.cancel(id: reminder.notificationID)
        profile.reminders.removeAll { $0.id == reminder.id }
        dismiss()
    }
}

#Preview {
    ReminderEditView(item: PreviewSample.feedItems[0])
        .environment(UserProfile())
}
