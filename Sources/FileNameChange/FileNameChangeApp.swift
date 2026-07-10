import SwiftUI
import AppKit
import FileNameCore

/// Handles PDFs dropped on the Dock icon / opened via "Open With".
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            RenameQueue.shared.add(urls: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct FileNameChangeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var queue = RenameQueue.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(queue)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add PDFs…") {
                    NotificationCenter.default.post(name: .fileNameChangeOpenImporter, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
