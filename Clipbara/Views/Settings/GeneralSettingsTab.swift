import SwiftUI
import SwiftData
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
struct GeneralSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    /// Maximum number of eligible history clips to keep.
    @AppStorage(ClipboardMonitor.historyLimitDefaultsKey) private var historyLimit: Int = ClipboardMonitor.defaultHistoryLimit
    /// Changes only when a proposed retention period has been accepted.
    @AppStorage(HistoryRetention.defaultsKey) private var retention: HistoryRetention = .defaultValue
    /// Short sounds on copy and paste.
    @AppStorage(SoundFeedback.defaultsKey) private var playsSounds = false
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @AppStorage(AppState.showsMenuBarIconDefaultsKey) private var showsMenuBarIcon = true
    @State private var showHiddenIconNotice = false
    @State private var pendingRetention: HistoryRetention?
    @State private var pendingRetentionCount = 0
    /// Clips selected when the user asks to clear history.
    @State private var pendingClearIDs: Set<UUID> = []
    @State private var transferMessage: String?
    @State private var showTransferAlert = false

    var body: some View {
        Form {
            Section {
                Toggle("Play Sounds", isOn: $playsSounds)

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }

                // #25. Opening the app again (AppDelegate) and ⌘, or the … menu
                // in the panel lead back here while the icon is hidden.
                Toggle(isOn: $showsMenuBarIcon) {
                    Text("Show Icon in Menu Bar")
                    if !showsMenuBarIcon {
                        Text("To open Settings, open Clipbara again or press \u{2318}, in the panel.")
                    }
                }
                .onChange(of: showsMenuBarIcon) { _, isShown in
                    if !isShown { showHiddenIconNotice = true }
                }

                if !showsMenuBarIcon {
                    Button("Quit \(Bundle.main.appName)") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }

            Section("History") {
                Picker("History Limit", selection: $historyLimit) {
                    Text("100").tag(100)
                    Text("500").tag(500)
                    Text("1,000").tag(1000)
                    Text("5,000").tag(5000)
                    Text("Unlimited").tag(0)
                }
                .pickerStyle(.menu)
                .onChange(of: historyLimit) { appState.clipboardMonitor.applyHistoryRules() }

                Picker(selection: retentionBinding) {
                    ForEach(HistoryRetention.allCases) { retention in
                        Text(retention.displayName).tag(retention)
                    }
                } label: {
                    Text("Keep History")
                    Text("Clips older than this are deleted. Clips on pinboards are kept.")
                }
                .pickerStyle(.menu)

                LabeledContent {
                    Button("Clear\u{2026}") { requestClear() }
                } label: {
                    Text("Clear History")
                    Text("Deletes every clip that isn't on a pinboard.")
                }
            }

            #if APPSTORE
            SyncSettingsSection()
            #endif

            Section("Backup") {
                LabeledContent {
                    Button("Export\u{2026}") { exportHistory() }
                } label: {
                    Text("Export Backup")
                    Text("Export history, pinboards, and settings to a JSON file.")
                }
                LabeledContent {
                    Button("Import\u{2026}") { importHistory() }
                } label: {
                    Text("Import Backup")
                    Text("Import a backup file. Existing clips are kept; duplicates are skipped.")
                }
            }

        }
        .alert("Menu Bar Icon Hidden", isPresented: $showHiddenIconNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Clipbara keeps running. To open Settings again, open Clipbara from Applications or Spotlight, or press \u{2318}, in the panel.")
        }
        .alert("Delete Older Clips?", isPresented: retentionAlertBinding, presenting: pendingRetention) { retention in
            Button("Cancel", role: .cancel) { pendingRetention = nil }
            Button("Delete Clips", role: .destructive) { applyRetention(retention) }
        } message: { retention in
            Text("\(pendingRetentionCount) clips older than \(retention.displayName) will be deleted. Clips on pinboards are kept. This can't be undone.")
        }
        .modifier(ClearHistoryConfirmation(selectedIDs: $pendingClearIDs))
        .alert("Backup", isPresented: $showTransferAlert, presenting: transferMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - History

    /// Previews the proposed setting without persisting it or mutating the history.
    private var retentionBinding: Binding<HistoryRetention> {
        Binding(get: { retention }, set: { proposed in
            guard proposed != retention else { return }
            do {
                // Only the time rule changes. The existing count rule runs independently.
                let count = try proposed.itemsToRemove(in: modelContext, limit: 0).count
                if count == 0 {
                    retention = proposed
                } else {
                    pendingRetentionCount = count
                    pendingRetention = proposed
                }
            } catch {
                NSApp.presentError(error)
            }
        })
    }

    /// Dismissing the confirmation discards the proposal.
    private var retentionAlertBinding: Binding<Bool> {
        Binding(get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } })
    }

    /// Applies a confirmed age limit and updates the persisted setting after a successful save.
    /// - Parameter proposed: The retention period selected by the user.
    private func applyRetention(_ proposed: HistoryRetention) {
        do {
            try proposed.prune(in: modelContext, limit: 0)
            retention = proposed
            appState.clipboardMonitor.refreshLatestItems()
        } catch {
            NSApp.presentError(error)
        }
        pendingRetention = nil
    }

    /// Captures the same off-board selection used by the history panel.
    private func requestClear() {
        do {
            pendingClearIDs = Set(try HistoryRetention.clearableItems(in: modelContext).map(\.id))
        } catch {
            NSApp.presentError(error)
        }
    }

    // MARK: - Backup

    /// Exports the current library as a JSON backup.
    private func exportHistory() {
        NSApp.activate(ignoringOtherApps: true)
        /// Destination for the JSON document.
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "clipbara-backup.json"
        panel.title = String(localized: "Export Clipbara Backup")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            /// The serialized contents of the library.
            let data = try TransferService.exportDocument(context: modelContext)
            try data.write(to: url)
            transferMessage = String(localized: "Backup exported successfully.")
        } catch {
            transferMessage = String(localized: "Export failed: \(error.localizedDescription)")
        }
        showTransferAlert = true
    }

    /// Merges the selected JSON backup into this library.
    private func importHistory() {
        NSApp.activate(ignoringOtherApps: true)
        /// The backup document to import.
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = String(localized: "Import Clipbara Backup")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            /// Bytes read from the selected backup.
            let data = try Data(contentsOf: url)
            /// Item counts to display after merging.
            let summary = try TransferService.importDocument(data, context: modelContext)
            transferMessage = summary.localizedMessage
        } catch {
            transferMessage = String(localized: "Import failed: \(error.localizedDescription)")
        }
        showTransferAlert = true
    }
}
