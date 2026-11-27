import SwiftUI

/// Estado da app: sessão, conta (`/auth/me`) e o que a conta pode ver.
@Observable
final class AppModel {
    enum Phase { case launching, signedOut, signedIn(Me) }

    let api = APIClient()
    private(set) var phase: Phase = .launching
    var selection: Section? = .dashboard
    /// Ficheiro aberto no Quick Look.
    var previewURL: URL?

    init() {
        api.onSessionExpired = { [weak self] in self?.phase = .signedOut }
    }

    var me: Me? {
        if case .signedIn(let me) = phase { return me }
        return nil
    }

    func can(_ capability: String) -> Bool { me?.capabilities.contains(capability) ?? false }

    var sections: [Section] { Section.allCases.filter { can($0.capability) } }

    func restore() async {
        #if DEBUG
        // Desenvolvimento: BALCAO_DEBUG_EMAIL/PASSWORD entram sozinhos; BALCAO_DEBUG_SECTION abre uma secção.
        let env = ProcessInfo.processInfo.environment
        if let email = env["BALCAO_DEBUG_EMAIL"], let password = env["BALCAO_DEBUG_PASSWORD"] {
            if let me = try? await api.signIn(email: email, password: password) { try? accept(me) }
            if let section = env["BALCAO_DEBUG_SECTION"].flatMap(Section.init(rawValue:)) { selection = section }
            if me != nil { return }
        }
        #endif
        guard api.session != nil else { phase = .signedOut; return }
        do {
            try accept(try await api.get("auth/me"))
        } catch let error as APIError where error.code == "NETWORK" {
            // Sem rede ao abrir: fica na entrada, que mostra o erro ao tentar.
            phase = .signedOut
        } catch {
            await api.signOut()
            phase = .signedOut
        }
    }

    /// Só a equipa usa esta app (como na web: a equipa só usa o backoffice).
    func accept(_ me: Me) throws {
        guard me.home == "admin" else {
            Task { await api.signOut() }
            throw APIError(status: 403, code: "FORBIDDEN",
                           message: "Esta app é do backoffice. A área pessoal está em \(AppConfig.current.webURL.host ?? "balcao.afpfv.pt").")
        }
        phase = .signedIn(me)
        if let selection, !can(selection.capability) { self.selection = sections.first }
    }

    func refreshMe() async {
        if let me: Me = try? await api.get("auth/me") { try? accept(me) }
    }

    func signOut() async {
        await api.signOut()
        phase = .signedOut
        selection = .dashboard
    }

    /// Descarrega um ficheiro privado e abre-o no Quick Look.
    func open(_ file: FileRef) async throws {
        let downloaded = try await api.file(file.id, fallbackName: file.fileName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(file.id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(downloaded.fileName.replacingOccurrences(of: "/", with: "-"))
        try downloaded.data.write(to: url, options: .atomic)
        previewURL = url
    }
}

/// Secções do backoffice; cada uma exige uma capacidade de `/auth/me` (`capabilities.ts`).
enum Section: String, CaseIterable, Identifiable, Hashable {
    case dashboard, requests, stalls, treasury, charges, races, passes, passScan, meals, mealMap, mealScan, team, audit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Painel"
        case .requests: "Pedidos"
        case .stalls: "Terrados"
        case .treasury: "Comprovativos"
        case .charges: "Cobranças"
        case .races: "Provas"
        case .passes: "Livres-trânsito"
        case .passScan: "Validar livres-trânsito"
        case .meals: "Senhas de refeição"
        case .mealMap: "Mapa de refeições"
        case .mealScan: "Validar senhas"
        case .team: "Equipa"
        case .audit: "Auditoria"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .requests: "tray.full"
        case .stalls: "storefront"
        case .treasury: "doc.text.magnifyingglass"
        case .charges: "eurosign.circle"
        case .races: "figure.run"
        case .passes: "car"
        case .passScan: "qrcode.viewfinder"
        case .meals: "fork.knife"
        case .mealMap: "calendar"
        case .mealScan: "qrcode.viewfinder"
        case .team: "person.2"
        case .audit: "list.bullet.rectangle"
        }
    }

    var capability: String {
        switch self {
        case .dashboard: "staff"
        case .requests: "queue"
        case .stalls: "stalls"
        case .treasury, .charges: "treasury"
        case .races: "races"
        case .passes: "passes"
        case .passScan: "validatePasses"
        case .meals, .mealMap: "canteen"
        case .mealScan: "validateMeals"
        case .team, .audit: "admin"
        }
    }

    var group: String {
        switch self {
        case .dashboard, .requests: ""
        case .stalls: "Terrados"
        case .treasury, .charges: "Tesouraria"
        case .races: "Provas"
        case .passes, .passScan: "Livres-trânsito"
        case .meals, .mealMap, .mealScan: "Refeitório"
        case .team, .audit: "Administração"
        }
    }

    /// Mosaico do painel → secção.
    static func forTile(_ key: String) -> Section? {
        switch key {
        case "cases": .requests
        case "stalls": .stalls
        case "treasury": .treasury
        case "races": .races
        case "passes": .passes
        case "meals": .meals
        default: nil
        }
    }
}
