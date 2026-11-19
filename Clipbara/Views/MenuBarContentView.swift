import SwiftUI
import SwiftData
import KeyboardShortcuts

/// Native menu commands for recent copies, panel shortcuts and app settings.
@MainActor
struct MenuBarContentView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var updaterViewModel: CheckForUpdatesViewModel
    @Query(sort: \ClipboardItem.copiedAt, order: .reverse)
    private var recentItems: [ClipboardItem]

    var body: some View {
        // Show the build name supplied by Debug or Local in the native menu.
        if let banner = Bundle.main.buildBanner {
            Text(verbatim: banner)
            Divider()
        }

        Section("Recent Copies") {
            if recentItems.isEmpty {
                Text("No clipboard history")
            } else {
                ForEach(recentItems.prefix(ClipboardMonitor.recentMenuLimit)) { item in
                    MenuBarItemRow(item: item)
                }
            }
        }
        #if APPSTORE
        .onAppear { Entitlements.shared.reevaluate() }
        #endif

        Divider()

        Button("Open History") {
            appState.togglePanel()
        }
        .globalKeyboardShortcut(.toggleHistoryPanel)

        Button(appState.clipQueue.isActive ? "End Clip Queue" : "Start Clip Queue") {
            appState.toggleClipQueue()
        }
        .globalKeyboardShortcut(.toggleClipQueue)

        Toggle("Clipboard Monitoring", isOn: Binding(
            get: { appState.clipboardMonitor.isMonitoring },
            set: { _ in appState.clipboardMonitor.toggle() }
        ))

        #if APPSTORE
        if showsPurchaseItems {
            Divider()

            Button {
                PaywallWindowController.shared.show()
            } label: {
                Text("Unlock Clipbara…")
                trialStatus
            }

            Button("Restore Purchases") {
                PaywallWindowController.shared.show(restore: true)
            }
        }
        #endif

        Divider()

        #if !APPSTORE
        Button("Check for Updates…") {
            updaterViewModel.checkForUpdates()
        }
        .disabled(!updaterViewModel.canCheckForUpdates)
        #endif

        Button("Send Feedback…") {
            NSWorkspace.shared.open(ReviewPrompter.feedbackURL)
        }

        #if APPSTORE
        Button("Rate on App Store") {
            NSWorkspace.shared.open(ReviewPrompter.writeReviewURL)
        }
        #endif

        Divider()

        Button("Settings…") {
            openSettings()
            SettingsWindowFront.bring()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit \(Bundle.main.appName)") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    #if APPSTORE
    /// Hidden once the app is owned, and while a StoreKit check has failed open.
    private var showsPurchaseItems: Bool {
        switch Entitlements.shared.state {
        case .trialActive, .trialNotStarted, .trialExpired: true
        case .unlocked: false
        }
    }

    @ViewBuilder
    private var trialStatus: some View {
        switch Entitlements.shared.state {
        case .trialActive(let daysLeft):
            Text("\(daysLeft) days left")
        case .trialExpired:
            Text("Trial ended")
        case .trialNotStarted, .unlocked:
            EmptyView()
        }
    }
    #endif
}

@MainActor
private struct MenuBarItemRow: View {
    /// Clipboard entry represented by this menu command.
    let item: ClipboardItem
    @Environment(AppState.self) private var appState

    /// Menus grow to fit their longest item, so long clips are cut here.
    private static let titleLimit = 42

    var body: some View {
        Button {
            #if APPSTORE
            guard Entitlements.shared.checkHistoryAccess() else {
                PaywallWindowController.shared.show()
                return
            }
            #endif
            appState.clipQueue.stop()
            appState.pasteService.paste(item: item)
        } label: {
            Image(systemName: item.contentType.systemImage)
            Text(verbatim: title)
            Text(verbatim: subtitle)
        }
    }

    private var title: String {
        // Use a localized label for clips without a textual preview.
        let text: String
        switch item.contentType {
        case .plainText, .richText, .html, .url:
            text = item.textContent ?? "…"
        case .image:
            text = String(localized: "Image")
        case .fileURL:
            text = item.textContent ?? String(localized: "File")
        case .color:
            text = item.textContent ?? String(localized: "Color")
        case .unknown:
            text = String(localized: "Unknown")
        }
        // Keep the first nonempty line within the native menu's width.
        let line = text.drop(while: \.isWhitespace).prefix(Self.titleLimit + 1).prefix(while: { !$0.isNewline })
        guard !line.isEmpty else { return "…" }
        return line.count > Self.titleLimit ? String(line.prefix(Self.titleLimit)) + "…" : String(line)
    }

    private var subtitle: String {
        [item.sourceAppName, RelativeTimeFormatter.string(for: item.copiedAt)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
