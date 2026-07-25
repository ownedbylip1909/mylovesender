import Foundation
import SwiftData

protocol LetterRepositoryProtocol: Sendable {
    @MainActor func send(_ draft: LetterDraft, context: ModelContext) async throws
}

struct LetterRepository: LetterRepositoryProtocol {
    let supabaseService: SupabaseServiceProtocol
    let pairingService: PairingServiceProtocol
    let validator = LetterValidator()

    @MainActor
    func send(_ draft: LetterDraft, context: ModelContext) async throws {
        guard await pairingService.loadMembership() != nil else {
            draft.status = .failed
            draft.lastErrorMessage = AppError.notPaired.userMessage
            try? context.save()
            throw AppError.notPaired
        }
        let publishedAt = draft.publishedAt ?? .now
        let validation = validator.validate(title: draft.title, body: draft.body, dateLabel: draft.dateLabel, publishedAt: publishedAt)
        guard validation.isValid else { throw AppError.validation(validation.errors.joined(separator: " ")) }

        draft.status = .sending
        draft.lastErrorMessage = nil
        try context.save()
        let payload = LetterPayload(
            clientRequestId: draft.clientRequestId,
            title: draft.title.trimmed,
            preview: draft.normalizedPreview,
            body: draft.body.trimmed,
            dateLabel: draft.dateLabel.trimmed,
            publishedAt: publishedAt
        )
        do {
            try await supabaseService.sendLetter(payload)
            draft.publishedAt = publishedAt
            draft.status = validator.status(for: publishedAt)
            draft.lastErrorMessage = nil
            try context.save()
        } catch let appError as AppError {
            draft.status = .failed
            draft.lastErrorMessage = appError.userMessage
            try? context.save()
            throw appError
        } catch {
            draft.status = .failed
            draft.lastErrorMessage = AppError.sendFailed.userMessage
            try? context.save()
            throw AppError.sendFailed
        }
    }
}
