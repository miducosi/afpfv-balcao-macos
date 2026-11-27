import SwiftUI

/// Senhas de refeição (área Refeitório).
struct MealsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = "pending"
    @State private var query = ""
    @State private var search = ""
    @State private var selected: String?

    private let filters = [("pending", "Pedidas"), ("approved", "Aprovadas"), ("closed", "Fechadas")]

    var body: some View {
        MasterDetail {
            VStack(spacing: 0) {
                ListToolbar(query: $query, prompt: "Nome, entidade ou código", filters: filters, filter: $filter)
                    .debounce(query, into: $search)
                Divider()
                Loader(key: [filter, search], load: {
                    try await model.api.get("admin/meals", query: ["filter": filter, "q": search]) as [StaffMealTicket]
                }) { tickets, _ in
                    List(tickets, selection: $selected) { ticket in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(ticket.displayName).font(.headline).lineLimit(1)
                                Spacer()
                                Text(Formatting.euros(ticket.totalCents)).monospacedDigit()
                            }
                            Text("\(ticket.code) · \(Labels.label(Labels.mealKind, ticket.kind)) · \(Formatting.plural(ticket.items.reduce(0) { $0 + $1.quantity }, "refeição", "refeições"))")
                                .font(.callout).foregroundStyle(.secondary)
                            HStack {
                                StatusBadge(ticket.status, labels: Labels.mealStatus)
                                if ticket.charged && !ticket.paid { StatusBadge("Por pagar", tone: .warning) }
                                Spacer()
                                if let next = ticket.next {
                                    Text("\(next.periodName) · \(Formatting.day(next.date))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(ticket.id)
                    }
                    .overlay { if tickets.isEmpty { ContentUnavailableView("Sem senhas", systemImage: "fork.knife") } }
                }
            }
        } detail: {
            if let selected {
                MealDetailView(id: selected).id(selected)
            } else {
                NoSelection(text: "Escolha uma senha.")
            }
        }
    }
}

struct MealDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    let id: String
    @State private var prompt: ReasonPrompt?
    @State private var approving = false
    @State private var charged = true

    var body: some View {
        Loader(load: { try await model.api.get("admin/meals/\(id)") as StaffMealTicket }) { ticket, _ in
            Form {
                SwiftUI.Section {
                    DetailHeader(title: ticket.displayName, subtitle: [ticket.code, ticket.reference].compactMap { $0 }.joined(separator: " · ")) {
                        StatusBadge(ticket.status, labels: Labels.mealStatus)
                        StatusBadge(Labels.label(Labels.mealKind, ticket.kind), tone: .neutral)
                        if ticket.charged { StatusBadge(ticket.paid ? "Paga" : "Por pagar", tone: ticket.paid ? .success : .warning) }
                    }
                    HStack {
                        if ticket.status == "PENDING" {
                            Button("Aprovar", systemImage: "checkmark") { approving = true }
                                .buttonStyle(.borderedProminent).tint(.green)
                            Button("Recusar", systemImage: "xmark") {
                                prompt = reasonPrompt("Recusar senha", confirm: "Recusar", path: "reject")
                            }
                        }
                        if ticket.status == "APPROVED" {
                            Button("Anular", systemImage: "nosign", role: .destructive) {
                                prompt = reasonPrompt("Anular senha", confirm: "Anular", path: "cancel")
                            }
                        }
                    }
                }

                if let token = ticket.token, ticket.status == "APPROVED",
                   let image = QRCode.image(for: AppConfig.current.webURL.appendingPathComponent("r/\(token)").absoluteString)
                {
                    SwiftUI.Section("QR") {
                        HStack(spacing: 16) {
                            Image(nsImage: image).interpolation(.none).resizable().frame(width: 120, height: 120)
                            Text(ticket.code).font(.title2.monospaced().weight(.semibold)).textSelection(.enabled)
                        }
                    }
                }

                SwiftUI.Section("Refeições") {
                    ForEach(ticket.items) { item in
                        LabeledContent {
                            Text("\(item.usedCount)/\(item.quantity)").monospacedDigit()
                                .foregroundStyle(item.cancelledAt != nil ? .secondary : .primary)
                        } label: {
                            Text("\(item.service.period.name) · \(Formatting.day(item.service.date))")
                                .strikethrough(item.cancelledAt != nil)
                            Text("\(item.service.period.startsAt)–\(item.service.period.endsAt) · \(Formatting.euros(item.priceCents))")
                        }
                    }
                    LabeledContent("Total", value: Formatting.euros(ticket.totalCents))
                }

                SwiftUI.Section("Pedido") {
                    OptionalRow("Titular", ticket.holderName)
                    OptionalRow("Entidade", ticket.entityName)
                    OptionalRow("Pedido por", [ticket.requesterName, ticket.requesterEmail].compactMap { $0 }.joined(separator: " · "))
                    LabeledContent("Origem", value: Labels.label(Labels.mealOrigin, ticket.origin))
                    OptionalRow("Restrições alimentares", ticket.dietaryNotes)
                    OptionalRow("Motivo da recusa", ticket.rejectionReason)
                    OptionalRow("Notas internas", ticket.internalNotes)
                    LabeledContent("Pedida em", value: Formatting.dateTime(ticket.createdAt))
                }
            }
            .formStyle(.grouped)
            .disabled(feedback.busy)
            .confirmationDialog("Aprovar senha", isPresented: $approving) {
                Button("Aprovar e cobrar \(Formatting.euros(ticket.totalCents))") { approve(charged: true) }
                Button("Aprovar sem cobrar") { approve(charged: false) }
            } message: {
                Text("Cobrar cria uma cobrança na Tesouraria.")
            }
        }
        .reasonSheet($prompt)
    }

    private func approve(charged: Bool) {
        Task {
            if await feedback.run({ try await model.api.mutate("admin/meals/\(id)/approve", body: ["charged": charged]) }) {
                feedback.requestReload()
            }
        }
    }

    private func reasonPrompt(_ title: String, confirm: String, path: String) -> ReasonPrompt {
        ReasonPrompt(title: title, message: "O motivo fica registado e é comunicado a quem pediu.", confirm: confirm,
                     destructive: true) { reason in
            let ok = await feedback.run {
                try await model.api.mutate("admin/meals/\(id)/\(path)", body: ["reason": reason])
            }
            if ok { feedback.requestReload() }
            return ok
        }
    }
}

/// Mapa de refeições: pedidas e servidas por dia e período.
struct MealMapView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Loader(load: { try await model.api.get("admin/meals/map") as [MealDayMap] }) { days, _ in
            let periods = days.flatMap { $0.periods.map(\.periodName) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            ScrollView {
                Grid(alignment: .trailing, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow {
                        Text("Dia").gridColumnAlignment(.leading)
                        ForEach(periods, id: \.self) { Text($0) }
                    }
                    .font(.headline)
                    Divider()
                    ForEach(days) { day in
                        GridRow {
                            Text(Formatting.day(day.date))
                            ForEach(periods, id: \.self) { name in
                                if let period = day.periods.first(where: { $0.periodName == name }) {
                                    VStack(alignment: .trailing, spacing: 0) {
                                        Text("\(period.ordered)").font(.title3.monospacedDigit())
                                        Text("\(period.served) servidas").font(.caption).foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("—").foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay { if days.isEmpty { ContentUnavailableView("Sem refeições marcadas", systemImage: "calendar") } }
        }
    }
}

/// Entrada do refeitório (Refeitório ou Validação de refeições). Unitária: consome 1; grupo: consulta e depois diz quantas entram.
struct MealScanView: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    @State private var outcome: MealScanOutcome?
    @State private var lastInput: String?
    @State private var quantity = 1
    @State private var scanning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScanInput(prompt: "QR ou código da senha") { input in
                    quantity = 1
                    scan(input, quantity: nil)
                }
                if scanning { ProgressView() }
                if let outcome {
                    MealOutcomeCard(outcome: outcome)
                    if outcome.kind == "GROUP", outcome.result == "VALID", outcome.consumed == 0, outcome.remaining > 0,
                       let lastInput
                    {
                        HStack {
                            Stepper("Entram \(Formatting.plural(quantity, "pessoa", "pessoas"))", value: $quantity, in: 1...outcome.remaining)
                            Spacer()
                            Button("Confirmar entrada") { scan(lastInput, quantity: quantity) }
                                .buttonStyle(.borderedProminent).tint(.green)
                                .keyboardShortcut(.return, modifiers: .command)
                        }
                        .padding(14)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .disabled(scanning)
    }

    private func scan(_ input: String, quantity: Int?) {
        Task {
            scanning = true
            defer { scanning = false }
            do {
                let result: MealScanOutcome = try await model.api.send(
                    "POST", "admin/meal-scans", body: MealScan(input: input, quantity: quantity))
                outcome = result
                lastInput = input
                let ok = result.result == "VALID"
                NSSound(named: ok ? "Glass" : "Basso")?.play()
            } catch {
                feedback.error = error.localizedDescription
            }
        }
    }

    private struct MealScan: Encodable {
        let input: String
        let quantity: Int?
    }
}

private struct MealOutcomeCard: View {
    let outcome: MealScanOutcome

    var body: some View {
        let tone: Color = outcome.result == "VALID" ? .green : Tone.of(outcome.result).color
        VStack(alignment: .leading, spacing: 8) {
            Label(Labels.label(Labels.mealScanResult, outcome.result),
                  systemImage: outcome.result == "VALID" ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.largeTitle.weight(.bold)).foregroundStyle(tone)
            if let name = outcome.holderName ?? outcome.entityName { Text(name).font(.title2.weight(.semibold)) }
            HStack(spacing: 14) {
                if let kind = outcome.kind { Text(Labels.label(Labels.mealKind, kind)) }
                if let period = outcome.periodName { Text(period) }
            }
            .foregroundStyle(.secondary)
            if outcome.consumed > 0 {
                Text("Entraram \(Formatting.plural(outcome.consumed, "pessoa", "pessoas")).").font(.title3)
            }
            Text("Restam \(outcome.remaining) neste período.").foregroundStyle(.secondary)
            if let next = outcome.nextMeal {
                Text("Próxima: \(next.periodName), \(Formatting.day(next.date)) às \(next.startsAt)").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
