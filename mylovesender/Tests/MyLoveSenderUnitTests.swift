#if DEBUG && canImport(Testing)
import Foundation
import SwiftData
import Testing
@testable import MyLove_Sender

@Suite("MyLove Sender")
struct MyLoveSenderUnitTests {
    @Test func letterValidationRejectsEmptyRequiredFields() {
        let result = LetterValidator().validate(title: "", body: "", dateLabel: "", publishedAt: .now)
        #expect(result.isValid == false)
        #expect(result.errors.count == 3)
    }

    @Test func scheduledStatusUsesFuturePublicationDate() {
        let status = LetterValidator().status(for: Date().addingTimeInterval(3600))
        #expect(status == .scheduled)
    }

    @Test func sentStatusUsesNowPublicationDate() {
        let status = LetterValidator().status(for: .now)
        #expect(status == .sent)
    }

    @Test func pairingCodeValidationNormalizesSeparators() {
        let code = PairingCodeValidator().normalizedCode(from: "ab12-cd34-ef56")
        #expect(code == "AB12CD34EF56")
    }

    @Test func pairingCodeValidationRejectsShortCode() {
        #expect(PairingCodeValidator().normalizedCode(from: "abc") == nil)
    }

    @Test func missingSessionSignsInBeforePairingRPC() async throws {
        let backend = MockSupabaseBackendClient(hasSession: false)
        let service = SupabaseService(configuration: configuredTestConfiguration, backend: backend)
        let membership = try await service.claimPairingCode("AB12CD34EF56")
        #expect(membership.role == "sender")
        #expect(await backend.events == [.hasCurrentSession, .signInAnonymously, .claimPairingCode])
    }

    @Test func existingSessionDoesNotCreateNewAnonymousUser() async throws {
        let backend = MockSupabaseBackendClient(hasSession: true)
        let service = SupabaseService(configuration: configuredTestConfiguration, backend: backend)
        _ = try await service.claimPairingCode("AB12CD34EF56")
        #expect(await backend.events == [.hasCurrentSession, .restoreValidSession, .claimPairingCode])
    }

    @Test func staleSessionSignsInBeforePairingRPC() async throws {
        let backend = MockSupabaseBackendClient(hasSession: true)
        await backend.setRestoreError(AppError.secureSessionFailed)
        let service = SupabaseService(configuration: configuredTestConfiguration, backend: backend)
        _ = try await service.claimPairingCode("AB12CD34EF56")
        #expect(await backend.events == [.hasCurrentSession, .restoreValidSession, .signInAnonymously, .claimPairingCode])
    }

    @Test func existingServerMembershipRecoversAfterPairingError() async throws {
        let backend = MockSupabaseBackendClient(hasSession: true)
        await backend.setCurrentMembership(MailboxMembership(recipientName: "Bella", role: "sender"))
        await backend.setPairingError(SupabaseErrorSignature(message: "invalid_pairing_code"))
        let service = SupabaseService(configuration: configuredTestConfiguration, backend: backend)
        let membership = try await service.claimPairingCode("AB12CD34EF56")
        #expect(membership == MailboxMembership(recipientName: "Bella", role: "sender"))
    }

    @Test func forbiddenPairingErrorIsSecureSessionFailure() {
        let mapped = SupabaseService.mapPairingError(SupabaseErrorSignature(code: "42501", message: "permission denied for function claim_mailbox_pairing_code"))
        #expect(mapped == .secureSessionFailed)
        #expect(mapped.userMessage == "Die sichere Sitzung konnte nicht hergestellt werden.")
    }

    @Test func functionNotFoundIsBackendUnavailable() {
        let mapped = SupabaseService.mapPairingError(SupabaseErrorSignature(code: "PGRST202", message: "Could not find the function public.claim_mailbox_pairing_code"))
        #expect(mapped == .pairingUnavailable)
    }

    @Test func invalidPairingCodeIsUserFacingPairingError() {
        let mapped = SupabaseService.mapPairingError(SupabaseErrorSignature(message: "invalid_pairing_code"))
        #expect(mapped == .invalidPairingCode)
    }

    @Test func rateLimitIsUserFacingRateLimitError() {
        let mapped = SupabaseService.mapPairingError(SupabaseErrorSignature(message: "rate_limited"))
        #expect(mapped == .rateLimited)
    }

    @Test func draftMapsToPayloadWithoutServerIds() {
        let draft = LetterDraft(title: "Titel", preview: "Kurz", body: "Text", dateLabel: "HEUTE", publishedAt: .now)
        let payload = LetterPayload(mailboxId: UUID(), clientRequestId: draft.clientRequestId, title: draft.title, preview: draft.normalizedPreview, body: draft.body, dateLabel: draft.dateLabel, publishedAt: draft.publishedAt ?? .now, serverStatus: .published)
        #expect(payload.clientRequestId == draft.clientRequestId)
        #expect(payload.title == "Titel")
    }

    @Test func connectionStateGermanTitlesAreStable() {
        #expect(ConnectionState.notConnected.title == "Nicht verbunden")
        #expect(ConnectionState.connected.title == "Mit Bella verbunden")
    }

    @Test func keychainAbstractionStoresAndDeletesValues() async throws {
        let keychain = InMemoryKeychainService()
        try await keychain.save(Data("token".utf8), account: "session")
        let stored = try await keychain.read(account: "session")
        #expect(String(data: stored ?? Data(), encoding: .utf8) == "token")
        try await keychain.delete(account: "session")
        #expect(try await keychain.read(account: "session") == nil)
    }

    @Test func sendFailsWhenNotPairedAndKeepsDraftFailed() async throws {
        let pairing = PairingService(supabaseService: MockSupabaseService(), keychain: InMemoryKeychainService())
        let repository = LetterRepository(supabaseService: MockSupabaseService(), pairingService: pairing)
        let container = try ModelContainer(for: LetterDraft.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let draft = LetterDraft(title: "Titel", body: "Text")
        container.mainContext.insert(draft)
        await #expect(throws: AppError.notPaired) { try await repository.send(draft, context: container.mainContext) }
        #expect(draft.status == .failed)
    }

    @Test func offlineDraftKeepsStableClientRequestId() {
        let draft = LetterDraft(title: "Titel", body: "Text")
        let first = draft.clientRequestId
        draft.body = "Anderer Text"
        #expect(draft.clientRequestId == first)
    }

    @Test func attachmentValidatorAcceptsSupportedSmallImage() throws {
        try AttachmentValidator().validate(mimeType: "image/png", sizeBytes: 1024)
    }

    @Test func attachmentValidatorRejectsOversizedImage() throws {
        #expect(throws: AppError.attachmentTooLarge) {
            try AttachmentValidator().validate(mimeType: "image/png", sizeBytes: AttachmentValidator.maximumSizeBytes + 1)
        }
    }

    @Test func attachmentValidatorRejectsUnsupportedMimeType() throws {
        #expect(throws: AppError.unsupportedAttachmentType) {
            try AttachmentValidator().validate(mimeType: "application/pdf", sizeBytes: 1024)
        }
    }

    @Test func serverStatusMapsScheduledPublicationDate() {
        let status = LetterValidator().serverStatus(for: Date().addingTimeInterval(3600))
        #expect(status == .scheduled)
    }

    @Test func editingSentLetterReusesClientRequestIdForServerUpdate() async throws {
        let backend = MockSupabaseBackendClient(hasSession: true)
        let service = SupabaseService(configuration: configuredTestConfiguration, backend: backend)
        let pairing = StaticPairingService(membership: MailboxMembership(recipientName: "Bella", role: "sender", mailboxId: UUID()))
        let repository = LetterRepository(supabaseService: service, pairingService: pairing)
        let container = try ModelContainer(for: LetterDraft.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let draft = LetterDraft(title: "Titel", body: "Text", publishedAt: .now, status: .sent)
        let requestId = draft.clientRequestId
        container.mainContext.insert(draft)

        try await repository.send(draft, context: container.mainContext)
        draft.body = "Aktualisierter Text"
        try await repository.send(draft, context: container.mainContext)

        let createEvents = await backend.events.filter { $0 == .createMailboxLetter }
        #expect(draft.clientRequestId == requestId)
        #expect(createEvents.count == 2)
        #expect(draft.status == .sent)
    }

    private var configuredTestConfiguration: AppConfiguration {
        AppConfiguration(supabaseURL: URL(string: "https://example.supabase.co")!, supabasePublishableKey: "test-publishable-key")
    }
}

private struct StaticPairingService: PairingServiceProtocol {
    let membership: MailboxMembership?

    func loadMembership() async -> MailboxMembership? { membership }
    func claim(code: String) async throws -> MailboxMembership {
        guard let membership else { throw AppError.notPaired }
        return membership
    }
    func disconnect() async throws { }
}
#endif
