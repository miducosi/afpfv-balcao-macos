import SwiftUI

/// Entrar, recuperar a palavra-passe e primeiro acesso da equipa (código do convite).
struct LoginView: View {
    enum Mode { case signIn, requestCode, enterCode }

    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .signIn
    @State private var codeType = "recovery"
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var error: String?
    @State private var info: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text("Balcão Vindimas").font(.largeTitle.weight(.semibold))
                Text("Backoffice da Festa das Vindimas").foregroundStyle(.secondary)
            }

            Group {
                switch mode {
                case .signIn: signInForm
                case .requestCode: requestCodeForm
                case .enterCode: enterCodeForm
                }
            }
            .frame(width: 320)
            .disabled(busy)

            if let error {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            if let info {
                Text(info).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            if !AppConfig.current.isConfigured {
                Text("Falta configurar o Supabase em Config/Secrets.xcconfig.").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.default, value: mode)
    }

    private var emailValid: Bool {
        email.trimmingCharacters(in: .whitespaces).range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    private var signInForm: some View {
        VStack(spacing: 10) {
            TextField("Email", text: $email).textContentType(.username)
            SecureField("Palavra-passe", text: $password).textContentType(.password)
                .onSubmit(signIn)
            Button(action: signIn) {
                Text("Entrar").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!emailValid || password.isEmpty)
            HStack {
                Button("Esqueci-me da palavra-passe") { switchTo(.requestCode, type: "recovery") }
                Spacer()
                Button("Primeiro acesso") { switchTo(.enterCode, type: "invite") }
            }
            .buttonStyle(.link).font(.callout)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var requestCodeForm: some View {
        VStack(spacing: 10) {
            Text("Enviamos um código para o seu email.").foregroundStyle(.secondary)
            TextField("Email", text: $email).textContentType(.username)
            Button {
                run {
                    let _: MessageResult = try await model.api.send(
                        "POST", "auth/password-reset/request", body: ["email": email.trimmingCharacters(in: .whitespaces)])
                    mode = .enterCode
                    info = "Se o email estiver registado, recebe um código dentro de momentos."
                }
            } label: { Text("Enviar código").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!emailValid)
            Button("Voltar") { switchTo(.signIn) }.buttonStyle(.link)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var enterCodeForm: some View {
        VStack(spacing: 10) {
            Text(codeType == "invite" ? "Use o código do email de convite." : "Use o código que recebeu por email.")
                .foregroundStyle(.secondary)
            TextField("Email", text: $email).textContentType(.username)
            TextField("Código", text: $code)
                .textContentType(.oneTimeCode)
                .font(.title3.monospacedDigit())
                .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(10)) }
            SecureField("Nova palavra-passe (mín. 8 caracteres)", text: $newPassword).textContentType(.newPassword)
            SecureField("Confirmar palavra-passe", text: $confirmPassword).textContentType(.newPassword)
            Button(action: verifyAndSetPassword) {
                Text("Guardar e entrar").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!emailValid || code.count < 6 || newPassword.count < 8 || newPassword != confirmPassword)
            if codeType == "invite" {
                Button("O código expirou? Pedir outro") { switchTo(.requestCode, type: "recovery") }.buttonStyle(.link)
            }
            Button("Voltar") { switchTo(.signIn) }.buttonStyle(.link)
        }
        .textFieldStyle(.roundedBorder)
    }

    private func switchTo(_ mode: Mode, type: String = "recovery") {
        error = nil
        info = nil
        codeType = type
        self.mode = mode
    }

    private func signIn() {
        guard emailValid, !password.isEmpty else { return }
        run {
            let me = try await model.api.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            try model.accept(me)
            password = ""
        }
    }

    private func verifyAndSetPassword() {
        run {
            let address = email.trimmingCharacters(in: .whitespaces)
            try await model.api.verify(email: address, code: code, type: codeType)
            try await model.api.mutate("auth/password", method: "PUT",
                                       body: ["password": newPassword, "confirmPassword": confirmPassword])
            let me: Me = try await model.api.send("POST", "auth/login")
            try model.accept(me)
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        error = nil
        info = nil
        busy = true
        Task {
            defer { busy = false }
            do { try await operation() } catch { self.error = error.localizedDescription }
        }
    }
}
