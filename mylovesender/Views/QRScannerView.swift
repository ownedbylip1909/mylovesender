import SwiftUI
#if os(iOS) && canImport(VisionKit)
import VisionKit
import Vision

struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case .barcode(let code) = item, let payload = code.payloadStringValue else { return }
            onCode(payload)
        }
    }
}
#else
struct QRScannerView: View {
    let onCode: (String) -> Void
    var body: some View {
        ContentUnavailableView {
            Label("QR-Scanner nicht verfügbar", systemImage: "qrcode.viewfinder")
        } description: {
            Text("Auf diesem Gerät kann der Pairing-Code manuell eingegeben werden.")
        }
    }
}
#endif
