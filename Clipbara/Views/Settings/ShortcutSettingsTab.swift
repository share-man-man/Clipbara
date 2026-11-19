import SwiftUI
import KeyboardShortcuts

@MainActor
struct ShortcutSettingsTab: View {
    /// Whether the queue shortcut collects the current selection as its first item.
    @AppStorage(SelectionCopy.enabledDefaultsKey) private var copiesSelection = SelectionCopy.enabledByDefault

    var body: some View {
        Form {
            Section {
                LabeledContent("Toggle History Panel") {
                    KeyboardShortcuts.Recorder(for: .toggleHistoryPanel)
                }
                LabeledContent {
                    KeyboardShortcuts.Recorder(for: .toggleClipQueue)
                } label: {
                    Text("Start or End Clip Queue")
                    Text("While the queue is on, everything you copy joins it, and each \u{2318}V pastes the next item in order.")
                }
                if SelectionCopy.isAvailable {
                    Toggle(isOn: $copiesSelection) {
                        Text("Copy Selection When Starting")
                        Text("Starting the queue with its shortcut presses \u{2318}C for you, so what's selected becomes the first item. Needs Accessibility permission.")
                    }
                    .onChange(of: copiesSelection) { _, isOn in
                        if isOn, !DirectPaste.hasPermission {
                            DirectPaste.requestPermission()
                        }
                    }
                }
                LabeledContent("Clear All History") {
                    KeyboardShortcuts.Recorder(for: .clearHistory)
                }
            } footer: {
                Text("Combine at least one of \u{2318}, \u{2325} or \u{2303} with a key, like \u{2325}V or \u{2303}\u{21e7}P. Function keys (F1\u{2013}F12) work on their own. Shift alone isn't supported by macOS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    LocalKeyRecorderView()
                } label: {
                    Text("Quick Look Preview")
                    Text("Pressed with a card selected. A single key, no modifiers.")
                }
                LabeledContent("History", value: "\u{2318}1")
                LabeledContent("First 8 Pinboards", value: "\u{2318}2\u{2013}\u{2318}9")
            } header: {
                Text("In the Panel")
            } footer: {
                Text("Fixed shortcuts in tab order. Only active while the history panel is open, including while searching.")
            }
        }
    }
}
