import SwiftUI

/// 经验 · 生存手册：节点导航风格，白色圆角卡片内两列分类行。
struct HandbookHomeView: View {
    /// 两列排布：每行一对分类。
    private var rowPairs: [[HandbookSection]] {
        let sections = MockData.handbookSections
        return stride(from: 0, to: sections.count, by: 2).map {
            Array(sections[$0 ..< min($0 + 2, sections.count)])
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(rowPairs.enumerated()), id: \.offset) { rowIndex, pair in
                    HStack(spacing: 0) {
                        ForEach(pair) { section in
                            NavigationLink(value: section) {
                                HandbookNodeCell(section: section, showsDivider: rowIndex < rowPairs.count - 1)
                            }
                            .buttonStyle(.plain)
                        }
                        if pair.count == 1 {
                            Spacer()
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .cardStyle(padding: 0)
            .padding()
        }
        .groupedBackground()
    }
}

/// 节点导航行：圆形彩色 icon + 分类名 + 小字条目数，行间细分隔线。
private struct HandbookNodeCell: View {
    let section: HandbookSection
    let showsDivider: Bool

    private var tint: Color {
        ForumPalette.solidColor(for: section.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(tint, in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text("\(section.entries.count) 篇条目")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(.rect)

            if showsDivider {
                Divider()
                    .padding(.leading, 58)
            }
        }
        .frame(maxWidth: .infinity)
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
