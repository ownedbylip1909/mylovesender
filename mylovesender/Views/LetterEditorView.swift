import SwiftUI
import SwiftData

struct LetterEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppViewModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LetterDraft
    @State private var sendMode: SendMode = .now
    @State private var showingPreview = false
    @State private var showingConfirm = false
    @State private var errorMessage: String?
    @State private var successEffect = false
    @FocusState private var focusedField: EditorField?

    init(draft: LetterDraft?) {
        _draft = State(initialValue: draft ?? LetterDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Brief") {
                    TextField("Titel", text: $draft.title)
                        .focused($focusedField, equals: .title)
                    TextField("Kurze Vorschau", text: $draft.preview, axis: .vertical)
                        .focused($focusedField, equals: .preview)
                    TextEditor(text: $draft.body)
                        .focused($focusedField, equals: .body)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Vollständiger Brief")
                    Text("\(draft.body.count) Zeichen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Details") {
                    Picker("Label", selection: $draft.dateLabel) {
                        ForEach(["HEUTE", "VON HERZEN", "FÜR DICH", "EIN KLEINER MOMENT"], id: \.self, content: Text.init)
                    }
                    TextField("Optionale Unterschrift", text: $draft.signature)
                        .focused($focusedField, equals: .signature)
                    LabeledContent("Absender", value: draft.senderName)
                    LabeledContent("Empfängerin", value: draft.recipientName)
                }

                Section("Veröffentlichung") {
                    Picker("Option", selection: $sendMode) {
                        Text("Sofort senden").tag(SendMode.now)
                        Text("Datum und Uhrzeit festlegen").tag(SendMode.scheduled)
                        Text("Als Entwurf speichern").tag(SendMode.draft)
                    }
                    .pickerStyle(.segmented)
                    if sendMode == .scheduled {
                        DatePicker("Zeitpunkt", selection: Binding(get: {
                            draft.publishedAt ?? Date().addingTimeInterval(3600)
                        }, set: { draft.publishedAt = $0 }), in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(draft.title.trimmed.isEmpty ? "Neuer Brief" : "Brief")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Speichern") { saveDraft() } }
                ToolbarItem(placement: .confirmationAction) { Button("Vorschau") { showingPreview = true } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focusedField = nil }
                }
            }
            .onChange(of: draft.title) { _, _ in autosave() }
            .onChange(of: draft.body) { _, _ in autosave() }
            .safeAreaInset(edge: .bottom) {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: sendMode == .draft ? "tray.and.arrow.down" : "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(LoveTheme.accent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
            .sheet(isPresented: $showingPreview) { LetterPreviewSheet(draft: draft) }
            .confirmationDialog("Brief endgültig senden?", isPresented: $showingConfirm, titleVisibility: .visible) {
                Button("Senden") { Task { await send() } }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Nach dem Senden erscheint der Brief bei Bella erst zum Veröffentlichungszeitpunkt.")
            }
            .overlay(alignment: .top) {
                if successEffect { Label("Gespeichert", systemImage: "checkmark.circle.fill").padding().background(.regularMaterial, in: Capsule()) }
            }
        }
    }

    private var primaryTitle: String { sendMode == .draft ? "Als Entwurf speichern" : "Senden" }

    private func primaryAction() {
        if sendMode == .draft { saveDraft() } else { showingConfirm = true }
    }

    private func autosave() { try? saveWithoutEffect() }

    private func saveDraft() {
        do {
            try saveWithoutEffect()
            successEffect = true
            Task { try? await Task.sleep(for: .seconds(1)); successEffect = false }
        } catch {
            errorMessage = AppError.storageFailed.userMessage
        }
    }

    private func saveWithoutEffect() throws {
        draft.status = .draft
        draft.updatedAt = .now
        modelContext.insert(draft)
        try modelContext.save()
    }

    private func send() async {
        let publishedAt = sendMode == .scheduled ? (draft.publishedAt ?? Date().addingTimeInterval(3600)) : .now
        draft.publishedAt = publishedAt
        let validation = appModel.validator.validate(title: draft.title, body: draft.body, dateLabel: draft.dateLabel, publishedAt: publishedAt)
        guard validation.isValid else {
            errorMessage = validation.errors.joined(separator: " ")
            return
        }
        do {
            try await appModel.letterRepository.send(draft, context: modelContext)
            successEffect = true
            appModel.lastSentTitle = draft.title
            appModel.selectedTab = .letters
        } catch let appError as AppError {
            errorMessage = appError.userMessage
        } catch {
            errorMessage = AppError.sendFailed.userMessage
        }
    }
}

enum SendMode: Hashable { case now, scheduled, draft }

enum EditorField: Hashable { case title, preview, body, signature }

struct LetterPreviewSheet: View {
    let draft: LetterDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(draft.dateLabel).font(.caption.weight(.bold)).foregroundStyle(LoveTheme.accent)
                    Text(draft.title.nilIfEmpty ?? "Ohne Titel").font(.largeTitle.bold())
                    Text(draft.body.nilIfEmpty ?? "Noch kein Text.").font(.body)
                    if !draft.signature.trimmed.isEmpty { Text(draft.signature).font(.headline).padding(.top, 12) }
                    Text("Für \(draft.recipientName), von \(draft.senderName)").foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Vorschau")
            .toolbar { Button("Schließen") { dismiss() } }
        }
    }
}

private extension String { var nilIfEmpty: String? { trimmed.isEmpty ? nil : self } }
