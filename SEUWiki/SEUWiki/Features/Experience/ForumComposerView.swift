import SwiftUI

/// `navigationDestination(item:)` 要求 Identifiable，String 不是 —— 包一层路由值。
private struct CreatedPostRoute: Identifiable, Hashable {
    let id: String
}

/// 发帖编辑器（原生表单）：标题选填（≤160 字）、正文必填（≤20000 字）、
/// 板块标签 ≤3 个（可选范围 = 内嵌的固定标签目录，与后端白名单同一份）。
///
/// 图片上传（`/api/media/upload`  multipart + COS）**本期未实现**，
/// 编辑器里不提供图片按钮，而不是放一个点了没反应的占位按钮。
struct ForumComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthStore.shared
    @State private var client = ForumAPIClient()

    @State private var title = ""
    @State private var content = ""
    @State private var selectedSlugs: [String] = []
    @State private var isSending = false
    @State private var errorMessage: String?
    /// 发帖成功后创建出来的帖子 id，用于跳转到新帖详情。
    /// 包一层而不是直接用 String?：`navigationDestination(item:)` 要求 Identifiable。
    @State private var createdPost: CreatedPostRoute?

    /// 发帖成功后回调（调用方用来让信息流失效重载）。
    var onPublished: () -> Void = {}

    private static let maxTitleLength = 160      // MAX_POST_TITLE_LENGTH
    private static let maxContentLength = 20_000 // MAX_POST_CONTENT_LENGTH

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canPublish: Bool {
        !isSending
            && !trimmedContent.isEmpty
            && trimmedContent.count <= Self.maxContentLength
            && title.count <= Self.maxTitleLength
            && selectedSlugs.count <= ForumTagCatalog.maxPostTags
    }

    var body: some View {
        NavigationStack {
            if !auth.isLoggedIn {
                ForumLoginGuide(message: "登录 IF.Link 账号后才能发帖。")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("取消") { dismiss() }
                        }
                    }
            } else {
                form
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("标题（选填）", text: $title)
                    .onChange(of: title) { _, newValue in
                        if newValue.count > Self.maxTitleLength {
                            title = String(newValue.prefix(Self.maxTitleLength))
                        }
                    }
            } footer: {
                Text("\(title.count)/\(Self.maxTitleLength)")
            }

            Section {
                TextEditor(text: $content)
                    .frame(minHeight: 180)
            } header: {
                Text("正文")
            } footer: {
                if content.count > Self.maxContentLength {
                    Text("超出 \(content.count - Self.maxContentLength) 字（上限 \(Self.maxContentLength) 字）")
                        .foregroundStyle(.red)
                } else {
                    Text("\(content.count)/\(Self.maxContentLength)")
                }
            }

            Section {
                ForEach(ForumTagCatalog.topics) { topic in
                    VStack(alignment: .leading, spacing: 8) {
                        tagChip(topic.tag)
                        ChipsFlowLayout(spacing: 8) {
                            ForEach(topic.children) { child in
                                tagChip(child)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("板块标签（最多 \(ForumTagCatalog.maxPostTags) 个）")
            } footer: {
                if selectedSlugs.count > ForumTagCatalog.maxPostTags {
                    Text("最多选择 \(ForumTagCatalog.maxPostTags) 个标签").foregroundStyle(.red)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("发帖")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await publish() }
                } label: {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("发布")
                    }
                }
                .disabled(!canPublish)
            }
        }
        .interactiveDismissDisabled(isSending)
        // 发帖成功后直接打开新帖详情。
        .navigationDestination(item: $createdPost) { route in
            ForumPostDetailView(postID: route.id)
        }
        // 详情页打开后关掉编辑器：返回时落在帖子详情而不是表单。
        .onChange(of: createdPost) { _, newValue in
            if newValue != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    dismiss()
                }
            }
        }
    }

    private func tagChip(_ tag: ForumTag) -> some View {
        let selected = selectedSlugs.contains(tag.slug)
        return Button {
            if selected {
                selectedSlugs.removeAll { $0 == tag.slug }
            } else if selectedSlugs.count < ForumTagCatalog.maxPostTags {
                selectedSlugs.append(tag.slug)
            }
        } label: {
            Text(tag.name)
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: .capsule
                )
                .foregroundStyle(selected ? Color.accentInk : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private func publish() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let id = try await client.createPost(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: trimmedContent,
                tags: selectedSlugs
            )
            onPublished()
            createdPost = CreatedPostRoute(id: id)
        } catch let error as ForumAPIClient.ForumAPIError {
            if case .unauthorized = error {
                errorMessage = "登录状态已失效，请重新登录后再发布。"
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = "发布失败：\(error.localizedDescription)"
        }
    }
}

#Preview {
    ForumComposerView()
}
