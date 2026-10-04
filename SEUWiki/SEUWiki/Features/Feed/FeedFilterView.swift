import SwiftUI

/// 「全部」列表的筛选 sheet：学院开关、学段 Picker、分类多选。
struct FeedFilterView: View {
    @Environment(UserProfile.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: FeedFilter

    private static let degrees = ["本科生", "硕士生", "博士生"]

    var body: some View {
        NavigationStack {
            Form {
                Section("学院") {
                    Toggle("只看我的学院", isOn: $filter.onlyMyCollege)
                    if filter.onlyMyCollege {
                        LabeledContent("当前学院", value: profile.college)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("学段") {
                    Picker("学段", selection: $filter.degree) {
                        Text("全部").tag(String?.none)
                        ForEach(Self.degrees, id: \.self) { degree in
                            Text(degree).tag(String?.some(degree))
                        }
                    }
                }

                Section("分类") {
                    ForEach(FeedCategory.allCases) { category in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                if filter.categories.contains(category) {
                                    filter.categories.remove(category)
                                } else {
                                    filter.categories.insert(category)
                                }
                            }
                        } label: {
                            HStack {
                                Label(category.name, systemImage: category.systemImage)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if filter.categories.contains(category) {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                        .sensoryFeedback(.selection, trigger: filter.categories.contains(category))
                    }
                }

                if filter.isActive {
                    Section {
                        Button("清除全部筛选", role: .destructive) {
                            withAnimation(.snappy) {
                                filter = FeedFilter()
                            }
                        }
                    }
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    @Previewable @State var filter = FeedFilter()
    FeedFilterView(filter: $filter)
        .environment(UserProfile())
}
