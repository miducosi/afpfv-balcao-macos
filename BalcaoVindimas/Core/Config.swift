import Foundation

/// Ambiente da app, lido do Info.plist (preenchido a partir de Config/Secrets.xcconfig).
nonisolated struct AppConfig: Sendable {
    let apiURL: URL
    let clientKey: String
    let supabaseURL: URL?
    let supabaseKey: String

    static let current: AppConfig = {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String {
            (info[key] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        return AppConfig(
            apiURL: URL(string: value("BalcaoAPIURL")) ?? URL(string: "http://localhost:3000/api/mobile")!,
            clientKey: value("BalcaoClientKey"),
            supabaseURL: URL(string: value("SupabaseURL")),
            supabaseKey: value("SupabasePublishableKey")
        )
    }()

    var isConfigured: Bool { supabaseURL?.host != nil && !supabaseKey.isEmpty }

    /// Endereço público da web (onde abrem as páginas que a app não tem).
    var webURL: URL {
        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)!
        components.path = ""
        return components.url ?? apiURL
    }
}
