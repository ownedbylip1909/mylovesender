import Foundation
import SwiftData

protocol LetterRepositoryProtocol: Sendable {
    @MainActor func send(_ draft: LetterDraft, context: ModelContext) async throws
    @MainActor func refreshStatuses(context: ModelContext) async
}

struct LetterRepository: LetterRepositoryProtocol {
    let supabaseService: SupabaseServiceProtocol
    let pairingService: PairingServiceProtocol
    let validator = LetterValidator()

    @MainActor
    func send(_ draft: LetterDraft, context: ModelContext) async throws {
        guard let membership = await pairingService.loadMembership(),
              let mailboxId = membership.mailboxId else {
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
            mailboxId: mailboxId,
            clientRequestId: draft.clientRequestId,
            title: draft.title.trimmed,
            preview: draft.normalizedPreview,
            body: draft.body.trimmed,
            dateLabel: draft.dateLabel.trimmed,
            publishedAt: publishedAt,
            serverStatus: validator.serverStatus(for: publishedAt),
            attachments: draft.attachments
        )
        do {
            try await supabaseService.sendLetter(payload)
            draft.publishedAt = publishedAt
            draft.serverStatus = validator.serverStatus(for: publishedAt)
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

    @MainActor
    func refreshStatuses(context: ModelContext) async {
        guard let statuses = try? await supabaseService.sentLetterStatuses(),
              !statuses.isEmpty,
              let drafts = try? context.fetch(FetchDescriptor<LetterDraft>()) else {
            return
        }
        let byRequestId = Dictionary(
            uniqueKeysWithValues: statuses.map { ($0.clientRequestId, $0) }
        )
        var changed = false
        for draft in drafts {
            guard let remote = byRequestId[draft.clientRequestId] else { continue }
            if draft.isRead != remote.isRead
                || draft.readAt != remote.readAt
                || draft.archivedAt != remote.archivedAt
                || draft.deletedAt != remote.deletedAt {
                draft.isRead = remote.isRead
                draft.readAt = remote.readAt
                draft.archivedAt = remote.archivedAt
                draft.deletedAt = remote.deletedAt
                changed = true
            }
        }
        if changed { try? context.save() }
    }
}
