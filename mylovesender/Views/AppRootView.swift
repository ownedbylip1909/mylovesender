import SwiftUI
import SwiftData

struct AppRootView: View {
    @Environment(AppViewModel.self) private var appModel
    @Environment(AppLockService.self) private var appLock
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LoveTheme.background(for: colorScheme).ignoresSafeArea()
            if appLock.isLocked {
                LockedView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appLock.isLocked)
    }
}

struct LockedView: View {
    @Environment(AppLockService.self) private var appLock

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.heart.fill")
                .font(.system(size: 58))
                .foregroundStyle(LoveTheme.accent)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("MyLove Sender")
                    .font(.largeTitle.bold())
                Text("Entsperre die App, um deine Briefe zu sehen.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let error = appLock.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Fehler: \(error)")
            }
            Button {
                Task { await appLock.unlock() }
            } label: {
                Label("App entsperren", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(LoveTheme.accent)
            .controlSize(.large)
        }
        .padding(28)
    }
}

struct MainTabView: View {
    @Environment(AppViewModel.self) private var appModel

    var body: some View {
        @Bindable var model = appModel
        TabView(selection: $model.selectedTab) {
            OverviewView()
                .tabItem { Label("Übersicht", systemImage: "house") }
                .tag(AppTab.overview)
            LettersView()
                .tabItem { Label("Briefe", systemImage: "tray.full") }
                .tag(AppTab.letters)
            LetterEditorView(draft: nil)
                .tabItem { Label("Neu", systemImage: "plus.circle.fill") }
                .tag(AppTab.new)
            ConnectionView()
                .tabItem { Label("Verbindung", systemImage: "link") }
                .tag(AppTab.connection)
        }
        .tint(LoveTheme.accent)
    }
}
