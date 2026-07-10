import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The app's one source of truth: the list of dropped PDFs and everything
/// that happens to them (analysis, renaming, reverting).
@MainActor
public final class RenameQueue: ObservableObject {
    public static let shared = RenameQueue()

    @Published var items: [RenameItem] = []

    public init() {}

    var readyCount: Int {
        items.filter { $0.status == .ready }.count
    }

    var renamedCount: Int {
        items.filter { $0.status == .renamed }.count
    }

    // MARK: - Adding files

    /// Accepts anything dropped or picked: PDFs directly, folders searched
    /// shallow-to-deep for PDFs (capped so a dropped home folder can't hang us).
    public func add(urls: [URL]) {
        let pdfs = Self.collectPDFs(from: urls)
        for url in pdfs {
            let standardized = url.standardizedFileURL
            guard !items.contains(where: {
                $0.currentURL.path == standardized.path || $0.originalURL.path == standardized.path
            }) else { continue }

            let item = RenameItem(url: standardized)
            items.append(item)
            analyze(itemID: item.id)
        }
    }

    nonisolated static func collectPDFs(from urls: [URL], cap: Int = 300) -> [URL] {
        var found: [URL] = []
        let fileManager = FileManager.default

        for url in urls {
            guard found.count < cap else { break }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: nil
                )
                while let entry = enumerator?.nextObject() as? URL {
                    guard found.count < cap else { break }
                    if entry.pathExtension.lowercased() == "pdf" {
                        found.append(entry)
                    }
                }
            } else if url.pathExtension.lowercased() == "pdf" {
                found.append(url)
            }
        }
        return found
    }

    // MARK: - Analysis

    func analyze(itemID: UUID) {
        guard let index = index(of: itemID) else { return }
        items[index].status = .analyzing
        items[index].engineNote = nil

        let url = items[index].currentURL

        Task { [weak self] in
            do {
                let extraction = try await PDFContentExtractor.extract(url: url)
                let prefs = Preferences.load()
                let result = await NamingEngine.suggest(for: extraction, prefs: prefs)

                guard let self, let currentIndex = self.index(of: itemID) else { return }
                self.items[currentIndex].suggestedBase = result.base
                self.items[currentIndex].editedBase = result.base
                self.items[currentIndex].engineNote = result.note
                self.items[currentIndex].status = .ready

                if prefs.autoRename {
                    self.applyRename(itemID: itemID)
                }
            } catch {
                guard let self, let currentIndex = self.index(of: itemID) else { return }
                self.items[currentIndex].status = .failed(Self.friendlyMessage(for: error))
            }
        }
    }

    // MARK: - Renaming

    func applyRename(itemID: UUID) {
        guard let index = index(of: itemID) else { return }
        let item = items[index]
        guard item.status == .ready || isApplyFailure(item.status) else { return }

        let base = FilenameSanitizer.sanitize(item.editedBase)
        guard !base.isEmpty else {
            items[index].engineNote = "Type a name first."
            return
        }

        if base == item.currentBase {
            items[index].status = .renamed
            items[index].engineNote = "Already had this name."
            return
        }

        let directory = item.currentURL.deletingLastPathComponent()
        let pathExtension = item.currentURL.pathExtension.isEmpty ? "pdf" : item.currentURL.pathExtension

        do {
            let destination = try FilenameSanitizer.availableURL(in: directory, base: base, pathExtension: pathExtension)
            try FileManager.default.moveItem(at: item.currentURL, to: destination)
            items[index].currentURL = destination
            items[index].status = .renamed
        } catch {
            items[index].status = .failed(Self.friendlyMessage(for: error))
        }
    }

    func renameAllReady() {
        for item in items where item.status == .ready {
            applyRename(itemID: item.id)
        }
    }

    func revert(itemID: UUID) {
        guard let index = index(of: itemID), items[index].status == .renamed else { return }
        let item = items[index]
        let directory = item.originalURL.deletingLastPathComponent()
        let base = item.originalURL.deletingPathExtension().lastPathComponent
        let pathExtension = item.originalURL.pathExtension.isEmpty ? "pdf" : item.originalURL.pathExtension

        do {
            let destination = try FilenameSanitizer.availableURL(in: directory, base: base, pathExtension: pathExtension)
            try FileManager.default.moveItem(at: item.currentURL, to: destination)
            items[index].currentURL = destination
            items[index].status = .ready
            items[index].engineNote = "Reverted to the original name."
        } catch {
            items[index].status = .failed(Self.friendlyMessage(for: error))
        }
    }

    /// Retry after a failure: re-apply if we already have a suggestion,
    /// otherwise analyze from scratch.
    func retry(itemID: UUID) {
        guard let index = index(of: itemID) else { return }
        if items[index].suggestedBase != nil {
            items[index].status = .ready
            applyRename(itemID: itemID)
        } else {
            analyze(itemID: itemID)
        }
    }

    func remove(itemID: UUID) {
        items.removeAll { $0.id == itemID }
    }

    func clearFinished() {
        items.removeAll { $0.status == .renamed }
    }

    // MARK: - Helpers

    private func index(of itemID: UUID) -> Int? {
        items.firstIndex { $0.id == itemID }
    }

    private func isApplyFailure(_ status: RenameItem.Status) -> Bool {
        if case .failed = status { return true }
        return false
    }

    nonisolated static func friendlyMessage(for error: Error) -> String {
        if let cocoaError = error as? CocoaError,
           cocoaError.code == .fileWriteNoPermission || cocoaError.code == .fileReadNoPermission {
            return "No permission to change this file. Allow access in System Settings → Privacy & Security → Files and Folders."
        }
        return error.localizedDescription
    }
}
