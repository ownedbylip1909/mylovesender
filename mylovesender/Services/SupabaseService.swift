import Foundation

#if canImport(Supabase)
import Supabase
#endif

// MARK: - Service Protocols

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

    func claimMailboxPairingCode(
        _ normalizedCode: String
    ) async throws -> MailboxMembership

    func createMailboxLetter(
        _ payload: LetterPayload
    ) async throws
}

// MARK: - Supabase DTOs

nonisolated private struct ClaimPairingCodeParams: Encodable, Sendable {
    let pairing_code: String
}

nonisolated private struct ClaimPairingCodeResponse: Decodable, Sendable {
    let recipient_name: String
    let role: String
}

nonisolated private struct ClaimPairingCodeResult: Decodable, Sendable {
    let value: ClaimPairingCodeResponse

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let directResponse = try? container.decode(
            ClaimPairingCodeResponse.self
        ) {
            value = directResponse
            return
        }

        let responses = try container.decode(
            [ClaimPairingCodeResponse].self
        )

        guard let firstResponse = responses.first else {
            throw AppError.invalidPairingCode
        }

        value = firstResponse
    }
}

nonisolated private struct MailboxMembershipRow: Decodable, Sendable {
    nonisolated struct Mailbox: Decodable, Sendable {
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

    nonisolated var signature: SupabaseErrorSignature {
        SupabaseErrorSignature(
            code: code,
            message: [
                message,
                msg,
                error,
                detail,
                hint
            ]
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

// MARK: - Supabase Service

struct SupabaseService: SupabaseServiceProtocol {
    let configuration: AppConfiguration

    private let backend: (any SupabaseBackendClientProtocol)?

    init(
        configuration: AppConfiguration = .current
    ) {
        self.configuration = configuration

        #if canImport(Supabase)
        if let url = configuration.supabaseURL,
           let key = configuration.supabasePublishableKey {
            backend = LiveSupabaseBackendClient(
                url: url,
                publishableKey: key
            )
        } else {
            backend = nil
        }
        #else
        backend = nil
        #endif
    }

    init(
        configuration: AppConfiguration,
        backend: (any SupabaseBackendClientProtocol)?
    ) {
        self.configuration = configuration
        self.backend = backend
    }

    // MARK: Membership

    func currentMailboxMembership() async throws -> MailboxMembership? {
        guard configuration.isSupabaseConfigured else {
            throw AppError.notConfigured
        }

        guard let backend else {
            throw AppError.notConfigured
        }

        do {
            try await ensureAuthenticated(backend)

            return try await backend.currentMailboxMembership()
        } catch let appError as AppError {
            throw appError
        } catch {
            throw Self.mapMembershipError(error)
        }
    }

    // MARK: Pairing

    func claimPairingCode(
        _ code: String
    ) async throws -> MailboxMembership {
        guard configuration.isSupabaseConfigured else {
            throw AppError.notConfigured
        }

        guard let backend else {
            throw AppError.notConfigured
        }

        do {
            try await ensureAuthenticated(backend)

            return try await backend.claimMailboxPairingCode(code)
        } catch let appError as AppError {
            Self.debugPairingFailure(
                stage: "app-error",
                error: appError,
                recoveryError: nil
            )

            throw appError
        } catch {
            let mappedError = Self.mapPairingError(error)

            guard Self.shouldAttemptPairingRecovery(
                originalError: error,
                mappedError: mappedError
            ) else {
                Self.debugPairingFailure(
                    stage: "unmapped",
                    error: error,
                    recoveryError: nil
                )

                throw mappedError
            }

            do {
                if let membership =
                    try await backend.currentMailboxMembership() {
                    return membership
                }

                Self.debugPairingFailure(
                    stage: "recovery-empty",
                    error: error,
                    recoveryError: nil
                )
            } catch let recoveryError {
                Self.debugPairingFailure(
                    stage: "recovery-failed",
                    error: error,
                    recoveryError: recoveryError
                )
            }

            throw mappedError
        }
    }

    // MARK: Letters

    func sendLetter(
        _ payload: LetterPayload
    ) async throws {
        guard configuration.isSupabaseConfigured else {
            throw AppError.notConfigured
        }

        guard let backend else {
            throw AppError.notConfigured
        }

        do {
            try await ensureAuthenticated(backend)
            try await backend.createMailboxLetter(payload)
        } catch let appError as AppError {
            throw appError
        } catch {
            throw Self.mapSendError(error)
        }
    }

    // MARK: Authentication

    private func ensureAuthenticated(
        _ backend: any SupabaseBackendClientProtocol
    ) async throws {
        if await backend.hasCurrentSession() {
            do {
                try await backend.restoreValidSession()
                return
            } catch {
                /*
                 Eine lokal vorhandene Session kann abgelaufen oder
                 beschädigt sein. In diesem Fall wird anschließend eine
                 neue anonyme Session erstellt.
                 */
            }
        }

        do {
            try await backend.signInAnonymously()
        } catch {
            throw AppError.secureSessionFailed
        }
    }

    // MARK: Error Mapping

    static func mapMembershipError(
        _ error: any Error
    ) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        if error.isNetworkConnectivityError {
            return .offline
        }

        let signature = SupabaseErrorSignature(error: error)

        if signature.isUnauthenticatedOrForbidden {
            return .secureSessionFailed
        }

        return .pairingUnavailable
    }

    static func mapPairingError(
        _ error: any Error
    ) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        if error.isNetworkConnectivityError {
            return .offline
        }

        let signature = SupabaseErrorSignature(error: error)

        if signature.isFunctionMissing {
            return .pairingUnavailable
        }

        if signature.isUnauthenticatedOrForbidden {
            return .secureSessionFailed
        }

        if signature.contains("invalid_pairing_code") {
            return .invalidPairingCode
        }

        if signature.contains("rate_limited") {
            return .rateLimited
        }

        return .pairingUnavailable
    }

    static func mapSendError(
        _ error: any Error
    ) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        if error.isNetworkConnectivityError {
            return .offline
        }

        let signature = SupabaseErrorSignature(error: error)

        if signature.isUnauthenticatedOrForbidden {
            return .secureSessionFailed
        }

        if signature.contains("not_paired") {
            return .notPaired
        }

        return .sendFailed
    }

    private static func shouldAttemptPairingRecovery(
        originalError: any Error,
        mappedError: AppError
    ) -> Bool {
        /*
         Bei einem ungültigen Code, Rate-Limit, fehlender Konfiguration
         oder Authentifizierungsfehler ist keine Recovery-Abfrage sinnvoll.
         */

        if case .invalidPairingCode = mappedError {
            return false
        }

        if case .rateLimited = mappedError {
            return false
        }

        if case .notConfigured = mappedError {
            return false
        }

        if case .secureSessionFailed = mappedError {
            return false
        }

        /*
         Bei Netzwerk- oder Decoding-Problemen könnte der RPC serverseitig
         trotzdem erfolgreich gewesen sein. Dann prüfen wir anschließend,
         ob bereits eine Membership existiert.
         */

        if originalError.isNetworkConnectivityError {
            return true
        }

        let signature = SupabaseErrorSignature(error: originalError)

        if signature.isDecodingError {
            return true
        }

        return true
    }

    // MARK: Diagnostics

    static func debugPairingFailure(
        stage: String,
        error: any Error,
        recoveryError: (any Error)?
    ) {
        let signature = SupabaseErrorSignature(error: error)

        let recoverySignature = recoveryError.map {
            SupabaseErrorSignature(error: $0)
        }

        print(
            """
            MYLOVE_PAIRING_DIAGNOSTIC \
            stage=\(stage) \
            code=\(signature.safeCode) \
            class=\(signature.safeClass) \
            recoveryCode=\(recoverySignature?.safeCode ?? "none") \
            recoveryClass=\(recoverySignature?.safeClass ?? "none")
            """
        )
    }
}

// MARK: - Live Supabase Backend

#if canImport(Supabase)
private actor LiveSupabaseBackendClient:
    SupabaseBackendClientProtocol {

    private let client: SupabaseClient
    private let supabaseURL: URL
    private let publishableKey: String

    init(
        url: URL,
        publishableKey: String
    ) {
        supabaseURL = url
        self.publishableKey = publishableKey

        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: publishableKey
        )
    }

    // MARK: Authentication

    func hasCurrentSession() async -> Bool {
        client.auth.currentSession != nil
    }

    func restoreValidSession() async throws {
        _ = try await client.auth.session
    }

    func signInAnonymously() async throws {
        _ = try await client.auth.signInAnonymously()
    }

    // MARK: Membership

    func currentMailboxMembership() async throws -> MailboxMembership? {
        let rows: [MailboxMembershipRow] = try await client
            .from("mailbox_members")
            .select("role, mailboxes(display_name)")
            .eq("role", value: "sender")
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else {
            return nil
        }

        return MailboxMembership(
            recipientName:
                row.mailboxes?.display_name
                ?? AppConstants.recipientName,
            role: row.role
        )
    }

    // MARK: Pairing RPC

    func claimMailboxPairingCode(
        _ normalizedCode: String
    ) async throws -> MailboxMembership {
        let session = try await client.auth.session

        let endpoint = supabaseURL.appending(
            path: "rest/v1/rpc/claim_mailbox_pairing_code"
        )

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

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
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

            if httpResponse.statusCode == 403 {
                throw SupabaseErrorSignature(
                    code: "403",
                    message: "forbidden"
                )
            }

            if httpResponse.statusCode == 429 {
                throw SupabaseErrorSignature(
                    code: "429",
                    message: "rate_limited"
                )
            }

            throw AppError.pairingUnavailable
        }

        let decoded = try JSONDecoder().decode(
            ClaimPairingCodeResult.self,
            from: data
        )

        return MailboxMembership(
            recipientName: decoded.value.recipient_name,
            role: decoded.value.role
        )
    }

    // MARK: Letter RPC

    func createMailboxLetter(
        _ payload: LetterPayload
    ) async throws {
        let row = InsertLetterRow(
            client_request_id: payload.clientRequestId,
            title: payload.title,
            preview: payload.preview,
            body: payload.body,
            date_label: payload.dateLabel,
            published_at: payload.publishedAt
        )

        try await client
            .rpc(
                "create_mailbox_letter",
                params: row
            )
            .execute()
    }
}
#endif

// MARK: - Supabase Error Signature

nonisolated struct SupabaseErrorSignature: Error, Sendable {
    let code: String?
    let message: String

    init(
        code: String? = nil,
        message: String
    ) {
        self.code = code
        self.message = message
    }

    init(error: any Error) {
        #if canImport(Supabase)
        if let postgrestError = error as? PostgrestError {
            code = postgrestError.code

            message = [
                postgrestError.message,
                postgrestError.detail,
                postgrestError.hint
            ]
            .compactMap { $0 }
            .joined(separator: " ")

            return
        }
        #endif

        let nsError = error as NSError

        code = nsError.code == 0
            ? nil
            : String(nsError.code)

        message = [
            String(describing: error),
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    var isFunctionMissing: Bool {
        code == "PGRST202"
            || contains("function not found")
            || contains("could not find the function")
            || contains("schema cache")
    }

    var isUnauthenticatedOrForbidden: Bool {
        code == "401"
            || code == "403"
            || code == "42501"
            || contains("permission denied")
            || contains("status code: 401")
            || contains("statuscode: 401")
            || contains("status code: 403")
            || contains("statuscode: 403")
            || contains("unauthorized")
            || contains("forbidden")
    }

    var isDecodingError: Bool {
        message.localizedCaseInsensitiveContains("decoding")
            || message.localizedCaseInsensitiveContains("decode")
            || message.localizedCaseInsensitiveContains("dataCorrupted")
            || message.localizedCaseInsensitiveContains("keyNotFound")
            || message.localizedCaseInsensitiveContains("typeMismatch")
            || message.localizedCaseInsensitiveContains("valueNotFound")
    }

    var safeCode: String {
        code ?? "none"
    }

    var safeClass: String {
        if isFunctionMissing {
            return "function-missing"
        }

        if isUnauthenticatedOrForbidden {
            return "auth-or-permission"
        }

        if contains("invalid_pairing_code") {
            return "invalid-pairing-code"
        }

        if contains("rate_limited") || code == "429" {
            return "rate-limited"
        }

        if isDecodingError {
            return "decoding"
        }

        return "unknown"
    }

    func contains(
        _ value: String
    ) -> Bool {
        code?.localizedCaseInsensitiveContains(value) == true
            || message.localizedCaseInsensitiveContains(value)
    }
}

// MARK: - Network Error Detection

private extension Error {
    var isNetworkConnectivityError: Bool {
        let nsError = self as NSError

        guard nsError.domain == NSURLErrorDomain else {
            return false
        }

        return [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorTimedOut,
            NSURLErrorDNSLookupFailed,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorCallIsActive,
            NSURLErrorDataNotAllowed
        ]
        .contains(nsError.code)
    }
}

// MARK: - Mock Supabase Service

struct MockSupabaseService: SupabaseServiceProtocol {
    var membership: MailboxMembership?

    var pairingResult: Result<MailboxMembership, AppError> =
        .failure(.pairingUnavailable)

    var sendResult: Result<Void, AppError> =
        .success(())

    init(
        membership: MailboxMembership? = nil,
        pairingResult: Result<MailboxMembership, AppError> =
            .failure(.pairingUnavailable),
        sendResult: Result<Void, AppError> =
            .success(())
    ) {
        self.membership = membership
        self.pairingResult = pairingResult
        self.sendResult = sendResult
    }

    func currentMailboxMembership() async throws
        -> MailboxMembership? {
        membership
    }

    func claimPairingCode(
        _ code: String
    ) async throws -> MailboxMembership {
        try pairingResult.get()
    }

    func sendLetter(
        _ payload: LetterPayload
    ) async throws {
        try sendResult.get()
    }
}

// MARK: - Mock Backend Client

actor MockSupabaseBackendClient:
    SupabaseBackendClientProtocol {

    enum Event: Equatable, Sendable {
        case hasCurrentSession
        case restoreValidSession
        case signInAnonymously
        case currentMailboxMembership
        case claimPairingCode
        case createMailboxLetter
    }

    private(set) var hasSession: Bool
    private(set) var events: [Event] = []

    private var signInError: (any Error)?
    private var restoreError: (any Error)?
    private var pairingError: (any Error)?
    private var sendError: (any Error)?
    private var currentMembership: MailboxMembership?

    init(
        hasSession: Bool = false
    ) {
        self.hasSession = hasSession
    }

    // MARK: Mock Configuration

    func setSignInError(
        _ error: (any Error)?
    ) {
        signInError = error
    }

    func setRestoreError(
        _ error: (any Error)?
    ) {
        restoreError = error
    }

    func setCurrentMembership(
        _ membership: MailboxMembership?
    ) {
        currentMembership = membership
    }

    func setPairingError(
        _ error: (any Error)?
    ) {
        pairingError = error
    }

    func setSendError(
        _ error: (any Error)?
    ) {
        sendError = error
    }

    func resetEvents() {
        events.removeAll()
    }

    // MARK: Authentication

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

        if let signInError {
            throw signInError
        }

        hasSession = true
    }

    // MARK: Membership

    func currentMailboxMembership() async throws
        -> MailboxMembership? {
        events.append(.currentMailboxMembership)
        return currentMembership
    }

    // MARK: Pairing

    func claimMailboxPairingCode(
        _ normalizedCode: String
    ) async throws -> MailboxMembership {
        events.append(.claimPairingCode)

        if let pairingError {
            throw pairingError
        }

        return await MailboxMembership(
            recipientName: AppConstants.recipientName,
            role: "sender"
        )
    }

    // MARK: Letters

    func createMailboxLetter(
        _ payload: LetterPayload
    ) async throws {
        events.append(.createMailboxLetter)

        if let sendError {
            throw sendError
        }
    }
}
