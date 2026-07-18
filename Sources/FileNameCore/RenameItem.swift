import Foundation

/// One PDF in the queue: where it lives, what we think it should be called,
/// and how far along it is.
public struct RenameItem: Identifiable, Equatable {
    public enum Status: Equatable {
        case queued
        case analyzing
        case ready
        case renamed
        case reverted
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .queued, .analyzing: return true
            default: return false
            }
        }

        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    /// What was in flight when a `.failed` status was set, so Retry can
    /// repeat the operation that actually failed instead of guessing.
    public enum FailedOperation: Equatable {
        case analysis
        case rename
        case revert
    }

    public let id = UUID()

    /// Where the file was when it was dropped in.
    public var originalURL: URL

    /// Where the file is right now (changes after a rename).
    public var currentURL: URL

    /// The name the analyzer proposed (without extension).
    public var suggestedBase: String?

    /// The name currently in the text field (user-editable, without extension).
    public var editedBase: String = ""

    /// Short blurb about how the name was produced ("Claude", "OCR", fallbacks…).
    public var engineNote: String?

    public var status: Status = .queued

    /// Set alongside `.failed` so Retry knows what to redo.
    public var failedOperation: FailedOperation?

    /// Identifies the analysis run allowed to write results back, so a stale
    /// task from an earlier "Analyze Again" can't clobber newer state.
    public var analysisToken: UUID?

    public init(url: URL) {
        self.originalURL = url
        self.currentURL = url
    }

    var originalName: String { originalURL.lastPathComponent }
    var currentName: String { currentURL.lastPathComponent }
    var currentBase: String { currentURL.deletingPathExtension().lastPathComponent }

    /// True when the file on disk currently carries a name other than the one
    /// it was dropped in with — i.e. there is something to revert.
    var isRenamedOnDisk: Bool {
        currentURL.standardizedFileURL.path != originalURL.standardizedFileURL.path
    }

    var statusLabel: String {
        switch status {
        case .queued: return "Waiting…"
        case .analyzing: return "Reading PDF…"
        case .ready: return "Ready to rename"
        case .renamed: return "Renamed"
        case .reverted: return "Reverted to the original name"
        case .failed(let message): return message
        }
    }
}
