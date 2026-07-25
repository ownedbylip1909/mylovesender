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
    let client_request_id: UUID
    let title: String
    let preview: String
    let body: String
    let date_label: String
    let published_at: Date
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
        if signature.isUnauthenticatedOrForbidden { return .secureSessionFailed }
        if signature.contains("not_paired") { return .notPaired }
        return .sendFailed
    }

    static func debugPairingFailure(stage: String, error: any Error, recoveryError: (any Error)?) {
        let signature = SupabaseErrorSignature(error: error)
        let recoverySignature = recoveryError.map(SupabaseErrorSignature.init(error:))
        print("MYLOVE_PAIRING_DIAGNOSTIC stage=\(stage) code=\(signature.safeCode) class=\(signature.safeClass) recoveryCode=\(recoverySignature?.safeCode ?? "none") recoveryClass=\(recoverySignature?.safeClass ?? "none")")
    }
}

#if canImport(Supabase)
private struct LiveSupabaseBackendClient: SupabaseBackendClientProtocol {
    private let client: SupabaseClient
    private let supabaseURL: URL
    private let publishableKey: String

    init(url: URL, publishableKey: String) {
        self.supabaseURL = url
        self.publishableKey = publishableKey
        client = SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
    }

    func hasCurrentSession() async -> Bool {
        client.auth.currentSession != nil
    }

    func restoreValidSession() async throws {
        _ = try await client.auth.session
    }

    func signInAnonymously() async throws {
        _ = try await client.auth.signInAnonymously()
    }

    func currentMailboxMembership() async throws -> MailboxMembership? {
        let rows: [MailboxMembershipRow] = try await client
            .from("mailbox_members")
            .select("role, mailboxes(display_name)")
            .eq("role", value: "sender")
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return MailboxMembership(recipientName: row.mailboxes?.display_name ?? AppConstants.recipientName, role: row.role)
    }

    func claimMailboxPairingCode(_ normalizedCode: String) async throws -> MailboxMembership {
        let session = try await client.auth.session
        var request = URLRequest(url: supabaseURL.appending(path: "rest/v1/rpc/claim_mailbox_pairing_code"))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ClaimPairingCodeParams(pairing_code: normalizedCode))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AppError.sendFailed }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorBody = try? JSONDecoder().decode(SupabaseRESTErrorBody.self, from: data) {
                throw errorBody.signature
            }
            if httpResponse.statusCode == 401 { throw SupabaseErrorSignature(code: "401", message: "unauthorized") }
            throw AppError.pairingUnavailable
        }

        let decoded = try JSONDecoder().decode([ClaimPairingCodeResponse].self, from: data)
        guard let membership = decoded.first else { throw AppError.invalidPairingCode }
        return MailboxMembership(recipientName: membership.recipient_name, role: membership.role)
    }

    func createMailboxLetter(_ payload: LetterPayload) async throws {
        let row = InsertLetterRow(
            client_request_id: payload.clientRequestId,
            title: payload.title,
            preview: payload.preview,
            body: payload.body,
            date_label: payload.dateLabel,
            published_at: payload.publishedAt
        )
        try await client.rpc("create_mailbox_letter", params: row).execute()
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
        if let restoreError { throw restoreError }
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
