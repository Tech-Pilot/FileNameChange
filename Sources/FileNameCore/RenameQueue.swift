import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The app's one source of truth: the list of dropped PDFs and everything
/// that happens to them (analysis, renaming, reverting).
@MainActor
public final class RenameQueue: ObservableObject {
    public static let shared = RenameQueue()

    @Published var items: [RenameItem] = []

    /// PDF parsing and OCR are heavy; a bounded pool keeps a 300-file drop
    /// from saturating every core (and from bursting the Claude API).
    static let maxConcurrentAnalyses = 4

    private var pendingAnalysis: [UUID] = []
    private var runningAnalyses = 0
    private var analysisTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    var readyCount: Int {
        items.filter { $0.status == .ready }.count
    }

    var renamedCount: Int {
        items.filter { $0.status == .renamed }.count
    }

    /// Items "Clear Renamed" would remove: renamed or deliberately reverted.
    var finishedCount: Int {
        items.filter { $0.status == .renamed || $0.status == .reverted }.count
    }

    // MARK: - Adding files

    /// Accepts anything dropped or picked: PDFs directly, folders searched
    /// for PDFs. The directory walk runs off the main thread so a huge
    /// dropped folder can't freeze the UI.
    public func add(urls: [URL]) {
        Task { [weak self] in
            let pdfs = await Task.detached(priority: .userInitiated) {
                Self.collectPDFs(from: urls)
            }.value
            self?.append(collected: pdfs)
        }
    }

    private func append(collected pdfs: [URL]) {
        for url in pdfs {
            let standardized = url.standardizedFileURL
            // Dedupe on where files are NOW — a renamed item's old path is
            // vacant again, and a new file there is a genuinely new file.
            guard !items.contains(where: { $0.currentURL.path == standardized.path }) else { continue }

            let item = RenameItem(url: standardized)
            items.append(item)
            analyze(itemID: item.id)
        }
    }

    nonisolated static func collectPDFs(from urls: [URL], cap: Int = 300, entryCap: Int = 50_000) -> [URL] {
        var found: [URL] = []
        var visited = 0
        let fileManager = FileManager.default

        for url in urls {
            guard found.count < cap, visited < entryCap else { break }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: nil
                )
                while let entry = enumerator?.nextObject() as? URL {
                    visited += 1
                    guard found.count < cap, visited < entryCap else { break }
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
        guard items[index].status != .analyzing, !pendingAnalysis.contains(itemID) else { return }
        items[index].status = .queued
        items[index].engineNote = nil
        pendingAnalysis.append(itemID)
        pumpAnalysisQueue()
    }

    private func pumpAnalysisQueue() {
        while runningAnalyses < Self.maxConcurrentAnalyses, !pendingAnalysis.isEmpty {
            let itemID = pendingAnalysis.removeFirst()
            guard let index = index(of: itemID) else { continue }
            startAnalysis(itemID: itemID, index: index)
        }
    }

    private func startAnalysis(itemID: UUID, index: Int) {
        let token = UUID()
        items[index].status = .analyzing
        items[index].analysisToken = token
        let url = items[index].currentURL
        runningAnalyses += 1

        analysisTasks[itemID] = Task { [weak self] in
            do {
                let extraction = try await PDFContentExtractor.extract(url: url)
                guard !Task.isCancelled else {
                    self?.finishAnalysis(itemID: itemID)
                    return
                }
                let prefs = Preferences.load()
                let result = await NamingEngine.suggest(for: extraction, prefs: prefs)
                self?.completeAnalysis(itemID: itemID, token: token, outcome: .success((result, prefs.autoRename)))
            } catch {
                self?.completeAnalysis(itemID: itemID, token: token, outcome: .failure(error))
            }
        }
    }

    private func completeAnalysis(
        itemID: UUID,
        token: UUID,
        outcome: Swift.Result<(NamingEngine.Result, Bool), Error>
    ) {
        finishAnalysis(itemID: itemID)

        // Only the newest analysis run for a still-present item may write back.
        guard !Task.isCancelled,
              let index = index(of: itemID),
              items[index].analysisToken == token else { return }

        switch outcome {
        case .success(let (result, autoRename)):
            items[index].suggestedBase = result.base
            items[index].editedBase = result.base
            items[index].engineNote = result.note
            items[index].status = .ready
            if autoRename {
                applyRename(itemID: itemID)
            }
        case .failure(let error):
            items[index].status = .failed(Self.friendlyMessage(for: error))
            items[index].failedOperation = .analysis
        }
    }

    private func finishAnalysis(itemID: UUID) {
        runningAnalyses -= 1
        analysisTasks[itemID] = nil
        pumpAnalysisQueue()
    }

    // MARK: - Renaming

    func applyRename(itemID: UUID) {
        guard let index = index(of: itemID) else { return }
        let item = items[index]
        guard item.status == .ready || item.status == .reverted || item.status.isFailed else { return }

        // Pasting a full file name shouldn't yield "Name.pdf.pdf".
        let base = FilenameSanitizer.sanitize(FilenameSanitizer.strippingPDFExtension(item.editedBase))
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
            let destination = try FilenameSanitizer.availableURL(
                in: directory,
                base: base,
                pathExtension: pathExtension,
                movingFrom: item.currentURL
            )
            try FileManager.default.moveItem(at: item.currentURL, to: destination)
            items[index].currentURL = destination
            // Keep the visible name in sync with what actually landed on disk
            // (collision handling may have appended " 2").
            items[index].editedBase = destination.deletingPathExtension().lastPathComponent
            items[index].status = .renamed
        } catch {
            items[index].status = .failed(Self.friendlyMessage(for: error))
            items[index].failedOperation = .rename
        }
    }

    func renameAllReady() {
        for item in items where item.status == .ready {
            applyRename(itemID: item.id)
        }
    }

    func revert(itemID: UUID) {
        guard let index = index(of: itemID), !items[index].status.isBusy else { return }
        let item = items[index]

        // Nothing to undo (e.g. the "Already had this name" path never moved
        // the file) — don't touch the disk, just record the state.
        guard item.isRenamedOnDisk else {
            items[index].status = .reverted
            items[index].engineNote = "The file already has its original name."
            return
        }

        let directory = item.originalURL.deletingLastPathComponent()
        let base = item.originalURL.deletingPathExtension().lastPathComponent
        let pathExtension = item.originalURL.pathExtension.isEmpty ? "pdf" : item.originalURL.pathExtension

        do {
            let destination = try FilenameSanitizer.availableURL(
                in: directory,
                base: base,
                pathExtension: pathExtension,
                movingFrom: item.currentURL
            )
            try FileManager.default.moveItem(at: item.currentURL, to: destination)
            items[index].currentURL = destination
            items[index].status = .reverted
            items[index].engineNote = "Reverted to the original name."
        } catch {
            items[index].status = .failed(Self.friendlyMessage(for: error))
            items[index].failedOperation = .revert
        }
    }

    /// Retry repeats the operation that actually failed.
    func retry(itemID: UUID) {
        guard let index = index(of: itemID), items[index].status.isFailed else { return }
        switch items[index].failedOperation {
        case .rename:
            applyRename(itemID: itemID)
        case .revert:
            revert(itemID: itemID)
        case .analysis, nil:
            analyze(itemID: itemID)
        }
    }

    func remove(itemID: UUID) {
        analysisTasks[itemID]?.cancel()
        pendingAnalysis.removeAll { $0 == itemID }
        items.removeAll { $0.id == itemID }
    }

    func clearFinished() {
        items.removeAll { $0.status == .renamed || $0.status == .reverted }
    }

    // MARK: - Helpers

    private func index(of itemID: UUID) -> Int? {
        items.firstIndex { $0.id == itemID }
    }

    nonisolated static func friendlyMessage(for error: Error) -> String {
        if let cocoaError = error as? CocoaError,
           cocoaError.code == .fileWriteNoPermission || cocoaError.code == .fileReadNoPermission {
            return "No permission to change this file. Allow access in System Settings → Privacy & Security → Files and Folders."
        }
        return error.localizedDescription
    }
}
