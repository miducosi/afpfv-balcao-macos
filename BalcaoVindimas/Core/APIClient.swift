import Foundation

/// Erro da API (`{ error: { message, code, fieldErrors } }`). `message` vem em pt-PT, pronta a mostrar.
nonisolated struct APIError: LocalizedError, Sendable {
    let status: Int
    let code: String
    let message: String
    var fieldErrors: [String: [String]] = [:]

    var errorDescription: String? {
        guard !fieldErrors.isEmpty else { return message }
        let details = fieldErrors.values.flatMap { $0 }
        return ([message] + details).joined(separator: "\n")
    }

    static let network = APIError(status: 0, code: "NETWORK", message: "Sem ligação ao Balcão. Verifique a internet e tente outra vez.")
}

private nonisolated struct Envelope<T: Decodable>: Decodable { let data: T }
private nonisolated struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let message: String
        let code: String
        let fieldErrors: [String: [String]]?
    }
    let error: Body
}

/// Ficheiro privado descarregado de `GET /files/{id}`.
struct DownloadedFile {
    let data: Data
    let fileName: String
}

/// Cliente da API mobile (`/api/mobile/*`). Junta o Bearer da sessão e renova-a quando expira.
@Observable
final class APIClient {
    private let config: AppConfig
    private let auth: SupabaseAuth
    private var refreshTask: Task<AuthSession, Error>?

    /// Sessão atual; `nil` depois de sair ou se a renovação falhar.
    private(set) var session: AuthSession?
    /// Chamado quando a sessão deixa de ser válida (401 depois de renovar).
    var onSessionExpired: (() -> Void)?

    init(config: AppConfig = .current) {
        self.config = config
        self.auth = SupabaseAuth(config: config)
        if let data = Keychain.read("session") {
            session = try? JSONDecoder().decode(AuthSession.self, from: data)
        }
    }

    // MARK: Sessão

    func setSession(_ session: AuthSession?) {
        self.session = session
        if let session, let data = try? JSONEncoder().encode(session) {
            Keychain.write(data, for: "session")
        } else {
            Keychain.delete("session")
        }
    }

    func signIn(email: String, password: String) async throws -> Me {
        setSession(try await auth.signIn(email: email, password: password))
        return try await send("POST", "auth/login")
    }

    func verify(email: String, code: String, type: String) async throws {
        setSession(try await auth.verify(email: email, code: code, type: type))
    }

    func signOut() async {
        if let session { await auth.signOut(session) }
        setSession(nil)
    }

    private func validSession() async throws -> AuthSession? {
        guard let session else { return nil }
        guard session.isExpiring else { return session }
        return try await refreshSession()
    }

    private func refreshSession() async throws -> AuthSession {
        if let refreshTask { return try await refreshTask.value }
        guard let current = session else { throw unauthenticated }
        let task = Task { try await auth.refresh(current) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let renewed = try await task.value
            setSession(renewed)
            return renewed
        } catch let error as AuthError where error.code == "network" {
            throw APIError.network
        } catch {
            setSession(nil)
            onSessionExpired?()
            throw unauthenticated
        }
    }

    private var unauthenticated: APIError {
        APIError(status: 401, code: "UNAUTHENTICATED", message: "A sessão terminou. Entre outra vez.")
    }

    // MARK: Pedidos

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try await send("GET", path, query: query)
    }

    func send<T: Decodable>(_ method: String, _ path: String, query: [String: String?] = [:],
                            body: (any Encodable)? = nil) async throws -> T
    {
        let data = try await perform(method, path, query: query, body: body).0
        do {
            return try Self.decoder.decode(Envelope<T>.self, from: data).data
        } catch {
            #if DEBUG
            print("Falha a ler \(method) \(path): \(error)")
            #endif
            throw APIError(status: 200, code: "DECODING", message: "A resposta do servidor não é a esperada. Atualize a app.")
        }
    }

    /// Mutações: devolve a mensagem de sucesso (`MessageResult`).
    @discardableResult
    func mutate(_ path: String, method: String = "POST", body: (any Encodable)? = nil) async throws -> String {
        let result: MessageResult = try await send(method, path, body: body ?? EmptyBody())
        return result.message
    }

    func file(_ id: String, fallbackName: String) async throws -> DownloadedFile {
        let (data, response) = try await perform("GET", "files/\(id)", query: [:], body: nil)
        let name = Self.fileName(from: response.value(forHTTPHeaderField: "Content-Disposition")) ?? fallbackName
        return DownloadedFile(data: data, fileName: name)
    }

    private func perform(_ method: String, _ path: String, query: [String: String?],
                         body: (any Encodable)?, retried: Bool = false) async throws -> (Data, HTTPURLResponse)
    {
        var components = URLComponents(url: config.apiURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { key, value in
            value.flatMap { $0.isEmpty ? nil : URLQueryItem(name: key, value: $0) }
        }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }

        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("mobile", forHTTPHeaderField: "X-Balcao-Client")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !config.clientKey.isEmpty { request.setValue(config.clientKey, forHTTPHeaderField: "X-Balcao-Client-Key") }
        if let session = try await validSession() {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.network }

        if http.statusCode == 401, session != nil, !retried {
            _ = try await refreshSession()
            return try await perform(method, path, query: query, body: body, retried: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? Self.decoder.decode(ErrorEnvelope.self, from: data) {
                let error = APIError(status: http.statusCode, code: envelope.error.code, message: envelope.error.message,
                                     fieldErrors: envelope.error.fieldErrors ?? [:])
                if error.code == "UNAUTHENTICATED" || error.code == "ACCOUNT_INACTIVE" {
                    setSession(nil)
                    onSessionExpired?()
                }
                throw error
            }
            throw APIError(status: http.statusCode, code: "HTTP_\(http.statusCode)",
                           message: "O servidor respondeu com um erro (\(http.statusCode)).")
        }
        return (data, http)
    }

    // MARK: JSON

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = Formatting.parseInstant(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Data inválida: \(text)")
        }
        return decoder
    }()

    static let encoder = JSONEncoder()

    static func fileName(from disposition: String?) -> String? {
        guard let disposition else { return nil }
        // filename*=UTF-8''nome%20com%20acentos.pdf tem prioridade sobre filename="..."
        for part in disposition.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if part.lowercased().hasPrefix("filename*="),
               let encoded = part.split(separator: "'", maxSplits: 2).last,
               let decoded = String(encoded).removingPercentEncoding
            {
                return decoded
            }
        }
        for part in disposition.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if part.lowercased().hasPrefix("filename=") {
                return String(part.dropFirst("filename=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }
}

nonisolated struct EmptyBody: Encodable {}
