import SwiftUI

/// Equipa (só admin): contas, perfis e áreas; convites.
struct TeamView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var search = ""
    @State private var selected: String?
    @State private var inviting = false

    var body: some View {
        MasterDetail {
            VStack(spacing: 0) {
                HStack {
                    TextField("Nome ou email", text: $query).textFieldStyle(.roundedBorder)
                        .debounce(query, into: $search)
                    Button("Convidar", systemImage: "person.badge.plus") { inviting = true }
                }
                .padding(10)
                Divider()
                Loader(key: search, load: {
                    try await model.api.get("admin/users", query: ["q": search]) as [StaffUser]
                }) { users, _ in
                    List(users, selection: $selected) { user in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(user.name).font(.headline).foregroundStyle(user.isActive ? .primary : .secondary)
                                if !user.isActive { StatusBadge("Inativa", tone: .danger) }
                                Spacer()
                                Text(Labels.label(Labels.role, user.role)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(user.email).font(.callout).foregroundStyle(.secondary)
                            if user.role == "OPERATOR" {
                                Text(user.areas.map { Labels.label(Labels.area, $0) }.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .padding(.vertical, 3)
                        .tag(user.id)
                    }
                }
            }
        } detail: {
            if let selected {
                UserDetailView(id: selected).id(selected)
            } else {
                NoSelection(text: "Escolha uma pessoa.")
            }
        }
        .sheet(isPresented: $inviting) { InviteSheet() }
    }
}

private struct UserDetailView: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        Loader(load: { try await model.api.get("admin/users/\(id)") as StaffUser }) { user, _ in
            UserEditor(user: user)
        }
    }
}

private struct UserEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    let user: StaffUser
    @State private var name: String
    @State private var phone: String
    @State private var role: String
    @State private var areas: Set<String>
    @State private var isActive: Bool

    init(user: StaffUser) {
        self.user = user
        _name = State(initialValue: user.name)
        _phone = State(initialValue: user.phone ?? "")
        _role = State(initialValue: user.role)
        _areas = State(initialValue: Set(user.areas))
        _isActive = State(initialValue: user.isActive)
    }

    private var changed: Bool {
        name != user.name || phone != (user.phone ?? "") || role != user.role || areas != Set(user.areas) || isActive != user.isActive
    }

    var body: some View {
        Form {
            SwiftUI.Section {
                DetailHeader(title: user.name, subtitle: user.email) {
                    StatusBadge(Labels.label(Labels.role, user.role), tone: .neutral)
                }
                LabeledContent("Último acesso", value: Formatting.dateTime(user.lastLoginAt))
                LabeledContent("Criada", value: Formatting.date(user.createdAt))
            }
            SwiftUI.Section("Dados") {
                TextField("Nome", text: $name)
                PhoneField(phone: $phone)
                Toggle("Conta ativa", isOn: $isActive)
            }
            SwiftUI.Section("Acesso") {
                Picker("Perfil", selection: $role) {
                    ForEach(["ADMIN", "OPERATOR", "USER"], id: \.self) { Text(Labels.label(Labels.role, $0)).tag($0) }
                }
                if role == "OPERATOR" { AreasPicker(areas: $areas) }
            }
            SwiftUI.Section {
                HStack {
                    Spacer()
                    Button("Repor") {
                        name = user.name; phone = user.phone ?? ""; role = user.role
                        areas = Set(user.areas); isActive = user.isActive
                    }
                    .disabled(!changed)
                    Button("Guardar") {
                        Task {
                            let body = UserUpdate(name: name.trimmingCharacters(in: .whitespaces), phone: phone.nilIfBlank,
                                                  role: role, areas: role == "OPERATOR" ? Labels.areas.map(\.code).filter(areas.contains) : [],
                                                  isActive: isActive)
                            if await feedback.run({ try await model.api.mutate("admin/users/\(user.id)", method: "PUT", body: body) }) {
                                feedback.requestReload()
                                if user.id == model.me?.user.id { await model.refreshMe() }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!changed || feedback.busy || name.trimmingCharacters(in: .whitespaces).count < 2
                        || (role == "OPERATOR" && areas.isEmpty) || !PhoneField.isValid(phone))
                }
            }
        }
        .formStyle(.grouped)
    }

    private struct UserUpdate: Encodable {
        let name: String
        let phone: String?
        let role: String
        let areas: [String]
        let isActive: Bool
    }
}

private struct AreasPicker: View {
    @Binding var areas: Set<String>

    var body: some View {
        ForEach(Labels.areas, id: \.code) { area in
            Toggle(isOn: Binding(
                get: { areas.contains(area.code) },
                set: { if $0 { areas.insert(area.code) } else { areas.remove(area.code) } }
            )) {
                Text(area.label)
                Text(area.hint)
            }
        }
    }
}

/// Telemóvel em E.164 (+351…), como o `PhoneInput` da web: só aceita dígitos e o "+".
struct PhoneField: View {
    @Binding var phone: String

    static func isValid(_ value: String) -> Bool {
        value.isEmpty || value.range(of: #"^\+[1-9]\d{7,14}$"#, options: .regularExpression) != nil
    }

    var body: some View {
        TextField("Telemóvel (opcional)", text: $phone, prompt: Text("+351 912 345 678"))
            .textContentType(.telephoneNumber)
            .onChange(of: phone) { _, value in
                var digits = value.filter { $0.isNumber }
                if digits.isEmpty { phone = ""; return }
                // Número nacional de 9 dígitos sem indicativo → Portugal.
                if !value.hasPrefix("+"), digits.count == 9, digits.first == "9" || digits.first == "2" { digits = "351" + digits }
                let normalized = "+" + digits.prefix(15)
                if normalized != phone { phone = normalized }
            }
            .foregroundStyle(Self.isValid(phone) ? .primary : Color.red)
    }
}

private struct InviteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var role = "OPERATOR"
    @State private var areas = Set<String>()

    private var valid: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 2
            && email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
            && PhoneField.isValid(phone) && (role == "ADMIN" || !areas.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                SwiftUI.Section("Convidar para a equipa") {
                    TextField("Nome", text: $name)
                    TextField("Email", text: $email).textContentType(.emailAddress)
                    PhoneField(phone: $phone)
                    Picker("Perfil", selection: $role) {
                        Text("Operador").tag("OPERATOR")
                        Text("Administrador").tag("ADMIN")
                    }
                }
                if role == "OPERATOR" {
                    SwiftUI.Section("Áreas") { AreasPicker(areas: $areas) }
                }
            }
            .formStyle(.grouped)
            HStack {
                Text("Recebe um email com o código de primeiro acesso.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enviar convite") {
                    Task {
                        let body = Invite(name: name.trimmingCharacters(in: .whitespaces),
                                          email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                                          phone: phone.nilIfBlank, role: role,
                                          areas: role == "OPERATOR" ? Labels.areas.map(\.code).filter(areas.contains) : [])
                        if await feedback.run({
                            let result: MessageWithId = try await model.api.send("POST", "admin/users/invite", body: body)
                            return result.message
                        }) {
                            feedback.requestReload()
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid || feedback.busy)
            }
            .padding()
        }
        .frame(width: 520, height: 600)
    }

    private struct Invite: Encodable {
        let name: String
        let email: String
        let phone: String?
        let role: String
        let areas: [String]
    }
}

/// Registo de auditoria (só admin).
struct AuditLogView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 1

    var body: some View {
        Loader(key: page, load: { try await model.api.get("admin/audit-logs", query: ["page": "\(page)"]) as AuditLogList }) { list, _ in
            Table(list.items) {
                TableColumn("Quando") { Text(Formatting.dateTime($0.createdAt)) }.width(min: 130, ideal: 150)
                TableColumn("Quem") { Text($0.actorName ?? "Sistema") }.width(min: 100, ideal: 140)
                TableColumn("Ação") { Text($0.action).font(.callout.monospaced()) }.width(min: 120, ideal: 170)
                TableColumn("Resumo") { Text($0.summary).help($0.summary) }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Anterior", systemImage: "chevron.left") { page -= 1 }.disabled(page <= 1)
                    Spacer()
                    Text("Página \(page) · \(list.pagination.total) registos").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Seguinte", systemImage: "chevron.right") { page += 1 }.disabled(!list.pagination.hasMore)
                }
                .labelStyle(.iconOnly).padding(8).background(.bar)
            }
        }
    }
}
