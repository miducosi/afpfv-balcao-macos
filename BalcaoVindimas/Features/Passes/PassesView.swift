import SwiftUI

/// Livres-trânsito: pedidos e emitidos (área Livres-trânsito).
struct PassesView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = "pending"
    @State private var query = ""
    @State private var search = ""
    @State private var selected: String?

    private let filters = [("pending", "Pedidos"), ("issued", "Emitidos"), ("closed", "Fechados")]

    var body: some View {
        MasterDetail {
            VStack(spacing: 0) {
                ListToolbar(query: $query, prompt: "Nome, matrícula ou código", filters: filters, filter: $filter)
                    .debounce(query, into: $search)
                Divider()
                Loader(key: [filter, search], load: {
                    try await model.api.get("admin/passes", query: ["filter": filter, "q": search]) as [StaffPass]
                }) { passes, _ in
                    List(passes, selection: $selected) { pass in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3).fill(Color(hex: pass.typeColor)).frame(width: 6)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(pass.holderName).font(.headline).lineLimit(1)
                                    Spacer()
                                    Text(pass.plate).font(.callout.monospaced())
                                }
                                Text([pass.typeName, pass.organization].compactMap { $0 }.joined(separator: " · "))
                                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                HStack {
                                    StatusBadge(pass.status, labels: Labels.passStatus)
                                    Spacer()
                                    Text(pass.code).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(pass.id)
                    }
                    .overlay { if passes.isEmpty { ContentUnavailableView("Sem livres-trânsito", systemImage: "car") } }
                }
            }
        } detail: {
            if let selected {
                PassDetailView(id: selected).id(selected)
            } else {
                NoSelection(text: "Escolha um livre-trânsito.")
            }
        }
    }
}

struct PassDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    let id: String
    @State private var prompt: ReasonPrompt?

    var body: some View {
        Loader(load: { try await model.api.get("admin/passes/\(id)") as StaffPass }) { pass, _ in
            Form {
                SwiftUI.Section {
                    DetailHeader(title: pass.holderName, subtitle: [pass.organization, pass.reference].compactMap { $0 }.joined(separator: " · ")) {
                        StatusBadge(pass.status, labels: Labels.passStatus)
                        StatusBadge(pass.typeName, tone: .neutral).foregroundStyle(Color(hex: pass.typeColor))
                    }
                    HStack {
                        if pass.status == "PENDING" {
                            Button("Emitir", systemImage: "checkmark.seal") { issue(pass) }
                                .buttonStyle(.borderedProminent).tint(.green)
                            Button("Recusar", systemImage: "xmark") {
                                prompt = reasonPrompt("Recusar pedido", confirm: "Recusar", path: "reject")
                            }
                        }
                        if pass.status == "ISSUED" {
                            Button("Revogar", systemImage: "nosign", role: .destructive) {
                                prompt = reasonPrompt("Revogar livre-trânsito", confirm: "Revogar", path: "revoke")
                            }
                        }
                    }
                }

                if let token = pass.token, pass.status == "ISSUED" {
                    SwiftUI.Section("QR") {
                        let content = AppConfig.current.webURL.appendingPathComponent("v/\(token)").absoluteString
                        HStack(alignment: .top, spacing: 16) {
                            if let image = QRCode.image(for: content) {
                                Image(nsImage: image).interpolation(.none).resizable().frame(width: 140, height: 140)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(pass.code).font(.title2.monospaced().weight(.semibold)).textSelection(.enabled)
                                Text("Código do dístico. O QR leva só o token.").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                SwiftUI.Section("Veículo e acesso") {
                    LabeledContent("Matrícula") { Text(pass.plate).font(.body.monospaced()).textSelection(.enabled) }
                    OptionalRow("Veículo", pass.vehicleDescription)
                    LabeledContent("Zonas", value: pass.zones.isEmpty ? "—" : pass.zones.joined(separator: ", "))
                    if pass.validFrom != nil || pass.validTo != nil {
                        LabeledContent("Validade", value: "\(Formatting.dateTime(pass.validFrom)) – \(Formatting.dateTime(pass.validTo))")
                    }
                    OptionalRow("Motivo do pedido", pass.purpose)
                }

                SwiftUI.Section("Contacto") {
                    OptionalRow("Pedido por", pass.requesterName)
                    OptionalRow("Email", pass.email)
                    OptionalRow("Telefone", pass.phone)
                    LabeledContent("Origem", value: Labels.label(Labels.passOrigin, pass.origin))
                    LabeledContent("Pedido em", value: Formatting.dateTime(pass.createdAt))
                    if let issued = pass.issuedAt { LabeledContent("Emitido em", value: Formatting.dateTime(issued)) }
                }

                if pass.rejectionReason != nil || pass.revokedReason != nil || pass.internalNotes != nil {
                    SwiftUI.Section("Notas") {
                        OptionalRow("Motivo da recusa", pass.rejectionReason)
                        OptionalRow("Motivo da revogação", pass.revokedReason)
                        OptionalRow("Notas internas", pass.internalNotes)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(feedback.busy)
        }
        .reasonSheet($prompt)
    }

    private func issue(_ pass: StaffPass) {
        Task {
            if await feedback.run({ try await model.api.mutate("admin/passes/\(pass.id)/issue") }) { feedback.requestReload() }
        }
    }

    private func reasonPrompt(_ title: String, confirm: String, path: String) -> ReasonPrompt {
        ReasonPrompt(title: title, message: "O motivo fica registado e é comunicado a quem pediu.", confirm: confirm,
                     destructive: true) { reason in
            let ok = await feedback.run {
                try await model.api.mutate("admin/passes/\(id)/\(path)", body: ["reason": reason])
            }
            if ok { feedback.requestReload() }
            return ok
        }
    }
}

/// Validação no terreno (Livres-trânsito ou Controlo de acessos). Cada leitura fica registada.
struct PassScanView: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    @AppStorage("passCheckpoint") private var checkpoint = ""
    @State private var outcome: PassScanOutcome?
    @State private var scanning = false

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Ponto de controlo (ex.: Portão Norte)", text: $checkpoint)
                        .textFieldStyle(.roundedBorder)
                    ScanInput(prompt: "QR ou código do dístico") { scan($0) }
                    if scanning { ProgressView() }
                    if let outcome { PassOutcomeCard(outcome: outcome) }
                }
                .padding(24)
            }
            .frame(minWidth: 420, idealWidth: 520)

            VStack(alignment: .leading, spacing: 0) {
                Text("Últimas leituras").font(.headline).padding()
                Loader(load: { try await model.api.get("admin/pass-scans") as [PassScanLog] }) { logs, _ in
                    List(logs) { log in
                        HStack {
                            Image(systemName: log.result == "VALID" ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(Tone.of(log.result).color)
                            VStack(alignment: .leading) {
                                Text(log.holderName ?? log.input).lineLimit(1)
                                Text([log.plate, log.checkpoint, log.scannedByName].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(log.createdAt.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minWidth: 280, idealWidth: 340)
        }
    }

    private func scan(_ input: String) {
        Task {
            scanning = true
            defer { scanning = false }
            do {
                outcome = try await model.api.send("POST", "admin/pass-scans",
                                                   body: PassScan(input: input, checkpoint: checkpoint.nilIfBlank))
                NSSound(named: outcome?.result == "VALID" ? "Glass" : "Basso")?.play()
                feedback.requestReload()
            } catch {
                feedback.error = error.localizedDescription
            }
        }
    }

    private struct PassScan: Encodable {
        let input: String
        let checkpoint: String?
    }
}

private struct PassOutcomeCard: View {
    let outcome: PassScanOutcome

    var body: some View {
        let valid = outcome.result == "VALID"
        VStack(alignment: .leading, spacing: 10) {
            Label(Labels.label(Labels.passScanResult, outcome.result),
                  systemImage: valid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(valid ? .green : Tone.of(outcome.result).color)
            if let pass = outcome.pass {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(hex: pass.typeColor)).frame(width: 10, height: 44)
                    VStack(alignment: .leading) {
                        Text(pass.holderName).font(.title2.weight(.semibold))
                        Text([pass.organization, pass.typeName].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                    }
                }
                Text(pass.plate).font(.system(size: 28, weight: .bold, design: .monospaced))
                if !pass.zones.isEmpty { Text("Zonas: \(pass.zones.joined(separator: ", "))") }
                if pass.validFrom != nil || pass.validTo != nil {
                    Text("Válido \(Formatting.dateTime(pass.validFrom)) – \(Formatting.dateTime(pass.validTo))").foregroundStyle(.secondary)
                }
            }
            if outcome.previousScans > 0 {
                Text("Já lido \(Formatting.plural(outcome.previousScans, "vez", "vezes")) antes.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((valid ? Color.green : Tone.of(outcome.result).color).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
