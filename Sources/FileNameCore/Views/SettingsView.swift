import SwiftUI

public struct SettingsView: View {
    @AppStorage(PrefKey.engine) private var engine: NamingEngineKind = .builtin
    @AppStorage(PrefKey.includeDate) private var includeDate = true
    @AppStorage(PrefKey.caseStyle) private var caseStyle: CaseStyle = .asIs
    @AppStorage(PrefKey.separator) private var separator: SeparatorStyle = .spaces
    @AppStorage(PrefKey.autoRename) private var autoRename = false
    @AppStorage(PrefKey.claudeModel) private var claudeModel = PrefKey.defaultClaudeModel

    @State private var apiKey: String = KeychainStore.loadAPIKey()
    @State private var verifyResult: String?
    @State private var isVerifying = false

    public init() {}

    public var body: some View {
        Form {
            Section {
                Picker("Naming engine", selection: $engine) {
                    ForEach(NamingEngineKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.radioGroup)

                switch engine {
                case .builtin:
                    Text("Reads titles, document types, companies, and dates straight out of the PDF. Works offline, nothing ever leaves your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .apple:
                    if let reason = AppleIntelligenceNamer.unavailabilityReason {
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Until then, files fall back to the built-in analysis.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Uses the on-device Apple Intelligence model. Private and free — nothing leaves your Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .claude:
                    claudeSettings
                }
            } header: {
                Text("How names are chosen")
            }

            Section {
                Toggle("Start transactional documents with their date (2026-05-12 Acme Invoice)", isOn: $includeDate)
                Picker("Capitalization", selection: $caseStyle) {
                    ForEach(CaseStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Picker("Word separator", selection: $separator) {
                    ForEach(SeparatorStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            } header: {
                Text("Name format")
            }

            Section {
                Toggle("Rename automatically as soon as a name is ready", isOn: $autoRename)
                Text("Off means you get to review and edit every name first. Files can always be reverted from the list either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Behavior")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 460)
    }

    @ViewBuilder
    private var claudeSettings: some View {
        SecureField("API key (sk-ant-…)", text: $apiKey)
            .textFieldStyle(.roundedBorder)
            .onChange(of: apiKey) { newValue in
                KeychainStore.saveAPIKey(newValue)
                verifyResult = nil
            }

        TextField("Model", text: $claudeModel)
            .textFieldStyle(.roundedBorder)

        HStack(spacing: 10) {
            Button(isVerifying ? "Verifying…" : "Verify Key") {
                isVerifying = true
                verifyResult = nil
                let key = apiKey
                let model = claudeModel
                Task { @MainActor in
                    do {
                        try await ClaudeNamer.verify(apiKey: key, model: model)
                        verifyResult = "✓ Key works"
                    } catch {
                        verifyResult = (error as? NamingError)?.errorDescription ?? error.localizedDescription
                    }
                    isVerifying = false
                }
            }
            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isVerifying)

            if let verifyResult {
                Text(verifyResult)
                    .font(.caption)
                    .foregroundStyle(verifyResult.hasPrefix("✓") ? Color.green : Color.red)
            }
        }

        Text("The key is stored in your macOS Keychain. Only the first pages of each PDF are sent to the API — swap in claude-haiku-4-5-20251001 for the fastest, cheapest naming.")
            .font(.caption)
            .foregroundStyle(.secondary)
        Link("Get an API key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/")!)
            .font(.caption)
    }
}
