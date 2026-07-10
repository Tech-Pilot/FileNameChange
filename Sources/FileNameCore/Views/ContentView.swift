import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

public extension Notification.Name {
    /// Posted by the File ▸ Add PDFs… menu item; the main window reacts by
    /// opening the file picker.
    static let fileNameChangeOpenImporter = Notification.Name("FileNameChangeOpenImporter")
}

public struct ContentView: View {
    @EnvironmentObject private var queue: RenameQueue
    @AppStorage(PrefKey.engine) private var engine: NamingEngineKind = .builtin
    @State private var isTargeted = false
    @State private var showImporter = false

    public init() {}

    public var body: some View {
        Group {
            if queue.items.isEmpty {
                emptyState
            } else {
                listView
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .overlay { dropOverlay }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                queue.add(urls: urls)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fileNameChangeOpenImporter)) { _ in
            showImporter = true
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showImporter = true
                } label: {
                    Label("Add PDFs", systemImage: "plus")
                }
                .help("Add PDFs (⌘O)")

                Button {
                    queue.renameAllReady()
                } label: {
                    Label("Rename All", systemImage: "wand.and.stars")
                }
                .disabled(queue.readyCount == 0)
                .help("Rename every file that's ready")

                Button {
                    queue.clearFinished()
                } label: {
                    Label("Clear Renamed", systemImage: "checkmark.circle")
                }
                .disabled(queue.renamedCount == 0)
                .help("Remove renamed files from the list")
            }
        }
        .navigationTitle("FileNameChange")
    }

    // MARK: - Pieces

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(Color.accentColor)
            Text("Drop PDFs here")
                .font(.title2.weight(.semibold))
            Text("Each file gets read, understood, and renamed\nto what the document is actually about.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose PDFs…") {
                showImporter = true
            }
            .keyboardShortcut("o", modifiers: .command)
            Text("Naming engine: \(engine.displayName) — change it in Settings (⌘,)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                )
                .padding(18)
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            List {
                ForEach($queue.items) { $item in
                    ItemRow(item: $item)
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if queue.readyCount > 0 {
                    Button("Rename All (\(queue.readyCount))") {
                        queue.renameAllReady()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(10)
        }
    }

    private var summaryText: String {
        var parts = ["\(queue.items.count) PDF\(queue.items.count == 1 ? "" : "s")"]
        if queue.readyCount > 0 { parts.append("\(queue.readyCount) ready") }
        if queue.renamedCount > 0 { parts.append("\(queue.renamedCount) renamed") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if isTargeted {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.08))
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 42))
                    Text("Drop to add")
                        .font(.title3.bold())
                }
                .foregroundStyle(Color.accentColor)
            }
            .padding(8)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let queue = self.queue
        var accepted = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                }
                guard let url else { return }
                Task { @MainActor in
                    queue.add(urls: [url])
                }
            }
        }
        return accepted
    }
}
