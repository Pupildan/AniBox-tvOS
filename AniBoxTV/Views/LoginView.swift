import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: Session
    @State private var server = UserDefaults.standard.string(forKey: "server") ?? ""
    @State private var username = UserDefaults.standard.string(forKey: "username") ?? ""
    @State private var password = ""
    @State private var remember = true
    @State private var busy = false
    @State private var error: String?
    @State private var showDisclaimer = !UserDefaults.standard.bool(forKey: "disclaimerAccepted")

    var body: some View {
        ZStack {
            AppBackground()
            HStack(spacing: 100) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("AniBox").font(.system(size: 110, weight: .heavy))
                        .foregroundStyle(LinearGradient(colors: [.white, .cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                    Text("把飞牛影视，变成你客厅里的私人影院").font(.title3).foregroundStyle(.secondary)
                    Text("tvOS 版 · 非官方第三方客户端").font(.callout).foregroundStyle(.tertiary)
                }
                VStack(spacing: 26) {
                    field("服务器地址", "例如 192.168.1.10:5666 或 https://xxx.fnos.net", $server)
                    field("用户名", "飞牛账号", $username)
                    SecureField("密码", text: $password).textContentType(.password).frame(width: 760)
                    Toggle("记住密码（会话过期自动重登）", isOn: $remember).frame(width: 760)
                    if let error { Text(error).foregroundStyle(.red).frame(width: 760, alignment: .leading) }
                    Button {
                        Task { await doLogin() }
                    } label: {
                        HStack { if busy { ProgressView() }; Text(busy ? "登录中…" : "登录") }.frame(width: 680)
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    .disabled(busy || server.isEmpty || username.isEmpty)
                }
                .padding(60).glass(44)
            }
        }
        .alert("使用须知", isPresented: $showDisclaimer) {
            Button("我已知悉") { UserDefaults.standard.set(true, forKey: "disclaimerAccepted") }
        } message: {
            Text("AniBox 为个人开源作品，与飞牛官方无关联。需登录你自己的飞牛影视账号，登录态仅保存在本机。请确保播放内容符合当地法律与版权规定。本软件按原样提供，无任何担保。")
        }
    }
    func field(_ title: String, _ prompt: String, _ v: Binding<String>) -> some View {
        TextField(title, text: v, prompt: Text(prompt)).frame(width: 760).autocorrectionDisabled().textInputAutocapitalization(.never)
    }
    func doLogin() async {
        busy = true; error = nil
        var s = server
        // 未带端口的内网地址：依次尝试 fnOS 默认端口
        let bare = s.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
        let candidates = bare.contains(":") ? [s] : [s + ":5666", s + ":8000", s + ":5667", s + ":8001", s]
        for c in candidates {
            do { try await session.login(server: c, username: username, password: password, remember: remember); busy = false; return }
            catch { self.error = error.localizedDescription; s = c }
        }
        busy = false
    }
}
