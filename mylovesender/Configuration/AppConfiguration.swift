import Foundation

struct AppConfiguration: Sendable {
    let supabaseURL: URL?
    let supabasePublishableKey: String?

    static let current = AppConfiguration(bundle: .main)

    init(
        supabaseURL: URL?,
        supabasePublishableKey: String?
    ) {
        if let supabaseURL,
           supabaseURL.host?.isEmpty == false {
            self.supabaseURL = supabaseURL
        } else {
            self.supabaseURL = nil
        }

        self.supabasePublishableKey =
            supabasePublishableKey?.isPlaceholder == false
            ? supabasePublishableKey
            : nil
    }

    init(bundle: Bundle) {
        let rawURL = bundle.object(
            forInfoDictionaryKey: "SUPABASE_URL"
        ) as? String

        let rawKey = bundle.object(
            forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY"
        ) as? String

        if let rawURL,
           rawURL.isPlaceholder == false,
           let url = URL(string: rawURL.trimmed),
           let host = url.host,
           host.isEmpty == false {
            supabaseURL = url
        } else {
            supabaseURL = nil
        }

        supabasePublishableKey =
            rawKey?.isPlaceholder == false
            ? rawKey?.trimmed
            : nil
    }

    var isSupabaseConfigured: Bool {
        supabaseURL != nil &&
        supabasePublishableKey != nil
    }
}

private extension String {

    var isPlaceholder: Bool {
        let normalizedValue = trimmed.uppercased()

        return normalizedValue.isEmpty ||
            normalizedValue.contains("$(") ||
            normalizedValue.contains("PASTE_") ||
            normalizedValue.contains("PLACEHOLDER") ||
            normalizedValue.contains("HIER_")
    }
}

enum AppConstants {
    static let senderName = "Nico"
    static let recipientName = "Bella"
    static let recipientNickname = "Schatz"
    static let defaultSignature = "Dein Junge"
    static let defaultLabel = "VON HERZEN"
    static let appName = "MyLove Sender"
}
