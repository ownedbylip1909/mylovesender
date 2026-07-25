import Foundation

enum AppError: Error, Equatable {
    case validation(String)
    case notConfigured
    case notPaired
    case offline
    case authenticationCancelled
    case authenticationFailed
    case pairingUnavailable
    case secureSessionFailed
    case invalidPairingCode
    case rateLimited
    case sendFailed
    case duplicateRequest
    case storageFailed

    var userMessage: String {
        switch self {
        case .validation(let message): message
        case .notConfigured: "Die Supabase-Konfiguration ist noch nicht vollständig eingerichtet."
        case .notPaired: "Die Verbindung zu Bella ist noch nicht eingerichtet."
        case .offline: "Du bist offline. Dein Entwurf bleibt lokal gespeichert."
        case .authenticationCancelled: "Die Entsperrung wurde abgebrochen."
        case .authenticationFailed: "Die Entsperrung ist fehlgeschlagen. Bitte versuche es erneut."
        case .pairingUnavailable: "Das Pairing-Backend ist noch nicht eingerichtet."
        case .secureSessionFailed: "Die sichere Sitzung konnte nicht hergestellt werden."
        case .invalidPairingCode: "Der Pairing-Code ist ungültig oder abgelaufen."
        case .rateLimited: "Zu viele Versuche. Bitte warte kurz und versuche es erneut."
        case .sendFailed: "Der Brief konnte nicht gesendet werden. Dein Entwurf bleibt erhalten."
        case .duplicateRequest: "Dieser Brief wurde bereits mit derselben Anfrage verarbeitet."
        case .storageFailed: "Der lokale Speicher konnte nicht aktualisiert werden."
        }
    }
}

struct LetterValidator: Sendable {
    func validate(title: String, body: String, dateLabel: String, publishedAt: Date?) -> LetterValidationResult {
        var errors: [String] = []
        if title.trimmed.isEmpty { errors.append("Bitte gib einen Titel ein.") }
        if body.trimmed.isEmpty { errors.append("Bitte schreibe deinen Brieftext.") }
        if dateLabel.trimmed.isEmpty { errors.append("Bitte wähle ein Label aus.") }
        if let publishedAt, publishedAt < Date().addingTimeInterval(-60) {
            errors.append("Der Veröffentlichungszeitpunkt darf nicht in der Vergangenheit liegen.")
        }
        return LetterValidationResult(errors: errors)
    }

    func status(for publishedAt: Date, now: Date = .now) -> LetterStatus {
        publishedAt > now ? .scheduled : .sent
    }
}

struct PairingCodeValidator: Sendable {
    func normalizedCode(from input: String) -> String? {
        let code = input
            .uppercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let compact = code.replacingOccurrences(of: "-", with: "")
        guard (12...32).contains(compact.count) else { return nil }
        return compact
    }
}
