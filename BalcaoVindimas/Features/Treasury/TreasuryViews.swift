import SwiftUI

/// Tesouraria: comprovativos por validar e totais.
struct SubmissionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    @State private var prompt: ReasonPrompt?

    var body: some View {
        Loader(load: { try await model.api.get("admin/payments") as TreasuryOverview }) { overview, _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        total("Por pagar", overview.totals.pendingCents, .blue)
                        total("Em atraso", overview.totals.overdueCents, .orange)
                        total("Pago", overview.totals.paidCents, .green)
                    }
                    Text("Comprovativos por validar").font(.title3.weight(.semibold))
                    if overview.pendingSubmissions.isEmpty {
                        ContentUnavailableView("Nada por validar", systemImage: "checkmark.seal",
                                               description: Text("Os comprovativos enviados aparecem aqui."))
                    }
                    ForEach(overview.pendingSubmissions) { submission in
                        SubmissionCard(submission: submission, onApprove: { approve(submission) }, onReject: {
                            prompt = ReasonPrompt(title: "Recusar comprovativo",
                                                  message: "O motivo vai para quem pagou.", confirm: "Recusar",
                                                  destructive: true) { reason in
                                await review(submission, decision: "reject", reason: reason)
                            }
                        })
                    }
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
            }
            .disabled(feedback.busy)
        }
        .reasonSheet($prompt)
    }

    private func total(_ label: String, _ cents: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Text(Formatting.euros(cents)).font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func approve(_ submission: TreasurySubmission) {
        Task { await review(submission, decision: "approve", reason: nil) }
    }

    private func review(_ submission: TreasurySubmission, decision: String, reason: String?) async -> Bool {
        let ok = await feedback.run {
            try await model.api.mutate("admin/payment-submissions/\(submission.id)/review",
                                       body: SubmissionReview(decision: decision, reason: reason))
        }
        if ok { feedback.requestReload() }
        return ok
    }
}

private struct SubmissionReview: Encodable {
    let decision: String
    let reason: String?
}

private struct SubmissionCard: View {
    let submission: TreasurySubmission
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(submission.payerName).font(.headline)
                    Text("\(submission.caseReference) · \(submission.chargeDescription)").foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatting.euros(submission.amountCents)).font(.title3.weight(.semibold).monospacedDigit())
                    if submission.amountCents != submission.chargeAmountCents {
                        Text("Cobrança: \(Formatting.euros(submission.chargeAmountCents))").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            HStack(spacing: 14) {
                Label(Labels.label(Labels.paymentMethod, submission.method), systemImage: "creditcard")
                Label(Formatting.date(submission.paidAt), systemImage: "calendar")
                if let reference = submission.reference { Label(reference, systemImage: "number").textSelection(.enabled) }
            }
            .font(.callout).foregroundStyle(.secondary)
            if let notes = submission.notes { Text(notes).font(.callout) }
            HStack {
                FileButton(file: submission.proof)
                Spacer()
                Button("Recusar", systemImage: "xmark", action: onReject)
                Button("Validar pagamento", systemImage: "checkmark", action: onApprove)
                    .buttonStyle(.borderedProminent).tint(.green)
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Cobranças (todas as áreas), com registo de pagamentos manuais.
struct ChargesView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = "open"
    @State private var query = ""
    @State private var search = ""
    @State private var selected: String?

    private let filters = [("open", "Por pagar"), ("overdue", "Em atraso"), ("paid", "Pagas"), ("all", "Todas")]

    var body: some View {
        MasterDetail {
            VStack(spacing: 0) {
                ListToolbar(query: $query, prompt: "Referência, nome ou email", filters: filters, filter: $filter)
                    .debounce(query, into: $search)
                Divider()
                Loader(key: [filter, search], load: {
                    try await model.api.get("admin/charges", query: ["filter": filter, "q": search]) as [TreasuryCharge]
                }) { charges, _ in
                    List(charges, selection: $selected) { charge in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(charge.payerName).font(.headline).lineLimit(1)
                                Spacer()
                                Text(Formatting.euros(charge.amountCents)).monospacedDigit()
                            }
                            Text("\(charge.caseReference) · \(charge.description)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: 6) {
                                StatusBadge(charge.displayStatus, labels: Labels.chargeStatus)
                                if charge.awaitingReview { StatusBadge("Comprovativo por validar", tone: .info) }
                                Spacer()
                                Text("Prazo \(Formatting.date(charge.dueAt))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(charge.id)
                    }
                    .overlay { if charges.isEmpty { ContentUnavailableView("Sem cobranças", systemImage: "eurosign.circle") } }
                }
            }
        } detail: {
            if let selected {
                ChargeDetailView(id: selected).id(selected)
            } else {
                NoSelection(text: "Escolha uma cobrança.")
            }
        }
    }
}

struct ChargeDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    let id: String
    @State private var registering = false

    var body: some View {
        Loader(load: { try await model.api.get("admin/charges/\(id)") as TreasuryCharge }) { charge, _ in
            Form {
                SwiftUI.Section {
                    DetailHeader(title: charge.description, subtitle: "\(charge.caseReference) · \(charge.payerName)") {
                        StatusBadge(charge.displayStatus, labels: Labels.chargeStatus)
                        Text(Labels.label(Labels.chargeKind, charge.kind)).font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent("Valor") {
                        Text(Formatting.euros(charge.amountCents)).font(.title3.weight(.semibold).monospacedDigit())
                    }
                    LabeledContent("Prazo", value: Formatting.date(charge.dueAt))
                    if let paidAt = charge.paidAt { LabeledContent("Paga em", value: Formatting.date(paidAt)) }
                    OptionalRow("Motivo da anulação", charge.cancelReason)
                    LabeledContent("Email") {
                        Link(charge.payerEmail, destination: URL(string: "mailto:\(charge.payerEmail)")!)
                    }
                    if charge.status == "PENDING" {
                        Button("Registar pagamento", systemImage: "plus.circle") { registering = true }
                    }
                }

                if charge.lines.count > 1 {
                    SwiftUI.Section("Detalhe") {
                        ForEach(Array(charge.lines.enumerated()), id: \.offset) { _, line in
                            LabeledContent(line.label, value: Formatting.euros(line.cents))
                        }
                    }
                }

                if !charge.payments.isEmpty {
                    SwiftUI.Section("Pagamentos") {
                        ForEach(charge.payments) { payment in
                            LabeledContent {
                                Text(Formatting.euros(payment.amountCents)).monospacedDigit()
                            } label: {
                                Text("\(Labels.label(Labels.paymentMethod, payment.method)) · \(Formatting.date(payment.paidAt))")
                                if let reference = payment.reference { Text(reference) }
                            }
                        }
                    }
                }

                if !charge.submissions.isEmpty {
                    SwiftUI.Section("Comprovativos") {
                        ForEach(charge.submissions) { submission in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(Labels.label(Labels.paymentMethod, submission.method)) · \(Formatting.euros(submission.amountCents))")
                                    StatusBadge(submission.status, labels: Labels.submissionStatus)
                                    Spacer()
                                    Text(Formatting.date(submission.paidAt)).foregroundStyle(.secondary)
                                }
                                FileButton(file: submission.proof)
                                if let reason = submission.rejectionReason { Text(reason).font(.callout).foregroundStyle(.secondary) }
                            }
                        }
                        if charge.awaitingReview {
                            Button("Validar em Comprovativos") { model.selection = .treasury }
                        }
                    }
                }

                if !charge.invoices.isEmpty {
                    SwiftUI.Section("Faturas") {
                        ForEach(charge.invoices) { invoice in
                            LabeledContent {
                                FileButton(file: invoice.file)
                            } label: {
                                Text("\(Labels.label(Labels.invoiceKind, invoice.kind)) \(invoice.number)")
                                Text(Formatting.date(invoice.issuedOn))
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .sheet(isPresented: $registering) { ManualPaymentSheet(charge: charge) }
        }
    }
}

private struct ManualPaymentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    let charge: TreasuryCharge
    @State private var method = "TRANSFER"
    @State private var paidAt = Date()
    @State private var reference = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                SwiftUI.Section {
                    LabeledContent("Cobrança", value: charge.description)
                    LabeledContent("Valor", value: Formatting.euros(charge.amountCents))
                }
                SwiftUI.Section {
                    Picker("Método", selection: $method) {
                        ForEach(Labels.paymentMethods, id: \.self) { Text(Labels.label(Labels.paymentMethod, $0)).tag($0) }
                    }
                    DatePicker("Data do pagamento", selection: $paidAt, in: ...Date(), displayedComponents: .date)
                    TextField("Referência (opcional)", text: $reference)
                    TextField("Notas (opcional)", text: $notes, axis: .vertical).lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Registar pagamento") {
                    Task {
                        let body = ManualPayment(method: method, paidAt: Formatting.dayString(paidAt),
                                                 reference: reference.nilIfBlank, notes: notes.nilIfBlank)
                        if await feedback.run({ try await model.api.mutate("admin/charges/\(charge.id)/payments", body: body) }) {
                            feedback.requestReload()
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(feedback.busy)
            }
            .padding()
        }
        .frame(width: 460)
    }

    private struct ManualPayment: Encodable {
        let method: String
        let paidAt: String
        let reference: String?
        let notes: String?
    }
}

extension String {
    /// `nil` quando vazio (campos opcionais da API).
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
