import Foundation
import LocalAuthentication
import Observation
import SwiftUI

protocol AuthenticationServiceProtocol: Sendable {
    func authenticate(reason: String) async throws
}

struct LocalAuthenticationService: AuthenticationServiceProtocol {
    func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw AppError.authenticationFailed
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if !success { throw AppError.authenticationFailed }
        } catch let laError as LAError where laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
            throw AppError.authenticationCancelled
        } catch {
            throw AppError.authenticationFailed
        }
    }
}

struct TestAuthenticationService: AuthenticationServiceProtocol {
    func authenticate(reason: String) async throws { }
}

@MainActor
@Observable
final class AppLockService {
    private let authenticationService: AuthenticationServiceProtocol
    private let relockInterval: TimeInterval = 120
    private var backgroundEnteredAt: Date?

    var isLocked: Bool
    var errorMessage: String?
    var hidesSensitiveContent = true
    var isFaceIDEnabled = true

    init(authenticationService: AuthenticationServiceProtocol, startsLocked: Bool = true) {
        self.authenticationService = authenticationService
        self.isLocked = startsLocked
    }

    func unlock() async {
        guard isFaceIDEnabled else {
            isLocked = false
            return
        }
        do {
            try await authenticationService.authenticate(reason: "Entsperre deine Briefe an Bella.")
            errorMessage = nil
            isLocked = false
        } catch let appError as AppError {
            errorMessage = appError.userMessage
        } catch {
            errorMessage = AppError.authenticationFailed.userMessage
        }
    }

    func scenePhaseDidChange(to phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundEnteredAt = .now
            hidesSensitiveContent = true
        case .active:
            if let backgroundEnteredAt, Date().timeIntervalSince(backgroundEnteredAt) > relockInterval {
                isLocked = true
            }
            hidesSensitiveContent = isLocked
        case .inactive:
            hidesSensitiveContent = true
        @unknown default:
            hidesSensitiveContent = true
        }
    }
}
