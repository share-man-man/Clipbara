import SwiftUI
import SwiftData

@MainActor
struct PrivacySettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \ExcludedApp.appName) private var excludedApps: [ExcludedApp]
    @AppStorage(ContentTypeClassifier.ignoresConfidentialDefaultsKey)
    private var ignoresConfidential = ContentTypeClassifier.ignoresMarkedContentByDefault
    @AppStorage(ContentTypeClassifier.ignoresTransientDefaultsKey)
    private var ignoresTransient = ContentTypeClassifier.ignoresMarkedContentByDefault

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $ignoresConfidential) {
                    Text("Ignore Confidential Content")
                    Text("Doesn't save passwords and other content that apps mark as confidential.")
                }
                Toggle(isOn: $ignoresTransient) {
                    Text("Ignore Temporary Content")
                    Text("Doesn't save data that other apps put on the clipboard only for a moment.")
                }
            }

            Section {
                if excludedApps.isEmpty {
                    Text("No apps are excluded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(excludedApps) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: AppIconProvider.icon(for: app.bundleId, size: 24))
                                .resizable()
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading) {
                                Text(app.appName)
                                Text(verbatim: app.bundleId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                remove(app)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(Text("Remove"))
                        }
                    }
                }
                HStack {
                    Button("Add App\u{2026}") { addApp() }
                    Spacer()
                }
            } header: {
                Text("Excluded Apps")
            } footer: {
                Text("Excluded apps will not have their clipboard content saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Lets the user choose an application whose copies will be excluded.
    private func addApp() {
        // macOS application picker, initially showing installed applications.
        let panel = NSOpenPanel()
        panel.title = String(localized: "Select App to Exclude")
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        // A bundle identifier distinguishes apps that share a display name.
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else { return }

        // Display name shown alongside the identifier in the exclusion list.
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        if excludedApps.contains(where: { $0.bundleId == bundleId }) { return }

        modelContext.insert(ExcludedApp(bundleId: bundleId, appName: appName))
        try? modelContext.save()
        appState.clipboardMonitor.loadExcludedApps()
    }

    /// Resumes capture from an excluded application.
    /// - Parameter app: The saved exclusion to remove.
    private func remove(_ app: ExcludedApp) {
        modelContext.delete(app)
        try? modelContext.save()
        appState.clipboardMonitor.loadExcludedApps()
    }
}
