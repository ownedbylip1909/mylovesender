import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    let pairingService: PairingServiceProtocol
    let letterRepository: LetterRepositoryProtocol
    let validator = LetterValidator()

    var connectionState: ConnectionState = .notConnected
    var pairingMessage: String?
    var isPairing = false
    var standardSignature = AppConstants.defaultSignature
    var standardLabel = AppConstants.defaultLabel
    var selectedTab: AppTab = .overview
    var lastSentTitle: String = "Noch kein Brief gesendet"

    init(pairingService: PairingServiceProtocol, letterRepository: LetterRepositoryProtocol) {
        self.pairingService = pairingService
        self.letterRepository = letterRepository
    }

    func refreshConnection() async {
        connectionState = .checking
        if let membership = await pairingService.loadMembership(), membership.role == "sender" {
            connectionState = .connected
            pairingMessage = "Mit \(membership.recipientName) verbunden."
        } else {
            connectionState = .notConnected
            pairingMessage = "Verbindung noch nicht eingerichtet."
        }
    }

    func claimPairingCode(_ code: String) async {
        isPairing = true
        connectionState = .checking
        defer { isPairing = false }
        do {
            let membership = try await pairingService.claim(code: code)
            connectionState = .connected
            pairingMessage = "Verbindung zu \(membership.recipientName) hergestellt."
        } catch let appError as AppError {
            connectionState = appError == .offline ? .offline : .failed
            pairingMessage = appError.userMessage
        } catch {
            connectionState = .failed
            pairingMessage = AppError.pairingUnavailable.userMessage
        }
    }

    func disconnect() async {
        do {
            try await pairingService.disconnect()
            connectionState = .notConnected
            pairingMessage = "Die Verbindung wurde getrennt."
        } catch let appError as AppError {
            connectionState = appError == .offline ? .offline : .failed
            pairingMessage = appError.userMessage
        } catch {
            connectionState = .failed
            pairingMessage = AppError.sendFailed.userMessage
        }
    }
}

enum AppTab: Hashable {
    case overview
    case letters
    case new
    case connection
}
