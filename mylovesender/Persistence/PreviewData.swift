import Foundation
import SwiftData

enum PreviewData {
    @MainActor
    static var modelContainer: ModelContainer {
        let schema = Schema([LetterDraft.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        let draft = LetterDraft(
            title: "Ein kleiner Morgen",
            preview: "Ich wollte dir nur ein paar Worte schicken.",
            body: "Hey Schatz, ich denke an dich.",
            publishedAt: Date().addingTimeInterval(3600),
            status: .scheduled
        )
        container.mainContext.insert(draft)
        return container
    }
}
