import SwiftUI
import KeyboardShortcuts

struct ShortcutSettingsTab: View {
    /// Whether starting the Clip Queue with its shortcut copies the selection.
    @AppStorage(SelectionCopy.enabledDefaultsKey) private var copiesSelection = SelectionCopy.enabledByDefault

    var body: some View {
        Form {
            HStack {
                Text("Toggle History Panel")
                InfoHoverButton(text: "Combine at least one of \u{2318}, \u{2325} or \u{2303} with a key, like \u{2325}V or \u{2303}\u{21e7}P. Function keys (F1\u{2013}F12) work on their own. Shift alone isn't supported by macOS.")
                Spacer()
                KeyboardShortcuts.Recorder(for: .toggleHistoryPanel)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("Start or End Clip Queue")
                        InfoHoverButton(text: "While the queue is on, everything you copy joins it, and each \u{2318}V pastes the next item in order.")
                    }
                    Text("Not set by default. Also available from the menu bar.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                KeyboardShortcuts.Recorder(for: .toggleClipQueue)
            }
            if SelectionCopy.isAvailable {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Copy Selection When Starting")
                        Text("Starting the queue with its shortcut presses \u{2318}C for you, so what's selected becomes the first item. Needs Accessibility permission.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $copiesSelection)
                        .labelsHidden()
                }
                .onChange(of: copiesSelection) { _, isOn in
                    if isOn, !DirectPaste.hasPermission {
                        DirectPaste.requestPermission()
                    }
                }
            }
            HStack {
                Text("Clear All History")
                Spacer()
                KeyboardShortcuts.Recorder(for: .clearHistory)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("Quick Look Preview")
                        InfoHoverButton(text: "A single key with no modifiers. It only works while the Clipbara panel is open, so it won't clash with other apps.")
                    }
                    Text("Pressed inside the panel with a card selected.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                LocalKeyRecorderView()
            }
            Section("Tab Navigation") {
                LabeledContent("History", value: "⌘1")
                LabeledContent("First 8 Pinboards", value: "⌘2–⌘9")
                Text("Fixed shortcuts in tab order. Only active while the history panel is open, including while searching.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
