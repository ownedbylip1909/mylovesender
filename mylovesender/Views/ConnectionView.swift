import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ConnectionView: View {
    @Environment(AppViewModel.self) private var appModel
    @State private var code = ""
    @State private var showingScanner = false
    @State private var showingDisconnectConfirm = false
    @FocusState private var isCodeFieldFocused: Bool
    private let validator = PairingCodeValidator()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LoveCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Bella verbinden")
                                .font(.title2.bold())
                            ConnectionBadge(state: appModel.connectionState)
                            Text(appModel.pairingMessage ?? "Verbindung noch nicht eingerichtet.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    LoveCard {
                        VStack(alignment: .leading, spacing: 14) {
                            TextField("Pairing-Code", text: $code)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                                .focused($isCodeFieldFocused)
                                .submitLabel(.done)
                                .onSubmit { connect() }
                                .accessibilityLabel("Pairing-Code eingeben")
                            HStack {
                                Button { pasteCode() } label: { Label("Einfügen", systemImage: "doc.on.clipboard") }
                                Button { showingScanner = true } label: { Label("QR scannen", systemImage: "qrcode.viewfinder") }
                            }
                            Button {
                                connect()
                            } label: {
                                if appModel.isPairing { ProgressView() } else { Label("Verbinden", systemImage: "link") }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(LoveTheme.accent)
                            .disabled(validator.normalizedCode(from: code) == nil || appModel.isPairing)
                        }
                    }

                    Button(role: .destructive) { showingDisconnectConfirm = true } label: {
                        Label("Verbindung trennen", systemImage: "xmark.circle")
                    }
                    .disabled(appModel.connectionState != .connected)
                }
                .padding(20)
            }
            .navigationTitle("Verbindung")
            .sheet(isPresented: $showingScanner) { QRScannerView { code = $0; showingScanner = false } }
            .confirmationDialog("Verbindung zu Bella trennen?", isPresented: $showingDisconnectConfirm, titleVisibility: .visible) {
                Button("Trennen", role: .destructive) { Task { await appModel.disconnect() } }
                Button("Abbrechen", role: .cancel) { }
            }
        }
    }

    private func pasteCode() {
        #if canImport(UIKit)
        code = UIPasteboard.general.string ?? code
        #endif
    }

    private func connect() {
        guard validator.normalizedCode(from: code) != nil, !appModel.isPairing else { return }
        isCodeFieldFocused = false
        Task { await appModel.claimPairingCode(code) }
    }
}
