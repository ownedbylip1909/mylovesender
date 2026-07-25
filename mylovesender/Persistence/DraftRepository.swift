import Foundation
import SwiftData

protocol DraftRepositoryProtocol: Sendable {
    @MainActor func fetchDrafts() throws -> [LetterDraft]
    @MainActor func save(_ draft: LetterDraft) throws
    @MainActor func delete(_ draft: LetterDraft) throws
}

struct SwiftDataDraftRepository: DraftRepositoryProtocol {
    let modelContext: ModelContext

    @MainActor
    func fetchDrafts() throws -> [LetterDraft] {
        let descriptor = FetchDescriptor<LetterDraft>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try modelContext.fetch(descriptor)
    }

    @MainActor
    func save(_ draft: LetterDraft) throws {
        draft.updatedAt = .now
        modelContext.insert(draft)
        try modelContext.save()
    }

    @MainActor
    func delete(_ draft: LetterDraft) throws {
        modelContext.delete(draft)
        try modelContext.save()
    }
}
