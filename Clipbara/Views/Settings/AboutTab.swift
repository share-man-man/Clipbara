import SwiftUI

@MainActor
struct AboutTab: View {
    @EnvironmentObject private var updaterViewModel: CheckForUpdatesViewModel
    @Environment(AppState.self) private var appState

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text("Version \(appVersion) (\(buildNumber))")
                } label: {
                    Text(verbatim: Bundle.main.appName)
                    Text("A simple clipboard manager for macOS.")
                }

                #if !APPSTORE
                Button("Check for Updates…") {
                    updaterViewModel.checkForUpdates()
                }
                .disabled(!updaterViewModel.canCheckForUpdates)
                #endif

                Button("Show Welcome Tour…") {
                    // The tour uses the current installation's store.
                    guard let container = appState.modelContainer else { return }
                    OnboardingWindowController.shared.show(appState: appState, modelContainer: container)
                }
            }
        }
    }
}
