import SwiftUI

/// 经验 · 生存手册：分类网格（参考系统设置的节点导航）。
struct HandbookHomeView: View {
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(MockData.handbookSections) { section in
                    NavigationLink(value: section) {
                        HandbookSectionCard(section: section)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .groupedBackground()
    }
}

private struct HandbookSectionCard: View {
    let section: HandbookSection

    private var tint: Color {
        ForumPalette.color(for: section.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.title2.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.name)
                    .font(.headline)
                Text("\(section.entries.count) 篇条目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
}

/// 手册分类页：该分类下的文档条目列表（参考 Apple 健康的分组 List）。
struct HandbookSectionView: View {
    let section: HandbookSection

    var body: some View {
        List {
            Section {
                ForEach(section.entries) { entry in
                    NavigationLink {
                        HandbookEntryView(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title)
                                .font(.subheadline.weight(.medium))
                            Text(entry.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } footer: {
                Text("共 \(section.entries.count) 篇条目")
            }
        }
        .navigationTitle(section.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 手册条目详情：标题、更新时间与正文。
struct HandbookEntryView: View {
    let entry: HandbookEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title)
                        .font(.title2.weight(.bold))
                    Text("更新于 \(entry.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)

                Text(entry.body)
                    .font(.body)
                    .lineSpacing(5)
                    .cardStyle()
            }
            .padding()
        }
        .groupedBackground()
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HandbookHomeView()
    }
    .environment(UserProfile())
}
