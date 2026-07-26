import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct LetterEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppViewModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LetterDraft
    @State private var sendMode: SendMode
    @State private var showingPreview = false
    @State private var showingConfirm = false
    @State private var showingFileImporter = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var errorMessage: String?
    @State private var uploadStatusMessage: String?
    @State private var isSending = false
    @State private var successEffect = false
    @FocusState private var focusedField: EditorField?

    init(draft: LetterDraft?) {
        let initialDraft = draft ?? LetterDraft()
        _draft = State(initialValue: initialDraft)
        _sendMode = State(initialValue: Self.initialSendMode(for: initialDraft, isNewDraft: draft == nil))
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

                Section("Anhänge") {
                    attachmentActions
                    attachmentList
                    Text("Maximal 6 MB pro Datei. Erlaubt sind JPEG, PNG, WebP und HEIC.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let uploadStatusMessage {
                    Section { ProgressView(uploadStatusMessage) }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(navigationTitle)
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
            .onChange(of: draft.preview) { _, _ in autosave() }
            .onChange(of: draft.body) { _, _ in autosave() }
            .onChange(of: draft.dateLabel) { _, _ in autosave() }
            .onChange(of: draft.signature) { _, _ in autosave() }
            .onChange(of: draft.publishedAt) { _, _ in autosave() }
            .onChange(of: selectedPhotoItems) { _, items in
                Task { await importPhotos(items) }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: AttachmentImport.allowedContentTypes,
                allowsMultipleSelection: true,
                onCompletion: importFiles
            )
            .safeAreaInset(edge: .bottom) {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: sendMode == .draft ? "tray.and.arrow.down" : "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isSending)
                .buttonStyle(.borderedProminent)
                .tint(LoveTheme.accent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
            .sheet(isPresented: $showingPreview) { LetterPreviewSheet(draft: draft) }
            .confirmationDialog(confirmTitle, isPresented: $showingConfirm, titleVisibility: .visible) {
                Button(confirmButtonTitle) { Task { await send() } }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text(confirmMessage)
            }
            .overlay(alignment: .top) {
                if successEffect { Label("Gespeichert", systemImage: "checkmark.circle.fill").padding().background(.regularMaterial, in: Capsule()) }
            }
        }
    }

    @ViewBuilder
    private var attachmentActions: some View {
        HStack(spacing: 12) {
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: max(0, AttachmentImport.maximumAttachmentCount - draft.attachments.count),
                matching: .images,
                preferredItemEncoding: .current
            ) {
                Label("Fotos", systemImage: "photo.on.rectangle")
            }
            .disabled(draft.attachments.count >= AttachmentImport.maximumAttachmentCount || isSending)

            Button {
                showingFileImporter = true
            } label: {
                Label("Dateien", systemImage: "paperclip")
            }
            .disabled(draft.attachments.count >= AttachmentImport.maximumAttachmentCount || isSending)
        }
    }

    @ViewBuilder
    private var attachmentList: some View {
        let attachments = draft.attachments
        if attachments.isEmpty {
            Text("Keine Anhänge ausgewählt")
                .foregroundStyle(.secondary)
        } else {
            ForEach(attachments) { attachment in
                HStack(spacing: 12) {
                    Image(systemName: "photo")
                        .foregroundStyle(LoveTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(attachment.fileName)
                            .lineLimit(1)
                        Text("\(attachment.mimeType), \(attachment.sizeBytes.formatted(.byteCount(style: .file)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        removeAttachment(attachment)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Anhang entfernen")
                }
            }
        }
    }

    private var navigationTitle: String {
        if draft.title.trimmed.isEmpty { return draft.status == .draft ? "Neuer Brief" : "Brief bearbeiten" }
        return draft.status == .draft ? "Brief" : "Bearbeiten"
    }

    private var primaryTitle: String {
        if sendMode == .draft { return "Lokal speichern" }
        return draft.status == .sent || draft.status == .scheduled ? "Änderungen senden" : "Senden"
    }

    private var confirmTitle: String {
        draft.status == .sent || draft.status == .scheduled ? "Änderungen an Bella senden?" : "Brief endgültig senden?"
    }

    private var confirmButtonTitle: String {
        draft.status == .sent || draft.status == .scheduled ? "Aktualisieren" : "Senden"
    }

    private var confirmMessage: String {
        if draft.status == .sent || draft.status == .scheduled {
            return "Die gespeicherte Version dieses Briefs wird aktualisiert. Bella sieht Änderungen erst zum Veröffentlichungszeitpunkt."
        }
        return "Nach dem Senden erscheint der Brief bei Bella erst zum Veröffentlichungszeitpunkt."
    }

    private static func initialSendMode(for draft: LetterDraft, isNewDraft: Bool) -> SendMode {
        if isNewDraft { return .now }
        switch draft.status {
        case .draft, .failed: return .draft
        case .scheduled: return .scheduled
        case .sent, .sending: return .now
        }
    }

    private func primaryAction() {
        if sendMode == .draft { saveDraft() } else { showingConfirm = true }
    }

    private func autosave() { try? saveWithoutEffect(markAsDraft: false) }

    private func saveDraft() {
        do {
            try saveWithoutEffect(markAsDraft: draft.status == .draft || draft.status == .failed)
            successEffect = true
            Task { try? await Task.sleep(for: .seconds(1)); successEffect = false }
        } catch {
            errorMessage = AppError.storageFailed.userMessage
        }
    }

    private func saveWithoutEffect(markAsDraft: Bool) throws {
        if markAsDraft { draft.status = .draft }
        draft.updatedAt = .now
        modelContext.insert(draft)
        try modelContext.save()
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        do {
            var attachments = draft.attachments
            for item in items where attachments.count < AttachmentImport.maximumAttachmentCount {
                let mimeType = AttachmentImport.mimeType(for: item.supportedContentTypes)
                guard let mimeType else { throw AppError.unsupportedAttachmentType }
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                try AttachmentValidator().validate(mimeType: mimeType, sizeBytes: data.count)
                attachments.append(
                    LetterAttachment(
                        fileName: "Foto \(attachments.count + 1).\(AttachmentImport.fileExtension(for: mimeType))",
                        mimeType: mimeType,
                        sizeBytes: data.count,
                        data: data
                    )
                )
            }
            draft.attachments = attachments
            try saveWithoutEffect(markAsDraft: false)
        } catch let appError as AppError {
            errorMessage = appError.userMessage
        } catch {
            errorMessage = AppError.storageFailed.userMessage
        }
        selectedPhotoItems = []
    }

    private func importFiles(_ result: Result<[URL], any Error>) {
        do {
            let urls = try result.get()
            var attachments = draft.attachments
            for url in urls where attachments.count < AttachmentImport.maximumAttachmentCount {
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing { url.stopAccessingSecurityScopedResource() }
                }
                let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .localizedNameKey])
                guard let mimeType = values.contentType?.preferredMIMEType,
                      AttachmentValidator.allowedMimeTypes.contains(mimeType) else {
                    throw AppError.unsupportedAttachmentType
                }
                let data = try Data(contentsOf: url)
                let sizeBytes = values.fileSize ?? data.count
                try AttachmentValidator().validate(mimeType: mimeType, sizeBytes: sizeBytes)
                attachments.append(
                    LetterAttachment(
                        fileName: values.localizedName ?? url.lastPathComponent,
                        mimeType: mimeType,
                        sizeBytes: sizeBytes,
                        data: data
                    )
                )
            }
            draft.attachments = attachments
            try saveWithoutEffect(markAsDraft: false)
        } catch let appError as AppError {
            errorMessage = appError.userMessage
        } catch {
            errorMessage = AppError.storageFailed.userMessage
        }
    }

    private func removeAttachment(_ attachment: LetterAttachment) {
        draft.attachments = draft.attachments.filter { $0.id != attachment.id }
        autosave()
    }

    private func send() async {
        guard !isSending else { return }
        isSending = true
        uploadStatusMessage = draft.attachments.isEmpty ? "Brief wird gesendet ..." : "Brief und Anhänge werden hochgeladen ..."
        defer {
            isSending = false
            uploadStatusMessage = nil
        }

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

enum AttachmentImport {
    static let maximumAttachmentCount = 8
    static let allowedContentTypes: [UTType] = [.jpeg, .png, .webP, .heic]

    static func mimeType(for contentTypes: [UTType]) -> String? {
        contentTypes
            .compactMap(\.preferredMIMEType)
            .first { AttachmentValidator.allowedMimeTypes.contains($0) }
    }

    static func fileExtension(for mimeType: String) -> String {
        switch mimeType {
        case "image/jpeg": "jpg"
        case "image/png": "png"
        case "image/webp": "webp"
        case "image/heic": "heic"
        default: "img"
        }
    }
}

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
