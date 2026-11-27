import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Loader(load: { try await model.api.get("admin/dashboard") as StaffDashboard }) { dashboard, _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let me = model.me {
                        Text("Olá, \(me.user.name.split(separator: " ").first.map(String.init) ?? me.user.name)")
                            .font(.largeTitle.weight(.semibold))
                    }
                    if let edition = dashboard.edition {
                        HStack(spacing: 8) {
                            Text(edition.name).font(.title3)
                            StatusBadge(edition.status, labels: Labels.editionStatus)
                            Text("\(Formatting.day(edition.startsOn)) – \(Formatting.day(edition.endsOn))")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Sem edição corrente.").foregroundStyle(.secondary)
                    }

                    if dashboard.urgentCases > 0 {
                        Button { model.selection = .requests } label: {
                            Label(Formatting.plural(dashboard.urgentCases, "pedido urgente", "pedidos urgentes"),
                                  systemImage: "exclamationmark.triangle.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        ForEach(dashboard.tiles) { tile in
                            let section = Section.forTile(tile.key)
                            Button { if let section { model.selection = section } } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: section?.icon ?? "circle").foregroundStyle(.tint)
                                        Text(tile.label).font(.headline)
                                        Spacer()
                                    }
                                    Text("\(tile.count)").font(.system(size: 34, weight: .semibold, design: .rounded))
                                        .contentTransition(.numericText())
                                    Text(tile.hint).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(section.map { !model.can($0.capability) } ?? true)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 1000, alignment: .leading)
            }
        }
    }
}
