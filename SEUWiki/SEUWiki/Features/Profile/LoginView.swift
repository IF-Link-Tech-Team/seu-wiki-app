import SwiftUI

/// 原生登录页（非网页）：本地 stub 表单，后续替换为 Logto OIDC（PKCE）授权流程。
struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth

    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case username, password
    }

    private var isFormValid: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

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
                TextField("用户名或邮箱", text: $username)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .username)
                    .onSubmit { focusedField = .password }
                SecureField("密码", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit(loginIfValid)
            }

            Section {
                Button(action: login) {
                    Text("登录")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isFormValid)
                .listRowBackground(Color.clear)
            } footer: {
                Label("其他登录方式（GitHub、邮箱验证码）将在接入 Logto 后开放", systemImage: "person.badge.key")
            }

            Section {
                Button("取消", role: .cancel) { dismiss() }
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("登录")
        .onAppear { focusedField = .username }
    }

    private func loginIfValid() {
        guard isFormValid else { return }
        login()
    }

    private func login() {
        withAnimation(.smooth) {
            auth.login(username: username.trimmingCharacters(in: .whitespaces), password: password)
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
    .environment(AuthStore())
}
