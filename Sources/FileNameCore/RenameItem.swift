import Foundation

/// One PDF in the queue: where it lives, what we think it should be called,
/// and how far along it is.
public struct RenameItem: Identifiable, Equatable {
    public enum Status: Equatable {
        case queued
        case analyzing
        case ready
        case renamed
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .queued, .analyzing: return true
            default: return false
            }
        }
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

    public init(url: URL) {
        self.originalURL = url
        self.currentURL = url
    }

    var originalName: String { originalURL.lastPathComponent }
    var currentName: String { currentURL.lastPathComponent }
    var currentBase: String { currentURL.deletingPathExtension().lastPathComponent }

    var statusLabel: String {
        switch status {
        case .queued: return "Waiting…"
        case .analyzing: return "Reading PDF…"
        case .ready: return "Ready to rename"
        case .renamed: return "Renamed"
        case .failed(let message): return message
        }
    }
}
