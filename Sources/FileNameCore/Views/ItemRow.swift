import SwiftUI
import AppKit

/// One row: original name, the editable suggested name, status, and actions.
struct ItemRow: View {
    @EnvironmentObject private var queue: RenameQueue
    @Binding var item: RenameItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.title2)
                .foregroundStyle(Color.red.opacity(0.85))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.status == .renamed ? item.originalName : item.currentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .strikethrough(item.status == .renamed && item.originalName != item.currentName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if item.suggestedBase != nil {
                    HStack(spacing: 4) {
                        TextField("New name", text: $item.editedBase)
                            .textFieldStyle(.roundedBorder)
                            .disabled(item.status == .renamed || item.status.isBusy)
                            .onSubmit {
                                queue.applyRename(itemID: item.id)
                            }
                        Text(".pdf")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(item.statusLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if case .failed(let message) = item.status {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else if let note = item.engineNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            statusControls

            Button {
                queue.remove(itemID: item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from list (doesn't touch the file)")
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.currentURL])
            }
            Button("Analyze Again") {
                queue.analyze(itemID: item.id)
            }
            Button("Copy Suggested Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.editedBase, forType: .string)
            }
            .disabled(item.suggestedBase == nil)
            Divider()
            Button("Remove from List") {
                queue.remove(itemID: item.id)
            }
        }
    }

    @ViewBuilder
    private var statusControls: some View {
        switch item.status {
        case .queued, .analyzing:
            ProgressView()
                .controlSize(.small)
        case .ready:
            Button("Rename") {
                queue.applyRename(itemID: item.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .renamed:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                    .help("Renamed to \(item.currentName)")
                Button("Revert") {
                    queue.revert(itemID: item.id)
                }
                .controlSize(.small)
            }
        case .failed:
            Button("Retry") {
                queue.retry(itemID: item.id)
            }
            .controlSize(.small)
        }
    }
}
