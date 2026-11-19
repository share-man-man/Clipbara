import AppKit
import SwiftData
import SwiftUI

/// The panel and Settings clear the same set of clips and present the same confirmation.
@MainActor
struct ClearHistoryConfirmation: ViewModifier {
    /// The exact clips counted when the user requested the operation.
    @Binding var selectedIDs: Set<UUID>
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    /// Presents the request until the user confirms or cancels it.
    /// - Parameter content: The view that initiated the clear.
    func body(content: Content) -> some View {
        content.alert("Clear Clipboard History?", isPresented: Binding(
            get: { !selectedIDs.isEmpty },
            set: { if !$0 { selectedIDs.removeAll() } }
        ), presenting: selectedIDs) { ids in
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) {
                do {
                    try HistoryRetention.clear(ids, in: modelContext)
                    appState.clipboardMonitor.refreshLatestItems()
                } catch {
                    NSApp.presentError(error)
                }
            }
        } message: { ids in
            Text("This deletes \(ids.count) unpinned clips from history. Pinboard items stay available.")
        }
    }
}
