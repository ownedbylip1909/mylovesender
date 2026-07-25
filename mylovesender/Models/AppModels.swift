import Foundation
import SwiftData

enum LetterStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case scheduled
    case sending
    case sent
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: "Entwurf"
        case .scheduled: "Geplant"
        case .sending: "Wird gesendet"
        case .sent: "Gesendet"
        case .failed: "Fehlgeschlagen"
        }
    }

    var systemImage: String {
        switch self {
        case .draft: "doc.text"
        case .scheduled: "calendar.badge.clock"
        case .sending: "paperplane"
        case .sent: "paperplane.fill"
        case .failed: "exclamationmark.triangle"
        }
    }
}

enum ConnectionState: String, Codable, CaseIterable {
    case notConnected
    case checking
    case connected
    case offline
    case failed

    var title: String {
        switch self {
        case .notConnected: "Nicht verbunden"
        case .checking: "Verbindung wird geprüft"
        case .connected: "Mit Bella verbunden"
        case .offline: "Offline"
        case .failed: "Verbindung fehlgeschlagen"
        }
    }
}

enum PairingState: Equatable, Codable {
    case unpaired
    case pairing
    case paired(displayName: String)
    case failed(message: String)
}

struct MailboxMembership: Codable, Equatable, Sendable {
    let recipientName: String
    let role: String
}

struct Letter: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let clientRequestId: UUID
    var title: String
    var preview: String
    var body: String
    var dateLabel: String
    var signature: String?
    var recipientName: String
    var senderName: String
    var createdAt: Date
    var publishedAt: Date
    var status: LetterStatus
}

@Model
final class LetterDraft {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var clientRequestId: UUID
    var title: String
    var preview: String
    var body: String
    var dateLabel: String
    var signature: String
    var recipientName: String
    var senderName: String
    var createdAt: Date
    var updatedAt: Date
    var publishedAt: Date?
    var statusRawValue: String
    var lastErrorMessage: String?

    init(
        id: UUID = UUID(),
        clientRequestId: UUID = UUID(),
        title: String = "",
        preview: String = "",
        body: String = "",
        dateLabel: String = "VON HERZEN",
        signature: String = "Dein Junge",
        recipientName: String = "Bella",
        senderName: String = "Nico",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        publishedAt: Date? = nil,
        status: LetterStatus = .draft,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.clientRequestId = clientRequestId
        self.title = title
        self.preview = preview
        self.body = body
        self.dateLabel = dateLabel
        self.signature = signature
        self.recipientName = recipientName
        self.senderName = senderName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.publishedAt = publishedAt
        self.statusRawValue = status.rawValue
        self.lastErrorMessage = lastErrorMessage
    }

    var status: LetterStatus {
        get { LetterStatus(rawValue: statusRawValue) ?? .draft }
        set { statusRawValue = newValue.rawValue }
    }

    var normalizedPreview: String {
        let trimmed = preview.trimmed
        if !trimmed.isEmpty { return trimmed }
        return String(body.trimmed.prefix(120))
    }
}

struct LetterPayload: Codable, Sendable {
    let clientRequestId: UUID
    let title: String
    let preview: String
    let body: String
    let dateLabel: String
    let publishedAt: Date
}

struct LetterValidationResult: Equatable {
    var errors: [String]
    var isValid: Bool { errors.isEmpty }
}

enum SortMode: String, CaseIterable, Identifiable {
    case createdAt
    case publishedAt

    var id: String { rawValue }
    var title: String { self == .createdAt ? "Erstellung" : "Veröffentlichung" }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
