import Foundation

/// Sessão do Supabase Auth (GoTrue). O `accessToken` é o Bearer da API mobile.
nonisolated struct AuthSession: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var email: String?

    var isExpiring: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

/// Cliente mínimo da API REST do Supabase Auth — o que a app RN faz com o SDK:
/// entrar com palavra-passe, renovar, validar códigos (recuperação e convite) e sair.
nonisolated struct SupabaseAuth: Sendable {
    let config: AppConfig

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Double
        let user: User?
        struct User: Decodable { let email: String? }
    }

    private struct ErrorResponse: Decodable {
        let code: String?
        let error_code: String?
        let msg: String?
        let message: String?
        let error_description: String?
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        do {
            return try await token(grant: "password", body: ["email": email, "password": password])
        } catch let error as AuthError where error.code == "email_not_confirmed" {
            throw AuthError(code: error.code, message: "Confirme primeiro o seu email (verifique a caixa de correio).")
        } catch let error as AuthError where error.code == "invalid_credentials" || error.code == "invalid_grant" {
            throw AuthError(code: error.code, message: "O email ou a palavra-passe não estão certos.")
        }
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        var renewed = try await token(grant: "refresh_token", body: ["refresh_token": session.refreshToken])
        renewed.email = renewed.email ?? session.email
        return renewed
    }

    /// `type`: "recovery" (código do email de recuperação) ou "invite" (primeiro acesso da equipa).
    func verify(email: String, code: String, type: String) async throws -> AuthSession {
        let data = try await post("verify", body: ["email": email, "token": code, "type": type])
        return try session(from: data)
    }

    func signOut(_ session: AuthSession) async {
        guard var request = try? request("logout") else { return }
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: -

    private func token(grant: String, body: [String: String]) async throws -> AuthSession {
        try session(from: try await post("token?grant_type=\(grant)", body: body))
    }

    private func session(from data: Data) throws -> AuthSession {
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        return AuthSession(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: Date().addingTimeInterval(response.expires_in),
            email: response.user?.email)
    }

    private func request(_ path: String) throws -> URLRequest {
        guard let base = config.supabaseURL, !config.supabaseKey.isEmpty,
              let url = URL(string: "auth/v1/\(path)", relativeTo: base.appendingPathComponent("/"))
        else { throw AuthError(code: "not_configured", message: "A app não está configurada (Supabase).") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(config.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func post(_ path: String, body: [String: String]) async throws -> Data {
        var request = try request(path)
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError(code: "network", message: "Sem ligação. Verifique a internet e tente outra vez.")
        }
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return data }
        let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data)
        let code = decoded?.error_code ?? decoded?.code ?? "http_\(http.statusCode)"
        let message: String
        switch code {
        case "otp_expired": message = "O código expirou ou não é válido. Peça um novo."
        case "over_request_rate_limit", "over_email_send_rate_limit": message = "Demasiadas tentativas. Aguarde um pouco."
        default: message = decoded?.msg ?? decoded?.message ?? decoded?.error_description ?? "Não foi possível entrar."
        }
        throw AuthError(code: code, message: message)
    }
}

nonisolated struct AuthError: LocalizedError, Sendable {
    let code: String
    let message: String
    var errorDescription: String? { message }
}
