import Foundation

protocol PairingServiceProtocol: Sendable {
    func loadMembership() async -> MailboxMembership?
    func claim(code: String) async throws -> MailboxMembership
    func disconnect() async throws
}

struct PairingService: PairingServiceProtocol {
    private let supabaseService: any SupabaseServiceProtocol
    private let keychain: any KeychainServiceProtocol
    private let validator: PairingCodeValidator

    private let account = "mailbox-membership"

    init(
        supabaseService: any SupabaseServiceProtocol,
        keychain: any KeychainServiceProtocol,
        validator: PairingCodeValidator = PairingCodeValidator()
    ) {
        self.supabaseService = supabaseService
        self.keychain = keychain
        self.validator = validator
    }

    func loadMembership() async -> MailboxMembership? {
        if let cachedMembership = await loadCachedMembership() {
            return cachedMembership
        }

        do {
            guard let membership =
                try await supabaseService.currentMailboxMembership()
            else {
                return nil
            }

            try await cache(membership)

            return membership
        } catch {
            print("Mailbox-Mitgliedschaft konnte nicht geladen werden:", error)
            return nil
        }
    }

    func claim(code: String) async throws -> MailboxMembership {
        guard let normalizedCode =
            validator.normalizedCode(from: code)
        else {
            throw AppError.validation(
                "Der Pairing-Code hat kein gültiges Format."
            )
        }

        let membership =
            try await supabaseService.claimPairingCode(normalizedCode)

        try await cache(membership)

        return membership
    }

    func disconnect() async throws {
        try await keychain.delete(account: account)
    }

    private func loadCachedMembership() async -> MailboxMembership? {
        do {
            guard let data = try await keychain.read(account: account) else {
                return nil
            }

            return try JSONDecoder().decode(
                MailboxMembership.self,
                from: data
            )
        } catch {
            print("Gespeicherte Mitgliedschaft konnte nicht gelesen werden:", error)

            // Kaputte oder veraltete Cache-Daten entfernen.
            try? await keychain.delete(account: account)

            return nil
        }
    }

    private func cache(
        _ membership: MailboxMembership
    ) async throws {
        let data = try JSONEncoder().encode(membership)

        try await keychain.save(
            data,
            account: account
        )
    }
}
