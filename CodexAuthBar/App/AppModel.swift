import AppKit
import CodexAuthCore
import Observation
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class AppModel {
    private(set) var accounts: [AccountRecord] = []
    private(set) var activeAccountKey: AccountKey?
    private(set) var previousAccountKey: AccountKey?
    private(set) var profiles: [ProfileName] = []
    var selectedProfile: ProfileName?
    var isLoading = false
    var statusMessage = ""
    var errorMessage: String?
    var searchText = ""

    let home: CodexHome
    private let repository: AccountRepository
    private let profileStore: ProfileStore
    private let usageService: ChatGPTUsageService
    private let processController: CodexProcessController
    private let codextManager = CodextManager()

    init() {
        let preference = UserDefaults.standard.string(forKey: "codexHome").map { URL(fileURLWithPath: $0, isDirectory: true) }
        home = CodexHome.resolve(preference: preference)
        repository = AccountRepository(home: home)
        profileStore = ProfileStore(home: home)
        usageService = ChatGPTUsageService(home: home)
        processController = CodexProcessController(home: home)
        if let raw = UserDefaults.standard.string(forKey: "selectedProfile") { selectedProfile = ProfileName(raw) }
        Task { await start() }
    }

    var activeAccount: AccountRecord? { accounts.first { $0.accountKey == activeAccountKey } }
    var hasError: Bool { errorMessage != nil }
    var filteredAccounts: [AccountRecord] {
        guard !searchText.isEmpty else { return accounts }
        return accounts.filter {
            [$0.alias, $0.email, $0.accountName ?? "", $0.accountKey.rawValue]
                .contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    func start() async {
        do { _ = try await RegistryStore(home: home).recoverPendingTransaction() } catch { errorMessage = "Recovery: \(error.localizedDescription)" }
        await reload()
        Task { await autoSwitchLoop() }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let state = try await repository.state(refresh: .stored)
            accounts = state.registry.accounts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            activeAccountKey = state.registry.activeAccountKey
            previousAccountKey = state.registry.previousActiveAccountKey
            profiles = try await profileStore.list()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func switchAccount(_ key: AccountKey, restart: Bool = true) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let wasRunning = await processController.isDesktopRunning()
            if restart, wasRunning { try await processController.terminateDesktopApp(timeout: .seconds(10)) }
            do {
                _ = try await repository.switchAccount(to: key)
            } catch {
                if restart, wasRunning { try? await processController.launchDesktopApp(CodexLaunchRequest(codexHome: home.root)) }
                throw error
            }
            if restart, wasRunning { try await processController.launchDesktopApp(CodexLaunchRequest(codexHome: home.root)) }
            statusMessage = restart && wasRunning ? "Switched and restarted Codex" : "Account switched"
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func switchPrevious() async {
        guard let previousAccountKey else { return }
        await switchAccount(previousAccountKey)
    }

    func refreshUsage(localOnly: Bool = false, activeOnly: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        let targets = activeOnly ? accounts.filter { $0.accountKey == activeAccountKey } : accounts
        if localOnly {
            do {
                if let activeAccountKey, let event = try LocalUsageScanner.newest(home: home, activatedAtMilliseconds: nil) {
                    try await repository.updateUsage(event.snapshot, for: activeAccountKey)
                }
            } catch { errorMessage = error.localizedDescription }
        } else {
            await withTaskGroup(of: (AccountKey, UsageFetchResult).self) { group in
                for account in targets { group.addTask { (account.accountKey, await self.usageService.usage(for: account)) } }
                for await (key, result) in group {
                    if case let .success(snapshot) = result { try? await repository.updateUsage(snapshot, for: key) }
                }
            }
        }
        await reload()
    }

    func importFile(_ url: URL) async {
        do {
            let report = try await repository.importAccounts(ImportRequest(source: url))
            statusMessage = "Imported \(report.importedAccountKeys.count) account(s)"
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func remove(_ key: AccountKey) async {
        do { _ = try await repository.remove([key]); await reload() } catch { errorMessage = error.localizedDescription }
    }

    func updateAlias(_ alias: String, for key: AccountKey) async {
        do { try await repository.setAlias(alias, for: key); await reload() } catch { errorMessage = error.localizedDescription }
    }

    func chooseProfile(_ profile: ProfileName?) {
        selectedProfile = profile
        UserDefaults.standard.set(profile?.rawValue, forKey: "selectedProfile")
    }

    func launchCLI() async {
        guard let selectedProfile else { return }
        do {
            let capabilities = try await processController.capabilities()
            guard capabilities.supportsProfiles else { throw ProcessError.profileUnsupported }
            try await processController.launchTerminal(profile: selectedProfile)
        } catch { errorMessage = error.localizedDescription }
    }

    func login(deviceCode: Bool) async {
        do {
            let artifact = try await processController.performLogin(deviceCode ? .deviceCode : .browser)
            defer { try? FileManager.default.removeItem(at: artifact.authURL) }
            _ = try await repository.importAccounts(ImportRequest(source: artifact.authURL, activate: true))
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func launchCodext() async {
        do {
            let cli = try await codextManager.installedCLI()
            if await processController.isDesktopRunning() { try await processController.terminateDesktopApp(timeout: .seconds(10)) }
            try await processController.launchDesktopApp(CodexLaunchRequest(codexHome: home.root, cliPath: cli))
            statusMessage = "Codex launched with verified codext"
        } catch { errorMessage = error.localizedDescription }
    }

    private func autoSwitchLoop() async {
        while !Task.isCancelled {
            let storedInterval = UserDefaults.standard.double(forKey: "refreshInterval")
            let interval = storedInterval == 0 ? 60 : max(5, storedInterval)
            try? await Task.sleep(for: .seconds(interval))
            guard UserDefaults.standard.bool(forKey: "autoSwitchEnabled") else { continue }
            await reload()
            let thresholds = AutoSwitchThresholds(
                fiveHour: UserDefaults.standard.double(forKey: "autoSwitch5h") == 0 ? 10 : UserDefaults.standard.double(forKey: "autoSwitch5h"),
                weekly: UserDefaults.standard.double(forKey: "autoSwitchWeekly") == 0 ? 5 : UserDefaults.standard.double(forKey: "autoSwitchWeekly")
            )
            let registry = RegistryV4(activeAccountKey: activeAccountKey, accounts: accounts)
            guard let decision = AutoSwitchPolicy().decision(registry: registry, thresholds: thresholds) else { continue }
            if await processController.isDesktopRunning() {
                let content = UNMutableNotificationContent()
                content.title = "Codex limit threshold reached"
                content.body = "Open Codex Auth Bar to switch and restart safely."
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "auto-switch", content: content, trigger: nil))
            } else {
                await switchAccount(decision.target, restart: false)
            }
        }
    }
}
