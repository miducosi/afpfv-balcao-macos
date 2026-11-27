import QuickLook
import SwiftUI

@main
struct BalcaoApp: App {
    @State private var model = AppModel()
    @State private var feedback = Feedback()
    /// A janela de definições tem os seus avisos (não aparecem na janela principal).
    @State private var settingsFeedback = Feedback()

    var body: some Scene {
        Window("Balcão Vindimas", id: "main") {
            RootView()
                .environment(model)
                .environment(feedback)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            SidebarCommands()
            CommandMenu("Balcão") {
                Button("Atualizar") { feedback.requestReload() }
                    .keyboardShortcut("r")
                Divider()
                ForEach(Array(model.sections.prefix(9).enumerated()), id: \.element) { index, section in
                    Button(section.title) { model.selection = section }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
                Divider()
                Button("Abrir na web") { NSWorkspace.shared.open(AppConfig.current.webURL.appendingPathComponent("admin")) }
                Button("Terminar sessão") { Task { await model.signOut() } }
                    .disabled(model.me == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .environment(settingsFeedback)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .launching:
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await model.restore() }
            case .signedOut:
                LoginView()
            case .signedIn(let me):
                MainView(me: me)
            }
        }
        .quickLookPreview($model.previewURL)
        .feedbackOverlay()
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    let me: Me

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                let groups = Dictionary(grouping: model.sections, by: \.group)
                ForEach(groupOrder.filter { groups[$0] != nil }, id: \.self) { group in
                    // Grupos com uma só secção dispensam o cabeçalho (ex.: "Terrados › Terrados").
                    if group.isEmpty || groups[group]!.count == 1 {
                        ForEach(groups[group]!) { row($0) }
                    } else {
                        SwiftUI.Section(group) { ForEach(groups[group]!) { row($0) } }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { account }
        } detail: {
            Group {
                switch model.selection ?? .dashboard {
                case .dashboard: DashboardView()
                case .requests: RequestsView()
                case .stalls: StallsView()
                case .treasury: SubmissionsView()
                case .charges: ChargesView()
                case .races: RacesView()
                case .passes: PassesView()
                case .passScan: PassScanView()
                case .meals: MealsView()
                case .mealMap: MealMapView()
                case .mealScan: MealScanView()
                case .team: TeamView()
                case .audit: AuditLogView()
                }
            }
            .id(model.selection)
            .navigationTitle((model.selection ?? .dashboard).title)
            .navigationSubtitle(me.edition.map { "\($0.name) · \(Labels.label(Labels.editionStatus, $0.status))" } ?? "")
        }
    }

    private var groupOrder: [String] {
        ["", "Terrados", "Tesouraria", "Provas", "Livres-trânsito", "Refeitório", "Administração"]
    }

    private func row(_ section: Section) -> some View {
        Label(section.title, systemImage: section.icon).tag(section)
    }

    private var account: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(me.user.name).font(.callout).lineLimit(1)
                Text(Labels.label(Labels.role, me.user.role)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Definições")
        }
        .padding(10)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    @State private var password = ""
    @State private var confirm = ""

    var body: some View {
        Form {
            if let me = model.me {
                SwiftUI.Section("Conta") {
                    LabeledContent("Nome", value: me.user.name)
                    LabeledContent("Email", value: me.user.email)
                    LabeledContent("Perfil", value: Labels.label(Labels.role, me.user.role))
                    if me.user.role == "OPERATOR" {
                        LabeledContent("Áreas", value: me.user.areas.map { Labels.label(Labels.area, $0) }.joined(separator: ", "))
                    }
                }
                SwiftUI.Section("Alterar palavra-passe") {
                    SecureField("Nova palavra-passe", text: $password).textContentType(.newPassword)
                    SecureField("Confirmar", text: $confirm).textContentType(.newPassword)
                    Button("Guardar palavra-passe") {
                        Task {
                            let body = ["password": password, "confirmPassword": confirm]
                            if await feedback.run({ try await model.api.mutate("auth/password", method: "PUT", body: body) }) {
                                password = ""; confirm = ""
                            }
                        }
                    }
                    .disabled(password.count < 8 || password != confirm)
                }
                SwiftUI.Section {
                    Button("Terminar sessão", role: .destructive) { Task { await model.signOut() } }
                }
            } else {
                Text("Sem sessão iniciada.").foregroundStyle(.secondary)
            }
            SwiftUI.Section("Servidor") {
                LabeledContent("API", value: AppConfig.current.apiURL.absoluteString)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .feedbackOverlay()
    }
}
