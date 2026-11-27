import SwiftUI

/// Provas: lista de provas e inscrições, com check-in (área Provas).
struct RacesView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: String?

    var body: some View {
        Loader(load: { try await model.api.get("admin/races") as [StaffRace] }) { races, _ in
            MasterDetail {
                List(races, selection: $selected) { race in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(race.name).font(.headline)
                        Text([Formatting.dateTime(race.startsAt), race.location].compactMap { $0 }.joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Label("\(race.counts.confirmed)/\(race.maxParticipants)", systemImage: "person.2")
                            Label("\(race.counts.checkedIn)", systemImage: "checkmark.circle")
                            if race.counts.pending > 0 { Label("\(race.counts.pending)", systemImage: "hourglass") }
                            if race.counts.waitlisted > 0 { Label("\(race.counts.waitlisted)", systemImage: "list.number") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .tag(race.id)
                }
                .overlay { if races.isEmpty { ContentUnavailableView("Sem provas", systemImage: "figure.run") } }
                .onAppear { if selected == nil { selected = races.first?.id } }
            } detail: {
                if let race = races.first(where: { $0.id == selected }) {
                    RegistrationsView(race: race).id(race.id)
                } else {
                    NoSelection(text: "Escolha uma prova.")
                }
            }
        }
    }
}

/// Uma linha por participante (uma inscrição pode ter vários).
private struct ParticipantRow: Identifiable {
    let participant: RaceParticipant
    let registration: StaffRaceRegistration
    var id: String { participant.id }
}

private struct RegistrationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    let race: StaffRace
    @State private var query = ""
    @State private var search = ""
    @State private var selection = Set<String>()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(race.name).font(.title2.weight(.semibold))
                    Text("\(race.counts.confirmed) confirmadas · \(race.counts.checkedIn) com check-in · \(race.seatsLeft) vagas")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Nome, dorsal ou referência", text: $query)
                    .textFieldStyle(.roundedBorder).frame(width: 240)
                    .debounce(query, into: $search)
            }
            .padding()
            Loader(key: search, load: {
                try await model.api.get("admin/races/\(race.id)/registrations", query: ["q": search]) as [StaffRaceRegistration]
            }) { registrations, _ in
                let rows = registrations.flatMap { registration in
                    registration.participants.map { ParticipantRow(participant: $0, registration: registration) }
                }
                Table(rows, selection: $selection) {
                    TableColumn("Dorsal") { row in
                        Text(row.participant.bib.map(String.init) ?? "—").monospacedDigit()
                    }
                    .width(56)
                    TableColumn("Nome") { row in Text(row.participant.fullName) }
                    TableColumn("Escalão") { row in Text(row.participant.categoryName ?? "—") }
                    TableColumn("T-shirt") { row in Text(row.participant.tshirtSize ?? "—") }.width(56)
                    TableColumn("Inscrição") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            StatusBadge(row.registration.status, labels: Labels.registrationStatus)
                            Text(row.registration.reference ?? row.registration.userName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    TableColumn("Check-in") { row in
                        Toggle("Check-in", isOn: Binding(
                            get: { row.participant.checkedInAt != nil },
                            set: { checkIn(row.participant, $0) }
                        ))
                        .labelsHidden()
                        .disabled(row.registration.status != "CONFIRMED" || feedback.busy)
                        .help(row.participant.checkedInAt.map { "Check-in \(Formatting.dateTime($0))" } ?? "Sem check-in")
                    }
                    .width(70)
                }
                .overlay { if rows.isEmpty { ContentUnavailableView("Sem inscrições", systemImage: "person.2") } }
            }
        }
    }

    private func checkIn(_ participant: RaceParticipant, _ value: Bool) {
        Task {
            if await feedback.run({
                try await model.api.mutate("admin/race-participants/\(participant.id)/check-in", body: ["checkedIn": value])
            }) { feedback.requestReload() }
        }
    }
}
