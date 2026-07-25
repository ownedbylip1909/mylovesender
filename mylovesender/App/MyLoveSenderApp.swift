import SwiftUI
import SwiftData

@main
struct MyLoveSenderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel: AppViewModel
    @State private var appLock: AppLockService
    private let container: ModelContainer

    init() {
        let processInfo = ProcessInfo.processInfo
        let isUITest = processInfo.arguments.contains("--ui-testing") && processInfo.environment["MYLOVE_UI_TESTING"] == "1"
        let configuration = AppConfiguration.current
        let keychain: KeychainServiceProtocol = isUITest ? InMemoryKeychainService() : KeychainService()
        let supabase: SupabaseServiceProtocol = isUITest ? MockSupabaseService() : SupabaseService(configuration: configuration)
        let pairing = PairingService(supabaseService: supabase, keychain: keychain)
        _appModel = State(initialValue: AppViewModel(pairingService: pairing, letterRepository: LetterRepository(supabaseService: supabase, pairingService: pairing)))
        _appLock = State(initialValue: AppLockService(authenticationService: isUITest ? TestAuthenticationService() : LocalAuthenticationService(), startsLocked: !isUITest))
        let schema = Schema([LetterDraft.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITest)
        container = try! ModelContainer(for: schema, configurations: [modelConfiguration])
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(appModel)
                .environment(appLock)
                .modelContainer(container)
                .onAppear { Task { await appModel.refreshConnection() } }
                .onChange(of: scenePhase) { _, phase in appLock.scenePhaseDidChange(to: phase) }
                .privacySensitive(appLock.hidesSensitiveContent)
        }
    }
}
