import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppLockService.self) private var appLock
    @Environment(AppViewModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Query private var drafts: [LetterDraft]
    @State private var confirmDeleteDrafts = false

    var body: some View {
        @Bindable var lock = appLock
        @Bindable var model = appModel
        Form {
            Section("Sicherheit") {
                Toggle("Face ID aktivieren", isOn: $lock.isFaceIDEnabled)
            }
            Section("Standards") {
                TextField("Standardsignatur", text: $model.standardSignature)
                TextField("Standard-Label", text: $model.standardLabel)
            }
            Section("Verbindung") {
                LabeledContent("Status", value: model.connectionState.title)
                Button(role: .destructive) { Task { await model.disconnect() } } label: { Text("Verbindung trennen") }
            }
            Section("Lokale Entwürfe") {
                LabeledContent("Anzahl", value: "\(drafts.filter { $0.status == .draft }.count)")
                Button(role: .destructive) { confirmDeleteDrafts = true } label: { Text("Entwürfe löschen") }
            }
            Section("Datenschutz") {
                Text("Tokens und Pairing-Daten liegen im Keychain. Entwürfe bleiben lokal in SwiftData. Es werden keine Standortdaten, Lesebestätigungen, Analytics oder Tracking-SDKs verwendet.")
                    .font(.callout)
            }
            Section("App") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
        }
        .navigationTitle("Einstellungen")
        .confirmationDialog("Alle lokalen Entwürfe löschen?", isPresented: $confirmDeleteDrafts, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { deleteLocalDrafts() }
            Button("Abbrechen", role: .cancel) { }
        }
    }

    private func deleteLocalDrafts() {
        for draft in drafts where draft.status == .draft { modelContext.delete(draft) }
        try? modelContext.save()
    }
}
