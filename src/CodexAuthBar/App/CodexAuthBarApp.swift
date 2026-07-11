import AppKit
import CodexAuthCore
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let action = UNNotificationAction(
            identifier: AppModel.autoSwitchNotificationAction,
            title: "Switch & Restart",
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: AppModel.autoSwitchNotificationCategory,
                actions: [action],
                intentIdentifiers: []
            ),
        ])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let rawKey = response.notification.request.content.userInfo["targetAccountKey"] as? String
        Task { [weak self] in
            defer { completionHandler() }
            guard response.actionIdentifier == AppModel.autoSwitchNotificationAction,
                  let rawKey,
                  let model = self?.model
            else { return }
            await model.switchAccount(AccountKey(rawKey))
        }
    }
}

@main
struct CodexAuthBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(model: model)
        } label: {
            Label("Codex Auth Bar", systemImage: model.hasError ? "person.crop.circle.badge.exclamationmark" : "person.crop.circle")
                .accessibilityLabel("Codex Auth Bar")
                .accessibilityIdentifier("CodexAuthBar.statusItem")
                .task { appDelegate.model = model }
        }
        .menuBarExtraStyle(.window)

        Window("Codex Auth Bar", id: "accounts") {
            ManagementView(model: model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 860, height: 600)

        Window("Codex Diagnostics", id: "diagnostics") {
            DiagnosticsView(model: model)
                .frame(minWidth: 720, minHeight: 440)
        }
        .defaultSize(width: 820, height: 560)

        Settings {
            SettingsView(model: model)
                .frame(width: 520, height: 420)
        }
    }
}
