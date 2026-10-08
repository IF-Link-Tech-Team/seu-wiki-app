import SwiftUI
import PhotosUI

/// 一张待上传配图：选图后统一转 JPEG 存内存（后端只收 jpeg/png/webp，
/// 相册原图常是 HEIC，直接传会 415）。
struct PendingImage: Identifiable {
    let id = UUID()
    let data: Data
    let uiImage: UIImage
}

/// 相册选图按钮（发帖页工具栏图标）。后端单张 ≤5MB（POST_IMAGE_MAX_BYTES），
/// 选图后先缩到长边 2048 再逐级降质，直到达标。
private struct ComposerImagePicker: View {
    @Binding var images: [PendingImage]
    @State private var selection: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(selection: $selection, maxSelectionCount: 9, matching: .images) {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加图片")
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            selection = []
            Task { await load(items) }
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: raw),
                  let jpeg = Self.jpegData(uiImage),
                  let preview = UIImage(data: jpeg) else { continue }
            let pending = PendingImage(data: jpeg, uiImage: preview)
            await MainActor.run { images.append(pending) }
        }
    }

    private static func jpegData(_ image: UIImage, maxBytes: Int = 5 * 1024 * 1024) -> Data? {
        let scaled = image.seuScaledToFit(maxDimension: 2048)
        for quality in [0.85, 0.7, 0.55, 0.4] {
            if let data = scaled.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
        }
        return nil
    }
}

private extension UIImage {
    /// 等比缩放到长边不超过 maxDimension（已经够小则原样返回）。
    func seuScaledToFit(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

/// `navigationDestination(item:)` 要求 Identifiable，String 不是 —— 包一层路由值。
private struct CreatedPostRoute: Identifiable, Hashable {
    let id: String
}

/// 发帖编辑器（豆瓣式专业论坛布局）：
/// 顶栏 = 取消 / 板块选择（居中胶囊）/ 发布；标题单行 + 通栏正文；
/// 底部工具栏（图片、#板块）贴在键盘上方。
///
/// 标题选填（≤160 字）、正文必填（≤20000 字）、板块标签 ≤3 个
/// （可选范围 = 内嵌的固定标签目录，与后端白名单同一份）。
///
/// 编辑模式（`editing` 非 nil）：预填标题/正文，走 `PATCH /api/posts/:id`；
/// 后端白名单不含标签，编辑模式不提供板块选择。
struct ForumComposerView: View {
    /// 编辑模式上下文：非 nil 时预填并走 PATCH。
    struct EditingContext: Hashable {
        let id: String
        let title: String
        let content: String
    }

    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthStore.shared
    @State private var client = ForumAPIClient()

    @State private var title: String
    @State private var content: String
    @State private var selectedSlugs: [String] = []
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showsTagPicker = false
    /// 待上传的配图（统一转成 JPEG 存 data，发布/保存成功后逐张上传）。
    @State private var pendingImages: [PendingImage] = []
    /// 发帖成功后创建出来的帖子 id，用于跳转到新帖详情。
    /// 包一层而不是直接用 String?：`navigationDestination(item:)` 要求 Identifiable。
    @State private var createdPost: CreatedPostRoute?

    let editing: EditingContext?
    /// 发帖/保存成功后回调（调用方用来让信息流或详情失效重载）。
    var onPublished: () -> Void

    init(editing: EditingContext? = nil, onPublished: @escaping () -> Void = {}) {
        self.editing = editing
        self.onPublished = onPublished
        _title = State(initialValue: editing?.title ?? "")
        _content = State(initialValue: editing?.content ?? "")
    }

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
                editor
            }
        }
    }

    // MARK: - 编辑器主体

    private var editor: some View {
        VStack(spacing: 0) {
            // 标题：单行通栏，无卡片边框，靠分隔线分区（豆瓣式）。
            TextField("标题（可不填）", text: $title, axis: .horizontal)
                .font(.title3.weight(.semibold))
                .onChange(of: title) { _, newValue in
                    if newValue.count > Self.maxTitleLength {
                        title = String(newValue.prefix(Self.maxTitleLength))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider().padding(.leading, 20)

            // 正文：占满剩余空间。
            ZStack(alignment: .topLeading) {
                if content.isEmpty {
                    Text("此刻你想要分享…")
                        .font(.body)
                        .foregroundStyle(Color(.placeholderText))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $content)
                    .font(.body)
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            if content.count > Self.maxContentLength {
                Text("超出 \(content.count - Self.maxContentLength) 字（上限 \(Self.maxContentLength) 字）")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            if !pendingImages.isEmpty {
                pendingImageStrip
            }

            toolBar
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(editing != nil ? "编辑帖子" : "发帖")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("取消")
            }
            // 居中：板块选择胶囊（编辑模式不显示 —— 后端不让改标签）。
            if editing == nil {
                ToolbarItem(placement: .principal) {
                    Button {
                        showsTagPicker = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: selectedSlugs.isEmpty ? "plus" : "number")
                                .font(.caption.weight(.bold))
                            Text(tagPickerTitle)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await publish() }
                } label: {
                    Group {
                        if isSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(editing != nil ? "保存" : "发布")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(canPublish ? Color.accentInk : .secondary)
                    .background(
                        canPublish ? Color.accentColor : Color(.tertiarySystemFill),
                        in: .capsule
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canPublish)
            }
        }
        .interactiveDismissDisabled(isSending)
        .sheet(isPresented: $showsTagPicker) {
            tagPickerSheet
        }
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

    private var tagPickerTitle: String {
        if selectedSlugs.isEmpty { return "选择板块" }
        return ForumTagCatalog.allTags
            .filter { selectedSlugs.contains($0.slug) }
            .map(\.name)
            .joined(separator: " · ")
    }

    /// 底部工具栏：图片 / 板块。贴在键盘上方（safeAreaBar 语义由系统处理）。
    private var toolBar: some View {
        HStack(spacing: 28) {
            // 图片：先存本地草稿（统一转 JPEG），发布/保存成功后逐张上传，
            // 与 Web 端 PostEditor 的顺序一致（先建帖拿 id，再传图）。
            ComposerImagePicker(images: $pendingImages)
            if editing == nil {
                Button {
                    showsTagPicker = true
                } label: {
                    Image(systemName: "number")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择板块")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// 待上传配图缩略图条：可单张移除。
    private var pendingImageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(pendingImages) { image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image.uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(.rect(cornerRadius: 8, style: .continuous))
                        Button {
                            pendingImages.removeAll { $0.id == image.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel("移除图片")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 板块选择 sheet

    private var tagPickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(ForumTagCatalog.topics) { topic in
                        VStack(alignment: .leading, spacing: 8) {
                            tagChip(topic.tag)
                            ChipsFlowLayout(spacing: 8) {
                                ForEach(topic.children) { child in
                                    tagChip(child)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("选择板块（最多 \(ForumTagCatalog.maxPostTags) 个）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showsTagPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
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

    // MARK: - 发布 / 保存

    private func publish() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let editing {
                try await client.updatePost(
                    id: editing.id,
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    content: trimmedContent
                )
                // 图片失败不拦保存：正文已更新，可再进编辑补传。
                try? await uploadPendingImages(postID: editing.id)
                onPublished()
                dismiss()
            } else {
                let id = try await client.createPost(
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    content: trimmedContent,
                    tags: selectedSlugs
                )
                try? await uploadPendingImages(postID: id)
                onPublished()
                createdPost = CreatedPostRoute(id: id)
            }
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

    /// 逐张上传配图（顺序与 Web 端 PostEditor 一致：帖子已存在后才能传）。
    private func uploadPendingImages(postID: String) async throws {
        for image in pendingImages {
            try await client.uploadPostImage(postID: postID, data: image.data)
        }
    }
}

#Preview {
    ForumComposerView()
}
