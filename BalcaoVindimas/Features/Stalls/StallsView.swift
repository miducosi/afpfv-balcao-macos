import SwiftUI

/// Candidaturas a terrados (área Terrados).
struct StallsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = "to_review"
    @State private var query = ""
    @State private var selected: String?

    private let filters = [
        ("to_review", "Por analisar"), ("awaiting", "Elementos"), ("waitlisted", "Espera"),
        ("approved", "Aprovadas"), ("closed", "Fechadas"),
    ]

    var body: some View {
        MasterDetail {
            VStack(spacing: 0) {
                ListToolbar(query: $query, prompt: "Filtrar por nome, referência ou lote", filters: filters, filter: $filter)
                Divider()
                Loader(key: filter, load: {
                    try await model.api.get("admin/stalls", query: ["filter": filter]) as [StaffStallApplication]
                }) { items, _ in
                    let visible = items.filter(matches)
                    List(visible, selection: $selected) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.holderName).font(.headline).lineLimit(1)
                                Spacer()
                                if let plot = item.plotCode { Text("Lote \(plot)").font(.caption.monospaced()) }
                            }
                            Text([item.reference, item.stallTypeName].compactMap { $0 }.joined(separator: " · "))
                                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: 6) {
                                StatusBadge(item.status, labels: Labels.stallStatus)
                                if !item.problems.isEmpty {
                                    StatusBadge(Formatting.plural(item.problems.count, "pendência", "pendências"), tone: .warning)
                                }
                                Spacer()
                                Text(Formatting.date(item.submittedAt ?? item.updatedAt)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(item.id)
                    }
                    .overlay { if visible.isEmpty { ContentUnavailableView("Sem candidaturas", systemImage: "storefront") } }
                }
            }
        } detail: {
            if let selected {
                StallDetailView(id: selected).id(selected)
            } else {
                NoSelection(text: "Escolha uma candidatura.")
            }
        }
    }

    private func matches(_ item: StaffStallApplication) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [item.holderName, item.applicantName, item.reference ?? "", item.plotCode ?? "", item.nif]
            .contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

struct StallDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    let id: String
    @State private var decision: StallDecision?
    @State private var prompt: ReasonPrompt?

    var body: some View {
        Loader(load: { try await model.api.get("admin/stalls/\(id)") as StaffStallApplication }) { app, _ in
            Form {
                SwiftUI.Section {
                    DetailHeader(title: app.holderName,
                                 subtitle: [app.reference, app.stallTypeName].compactMap { $0 }.joined(separator: " · ")) {
                        StatusBadge(app.status, labels: Labels.stallStatus)
                        if let plot = app.plotCode { StatusBadge("Lote \(plot)", tone: .success) }
                    }
                    if !app.staffActions.isEmpty {
                        HStack {
                            ForEach(app.staffActions, id: \.self) { action in
                                Button(Labels.label(Labels.stallAction, action)) {
                                    decision = StallDecision(action: action, plots: app.freePlots)
                                }
                                .buttonStyle(.bordered)
                                .tint(action == "approve" ? .green : (action == "reject" || action == "cancel") ? .red : nil)
                            }
                        }
                    }
                }

                if !app.problems.isEmpty {
                    SwiftUI.Section("Pendências") {
                        ForEach(app.problems, id: \.requirementId) { problem in
                            Label("\(problem.name): \(Labels.label(Labels.requirementProblem, problem.problem))",
                                  systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                    }
                }

                SwiftUI.Section("Titular") {
                    LabeledContent("Tipo", value: Labels.label(Labels.holderType, app.holderType))
                    LabeledContent("NIF") { Text(app.nif).textSelection(.enabled) }
                    LabeledContent("Morada") {
                        Text("\(app.address)\n\(app.postalCode) \(app.locality)").multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                    LabeledContent("Telefone") { Text(app.phone).textSelection(.enabled) }
                    LabeledContent("Conta") {
                        Text("\(app.applicantName) · \(app.applicantEmail)").textSelection(.enabled)
                    }
                }

                SwiftUI.Section("Atividade") {
                    LabeledContent("Atividade") { Text(app.activityDescription).multilineTextAlignment(.trailing) }
                    LabeledContent("Produtos") { Text(app.productsDescription).multilineTextAlignment(.trailing) }
                    LabeledContent("Dimensões pedidas",
                                   value: "\(Formatting.meters(app.requestedWidthM)) × \(Formatting.meters(app.requestedDepthM))")
                    if let kw = app.powerNeedsKw { LabeledContent("Potência", value: "\(kw.formatted()) kW") }
                    LabeledContent("Água", value: app.needsWater ? "Sim" : "Não")
                    OptionalRow("Zona preferida", app.preferredZoneName)
                    if let cents = app.quotedAmountCents { LabeledContent("Valor", value: Formatting.euros(cents)) }
                    OptionalRow("Motivo da decisão", app.decisionReason)
                }

                SwiftUI.Section("Documentos") {
                    if app.documents.isEmpty { Text("Sem documentos.").foregroundStyle(.secondary) }
                    ForEach(app.documents) { document in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(document.requirementName ?? "Outro documento").font(.headline)
                                StatusBadge(document.reviewStatus, labels: Labels.documentReview)
                                Spacer()
                                if let expires = document.expiresOn {
                                    Text("Válido até \(Formatting.day(expires))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            FileButton(file: document.file)
                            if let note = document.reviewNote { Text(note).font(.callout).foregroundStyle(.secondary) }
                            if document.reviewStatus == "PENDING" {
                                HStack {
                                    Button("Aceitar", systemImage: "checkmark") { startReview(document, status: "ACCEPTED") }
                                    Button("Recusar", systemImage: "xmark") {
                                        prompt = ReasonPrompt(title: "Recusar documento",
                                                              message: "A nota vai para o candidato.", confirm: "Recusar",
                                                              destructive: true) { note in
                                            await review(document, status: "REJECTED", note: note)
                                        }
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(feedback.busy)
        }
        .sheet(item: $decision) { StallDecisionSheet(applicationId: id, decision: $0) }
        .reasonSheet($prompt)
    }

    @discardableResult
    private func review(_ document: StallDocument, status: String, note: String?) async -> Bool {
        let ok = await feedback.run {
            try await model.api.mutate("admin/stall-documents/\(document.id)/review",
                                       body: DocumentReview(reviewStatus: status, reviewNote: note?.isEmpty == false ? note : nil))
        }
        if ok { feedback.requestReload() }
        return ok
    }

    private func startReview(_ document: StallDocument, status: String) {
        Task { await review(document, status: status, note: nil) }
    }
}

private struct DocumentReview: Encodable {
    let reviewStatus: String
    let reviewNote: String?
}

struct StallDecision: Identifiable {
    let action: String
    let plots: [FreePlot]
    var id: String { action }
}

private struct StallDecisionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    let applicationId: String
    let decision: StallDecision
    @State private var plotId: String?
    @State private var message = ""

    private var needsPlot: Bool { decision.action == "approve" }
    private var needsMessage: Bool { decision.action == "request_documents" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Labels.label(Labels.stallAction, decision.action)).font(.headline)
            if needsPlot {
                if decision.plots.isEmpty {
                    Label("Não há lotes livres compatíveis.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    Picker("Lote", selection: $plotId) {
                        Text("Escolher…").tag(String?.none)
                        ForEach(decision.plots) { plot in
                            Text("\(plot.code) · \(plot.zoneName) · \(Formatting.meters(plot.widthM)) × \(Formatting.meters(plot.depthM))")
                                .tag(Optional(plot.id))
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(needsMessage ? "Mensagem para o candidato" : "Mensagem para o candidato (opcional)")
                    .font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $message)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Confirmar") {
                    Task {
                        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        if await feedback.run({
                            try await model.api.mutate("admin/stalls/\(applicationId)/decision",
                                                       body: DecisionBody(action: decision.action, plotId: needsPlot ? plotId : nil,
                                                                  message: text.isEmpty ? nil : text))
                        }) {
                            feedback.requestReload()
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(feedback.busy || (needsPlot && plotId == nil)
                    || (needsMessage && message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private struct DecisionBody: Encodable {
        let action: String
        let plotId: String?
        let message: String?
    }
}
