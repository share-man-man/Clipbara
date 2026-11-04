import SwiftUI

struct ClipQueueView: View {
    let queue: ClipQueue

    @Environment(\.colorScheme) private var colorScheme

    /// Sizes of the queue window's content.
    private typealias Tokens = DesignTokens.ClipQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.6)
            // The list also shows what was pasted, so it stays while that is left.
            if queue.list.isEmpty && queue.list.pasted.isEmpty {
                emptyState
            } else {
                list
            }
        }
        // Fills the window, whose size the user sets; the list scrolls when
        // there are more rows than fit.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            VisualEffectBackground(material: colorScheme == .dark ? .hudWindow : .popover)
        )
        // No rounded clip or border here: the window draws its own.
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 7) {
            title
            Spacer(minLength: 4)
            headerButton(
                systemImage: queue.pastesNewestFirst ? "arrow.up" : "arrow.down",
                help: queue.pastesNewestFirst
                    ? String(localized: "Pasting newest first. Click to paste oldest first.")
                    : String(localized: "Pasting oldest first. Click to paste newest first.")
            ) {
                queue.pastesNewestFirst.toggle()
            }
            headerButton(systemImage: "xmark", help: String(localized: "End Clip Queue")) {
                queue.stop()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Tokens.headerHeight)
    }

    /// The icon, title and count.
    private var title: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Clip Queue")
                .font(.system(size: 13, weight: .semibold))
            if !queue.list.isEmpty {
                Text(verbatim: "\(queue.list.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
    }

    private func headerButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: Tokens.headerButtonSize, height: Tokens.headerButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    // MARK: - Content

    /// Shown before anything is copied, in the middle of the window.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Copy a few things. Each \u{2318}V then pastes the next one in order.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The queue in paste order, then, below a line, the clips pasted most recently.
    private var list: some View {
        let entries = queue.list.pasteOrder
        return List {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                row(entry: entry, isNext: index == 0)
            }
            // AppKit's own table reordering: drag a row, drop it between two others.
            .onMove { source, destination in
                move(from: source, to: destination, in: entries)
            }
            // Below a line, the clips pasted most recently, dimmed.
            if !queue.list.pasted.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                    .listRowSeparator(.hidden)
                ForEach(queue.list.pasted) { entry in
                    pastedRow(entry: entry)
                }
            }
        }
        // Lets the line row be only as tall as the line, not a full row.
        .environment(\.defaultMinListRowHeight, 0)
        // The system's standard list: it lays out the rows, the drop line and
        // the scroll bar together. Rows add no background or insets of their
        // own, so nothing has to be lined up with what the system draws.
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        // The table drag alone doesn't scroll the list when a row nears its edge.
        .autoScrollsWhileDragging()
    }

    /// A queue row: what the clip is, and a button that takes it out of the queue.
    /// - Parameters:
    ///   - entry: the queue entry shown
    ///   - isNext: whether the next ⌘V pastes it
    private func row(entry: ClipQueueList<ClipboardItem>.Entry, isNext: Bool) -> some View {
        let item = entry.item
        return HStack(spacing: 8) {
            // The next item to paste is marked in the row itself: its icon in
            // the accent color and its text in bold.
            leadingIcon(for: item, tint: isNext ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(verbatim: preview(of: item))
                .font(.system(size: 12, weight: isNext ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            removeButton(for: entry.id)
        }
        .frame(height: Tokens.rowContentHeight)
        // The whole clip, for one cut short in the row or that starts like another.
        .help(Text(verbatim: tooltip(for: item)))
        .listRowSeparator(.hidden)
        // Dragged out of the window, the row carries the clip's text to another app.
        .itemProvider {
            item.textContent.map { NSItemProvider(object: $0 as NSString) }
        }
    }

    /// A row for a clip already pasted. Clicking it puts the clip back in the
    /// queue as the next one to paste.
    /// - Parameter entry: the pasted entry shown
    private func pastedRow(entry: ClipQueueList<ClipboardItem>.Entry) -> some View {
        let item = entry.item
        return Button {
            withAnimation(Tokens.removeAnimation) {
                queue.restore(id: entry.id)
            }
        } label: {
            HStack(spacing: 8) {
                leadingIcon(for: item, tint: AnyShapeStyle(.tertiary))
                    .opacity(0.6)
                Text(verbatim: preview(of: item))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: Tokens.removeButtonSize, height: Tokens.removeButtonSize)
            }
            .frame(height: Tokens.rowContentHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Paste Again Next"))
        .listRowSeparator(.hidden)
    }

    /// The start of a row: an image's thumbnail, or the clip type's icon.
    /// - Parameters:
    ///   - item: the clip in the row
    ///   - tint: color of the type icon
    @ViewBuilder
    private func leadingIcon(for item: ClipboardItem, tint: AnyShapeStyle) -> some View {
        if item.contentType == .image, let image = ThumbnailImageCache.image(for: item) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Tokens.leadingColumnWidth, height: Tokens.thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.thumbnailCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.thumbnailCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        } else {
            Image(systemName: item.contentType.systemImage)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: Tokens.leadingColumnWidth)
        }
    }

    /// Applies a reorder from the list, which reports it as offsets.
    /// - Parameters:
    ///   - source: the dragged row's slot, in paste order
    ///   - destination: the slot it was dropped before, counted before the row is taken out
    ///   - entries: the rows in paste order when the drag began
    private func move(from source: IndexSet, to destination: Int, in entries: [ClipQueueList<ClipboardItem>.Entry]) {
        guard let from = source.first, entries.indices.contains(from) else { return }
        /// Where the row ends up once it is taken out of its old slot.
        let to = destination > from ? destination - 1 : destination
        guard to != from, entries.indices.contains(to) else { return }
        queue.move(id: entries[from].id, to: entries[to].id)
    }

    /// The always-shown button that takes a row out of the queue.
    /// - Parameter id: the entry it removes
    private func removeButton(for id: UUID) -> some View {
        Button {
            withAnimation(Tokens.removeAnimation) {
                queue.remove(id: id)
            }
        } label: {
            // Not an ✕: that is the header's End Clip Queue button.
            Image(systemName: "minus.circle")
                .font(.system(size: 12))
                .frame(width: Tokens.removeButtonSize, height: Tokens.removeButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(String(localized: "Remove from Queue"))
    }

    /// One line for the row: the clip's title, its first line of text, or its type.
    /// - Parameter item: the clip in the row
    private func preview(of item: ClipboardItem) -> String {
        if let title = item.userTitle, !title.isEmpty { return title }
        if let text = item.textContent?
            .split(whereSeparator: \.isNewline)
            .first?
            .trimmingCharacters(in: .whitespaces),
           !text.isEmpty {
            return text
        }
        return item.contentType.displayName
    }

    /// The row's tooltip: the clip's whole text, cut at `Tokens.tooltipCharacterLimit`,
    /// or its type when it has no text.
    /// - Parameter item: the clip in the row
    private func tooltip(for item: ClipboardItem) -> String {
        guard let text = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return preview(of: item)
        }
        guard text.count > Tokens.tooltipCharacterLimit else { return text }
        return String(text.prefix(Tokens.tooltipCharacterLimit)) + "…"
    }
}
