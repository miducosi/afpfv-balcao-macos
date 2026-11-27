import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import Vision

// MARK: Gerar

enum QRCode {
    /// Imagem do QR (o conteúdo é só o caminho com o token, nunca dados pessoais).
    static func image(for text: String, scale: CGFloat = 10) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

// MARK: Ler com a câmara

/// Lê QR da câmara (AVFoundation + Vision). Também servem leitores USB (escrevem no campo de texto).
nonisolated final class CameraScanner: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "pt.afpfv.balcao.camera")
    private let onCode: @MainActor (String) -> Void
    private var lastCode: String?
    private var lastAt = Date.distantPast
    private var configured = false

    init(onCode: @escaping @MainActor (String) -> Void) {
        self.onCode = onCode
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    func start() {
        queue.async { [self] in
            if !configured { configure() }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input)
        {
            session.addInput(input)
        }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cvPixelBuffer: pixels, options: [:]).perform([request])
        guard let code = request.results?.first?.payloadStringValue, !code.isEmpty else { return }
        // O mesmo QR à frente da câmara só conta de novo passados 3 s.
        if code == lastCode, Date().timeIntervalSince(lastAt) < 3 { return }
        lastCode = code
        lastAt = Date()
        let onCode = onCode
        Task { @MainActor in onCode(code) }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Campo de leitura: escrever/colar o código ou usar a câmara. Enter lê.
struct ScanInput: View {
    let prompt: String
    let onSubmit: (String) -> Void
    @State private var input = ""
    @State private var cameraOn = false
    @State private var cameraDenied = false
    @State private var scanner: CameraScanner?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField(prompt, text: $input)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.monospaced())
                    .focused($focused)
                    .onSubmit(submit)
                Button("Ler", action: submit).keyboardShortcut(.defaultAction).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                Toggle(isOn: $cameraOn) { Label("Câmara", systemImage: "camera") }
                    .toggleStyle(.button)
            }
            if cameraOn, let scanner {
                CameraPreview(session: scanner.session)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
            }
            if cameraDenied {
                Label("Sem acesso à câmara. Autorize em Definições do Sistema › Privacidade › Câmara.",
                      systemImage: "video.slash").font(.callout).foregroundStyle(.orange)
            }
        }
        .onAppear { focused = true }
        .onChange(of: cameraOn) { _, on in Task { await toggleCamera(on) } }
        .onDisappear { scanner?.stop() }
    }

    private func submit() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onSubmit(value)
        input = ""
        focused = true
    }

    private func toggleCamera(_ on: Bool) async {
        guard on else { scanner?.stop(); return }
        guard await CameraScanner.requestAccess() else {
            cameraDenied = true
            cameraOn = false
            return
        }
        cameraDenied = false
        if scanner == nil { scanner = CameraScanner { code in onSubmit(code) } }
        scanner?.start()
    }
}
