import SwiftUI

struct RequestDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    let id: String

    @State private var reply = ""
    @State private var internalNote = false

    var body: some View {
        Loader(load: { try await model.api.get("admin/requests/\(id)") as CaseDetail }) { detail, reload in
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header(detail, reload: reload)
                            Divider()
                            ForEach(detail.messages) { MessageBubble(message: $0) }
                            if !detail.events.isEmpty {
                                DisclosureGroup("Histórico (\(detail.events.count))") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(detail.events) { event in
                                            HStack(alignment: .firstTextBaseline) {
                                                Text(event.label)
                                                if let actor = event.actorName { Text("· \(actor)").foregroundStyle(.secondary) }
                                                Spacer()
                                                Text(Formatting.dateTime(event.createdAt)).foregroundStyle(.secondary)
                                            }
                                            .font(.callout)
                                        }
                                    }
                                    .padding(.top, 6)
                                }
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(20)
                    }
                    .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                }
                if detail.canReply { composer(reload: reload) }
            }
        }
    }

    @ViewBuilder
    private func header(_ detail: CaseDetail, reload: @escaping () async -> Void) -> some View {
        DetailHeader(title: detail.subject, subtitle: "\(detail.reference) · \(Labels.label(Labels.caseType, detail.type))") {
            StatusBadge(detail.status, labels: Labels.caseStatus)
            StatusBadge(Labels.label(Labels.casePriority, detail.priority), tone: .of(detail.priority))
            Text(Labels.label(Labels.area, detail.area)).font(.caption).foregroundStyle(.secondary)
        }
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Text("Requerente").foregroundStyle(.secondary)
                Text(detail.requesterName).textSelection(.enabled)
            }
            GridRow {
                Text("Contacto").foregroundStyle(.secondary)
                HStack {
                    Link(detail.requesterEmail, destination: URL(string: "mailto:\(detail.requesterEmail)")!)
                    if let phone = detail.requesterPhone { Text("· \(phone)").textSelection(.enabled) }
                }
            }
            if let category = detail.categoryName {
                GridRow { Text("Assunto").foregroundStyle(.secondary); Text(category) }
            }
            GridRow {
                Text("Responsável").foregroundStyle(.secondary)
                Text(detail.assignedToName ?? "Ninguém")
            }
            GridRow { Text("Criado").foregroundStyle(.secondary); Text(Formatting.dateTime(detail.createdAt)) }
        }
        .font(.callout)

        HStack {
            Menu("Estado: \(Labels.label(Labels.caseStatus, detail.status))") {
                ForEach(Labels.caseStatusOrder.filter { $0 != detail.status }, id: \.self) { status in
                    Button(Labels.label(Labels.caseStatus, status)) {
                        Task {
                            if await feedback.run({
                                try await model.api.mutate("admin/requests/\(id)/status", method: "PUT", body: ["status": status])
                            }) { feedback.requestReload() }
                        }
                    }
                }
            }
            .fixedSize()
            if detail.assignedToId != model.me?.user.id {
                Button("Ficar com o pedido", systemImage: "person.crop.circle.badge.checkmark") {
                    Task {
                        if await feedback.run({ try await model.api.mutate("admin/requests/\(id)/assign") }) {
                            feedback.requestReload()
                        }
                    }
                }
            }
            if let link = detail.link, let section = section(for: link.kind), model.can(section.capability) {
                Button("Abrir \(section.title.lowercased())", systemImage: section.icon) { model.selection = section }
            }
        }
        .disabled(feedback.busy)
    }

    private func section(for kind: String) -> Section? {
        switch kind {
        case "stall": .stalls
        case "race": .races
        case "pass": .passes
        case "meal": .meals
        default: nil
        }
    }

    private func composer(reload: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            TextEditor(text: $reply)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(internalNote ? Color.yellow.opacity(0.12) : Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .overlay(alignment: .topLeading) {
                    if reply.isEmpty {
                        Text(internalNote ? "Nota interna (só a equipa vê)" : "Responder a quem pediu")
                            .foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                Toggle("Nota interna", isOn: $internalNote)
                Spacer()
                Button(internalNote ? "Guardar nota" : "Enviar resposta") {
                    let body = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        if await feedback.run({
                            try await model.api.mutate("admin/requests/\(id)/messages",
                                                       body: StaffReply(body: body, internal: internalNote))
                        }) {
                            reply = ""
                            feedback.requestReload()
                        }
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(feedback.busy || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding([.horizontal, .bottom], 16)
    }
}

private struct StaffReply: Encodable {
    let body: String
    let `internal`: Bool
}

private struct MessageBubble: View {
    let message: CaseMessage

    var body: some View {
        HStack {
            if !message.fromRequester { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if message.isInternal { Label("Nota interna", systemImage: "lock.fill").font(.caption.weight(.semibold)) }
                    Text(message.authorName ?? (message.fromRequester ? "Requerente" : "Equipa")).font(.caption.weight(.semibold))
                    Text(Formatting.dateTime(message.createdAt)).font(.caption).foregroundStyle(.secondary)
                }
                Text(message.body).textSelection(.enabled)
            }
            .padding(10)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
            if message.fromRequester { Spacer(minLength: 60) }
        }
    }

    private var background: Color {
        if message.isInternal { return .yellow.opacity(0.15) }
        return message.fromRequester ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.14)
    }
}
