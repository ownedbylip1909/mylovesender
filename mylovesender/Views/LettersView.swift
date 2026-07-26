import SwiftUI
import SwiftData

struct LettersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppViewModel.self) private var appModel
    @Query(sort: \LetterDraft.createdAt, order: .reverse) private var drafts: [LetterDraft]
    @State private var searchText = ""
    @State private var selectedStatus: LetterStatus?
    @State private var sortMode: SortMode = .createdAt
    @State private var errorMessage: String?

    private var filtered: [LetterDraft] {
        drafts
            .filter { draft in
                !draft.isArchivedOrDeleted
            }
            .filter { draft in
                selectedStatus == nil || draft.status == selectedStatus
            }
            .filter { draft in
                searchText.trimmed.isEmpty || draft.title.localizedCaseInsensitiveContains(searchText) || draft.body.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { first, second in
                switch sortMode {
                case .createdAt: first.createdAt > second.createdAt
                case .publishedAt: (first.publishedAt ?? .distantFuture) > (second.publishedAt ?? .distantFuture)
                }
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Entwürfe") { rows(for: .draft) }
                Section("Geplant") { rows(for: .scheduled) }
                Section("Gesendet") { rows(for: .sent) }
                Section("Fehlgeschlagen") { rows(for: .failed) }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Briefe")
            .searchable(text: $searchText, prompt: "Titel und Inhalt suchen")
            .toolbar {
                Menu {
                    Picker("Sortierung", selection: $sortMode) {
                        ForEach(SortMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    Picker("Status", selection: $selectedStatus) {
                        Text("Alle").tag(nil as LetterStatus?)
                        ForEach(LetterStatus.allCases) { status in Text(status.title).tag(status as LetterStatus?) }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            .alert("Fehler", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                await appModel.letterRepository.refreshStatuses(context: modelContext)
            }
            .refreshable {
                await appModel.letterRepository.refreshStatuses(context: modelContext)
            }
        }
    }

    @ViewBuilder
    private func rows(for status: LetterStatus) -> some View {
        let values = filtered.filter { $0.status == status }
        if values.isEmpty {
            Text("Keine Einträge")
                .foregroundStyle(.secondary)
        } else {
            ForEach(values) { draft in
                NavigationLink { LetterEditorView(draft: draft) } label: { LetterRow(draft: draft) }
                    .swipeActions {
                        if draft.status == .failed {
                            Button("Erneut") { retry(draft) }
                                .tint(LoveTheme.accent)
                        }
                        Button("Lokal löschen", role: .destructive) {
                            deleteLocal(draft)
                        }
                    }
            }
        }
    }

    private func retry(_ draft: LetterDraft) {
        Task {
            do { try await appModel.letterRepository.send(draft, context: modelContext) }
            catch let appError as AppError { errorMessage = appError.userMessage }
            catch { errorMessage = AppError.sendFailed.userMessage }
        }
    }

    private func deleteLocal(_ draft: LetterDraft) {
        modelContext.delete(draft)
        do {
            try modelContext.save()
        } catch {
            errorMessage = AppError.storageFailed.userMessage
        }
    }
}

struct LetterRow: View {
    let draft: LetterDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(draft.title.nilIfEmpty ?? "Ohne Titel")
                    .font(.headline)
                Spacer()
                StatusBadge(status: draft.status)
            }
            Text(draft.normalizedPreview.nilIfEmpty ?? "Keine Vorschau")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Empfängerin: \(draft.recipientName)")
                Text("Erstellt: \(draft.createdAt.formatted(date: .abbreviated, time: .shortened))")
                if let publishedAt = draft.publishedAt {
                    Text("Veröffentlichung: \(publishedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                if draft.status == .sent {
                    Text(draft.readStatusText)
                }
                if !draft.attachments.isEmpty {
                    Text("Anhänge: \(draft.attachments.count)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private extension String {
    var nilIfEmpty: String? { trimmed.isEmpty ? nil : self }
}
