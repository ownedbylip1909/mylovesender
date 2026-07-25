import SwiftUI
import SwiftData

struct OverviewView: View {
    @Environment(AppViewModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LetterDraft.createdAt, order: .reverse) private var drafts: [LetterDraft]

    private var scheduledCount: Int { drafts.filter { $0.status == .scheduled }.count }
    private var localDraftCount: Int { drafts.filter { $0.status == .draft }.count }
    private var lastSent: LetterDraft? { drafts.first { $0.status == .sent } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hey, Nico.")
                            .font(.largeTitle.bold())
                        Text("Ein kleiner Ort für deine Worte an Bella.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    LoveCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Verbindung")
                                    .font(.headline)
                                ConnectionBadge(state: appModel.connectionState)
                            }
                            Spacer()
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(LoveTheme.lavender)
                                .accessibilityHidden(true)
                        }
                    }

                    HStack(spacing: 12) {
                        MetricView(value: "\(scheduledCount)", label: "Geplant", image: "calendar")
                        MetricView(value: "\(localDraftCount)", label: "Entwürfe", image: "doc.text")
                    }

                    LoveCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Zuletzt gesendet")
                                .font(.headline)
                            Text(lastSent?.title.nilIfEmpty ?? appModel.lastSentTitle)
                                .font(.title3.weight(.semibold))
                            Text(lastSent?.normalizedPreview ?? "Sobald ein Brief gesendet wurde, erscheint er hier.")
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        appModel.selectedTab = .new
                    } label: {
                        Label("Neuen Brief schreiben", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LoveTheme.accent)
                    .controlSize(.large)
                }
                .padding(20)
            }
            .navigationTitle("Übersicht")
            .toolbar { NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") } }
        }
    }
}

struct MetricView: View {
    let value: String
    let label: String
    let image: String

    var body: some View {
        LoveCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: image)
                    .foregroundStyle(LoveTheme.accent)
                    .accessibilityHidden(true)
                Text(value).font(.title.bold())
                Text(label).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { trimmed.isEmpty ? nil : self }
}
