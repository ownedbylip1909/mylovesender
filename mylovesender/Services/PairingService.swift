import Foundation

protocol PairingServiceProtocol: Sendable {
    func loadMembership() async -> MailboxMembership?
    func claim(code: String) async throws -> MailboxMembership
    func disconnect() async throws
}

struct PairingService: PairingServiceProtocol {
    private let supabaseService: SupabaseServiceProtocol
    private let keychain: KeychainServiceProtocol
    private let validator = PairingCodeValidator()
    private let account = "mailbox-membership"

    init(supabaseService: SupabaseServiceProtocol, keychain: KeychainServiceProtocol) {
        self.supabaseService = supabaseService
        self.keychain = keychain
    }

    func loadMembership() async -> MailboxMembership? {
        if let membership = try? await supabaseService.currentMailboxMembership() {
            if let data = try? JSONEncoder().encode(membership) {
                try? await keychain.save(data, account: account)
            }
            return membership
        }

        if let data = try? await keychain.read(account: account),
           let membership = try? JSONDecoder().decode(MailboxMembership.self, from: data) {
            return membership
        }
        return nil
    }

    func claim(code: String) async throws -> MailboxMembership {
        guard let normalized = validator.normalizedCode(from: code) else {
            throw AppError.validation("Der Pairing-Code hat kein gültiges Format.")
        }
        let membership = try await supabaseService.claimPairingCode(normalized)
        let data = try JSONEncoder().encode(membership)
        try await keychain.save(data, account: account)
        return membership
    }

    func disconnect() async throws {
        guard let membership = await loadMembership(),
              let mailboxId = membership.mailboxId else {
            throw AppError.notPaired
        }
        try await supabaseService.disconnectMailbox(mailboxId)
        try await keychain.delete(account: account)
    }
}
