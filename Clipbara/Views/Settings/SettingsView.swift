import SwiftUI

/// The panes of the Settings window, listed in its sidebar.
private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case pasting
    case privacy
    case appearance
    case shortcuts
    case about

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .general: "General"
        case .pasting: "Pasting"
        case .privacy: "Privacy"
        case .appearance: "Appearance"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }

    /// Native symbol and semantic color that identify each settings category.
    var sidebarIcon: (name: String, tint: Color) {
        switch self {
        case .general: ("gearshape.fill", .gray)
        case .pasting: ("list.clipboard.fill", .blue)
        case .privacy: ("hand.raised.fill", .green)
        case .appearance: ("circle.lefthalf.filled", .purple)
        case .shortcuts: ("command", .orange)
        case .about: ("info.circle.fill", .teal)
        }
    }

    /// User-visible controls that can lead a search to this pane.
    private var searchTerms: [LocalizedStringResource] {
        switch self {
        case .general:
            /// General controls available across all Mac distributions.
            let terms: [LocalizedStringResource] = [
                "Play Sounds", "Launch at Login", "Show Icon in Menu Bar", "History Limit", "Keep History",
                "Clear History", "Export Backup", "Import Backup"
            ]
            #if APPSTORE
            return terms + ["iCloud Sync", "Sync Images"]
            #else
            return terms
            #endif
        case .pasting:
            return ["Always Paste as Plain Text"] + (DirectPaste.isAvailable
                ? ["Paste into the Active App", "Open Accessibility Settings…"] : [])
        case .privacy:
            return ["Ignore Confidential Content", "Ignore Temporary Content", "Excluded Apps", "Add App…"]
        case .appearance:
            return ["Theme", "System", "Light", "Dark", "Animate Panel", "Panel Width", "Card Size",
                    "Show Panel On", "Background Transparency", "Restore Defaults"]
        case .shortcuts:
            return ["Toggle History Panel", "Start or End Clip Queue", "Clear All History", "Quick Look Preview", "First 8 Pinboards"]
                + (SelectionCopy.isAvailable ? ["Copy Selection When Starting"] : [])
        case .about:
            #if APPSTORE
            return ["Show Welcome Tour…"]
            #else
            return ["Show Welcome Tour…", "Check for Updates…"]
            #endif
        }
    }

    /// Matches the translated category name or one of its controls.
    /// - Parameters:
    ///   - query: The user's trimmed search text.
    ///   - locale: The locale used by the settings window.
    func matches(_ query: String, locale: Locale) -> Bool {
        ([title] + searchTerms).contains { resource in
            // Resolve catalog strings in the same locale as the visible labels.
            var localizedResource = resource
            localizedResource.locale = locale
            return String(localized: localizedResource)
                .range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale) != nil
        }
    }
}

/// Sidebar navigation for the native Settings window.
@MainActor
struct SettingsView: View {
    @Environment(\.locale) private var locale
    @State private var search = ""
    /// Panes visited in order, including forward history after a back navigation.
    @State private var history: [SettingsPane] = [.general]
    /// Position of the pane shown in the detail column.
    @State private var position = 0

    private var currentPane: SettingsPane { history[position] }

    private var matchingPanes: [SettingsPane] {
        // Ignore surrounding whitespace, including pasted line breaks.
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? SettingsPane.allCases : SettingsPane.allCases.filter { $0.matches(query, locale: locale) }
    }

    /// Filtering a row away clears the list highlight while keeping its detail open.
    private var selection: Binding<SettingsPane?> {
        Binding(
            get: { matchingPanes.contains(currentPane) ? currentPane : nil },
            set: { pane in
                if let pane { visit(pane) }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(matchingPanes, selection: selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.sidebarIcon.name)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(pane.sidebarIcon.tint)
                }
                .tag(pane)
            }
            .listStyle(.sidebar)
            .overlay {
                if matchingPanes.isEmpty {
                    Text("No Results")
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .searchable(text: $search, placement: .sidebar)
            .onSubmit(of: .search) {
                if let first = matchingPanes.first { visit(first) }
            }
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(for: currentPane)
                .formStyle(.grouped)
                .navigationTitle(Text(currentPane.title))
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button("Back", systemImage: "chevron.backward") { step(by: -1) }
                            .labelStyle(.iconOnly)
                            .help("Back")
                            .keyboardShortcut("[", modifiers: .command)
                            .disabled(position == history.startIndex)
                        Button("Forward", systemImage: "chevron.forward") { step(by: 1) }
                            .labelStyle(.iconOnly)
                            .help("Forward")
                            .keyboardShortcut("]", modifiers: .command)
                            .disabled(position == history.count - 1)
                    }
                }
        }
        .frame(minWidth: 670, minHeight: 500)
        .background(SettingsWindowReader())
    }

    /// Opens a pane and drops any forward history after branching.
    /// - Parameter pane: The category selected in the sidebar or search results.
    private func visit(_ pane: SettingsPane) {
        guard pane != currentPane else { return }
        history.removeSubrange((position + 1)..<history.endIndex)
        history.append(pane)
        position = history.count - 1
    }

    /// Moves through visited panes without adding a history entry.
    /// - Parameter offset: One step backward or forward from the displayed pane.
    private func step(by offset: Int) {
        // Reveal the destination in the sidebar if it falls outside the search.
        let destination = position + offset
        guard history.indices.contains(destination) else { return }
        if !matchingPanes.contains(history[destination]) { search = "" }
        position = destination
    }

    /// Creates the detail view for the selected pane.
    /// - Parameter pane: The active settings sidebar item.
    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralSettingsTab()
        case .pasting: PastingSettingsTab()
        case .privacy: PrivacySettingsTab()
        case .appearance: AppearanceSettingsTab()
        case .shortcuts: ShortcutSettingsTab()
        case .about: AboutTab()
        }
    }
}
