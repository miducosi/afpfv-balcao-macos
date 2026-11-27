import SwiftUI

/// Mensagens das mutações (sucesso num aviso breve, erros num alerta) e o "Atualizar" (⌘R).
@Observable
final class Feedback {
    var toast: String?
    var error: String?
    var busy = false
    /// Muda a cada ⌘R; as vistas recarregam quando muda.
    private(set) var reloadToken = 0
    private var toastTask: Task<Void, Never>?

    func requestReload() { reloadToken += 1 }

    func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { toast = nil }
        }
    }

    /// Corre uma mutação; mostra a mensagem do servidor. Devolve `true` se correu bem.
    @discardableResult
    func run(_ operation: () async throws -> String) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            show(try await operation())
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

private struct FeedbackOverlay: ViewModifier {
    @Environment(Feedback.self) private var feedback

    func body(content: Content) -> some View {
        @Bindable var feedback = feedback
        content
            .overlay(alignment: .bottom) {
                if let toast = feedback.toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(radius: 6, y: 2)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture { feedback.toast = nil }
                }
            }
            .animation(.snappy, value: feedback.toast)
            .alert("Não foi possível concluir", isPresented: Binding(
                get: { feedback.error != nil }, set: { if !$0 { feedback.error = nil } }
            )) {
                Button("OK") { feedback.error = nil }
            } message: {
                Text(feedback.error ?? "")
            }
    }
}

extension View {
    func feedbackOverlay() -> some View { modifier(FeedbackOverlay()) }
}
