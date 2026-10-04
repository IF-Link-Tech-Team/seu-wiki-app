import SwiftUI

/// 手册条目详情（搜索结果的落地页；手册模块完善后可替换为全局目的地）。
struct SearchHandbookEntryView: View {
    let entry: HandbookEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("生存手册", systemImage: "book.closed.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)

                Text(entry.title)
                    .font(.title2.weight(.bold))
                Text(entry.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                Text(entry.body)
                    .font(.body)

                Text("更新于 \(entry.updatedAt, format: .dateTime.year().month().day())")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .cardStyle()
            .padding()
        }
        .groupedBackground()
        .navigationTitle("手册")
        .navigationBarTitleDisplayMode(.inline)
    }
}
