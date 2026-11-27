import SwiftUI

/// Fila de pedidos (`queue`): todas as áreas que atendem pedidos.
struct RequestsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = "open"
    @State private var query = ""
    @State private var search = ""
    @State private var page = 1
    @State private var selected: String?

    private let filters = [("open", "Abertos"), ("mine", "Meus"), ("waiting", "À espera"), ("closed", "Fechados")]

    var body: some View {
        MasterDetail {
            VStack(spacing: 0) {
                ListToolbar(query: $query, prompt: "Referência, assunto ou nome", filters: filters, filter: $filter)
                    .debounce(query, into: $search)
                Divider()
                Loader(key: [filter, search, "\(page)"], load: {
                    try await model.api.get("admin/requests", query: ["filter": filter, "q": search, "page": "\(page)"]) as CasePage
                }) { result, _ in
                    List(result.items, selection: $selected) { item in
                        CaseRow(item: item).tag(item.id)
                    }
                    .overlay { if result.items.isEmpty { ContentUnavailableView("Sem pedidos", systemImage: "tray") } }
                    .safeAreaInset(edge: .bottom) {
                        if result.pagination.total > result.pagination.limit {
                            HStack {
                                Button("Anterior", systemImage: "chevron.left") { page -= 1 }.disabled(page <= 1)
                                Spacer()
                                Text("\(result.pagination.total) pedidos · página \(page)").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Seguinte", systemImage: "chevron.right") { page += 1 }.disabled(!result.pagination.hasMore)
                            }
                            .labelStyle(.iconOnly).padding(8).background(.bar)
                        }
                    }
                }
            }
            .onChange(of: filter) { page = 1 }
            .onChange(of: search) { page = 1 }
        } detail: {
            if let selected {
                RequestDetailView(id: selected).id(selected)
            } else {
                NoSelection(text: "Escolha um pedido.")
            }
        }
    }
}

private struct CaseRow: View {
    let item: CaseSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if item.unread { Circle().fill(.tint).frame(width: 8, height: 8).help("Respondeu e espera resposta") }
                Text(item.subject).font(.headline).lineLimit(1)
                Spacer()
                Text(Formatting.relative(item.lastActivityAt)).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(item.reference) · \(item.requesterName)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                StatusBadge(item.status, labels: Labels.caseStatus)
                if item.priority == "HIGH" || item.priority == "URGENT" {
                    StatusBadge(Labels.label(Labels.casePriority, item.priority), tone: item.priority == "URGENT" ? .danger : .warning)
                }
                Text(Labels.label(Labels.caseType, item.type)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
