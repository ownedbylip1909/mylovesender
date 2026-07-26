import Foundation
#if canImport(Supabase)
import Supabase
#endif

protocol SupabaseServiceProtocol: Sendable {
    func currentMailboxMembership() async throws -> MailboxMembership?
    func claimPairingCode(_ code: String) async throws -> MailboxMembership
    func sendLetter(_ payload: LetterPayload) async throws
}

protocol SupabaseBackendClientProtocol: Sendable {
    func hasCurrentSession() async -> Bool
    func restoreValidSession() async throws
    func signInAnonymously() async throws
    func currentMailboxMembership() async throws -> MailboxMembership?
    func claimMailboxPairingCode(_ normalizedCode: String) async throws -> MailboxMembership
    func createMailboxLetter(_ payload: LetterPayload) async throws
}

nonisolated private struct ClaimPairingCodeParams: Encodable, Sendable {
    let pairing_code: String
}

nonisolated private struct ClaimPairingCodeResponse: Decodable, Sendable {
    let recipient_name: String
    let role: String
}

nonisolated private struct MailboxMembershipRow: Decodable, Sendable {
    struct Mailbox: Decodable, Sendable {
        let display_name: String?
    }

    let mailbox_id: UUID?
    let role: String
    let mailboxes: Mailbox?
}

nonisolated private struct SupabaseRESTErrorBody: Decodable, Sendable {
    let code: String?
    let message: String?
    let msg: String?
    let error: String?
    let detail: String?
    let hint: String?

    var signature: SupabaseErrorSignature {
        SupabaseErrorSignature(
            code: code,
            message: [message, msg, error, detail, hint]
                .compactMap { $0 }
                .joined(separator: " ")
        )
    }
}

nonisolated private struct InsertLetterRow: Encodable, Sendable {
    let p_client_request_id: UUID
    let p_title: String
    let p_preview: String
    let p_body: String
    let p_date_label: String
    let p_published_at: Date
}

nonisolated private struct InsertLetterWithResultRow: Encodable, Sendable {
    let p_client_request_id: UUID
    let p_title: String
    let p_preview: String
    let p_body: String
    let p_date_label: String
    let p_published_at: Date
    let p_status: String
}

nonisolated private struct CreatedLetterRow: Decodable, Sendable {
    let letter_id: UUID
    let mailbox_id: UUID
}

nonisolated private struct InsertAttachmentMetadataRow: Encodable, Sendable {
    let letter_id: UUID
    let mailbox_id: UUID
    let storage_path: String
    let mime_type: String
    let size_bytes: Int
}

struct SupabaseService: SupabaseServiceProtocol {
    let configuration: AppConfiguration
    private let backend: SupabaseBackendClientProtocol?

    init(configuration: AppConfiguration = .current) {
        self.configuration = configuration
        #if canImport(Supabase)
        if let url = configuration.supabaseURL, let key = configuration.supabasePublishableKey {
            backend = LiveSupabaseBackendClient(url: url, publishableKey: key)
        } else {
            backend = nil
        }
        #else
        backend = nil
        #endif
    }

    init(configuration: AppConfiguration, backend: SupabaseBackendClientProtocol?) {
        self.configuration = configuration
        self.backend = backend
    }

    func currentMailboxMembership() async throws -> MailboxMembership? {
        guard configuration.isSupabaseConfigured else { return nil }
        guard let backend else { return nil }
        do {
            try await ensureAuthenticated(backend)
            return try await backend.currentMailboxMembership()
        } catch {
            return nil
        }
    }

    func claimPairingCode(_ code: String) async throws -> MailboxMembership {
        guard configuration.isSupabaseConfigured else { throw AppError.notConfigured }
        guard let backend else { throw AppError.notConfigured }
        do {
            try await ensureAuthenticated(backend)
            return try await backend.claimMailboxPairingCode(code)
        } catch let appError as AppError {
            if let membership = try? await backend.currentMailboxMembership() { return membership }
            Self.debugPairingFailure(stage: "app-error", error: appError, recoveryError: nil)
            throw appError
        } catch let originalError {
            do {
                if let membership = try await backend.currentMailboxMembership() { return membership }
                Self.debugPairingFailure(stage: "unmapped", error: originalError, recoveryError: nil)
            } catch let recoveryError {
                Self.debugPairingFailure(stage: "recovery-failed", error: originalError, recoveryError: recoveryError)
            }
            throw Self.mapPairingError(originalError)
        }
    }

    func sendLetter(_ payload: LetterPayload) async throws {
        guard configuration.isSupabaseConfigured else { throw AppError.notConfigured }
        guard let backend else { throw AppError.notConfigured }
        do {
            try await ensureAuthenticated(backend)
            try await backend.createMailboxLetter(payload)
        } catch let appError as AppError {
            throw appError
        } catch {
            throw Self.mapSendError(error)
        }
    }

    private func ensureAuthenticated(_ backend: SupabaseBackendClientProtocol) async throws {
        if await backend.hasCurrentSession() {
            do {
                try await backend.restoreValidSession()
                return
            } catch {
                // A stale local session is not usable; establish one fresh anonymous session before the RPC.
            }
        }

        do {
            try await backend.signInAnonymously()
        } catch {
            throw AppError.secureSessionFailed
        }
    }

    static func mapPairingError(_ error: any Error) -> AppError {
        if let appError = error as? AppError { return appError }
        if error.isNetworkConnectivityError { return .offline }

        let signature = SupabaseErrorSignature(error: error)
        if signature.isFunctionMissing { return .pairingUnavailable }
        if signature.isUnauthenticatedOrForbidden { return .secureSessionFailed }
        if signature.contains("invalid_pairing_code") { return .invalidPairingCode }
        if signature.contains("rate_limited") { return .rateLimited }
        return .pairingUnavailable
    }

    static func mapSendError(_ error: any Error) -> AppError {
        if let appError = error as? AppError { return appError }
        if error.isNetworkConnectivityError { return .offline }

        let signature = SupabaseErrorSignature(error: error)
        if signature.isFunctionMissing { return .attachmentBackendUnavailable }
        if signature.isUnauthenticatedOrForbidden { return .secureSessionFailed }
        if signature.contains("not_paired") { return .notPaired }
        if signature.contains("attachment") || signature.contains("storage") { return .attachmentUploadFailed }
        return .sendFailed
    }

    static func debugPairingFailure(stage: String, error: any Error, recoveryError: (any Error)?) {
        let signature = SupabaseErrorSignature(error: error)
        let recoverySignature = recoveryError.map(SupabaseErrorSignature.init(error:))
        print("MYLOVE_PAIRING_DIAGNOSTIC stage=\(stage) code=\(signature.safeCode) class=\(signature.safeClass) recoveryCode=\(recoverySignature?.safeCode ?? "none") recoveryClass=\(recoverySignature?.safeClass ?? "none")")
    }
}

#if canImport(Supabase)
private actor LiveSupabaseBackendClient: SupabaseBackendClientProtocol {
    private let client: SupabaseClient
    private let supabaseURL: URL
    private let publishableKey: String

    init(url: URL, publishableKey: String) {
        self.supabaseURL = url
        self.publishableKey = publishableKey

        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: publishableKey,
            options: SupabaseClientOptions(
                auth: .init(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    func hasCurrentSession() async -> Bool {
        client.auth.currentSession != nil
    }

    func restoreValidSession() async throws {
        let session = try await client.auth.session

        if session.isExpired {
            _ = try await client.auth.refreshSession()
        }
    }

    func signInAnonymously() async throws {
        if let session = client.auth.currentSession {
            if session.isExpired {
                do {
                    let refreshedSession = try await client.auth.refreshSession()

                    _ = refreshedSession
                    print("MYLOVE_AUTH_REFRESHED")
                    return
                } catch {
                    // Die gespeicherte Session ist nicht mehr nutzbar.
                    // Anschließend wird eine neue anonyme Session erstellt.
                }
            } else {
                _ = session
                print("MYLOVE_AUTH_REUSED")
                return
            }
        }

        do {
            _ = try await client.auth.signInAnonymously()
            print("MYLOVE_AUTH_SUCCESS")
        } catch {
            let nsError = error as NSError
            print("MYLOVE_AUTH_FAILURE domain=\(nsError.domain) code=\(nsError.code)")
            throw error
        }
    }

    func currentMailboxMembership() async throws -> MailboxMembership? {
        let rows: [MailboxMembershipRow] = try await client
            .from("mailbox_members")
            .select("mailbox_id, role, mailboxes(display_name)")
            .eq("role", value: "sender")
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else {
            return nil
        }

        return MailboxMembership(
            recipientName: row.mailboxes?.display_name
                ?? "Bella",
            role: row.role,
            mailboxId: row.mailbox_id
        )
    }

    func claimMailboxPairingCode(
        _ normalizedCode: String
    ) async throws -> MailboxMembership {
        let session = try await client.auth.session

        let endpoint = supabaseURL
            .appending(path: "rest")
            .appending(path: "v1")
            .appending(path: "rpc")
            .appending(path: "claim_mailbox_pairing_code")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(
            publishableKey,
            forHTTPHeaderField: "apikey"
        )
        request.setValue(
            "Bearer \(session.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONEncoder().encode(
            ClaimPairingCodeParams(
                pairing_code: normalizedCode
            )
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.pairingUnavailable
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorBody = try? JSONDecoder().decode(
                SupabaseRESTErrorBody.self,
                from: data
            ) {
                throw errorBody.signature
            }

            if httpResponse.statusCode == 401 {
                throw SupabaseErrorSignature(
                    code: "401",
                    message: "unauthorized"
                )
            }

            throw AppError.pairingUnavailable
        }

        let decoded = try JSONDecoder().decode(
            [ClaimPairingCodeResponse].self,
            from: data
        )

        guard let membership = decoded.first else {
            throw AppError.invalidPairingCode
        }

        if let currentMembership = try? await currentMailboxMembership() {
            return currentMembership
        }

        return MailboxMembership(
            recipientName: membership.recipient_name,
            role: membership.role
        )
    }

    func createMailboxLetter(_ payload: LetterPayload) async throws {
        _ = try await client.auth.session
        print("MYLOVE_SEND_START")

        do {
            if payload.attachments.isEmpty {
                try await createLegacyMailboxLetter(payload)
            } else {
                let createdLetter = try await createMailboxLetterWithResult(payload)
                try await uploadAttachments(payload.attachments, for: createdLetter)
            }

            print("MYLOVE_SEND_SUCCESS")
        } catch let appError as AppError {
            throw appError
        } catch {
            let nsError = error as NSError
            let signature = SupabaseErrorSignature(error: error)

            print("MYLOVE_SEND_FAILURE domain=\(nsError.domain) code=\(nsError.code) supabaseCode=\(signature.safeCode) supabaseClass=\(signature.safeClass)")
            throw error
        }
    }

    private func createLegacyMailboxLetter(_ payload: LetterPayload) async throws {
        let row = InsertLetterRow(
            p_client_request_id: payload.clientRequestId,
            p_title: payload.title,
            p_preview: payload.preview,
            p_body: payload.body,
            p_date_label: payload.dateLabel,
            p_published_at: payload.publishedAt
        )

        try await client
            .rpc("create_mailbox_letter", params: row)
            .execute()
    }

    private func createMailboxLetterWithResult(_ payload: LetterPayload) async throws -> CreatedLetterRow {
        let row = InsertLetterWithResultRow(
            p_client_request_id: payload.clientRequestId,
            p_title: payload.title,
            p_preview: payload.preview,
            p_body: payload.body,
            p_date_label: payload.dateLabel,
            p_published_at: payload.publishedAt,
            p_status: payload.serverStatus.rawValue
        )

        do {
            let response: [CreatedLetterRow] = try await client
                .rpc("create_mailbox_letter_with_result", params: row)
                .execute()
                .value

            guard let createdLetter = response.first else {
                throw AppError.attachmentBackendUnavailable
            }

            return createdLetter
        } catch {
            if SupabaseErrorSignature(error: error).isFunctionMissing {
                throw AppError.attachmentBackendUnavailable
            }
            throw error
        }
    }

    private func uploadAttachments(_ attachments: [LetterAttachment], for createdLetter: CreatedLetterRow) async throws {
        let validator = AttachmentValidator()
        for attachment in attachments {
            try validator.validate(mimeType: attachment.mimeType, sizeBytes: attachment.sizeBytes)
            let storagePath = attachmentStoragePath(
                mailboxId: createdLetter.mailbox_id,
                letterId: createdLetter.letter_id,
                attachment: attachment
            )
            var objectUploaded = false

            do {
                try await client.storage
                    .from("letter-attachments")
                    .upload(
                        storagePath,
                        data: attachment.data,
                        options: FileOptions(
                            contentType: attachment.mimeType,
                            upsert: false
                        )
                    )
                objectUploaded = true

                let metadata = InsertAttachmentMetadataRow(
                    letter_id: createdLetter.letter_id,
                    mailbox_id: createdLetter.mailbox_id,
                    storage_path: storagePath,
                    mime_type: attachment.mimeType,
                    size_bytes: attachment.sizeBytes
                )

                try await client
                    .from("letter_attachments")
                    .insert(metadata)
                    .execute()
            } catch {
                if objectUploaded {
                    _ = try? await client.storage
                        .from("letter-attachments")
                        .remove(paths: [storagePath])
                }
                throw AppError.attachmentUploadFailed
            }
        }
    }

    private func attachmentStoragePath(mailboxId: UUID, letterId: UUID, attachment: LetterAttachment) -> String {
        let fileExtension = attachment.fileName.fileExtension(for: attachment.mimeType)
        return "\(mailboxId.uuidString)/\(letterId.uuidString)/\(attachment.id.uuidString).\(fileExtension)"
    }
}
#endif

struct SupabaseErrorSignature: Error, Sendable {
    let code: String?
    let message: String

    init(code: String? = nil, message: String) {
        self.code = code
        self.message = message
    }

    init(error: any Error) {
        #if canImport(Supabase)
        if let postgrestError = error as? PostgrestError {
            self.code = postgrestError.code
            self.message = [postgrestError.message, postgrestError.detail, postgrestError.hint]
                .compactMap { $0 }
                .joined(separator: " ")
            return
        }
        #endif
        self.code = nil
        self.message = String(describing: error)
    }

    var isFunctionMissing: Bool {
        code == "PGRST202" || contains("function not found") || contains("could not find the function") || contains("schema cache")
    }

    var isUnauthenticatedOrForbidden: Bool {
        code == "401" || code == "42501" || contains("permission denied") || contains("status code: 401") || contains("statuscode: 401") || contains("unauthorized")
    }

    var safeCode: String {
        code ?? "none"
    }

    var safeClass: String {
        if isFunctionMissing { return "function-missing" }
        if isUnauthenticatedOrForbidden { return "auth-or-permission" }
        if contains("invalid_pairing_code") { return "invalid-pairing-code" }
        if contains("rate_limited") { return "rate-limited" }
        if message.localizedCaseInsensitiveContains("decoding") { return "decoding" }
        return "unknown"
    }

    func contains(_ value: String) -> Bool {
        code?.localizedCaseInsensitiveContains(value) == true || message.localizedCaseInsensitiveContains(value)
    }
}

private extension String {
    nonisolated func fileExtension(for mimeType: String) -> String {
        let currentExtension = (self as NSString).pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp", "heic"].contains(currentExtension) {
            return currentExtension == "jpeg" ? "jpg" : currentExtension
        }

        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        default: return "img"
        }
    }
}

private extension Error {
    var isNetworkConnectivityError: Bool {
        let nsError = self as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorTimedOut,
            NSURLErrorDNSLookupFailed
        ].contains(nsError.code)
    }
}

struct MockSupabaseService: SupabaseServiceProtocol {
    var membership: MailboxMembership?
    var pairingResult: Result<MailboxMembership, AppError> = .failure(.pairingUnavailable)
    var sendResult: Result<Void, AppError> = .success(())

    func currentMailboxMembership() async throws -> MailboxMembership? { membership }
    func claimPairingCode(_ code: String) async throws -> MailboxMembership { try pairingResult.get() }
    func sendLetter(_ payload: LetterPayload) async throws { try sendResult.get() }
}

actor MockSupabaseBackendClient: SupabaseBackendClientProtocol {
    enum Event: Equatable { case hasCurrentSession, restoreValidSession, signInAnonymously, currentMailboxMembership, claimPairingCode, createMailboxLetter }

    var hasSession: Bool
    var events: [Event] = []
    var signInError: (any Error)?
    var restoreError: (any Error)?
    var pairingError: (any Error)?
    var sendError: (any Error)?
    var currentMembership: MailboxMembership?

    init(hasSession: Bool = false) {
        self.hasSession = hasSession
    }

    func setRestoreError(_ error: (any Error)?) {
        restoreError = error
    }

    func setCurrentMembership(_ membership: MailboxMembership?) {
        currentMembership = membership
    }

    func setPairingError(_ error: (any Error)?) {
        pairingError = error
    }

    func hasCurrentSession() async -> Bool {
        events.append(.hasCurrentSession)
        return hasSession
    }

    func restoreValidSession() async throws {
        events.append(.restoreValidSession)

        if let restoreError {
            throw restoreError
        }
    }

    func signInAnonymously() async throws {
        events.append(.signInAnonymously)
        if let signInError { throw signInError }
        hasSession = true
    }

    func currentMailboxMembership() async throws -> MailboxMembership? {
        events.append(.currentMailboxMembership)
        return currentMembership
    }

    func claimMailboxPairingCode(_ normalizedCode: String) async throws -> MailboxMembership {
        events.append(.claimPairingCode)
        if let pairingError { throw pairingError }
        return MailboxMembership(recipientName: "Bella", role: "sender")
    }

    func createMailboxLetter(_ payload: LetterPayload) async throws {
        events.append(.createMailboxLetter)
        if let sendError { throw sendError }
    }
}
