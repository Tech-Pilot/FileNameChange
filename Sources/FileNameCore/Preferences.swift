import Foundation
import Security

/// Which engine turns extracted PDF text into a file name.
public enum NamingEngineKind: String, CaseIterable, Identifiable {
    case builtin
    case apple
    case claude

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .builtin: return "Built-in analysis (offline)"
        case .apple: return "Apple Intelligence (on-device)"
        case .claude: return "Claude API (cloud)"
        }
    }
}

public enum CaseStyle: String, CaseIterable, Identifiable {
    case asIs
    case titleCase
    case lowercase

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .asIs: return "Keep as suggested"
        case .titleCase: return "Title Case"
        case .lowercase: return "lowercase"
        }
    }
}

public enum SeparatorStyle: String, CaseIterable, Identifiable {
    case spaces
    case hyphens
    case underscores

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .spaces: return "Spaces"
        case .hyphens: return "Hyphens-between-words"
        case .underscores: return "Underscores_between_words"
        }
    }
}

/// UserDefaults keys, shared between the Settings UI and the services.
public enum PrefKey {
    public static let engine = "namingEngine"
    public static let includeDate = "includeDateInName"
    public static let caseStyle = "nameCaseStyle"
    public static let separator = "nameSeparatorStyle"
    public static let autoRename = "autoRenameWhenReady"
    public static let claudeModel = "claudeModel"

    public static let defaultClaudeModel = "claude-sonnet-5"
}

/// A snapshot of the user's settings, read once per analysis.
public struct Preferences {
    public var engine: NamingEngineKind
    public var includeDate: Bool
    public var caseStyle: CaseStyle
    public var separator: SeparatorStyle
    public var autoRename: Bool
    public var claudeModel: String

    public static func load() -> Preferences {
        let defaults = UserDefaults.standard
        let engine = NamingEngineKind(rawValue: defaults.string(forKey: PrefKey.engine) ?? "") ?? .builtin
        let caseStyle = CaseStyle(rawValue: defaults.string(forKey: PrefKey.caseStyle) ?? "") ?? .asIs
        let separator = SeparatorStyle(rawValue: defaults.string(forKey: PrefKey.separator) ?? "") ?? .spaces
        let includeDate = defaults.object(forKey: PrefKey.includeDate) == nil
            ? true
            : defaults.bool(forKey: PrefKey.includeDate)
        let model = defaults.string(forKey: PrefKey.claudeModel) ?? PrefKey.defaultClaudeModel
        return Preferences(
            engine: engine,
            includeDate: includeDate,
            caseStyle: caseStyle,
            separator: separator,
            autoRename: defaults.bool(forKey: PrefKey.autoRename),
            claudeModel: model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public init(
        engine: NamingEngineKind = .builtin,
        includeDate: Bool = true,
        caseStyle: CaseStyle = .asIs,
        separator: SeparatorStyle = .spaces,
        autoRename: Bool = false,
        claudeModel: String = PrefKey.defaultClaudeModel
    ) {
        self.engine = engine
        self.includeDate = includeDate
        self.caseStyle = caseStyle
        self.separator = separator
        self.autoRename = autoRename
        self.claudeModel = claudeModel
    }
}

/// Minimal Keychain wrapper for the Claude API key, so it never sits in
/// plain-text preferences.
public enum KeychainStore {
    private static let service = "FileNameChange"
    private static let account = "AnthropicAPIKey"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public static func loadAPIKey() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return ""
        }
        return key
    }

    public static func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            SecItemDelete(baseQuery as CFDictionary)
            return
        }
        let data = Data(trimmed.utf8)

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
