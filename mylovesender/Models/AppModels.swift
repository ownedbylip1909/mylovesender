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
    let mailboxId: UUID?

    nonisolated init(recipientName: String, role: String, mailboxId: UUID? = nil) {
        self.recipientName = recipientName
        self.role = role
        self.mailboxId = mailboxId
    }
}

enum ServerLetterStatus: String, Codable, Sendable {
    case draft
    case scheduled
    case published
}

struct LetterAttachment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var fileName: String
    var mimeType: String
    var sizeBytes: Int
    var data: Data
    var storagePath: String?

    init(
        id: UUID = UUID(),
        fileName: String,
        mimeType: String,
        sizeBytes: Int,
        data: Data,
        storagePath: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.data = data
        self.storagePath = storagePath
    }
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
    var serverStatus: ServerLetterStatus?
    var isRead: Bool
    var readAt: Date?
    var archivedAt: Date?
    var deletedAt: Date?
    var senderUserId: UUID?
    var attachments: [LetterAttachment]

    var isVisibleInNormalLists: Bool {
        archivedAt == nil && deletedAt == nil
    }
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
    var serverStatusRawValue: String?
    var isRead: Bool = false
    var readAt: Date?
    var archivedAt: Date?
    var deletedAt: Date?
    var senderUserId: UUID?
    var attachmentsData: Data?
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
        serverStatus: ServerLetterStatus? = nil,
        isRead: Bool = false,
        readAt: Date? = nil,
        archivedAt: Date? = nil,
        deletedAt: Date? = nil,
        senderUserId: UUID? = nil,
        attachments: [LetterAttachment] = [],
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
        self.serverStatusRawValue = serverStatus?.rawValue
        self.isRead = isRead
        self.readAt = readAt
        self.archivedAt = archivedAt
        self.deletedAt = deletedAt
        self.senderUserId = senderUserId
        self.attachmentsData = try? JSONEncoder().encode(attachments)
        self.lastErrorMessage = lastErrorMessage
    }

    var status: LetterStatus {
        get { LetterStatus(rawValue: statusRawValue) ?? .draft }
        set { statusRawValue = newValue.rawValue }
    }

    var serverStatus: ServerLetterStatus? {
        get { serverStatusRawValue.flatMap(ServerLetterStatus.init(rawValue:)) }
        set { serverStatusRawValue = newValue?.rawValue }
    }

    var attachments: [LetterAttachment] {
        get {
            guard let attachmentsData else { return [] }
            return (try? JSONDecoder().decode([LetterAttachment].self, from: attachmentsData)) ?? []
        }
        set { attachmentsData = try? JSONEncoder().encode(newValue) }
    }

    var isArchivedOrDeleted: Bool {
        archivedAt != nil || deletedAt != nil
    }

    var readStatusText: String {
        if let readAt {
            return "Gelesen am \(readAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return isRead ? "Gelesen" : "Ungelesen"
    }

    var normalizedPreview: String {
        let trimmed = preview.trimmed
        if !trimmed.isEmpty { return trimmed }
        return String(body.trimmed.prefix(120))
    }
}

struct SupabaseLetterRecord: Decodable, Sendable {
    let id: UUID
    let ownerId: UUID?
    let mailboxId: UUID?
    let clientRequestId: UUID?
    let title: String
    let preview: String?
    let body: String
    let dateLabel: String?
    let publishedAt: Date
    let createdAt: Date?
    let isRead: Bool?
    let readAt: Date?
    let archivedAt: Date?
    let deletedAt: Date?
    let senderUserId: UUID?
    let status: ServerLetterStatus?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case mailboxId = "mailbox_id"
        case clientRequestId = "client_request_id"
        case title
        case preview
        case body
        case dateLabel = "date_label"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case isRead = "is_read"
        case readAt = "read_at"
        case archivedAt = "archived_at"
        case deletedAt = "deleted_at"
        case senderUserId = "sender_user_id"
        case status
    }
}

struct LetterPayload: Codable, Sendable {
    let clientRequestId: UUID
    let title: String
    let preview: String
    let body: String
    let dateLabel: String
    let publishedAt: Date
    let serverStatus: ServerLetterStatus
    let attachments: [LetterAttachment]

    init(
        clientRequestId: UUID,
        title: String,
        preview: String,
        body: String,
        dateLabel: String,
        publishedAt: Date,
        serverStatus: ServerLetterStatus,
        attachments: [LetterAttachment] = []
    ) {
        self.clientRequestId = clientRequestId
        self.title = title
        self.preview = preview
        self.body = body
        self.dateLabel = dateLabel
        self.publishedAt = publishedAt
        self.serverStatus = serverStatus
        self.attachments = attachments
    }
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
