import AppKit
import SwiftUI

@main
struct CodexAuthBarApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(model: model)
        } label: {
            Label("Codex Auth Bar", systemImage: model.hasError ? "person.crop.circle.badge.exclamationmark" : "person.crop.circle")
        }
        .menuBarExtraStyle(.window)

        Window("Codex Auth Bar", id: "accounts") {
            ManagementView(model: model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 860, height: 600)

        Settings {
            SettingsView(model: model)
                .frame(width: 520, height: 420)
        }
    }
}
