import SwiftUI

/// Carrega um valor da API e mostra-o; recarrega quando `key` muda ou com ⌘R.
struct Loader<Value, Content: View>: View {
    @Environment(Feedback.self) private var feedback
    let key: AnyHashable
    let load: () async throws -> Value
    @ViewBuilder let content: (Value, _ reload: @escaping () async -> Void) -> Content

    @State private var value: Value?
    @State private var error: String?

    init(key: AnyHashable = 0, load: @escaping () async throws -> Value,
         @ViewBuilder content: @escaping (Value, _ reload: @escaping () async -> Void) -> Content)
    {
        self.key = key
        self.load = load
        self.content = content
    }

    var body: some View {
        Group {
            if let value {
                content(value, refresh)
            } else if let error {
                ContentUnavailableView {
                    Label("Não foi possível carregar", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Tentar outra vez") { Task { await refresh() } }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: TaskKey(key: key, reload: feedback.reloadToken)) { await refresh() }
    }

    private struct TaskKey: Hashable {
        let key: AnyHashable
        let reload: Int
    }

    private func refresh() async {
        do {
            value = try await load()
            error = nil
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            if value == nil { self.error = error.localizedDescription } else { feedback.error = error.localizedDescription }
        }
    }
}

/// Lista à esquerda, detalhe à direita (redimensionável).
struct MasterDetail<Master: View, Detail: View>: View {
    @ViewBuilder let master: Master
    @ViewBuilder let detail: Detail

    var body: some View {
        HSplitView {
            master.frame(minWidth: 300, idealWidth: 380, maxWidth: 560)
            detail.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct NoSelection: View {
    var text = "Escolha um registo na lista."
    var body: some View {
        ContentUnavailableView(text, systemImage: "sidebar.left")
    }
}

struct StatusBadge: View {
    let text: String
    let tone: Tone

    init(_ text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    /// Selo a partir do código do estado e do mapa de labels.
    init(_ code: String, labels: [String: String]) {
        self.init(Labels.label(labels, code), tone: .of(code))
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(tone.color)
            .background(tone.color.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}

/// Abre um ficheiro privado (`/files/{id}`) no Quick Look.
struct FileButton: View {
    @Environment(AppModel.self) private var model
    @Environment(Feedback.self) private var feedback
    let file: FileRef
    @State private var loading = false

    var body: some View {
        Button {
            Task {
                loading = true
                defer { loading = false }
                do { try await model.open(file) } catch { feedback.error = error.localizedDescription }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: file.mimeType == "application/pdf" ? "doc.richtext" : "photo")
                Text(file.fileName).lineLimit(1).truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                    .foregroundStyle(.secondary)
                if loading { ProgressView().controlSize(.small) }
            }
        }
        .buttonStyle(.link)
        .disabled(loading)
        .help("Abrir \(file.fileName)")
    }
}

/// Pede um motivo/nota antes de uma ação (recusar, revogar, anular…).
struct ReasonPrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
    let confirm: String
    var required = true
    var destructive = false
    let action: (String) async -> Bool
}

struct ReasonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let prompt: ReasonPrompt
    @State private var text = ""
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.title).font(.headline)
            if let message = prompt.message { Text(message).foregroundStyle(.secondary) }
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(prompt.confirm, role: prompt.destructive ? .destructive : nil) {
                    Task {
                        running = true
                        if await prompt.action(text.trimmingCharacters(in: .whitespacesAndNewlines)) { dismiss() }
                        running = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(running || (prompt.required && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

extension View {
    func reasonSheet(_ prompt: Binding<ReasonPrompt?>) -> some View {
        sheet(item: prompt) { ReasonSheet(prompt: $0) }
    }
}

/// Cabeçalho dos detalhes: título, subtítulo e selos.
struct DetailHeader<Badges: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var badges: Badges

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title2.weight(.semibold)).textSelection(.enabled)
            if let subtitle { Text(subtitle).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack(spacing: 6) { badges }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Valor opcional num `LabeledContent` (esconde a linha quando falta).
struct OptionalRow: View {
    let label: String
    let value: String?

    init(_ label: String, _ value: String?) {
        self.label = label
        self.value = value
    }

    var body: some View {
        if let value, !value.isEmpty {
            LabeledContent(label) { Text(value).textSelection(.enabled) }
        }
    }
}

/// Barra de pesquisa + filtro por segmentos, acima das listas.
struct ListToolbar: View {
    @Binding var query: String
    var prompt = "Pesquisar"
    var filters: [(String, String)] = []
    @Binding var filter: String

    var body: some View {
        VStack(spacing: 8) {
            if !filters.isEmpty {
                Picker("Filtro", selection: $filter) {
                    ForEach(filters, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            TextField(prompt, text: $query)
                .textFieldStyle(.roundedBorder)
        }
        .padding(10)
    }
}

/// Atraso da pesquisa para não pedir ao servidor a cada tecla.
struct Debounced: ViewModifier {
    let value: String
    @Binding var output: String

    func body(content: Content) -> some View {
        content.task(id: value) {
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled { output = value }
        }
    }
}

extension View {
    func debounce(_ value: String, into output: Binding<String>) -> some View {
        modifier(Debounced(value: value, output: output))
    }
}

/// Cor `#RRGGBB` dos tipos de livre-trânsito.
extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(clean, radix: 16) ?? 0x777777
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
