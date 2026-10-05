import SwiftUI

/// 登录页：发起 Logto OIDC（PKCE）系统浏览器授权。
///
/// 原先这里是「用户名 + 密码」的本地 stub 表单 —— 既不安全（明文收集密码）也不可能
/// 真正登录（Logto 走的是浏览器授权，密码只在 auth.iflink.tech 的页面里输入）。
/// 现在改为单个授权按钮：点开系统浏览器 → 在 Logto 登录 → 回调 `tech.iflink.seuwiki://callback`
/// → 换 token → 填充资料。
struct LoginView: View {
    @Environment(\.dismiss) private var dismiss

    /// 显式注入，不走 `@Environment(AuthStore.self)`。
    ///
    /// 踩过的坑：`navigationDestination` 拿不到 Form 上 `.environment(auth)` 注入的
    /// Observable，一进本页就 `Fatal error: No Observable object of type AuthStore found`。
    /// 显式传参不依赖 environment 传播，顺带也不受修饰符顺序影响。
    /// AuthStore 是 `@Observable`，在 body 里读属性照样会触发视图更新。
    ///
    /// 注意：那行 `.environment(auth)` 已经随之从 `ProfileView` 删掉了 —— 全工程
    /// 都没有 `@Environment(AuthStore.self)` 的读取者，留着只会让人以为传播路径还在，
    /// 然后重蹈上面那个崩溃。
    let auth: AuthStore

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)
                    Text("IF.Link 统一登录")
                        .font(.title2.weight(.bold))
                    Text("身份服务由 auth.iflink.tech 提供")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    auth.signIn()
                } label: {
                    HStack {
                        if auth.isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "safari")
                        }
                        Text(auth.isBusy ? "正在登录…" : "使用 IF.Link 账号登录")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(auth.isBusy || !auth.isConfigured)
                .listRowBackground(Color.clear)
            } footer: {
                if !auth.isConfigured {
                    Label("登录服务配置中", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    Label("在系统浏览器中完成登录，密码不会经过本 App", systemImage: "lock.shield")
                        .foregroundStyle(.secondary)
                }
            }

            if let error = auth.lastError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } header: {
                    Text("登录失败")
                }
            }

            Section {
                Button("取消", role: .cancel) { dismiss() }
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("登录")
        // 授权回调回来后会自动填充登录态，此时把本页关掉。
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            if loggedIn { dismiss() }
        }
    }
}

#Preview {
    NavigationStack {
        LoginView(auth: AuthStore())
    }
}
