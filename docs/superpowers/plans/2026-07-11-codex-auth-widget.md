# Codex Auth Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only native macOS WidgetKit extension that shows managed Codex accounts and their 5-hour/weekly remaining limits in small, medium, and large Precision Ledger layouts.

**Architecture:** The unsandboxed menu-bar host projects `RegistryV4` into a secret-free schema-v1 snapshot and atomically writes it to `group.com.mesteriis.CodexAuthBar`. A sandboxed WidgetKit extension reads only that snapshot, builds 30-minute/reset-aware timelines, and renders native SwiftUI radial gauges without network or account-switching capabilities.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, Foundation, CryptoKit, POSIX atomic file operations, XCTest/Swift Testing, macOS 14+, Xcode app-extension targets.

## Global Constraints

- All application, extension, and test source code lives under repository-root `src/`.
- Host bundle ID remains `com.mesteriis.CodexAuthBar`; widget bundle ID is `com.mesteriis.CodexAuthBar.Widget`.
- App Group identifier is exactly `group.com.mesteriis.CodexAuthBar`.
- Host App Sandbox remains disabled; widget App Sandbox is enabled.
- The widget receives no network, keychain, automation, or arbitrary-file entitlement.
- Widget data never includes email, raw account/user IDs, raw account keys, auth mode, tokens, JWTs, API keys, or auth JSON.
- Widget is read-only; the only interaction opens `codexauthbar://accounts`.
- Supported families are `.systemSmall`, `.systemMedium`, and `.systemLarge`.
- Automatic reload requests are coalesced to 15 minutes; normal timeline refresh is 30 minutes.
- English and Russian localization, VoiceOver, Light/Dark, increased contrast, and Dynamic Type are required.
- Release remains gated on Apple Developer credentials and successful App Group provisioning.
- No third-party dependency or update framework is added.

## File and target map

Create:

```text
src/Packages/CodexAuthCore/Sources/CodexAuthCore/WidgetSnapshot.swift
src/Packages/CodexAuthCore/Sources/CodexAuthCore/WidgetSnapshotStore.swift
src/Packages/CodexAuthCore/Tests/CodexAuthCoreTests/WidgetSnapshotTests.swift
src/CodexAuthBar/Services/WidgetSnapshotPublisher.swift
src/CodexAuthBar/Support/WidgetDeepLink.swift
src/CodexAuthWidget/App/CodexAuthWidgetBundle.swift
src/CodexAuthWidget/Models/WidgetEntry.swift
src/CodexAuthWidget/Services/WidgetTimelineProvider.swift
src/CodexAuthWidget/Views/CodexAuthWidgetView.swift
src/CodexAuthWidget/Views/LimitRing.swift
src/CodexAuthWidget/Views/SmallWidgetView.swift
src/CodexAuthWidget/Views/MediumWidgetView.swift
src/CodexAuthWidget/Views/LargeWidgetView.swift
src/CodexAuthWidget/Views/WidgetPreviewHarness.swift
src/CodexAuthWidget/Resources/Info.plist
src/CodexAuthWidget/Resources/Localizable.xcstrings
src/CodexAuthWidgetTests/CodexAuthWidgetTests.swift
src/Entitlements/CodexAuthBar.entitlements
src/Entitlements/CodexAuthWidget.entitlements
CodexAuthBar.xcodeproj/xcshareddata/xcschemes/CodexAuthWidget.xcscheme
script/render_widget_previews.sh
```

Modify:

```text
CodexAuthBar.xcodeproj/project.pbxproj
CodexAuthBar.xcodeproj/xcshareddata/xcschemes/CodexAuthBar.xcscheme
src/CodexAuthBar/App/AppModel.swift
src/CodexAuthBar/App/CodexAuthBarApp.swift
src/CodexAuthBar/Resources/Info.plist
.github/workflows/ci.yml
script/package_release.sh
README.md
README.ru.md
docs/architecture.md
docs/implementation-status.md
```

---

### Task 1: Secret-free widget snapshot projection

**Files:**
- Create: `src/Packages/CodexAuthCore/Sources/CodexAuthCore/WidgetSnapshot.swift`
- Create: `src/Packages/CodexAuthCore/Tests/CodexAuthCoreTests/WidgetSnapshotTests.swift`

**Interfaces:**
- Consumes: `RegistryV4`, `AccountRecord`, `RateLimitWindow`, `PlanType`, `SecretRedactor`.
- Produces: `WidgetSnapshot`, `WidgetAccountSnapshot`, `WidgetLimitSnapshot`, `WidgetSnapshotProjector.project(_:generatedAt:fallbackName:)`.

- [ ] **Step 1: Write projection and secret-boundary tests**

Add tests covering schema keys, active-first/attention ordering, safe-name precedence, clamping, reset semantics, and forbidden data:

```swift
import Foundation
import Testing
@testable import CodexAuthCore

@Suite struct WidgetSnapshotTests {
    @Test func projectionContainsOnlySafeFieldsAndOrdersByAttention() throws {
        let active = widgetAccount(
            key: "user-active::account-active",
            email: "active@example.com",
            alias: "Personal",
            fiveHourUsed: 28,
            weeklyUsed: 54
        )
        let low = widgetAccount(
            key: "user-low::account-low",
            email: "low@example.com",
            alias: "Client",
            fiveHourUsed: 91,
            weeklyUsed: 70
        )
        let registry = RegistryV4(
            activeAccountKey: active.accountKey,
            accounts: [low, active]
        )

        let snapshot = WidgetSnapshotProjector.project(
            registry,
            generatedAt: Date(timeIntervalSince1970: 100),
            fallbackName: { "Account \($0)" }
        )

        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.accounts.map(\.displayName) == ["Personal", "Client"])
        #expect(snapshot.accounts[0].isActive)
        #expect(snapshot.accounts[0].fiveHour?.remainingPercent == 72)

        let data = try JSONEncoder().encode(snapshot)
        let text = String(decoding: data, as: UTF8.self)
        for forbidden in [
            "active@example.com", "low@example.com", "user-active",
            "account-active", "chatgpt_account_id", "email", "auth_mode",
            "access_token", "refresh_token", "OPENAI_API_KEY",
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test func unsafeNamesFallBackWithoutLeakingIdentity() {
        let account = widgetAccount(
            key: "user::account",
            email: "person@example.com",
            alias: "person@example.com",
            accountName: "sk-not-a-safe-widget-name",
            fiveHourUsed: 130,
            weeklyUsed: -10
        )

        let snapshot = WidgetSnapshotProjector.project(
            RegistryV4(accounts: [account]),
            fallbackName: { "Account \($0)" }
        )

        #expect(snapshot.accounts[0].displayName == "Account 1")
        #expect(snapshot.accounts[0].fiveHour?.remainingPercent == 0)
        #expect(snapshot.accounts[0].weekly?.remainingPercent == 100)
    }

    @Test func expiredWindowPresentsAsFullyAvailable() {
        let limit = WidgetLimitSnapshot(remainingPercent: 7, resetsAtSeconds: 100)
        #expect(limit.effectiveRemainingPercent(at: Date(timeIntervalSince1970: 99)) == 7)
        #expect(limit.effectiveRemainingPercent(at: Date(timeIntervalSince1970: 100)) == 100)
    }
}
```

Add a private fixture builder using synthetic short values that cannot match the repository secret scan.

```swift
private func widgetAccount(
    key: AccountKey,
    email: String,
    alias: String = "",
    accountName: String? = nil,
    fiveHourUsed: Double,
    weeklyUsed: Double
) -> AccountRecord {
    AccountRecord(
        accountKey: key,
        chatGPTAccountID: "synthetic-account",
        chatGPTUserID: "synthetic-user",
        email: email,
        alias: alias,
        accountName: accountName,
        plan: .pro,
        authMode: .chatgpt,
        lastUsage: RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: fiveHourUsed),
            secondary: RateLimitWindow(usedPercent: weeklyUsed)
        )
    )
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --package-path src/Packages/CodexAuthCore \
  --filter WidgetSnapshotTests
```

Expected: compile failure because widget snapshot types do not exist.

- [ ] **Step 3: Implement the snapshot types and pure projector**

Implement exact snake-case coding keys and deterministic projection:

```swift
import CryptoKit
import Foundation

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var generatedAtMilliseconds: Int64
    public var accounts: [WidgetAccountSnapshot]

    public init(
        generatedAtMilliseconds: Int64,
        accounts: [WidgetAccountSnapshot],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAtMilliseconds = generatedAtMilliseconds
        self.accounts = accounts
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMilliseconds = "generated_at_ms"
        case accounts
    }
}

public struct WidgetAccountSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var plan: PlanType?
    public var isActive: Bool
    public var fiveHour: WidgetLimitSnapshot?
    public var weekly: WidgetLimitSnapshot?

    public init(
        id: String,
        displayName: String,
        plan: PlanType?,
        isActive: Bool,
        fiveHour: WidgetLimitSnapshot?,
        weekly: WidgetLimitSnapshot?
    ) {
        self.id = id
        self.displayName = displayName
        self.plan = plan
        self.isActive = isActive
        self.fiveHour = fiveHour
        self.weekly = weekly
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case plan
        case isActive = "is_active"
        case fiveHour = "five_hour"
        case weekly
    }
}

public struct WidgetLimitSnapshot: Codable, Equatable, Sendable {
    public var remainingPercent: Double
    public var resetsAtSeconds: Int64?

    public init(remainingPercent: Double, resetsAtSeconds: Int64?) {
        self.remainingPercent = max(0, min(100, remainingPercent))
        self.resetsAtSeconds = resetsAtSeconds
    }

    public func effectiveRemainingPercent(at date: Date) -> Double {
        guard let resetsAtSeconds,
              resetsAtSeconds <= Int64(date.timeIntervalSince1970)
        else { return remainingPercent }
        return 100
    }

    enum CodingKeys: String, CodingKey {
        case remainingPercent = "remaining_percent"
        case resetsAtSeconds = "resets_at"
    }
}

public enum WidgetSnapshotProjector {
    public static func project(
        _ registry: RegistryV4,
        generatedAt: Date = .now,
        fallbackName: (Int) -> String = { "Account \($0)" }
    ) -> WidgetSnapshot {
        let ordered = registry.accounts.sorted {
            let leftActive = $0.accountKey == registry.activeAccountKey
            let rightActive = $1.accountKey == registry.activeAccountKey
            if leftActive != rightActive { return leftActive }
            let left = attentionScore($0, at: generatedAt)
            let right = attentionScore($1, at: generatedAt)
            if left != right { return left < right }
            return safeCandidate($0) < safeCandidate($1)
        }
        let accounts = ordered.enumerated().map { index, account in
            WidgetAccountSnapshot(
                id: stableID(account.accountKey),
                displayName: safeName(account, fallback: fallbackName(index + 1)),
                plan: account.resolvedPlan,
                isActive: account.accountKey == registry.activeAccountKey,
                fiveHour: limit(account.lastUsage?.primary, at: generatedAt),
                weekly: limit(account.lastUsage?.secondary, at: generatedAt)
            )
        }
        return WidgetSnapshot(
            generatedAtMilliseconds: Int64(generatedAt.timeIntervalSince1970 * 1_000),
            accounts: accounts
        )
    }

    private static func stableID(_ key: AccountKey) -> String {
        SHA256.hash(data: Data(key.rawValue.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func safeCandidate(_ account: AccountRecord) -> String {
        [account.alias, account.accountName ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: isSafeName) ?? ""
    }

    private static func safeName(_ account: AccountRecord, fallback: String) -> String {
        let candidate = safeCandidate(account)
        let value = candidate.isEmpty ? fallback : candidate
        return value.count > 30 ? String(value.prefix(29)) + "…" : value
    }

    private static func isSafeName(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("@") && SecretRedactor.redact(value) == value
    }

    private static func limit(_ window: RateLimitWindow?, at date: Date) -> WidgetLimitSnapshot? {
        guard let window else { return nil }
        return WidgetLimitSnapshot(
            remainingPercent: window.remainingPercent(at: date),
            resetsAtSeconds: window.resetsAt
        )
    }

    private static func attentionScore(_ account: AccountRecord, at date: Date) -> Double {
        let values = [account.lastUsage?.primary, account.lastUsage?.secondary]
            .compactMap { $0?.remainingPercent(at: date) }
        return values.min() ?? 100
    }
}

public enum CodexWidgetContract {
    public static let kind = "com.mesteriis.CodexAuthBar.accounts"
    public static let appGroup = "group.com.mesteriis.CodexAuthBar"
}
```

- [ ] **Step 4: Run focused and full core tests**

```bash
swift test --package-path src/Packages/CodexAuthCore \
  --filter WidgetSnapshotTests
swift test --package-path src/Packages/CodexAuthCore
```

Expected: all widget tests and the existing 53 core tests pass.

- [ ] **Step 5: Commit the projection slice**

```bash
git add src/Packages/CodexAuthCore
git commit -m "feat: add secret-free widget snapshot model"
```

---

### Task 2: Atomic shared snapshot persistence

**Files:**
- Create: `src/Packages/CodexAuthCore/Sources/CodexAuthCore/WidgetSnapshotStore.swift`
- Modify: `src/Packages/CodexAuthCore/Tests/CodexAuthCoreTests/WidgetSnapshotTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot`, existing internal `SecureFiles` POSIX primitives.
- Produces: `WidgetSnapshotStore.init(containerURL:)`, `load()`, `write(_:)`, `WidgetSnapshotStoreError`.

- [ ] **Step 1: Add persistence regression tests**

```swift
@Test func widgetStoreRoundTripsPrivateAtomicSnapshot() throws {
    let root = try temporaryDirectory()
    let store = WidgetSnapshotStore(containerURL: root)
    let snapshot = WidgetSnapshot(
        generatedAtMilliseconds: 1,
        accounts: []
    )

    try store.write(snapshot)

    #expect(try store.load() == snapshot)
    let attributes = try FileManager.default.attributesOfItem(atPath: store.snapshotURL.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func widgetStoreRejectsFutureSchemaWithoutChangingBytes() throws {
    let root = try temporaryDirectory()
    let store = WidgetSnapshotStore(containerURL: root)
    try store.write(WidgetSnapshot(generatedAtMilliseconds: 1, accounts: []))
    let original = try Data(contentsOf: store.snapshotURL)
    let future = Data(#"{"schema_version":2,"generated_at_ms":2,"accounts":[]}"#.utf8)
    try future.write(to: store.snapshotURL)

    #expect(throws: WidgetSnapshotStoreError.unsupportedSchema(2)) {
        _ = try store.load()
    }
    #expect(try Data(contentsOf: store.snapshotURL) == future)
    #expect(original != future)
}

@Test func widgetStoreRejectsSymlinkSnapshot() throws {
    let root = try temporaryDirectory()
    let store = WidgetSnapshotStore(containerURL: root)
    try FileManager.default.createDirectory(
        at: store.snapshotURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
        at: store.snapshotURL,
        withDestinationURL: root.appending(path: "outside.json")
    )
    #expect(throws: StorageError.self) { _ = try store.load() }
}
```

- [ ] **Step 2: Verify RED**

```bash
swift test --package-path src/Packages/CodexAuthCore \
  --filter WidgetSnapshotTests
```

Expected: compile failure because `WidgetSnapshotStore` is missing.

- [ ] **Step 3: Implement the store using the existing secure file layer**

```swift
import Foundation

public enum WidgetSnapshotStoreError: Error, Equatable, Sendable {
    case missing
    case unsupportedSchema(Int)
    case invalidJSON
}

public struct WidgetSnapshotStore: Sendable {
    public let containerURL: URL
    public var snapshotURL: URL {
        containerURL.appending(path: "widget/snapshot.json")
    }

    public init(containerURL: URL) { self.containerURL = containerURL }

    public func load() throws -> WidgetSnapshot {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            throw WidgetSnapshotStoreError.missing
        }
        let data = try SecureFiles.readRegularFile(snapshotURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = (object["schema_version"] as? NSNumber)?.intValue
        else { throw WidgetSnapshotStoreError.invalidJSON }
        guard version <= WidgetSnapshot.currentSchemaVersion else {
            throw WidgetSnapshotStoreError.unsupportedSchema(version)
        }
        return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try SecureFiles.atomicWrite(encoder.encode(snapshot), to: snapshotURL)
    }
}
```

Do not add backup rotation: the atomic previous-or-new guarantee is sufficient, and the shared snapshot is derived/rebuildable data.

- [ ] **Step 4: Run storage and full core tests**

```bash
swift test --package-path src/Packages/CodexAuthCore \
  --filter WidgetSnapshotTests
swift test --package-path src/Packages/CodexAuthCore
```

Expected: all pass; no token-like fixture appears in output.

- [ ] **Step 5: Commit the persistence slice**

```bash
git add src/Packages/CodexAuthCore
git commit -m "feat: persist widget snapshots atomically"
```

---

### Task 3: Widget extension target, embedding, and entitlements

**Files:**
- Create: `src/Entitlements/CodexAuthBar.entitlements`
- Create: `src/Entitlements/CodexAuthWidget.entitlements`
- Create: `src/CodexAuthWidget/Resources/Info.plist`
- Create: `src/CodexAuthWidget/App/CodexAuthWidgetBundle.swift`
- Create: `CodexAuthBar.xcodeproj/xcshareddata/xcschemes/CodexAuthWidget.xcscheme`
- Modify: `CodexAuthBar.xcodeproj/project.pbxproj`
- Modify: `CodexAuthBar.xcodeproj/xcshareddata/xcschemes/CodexAuthBar.xcscheme`
- Modify: `src/CodexAuthBar/Resources/Info.plist`

**Interfaces:**
- Consumes: local Swift package product `CodexAuthCore`.
- Produces: embedded `CodexAuthWidget.appex`, app group capabilities, `codexauthbar` URL scheme, testable widget scheme.

- [ ] **Step 1: Add failing build-contract assertions**

Before changing the project, run and confirm the extension is absent:

```bash
xcodebuild -project CodexAuthBar.xcodeproj -list | \
  rg 'CodexAuthWidget' && exit 1 || true
test ! -e src/Entitlements/CodexAuthWidget.entitlements
```

Expected: no widget target or entitlement file.

- [ ] **Step 2: Add exact entitlement and Info.plist contracts**

Host entitlements:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.application-groups</key>
  <array><string>group.com.mesteriis.CodexAuthBar</string></array>
</dict></plist>
```

Widget entitlements:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.application-groups</key>
  <array><string>group.com.mesteriis.CodexAuthBar</string></array>
</dict></plist>
```

Widget Info.plist includes only the standard extension declaration:

```xml
<key>CFBundleDisplayName</key><string>Codex Accounts</string>
<key>NSExtension</key>
<dict>
  <key>NSExtensionPointIdentifier</key>
  <string>com.apple.widgetkit-extension</string>
</dict>
```

Add the host URL type to `src/CodexAuthBar/Resources/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array><dict>
  <key>CFBundleURLName</key><string>com.mesteriis.CodexAuthBar.accounts</string>
  <key>CFBundleURLSchemes</key><array><string>codexauthbar</string></array>
</dict></array>
```

- [ ] **Step 3: Add a minimal compilable WidgetKit entry point**

```swift
import SwiftUI
import WidgetKit

@main
struct CodexAuthWidgetBundle: WidgetBundle {
    var body: some Widget { CodexAccountsWidget() }
}

struct CodexAccountsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CodexWidgetContract.kind, provider: PlaceholderProvider()) { entry in
            Text("Codex Auth Bar")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Codex Accounts")
        .description("Shows remaining Codex account limits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PlaceholderEntry: TimelineEntry { let date: Date }

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { .init(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(.init(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: .now)], policy: .never))
    }
}
```

Keep `PlaceholderProvider` in this file only until Task 5 replaces it.

- [ ] **Step 4: Add Xcode targets and embedding contract**

Modify `project.pbxproj` with stable new object IDs and these exact settings:

```text
Target: CodexAuthWidget
Product type: com.apple.product-type.app-extension
Product: CodexAuthWidget.appex
Bundle ID: com.mesteriis.CodexAuthBar.Widget
INFOPLIST_FILE: src/CodexAuthWidget/Resources/Info.plist
CODE_SIGN_ENTITLEMENTS: src/Entitlements/CodexAuthWidget.entitlements
ENABLE_APP_SANDBOX: YES
ENABLE_HARDENED_RUNTIME: YES
APPLICATION_EXTENSION_API_ONLY: YES
MACOSX_DEPLOYMENT_TARGET: 14.0
SWIFT_VERSION: 6.0
SWIFT_STRICT_CONCURRENCY: complete
SKIP_INSTALL: YES
```

Add `CodexAuthCore`, `SwiftUI.framework`, and `WidgetKit.framework` to the widget frameworks phase. Add an `Embed App Extensions` copy-files phase (`dstSubfolderSpec = 13`) to `CodexAuthBar`, with `CodeSignOnCopy` and `RemoveHeadersOnCopy`. Add a target dependency from the host to the widget.

Set host `CODE_SIGN_ENTITLEMENTS = src/Entitlements/CodexAuthBar.entitlements` while preserving `ENABLE_APP_SANDBOX = NO`. Add the widget buildable to the host scheme's BuildAction for running/testing/archiving, and create a shared `CodexAuthWidget` scheme.

- [ ] **Step 5: Validate project and unsigned embedding**

```bash
plutil -lint src/Entitlements/*.entitlements \
  src/CodexAuthWidget/Resources/Info.plist \
  src/CodexAuthBar/Resources/Info.plist
xcodebuild -project CodexAuthBar.xcodeproj -list
xcodebuild build -project CodexAuthBar.xcodeproj -scheme CodexAuthBar \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
test -d "$HOME/Library/Developer/Xcode/DerivedData" # locate product via xcodebuild settings
```

Expected: `CodexAuthWidget` appears as target/scheme and the built app contains `Contents/PlugIns/CodexAuthWidget.appex`.

- [ ] **Step 6: Commit the extension scaffold**

```bash
git add CodexAuthBar.xcodeproj src/Entitlements src/CodexAuthWidget \
  src/CodexAuthBar/Resources/Info.plist
git commit -m "feat: scaffold Codex account widget extension"
```

---

### Task 4: Host publisher, coalescing, workflow hooks, and deep link

**Files:**
- Create: `src/CodexAuthBar/Services/WidgetSnapshotPublisher.swift`
- Create: `src/CodexAuthBar/Support/WidgetDeepLink.swift`
- Modify: `src/CodexAuthBar/App/AppModel.swift`
- Modify: `src/CodexAuthBar/App/CodexAuthBarApp.swift`
- Modify: `src/CodexAuthBarTests/CodexAuthBarTests.swift`
- Modify: `CodexAuthBar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `WidgetSnapshotProjector`, `WidgetSnapshotStore`, `RegistryV4`, `WidgetCenter`.
- Produces: `WidgetPublishReason`, `WidgetSnapshotPublisher.publish(registry:reason:now:)`, `WidgetDeepLink`.

- [ ] **Step 1: Write publisher and route tests first**

```swift
func testAutomaticWidgetReloadsAreCoalescedForFifteenMinutes() async throws {
    let store = RecordingWidgetStore()
    let reloader = RecordingWidgetReloader()
    let publisher = WidgetSnapshotPublisher(
        store: store,
        reloader: reloader,
        fallbackName: { "Account \($0)" }
    )
    let registry = syntheticWidgetRegistry()

    try await publisher.publish(
        registry: registry,
        reason: .automatic,
        now: Date(timeIntervalSince1970: 0)
    )
    try await publisher.publish(
        registry: changedSyntheticWidgetRegistry(),
        reason: .automatic,
        now: Date(timeIntervalSince1970: 14 * 60)
    )
    try await publisher.publish(
        registry: secondChangedSyntheticWidgetRegistry(),
        reason: .automatic,
        now: Date(timeIntervalSince1970: 15 * 60)
    )

    XCTAssertEqual(await reloader.reloadCount, 2)
    XCTAssertEqual(await store.writeCount, 3)
}

func testManualRefreshReloadsAndAdvancesFreshnessEvenWhenValuesMatch() async throws {
    let store = RecordingWidgetStore()
    let reloader = RecordingWidgetReloader()
    let publisher = WidgetSnapshotPublisher(
        store: store,
        reloader: reloader,
        fallbackName: { "Account \($0)" }
    )
    let registry = syntheticWidgetRegistry()

    try await publisher.publish(
        registry: registry,
        reason: .manualRefresh,
        now: Date(timeIntervalSince1970: 0)
    )
    try await publisher.publish(
        registry: registry,
        reason: .manualRefresh,
        now: Date(timeIntervalSince1970: 60)
    )

    XCTAssertEqual(await store.writeCount, 2)
    XCTAssertEqual(await reloader.reloadCount, 2)
}

func testWidgetDeepLinkAcceptsOnlyAccountsRoute() {
    XCTAssertEqual(WidgetDeepLink(URL(string: "codexauthbar://accounts")!), .accounts)
    XCTAssertNil(WidgetDeepLink(URL(string: "https://example.com")!))
    XCTAssertNil(WidgetDeepLink(URL(string: "codexauthbar://switch/account")!))
}
```

Use actor-backed fakes. They must record counts only, never snapshot bodies in assertion messages.

- [ ] **Step 2: Verify RED**

```bash
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthBar \
  -destination 'platform=macOS' -skip-testing:CodexAuthBarUITests \
  -only-testing:CodexAuthBarTests/CodexAuthBarTests/testAutomaticWidgetReloadsAreCoalescedForFifteenMinutes \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compile failure because publisher interfaces are missing.

- [ ] **Step 3: Implement an injectable publisher actor**

```swift
import CodexAuthCore
import Foundation
import WidgetKit

enum WidgetPublishReason: Sendable {
    case startup, manualRefresh, structural, automatic
    var forcesReload: Bool { self != .automatic }
}

protocol WidgetTimelineReloading: Sendable {
    func reload() async
}

struct SystemWidgetTimelineReloader: WidgetTimelineReloading {
    func reload() async {
        WidgetCenter.shared.reloadTimelines(ofKind: CodexWidgetContract.kind)
    }
}

protocol WidgetSnapshotWriting: Sendable {
    func writeSnapshot(_ snapshot: WidgetSnapshot) async throws
}

extension WidgetSnapshotStore: WidgetSnapshotWriting {
    func writeSnapshot(_ snapshot: WidgetSnapshot) async throws { try write(snapshot) }
}

actor WidgetSnapshotPublisher {
    static let automaticReloadInterval: TimeInterval = 15 * 60

    private let store: any WidgetSnapshotWriting
    private let reloader: any WidgetTimelineReloading
    private let fallbackName: @Sendable (Int) -> String
    private var lastReload: Date?
    private var lastAccounts: [WidgetAccountSnapshot]?

    init(
        store: any WidgetSnapshotWriting,
        reloader: any WidgetTimelineReloading = SystemWidgetTimelineReloader(),
        fallbackName: @escaping @Sendable (Int) -> String
    ) {
        self.store = store
        self.reloader = reloader
        self.fallbackName = fallbackName
    }

    func publish(
        registry: RegistryV4,
        reason: WidgetPublishReason,
        now: Date = .now
    ) async throws {
        let snapshot = WidgetSnapshotProjector.project(
            registry,
            generatedAt: now,
            fallbackName: fallbackName
        )
        let contentChanged = snapshot.accounts != lastAccounts
        guard contentChanged || reason.forcesReload else { return }

        try await store.writeSnapshot(snapshot)
        lastAccounts = snapshot.accounts

        let elapsed = lastReload.map { now.timeIntervalSince($0) } ?? .infinity
        guard reason.forcesReload || elapsed >= Self.automaticReloadInterval else { return }
        await reloader.reload()
        lastReload = now
    }
}
```

Do not make the app target depend on the widget executable module merely to read the kind. Use `CodexWidgetContract.kind` and `CodexWidgetContract.appGroup` from Task 1.

- [ ] **Step 4: Integrate publication at `AppModel` workflow boundaries**

Create the publisher after resolving App Group container. If the entitlement/container is unavailable, keep a disabled publisher and emit only safe OSLog code `widget_container_unavailable`; account operations must continue.

Change reload to accept a reason:

```swift
func reload(widgetReason: WidgetPublishReason = .automatic) async {
    isLoading = true
    defer { isLoading = false }
    let state: AccountState
    do {
        state = try await repository.state(refresh: .stored)
        accounts = state.registry.accounts.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        activeAccountKey = state.registry.activeAccountKey
        previousAccountKey = state.registry.previousActiveAccountKey
        activeAccountActivatedAtMilliseconds = state.registry.activeAccountActivatedAtMilliseconds
        profiles = try await profileStore.list()
        errorMessage = nil
    } catch {
        errorMessage = error.localizedDescription
        return
    }
    try? await widgetPublisher?.publish(
        registry: state.registry,
        reason: widgetReason
    )
}
```

Use `.startup` after recovery, `.manualRefresh` after manual remote/local refresh, `.structural` after switch/import/login/remove/alias/purge/clean/account-name updates, and `.automatic` inside the auto-switch monitoring loop/file watcher. Avoid a second registry read solely for the widget.

- [ ] **Step 5: Implement safe deep-link routing**

`WidgetDeepLink` accepts only scheme `codexauthbar` and host `accounts`. Attach `.onOpenURL` to the menu-bar root, activate the accessory app, and call `openWindow(id: "accounts")`. Never accept an account key or switch command in the URL.

- [ ] **Step 6: Run app regression tests**

```bash
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthBar \
  -destination 'platform=macOS' -skip-testing:CodexAuthBarUITests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: publisher/deep-link tests and all existing app tests pass; real `~/.codex` is untouched.

- [ ] **Step 7: Commit host integration**

```bash
git add src/CodexAuthBar src/CodexAuthBarTests \
  src/Packages/CodexAuthCore CodexAuthBar.xcodeproj
git commit -m "feat: publish account limits to WidgetKit"
```

---

### Task 5: Timeline builder and testable presentation model

**Files:**
- Create: `src/CodexAuthWidget/Models/WidgetEntry.swift`
- Create: `src/CodexAuthWidget/Services/WidgetTimelineProvider.swift`
- Create: `src/CodexAuthWidgetTests/CodexAuthWidgetTests.swift`
- Modify: `src/CodexAuthWidget/App/CodexAuthWidgetBundle.swift`
- Modify: `CodexAuthBar.xcodeproj/project.pbxproj`
- Modify: `CodexAuthBar.xcodeproj/xcshareddata/xcschemes/CodexAuthWidget.xcscheme`

**Interfaces:**
- Consumes: safe snapshot store and App Group container only.
- Produces: `CodexWidgetEntry`, `WidgetTimelineBuilder`, `CodexWidgetProvider`, `WidgetPresentation`.

- [ ] **Step 1: Add a widget unit-test target and write timeline tests**

Configure `CodexAuthWidgetTests.xctest` as a hostless macOS unit-test target that links `CodexAuthCore`, WidgetKit, SwiftUI, and the non-`@main` widget sources under test.

```swift
import CodexAuthCore
import XCTest
@testable import CodexAuthWidget

final class CodexAuthWidgetTests: XCTestCase {
    func testTimelineRefreshesInThirtyMinutesAndIncludesSpacedResets() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = widgetSnapshot(
            resets: [now.addingTimeInterval(4 * 60),
                     now.addingTimeInterval(10 * 60),
                     now.addingTimeInterval(20 * 60)]
        )

        let result = WidgetTimelineBuilder.build(snapshot: snapshot, now: now)

        XCTAssertEqual(result.reloadDate, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(result.entries.map(\.date), [now,
            now.addingTimeInterval(10 * 60),
            now.addingTimeInterval(20 * 60)])
    }

    func testFamilyCapacityIsOneThreeAndSix() {
        let snapshot = widgetSnapshot(accountCount: 8)
        XCTAssertEqual(WidgetPresentation(snapshot, family: .systemSmall).accounts.count, 1)
        XCTAssertEqual(WidgetPresentation(snapshot, family: .systemMedium).accounts.count, 3)
        XCTAssertEqual(WidgetPresentation(snapshot, family: .systemLarge).accounts.count, 6)
        XCTAssertEqual(WidgetPresentation(snapshot, family: .systemLarge).hiddenCount, 2)
    }

    func testFreshnessBoundaries() {
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertEqual(
            WidgetFreshness.resolve(generatedAt: now.addingTimeInterval(-119 * 60), now: now),
            .fresh
        )
        XCTAssertEqual(
            WidgetFreshness.resolve(generatedAt: now.addingTimeInterval(-2 * 60 * 60), now: now),
            .aging
        )
        XCTAssertEqual(
            WidgetFreshness.resolve(generatedAt: now.addingTimeInterval(-24 * 60 * 60), now: now),
            .stale
        )
    }
}
```

- [ ] **Step 2: Verify RED**

```bash
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthWidget \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: compile failure for missing timeline/presentation types.

- [ ] **Step 3: Implement entry, freshness, presentation, and timeline builder**

```swift
import CodexAuthCore
import Foundation
import WidgetKit

struct CodexWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
    var loadState: WidgetLoadState
}

enum WidgetLoadState: Equatable { case loaded, missing, invalid }
enum WidgetFreshness: Equatable {
    case fresh, aging, stale

    static func resolve(generatedAt: Date, now: Date) -> Self {
        let age = now.timeIntervalSince(generatedAt)
        if age >= 24 * 60 * 60 { return .stale }
        if age >= 2 * 60 * 60 { return .aging }
        return .fresh
    }
}

struct WidgetTimelineResult {
    var entries: [CodexWidgetEntry]
    var reloadDate: Date
}

struct WidgetPresentation {
    let accounts: [WidgetAccountSnapshot]
    let hiddenCount: Int
    let freshness: WidgetFreshness?
    let now: Date

    init(_ snapshot: WidgetSnapshot?, family: WidgetFamily, now: Date = .now) {
        let capacity: Int
        switch family {
        case .systemSmall: capacity = 1
        case .systemMedium: capacity = 3
        case .systemLarge: capacity = 6
        default: capacity = 1
        }
        let all = snapshot?.accounts ?? []
        accounts = Array(all.prefix(capacity))
        hiddenCount = max(0, all.count - capacity)
        self.now = now
        freshness = snapshot.map {
            WidgetFreshness.resolve(
                generatedAt: Date(timeIntervalSince1970: TimeInterval($0.generatedAtMilliseconds) / 1_000),
                now: now
            )
        }
    }
}

enum WidgetTimelineBuilder {
    static let normalRefresh: TimeInterval = 30 * 60
    static let minimumSpacing: TimeInterval = 5 * 60

    static func build(snapshot: WidgetSnapshot?, now: Date) -> WidgetTimelineResult {
        let horizon = now.addingTimeInterval(24 * 60 * 60)
        let resetDates = (snapshot?.accounts ?? []).flatMap { account in
            [account.fiveHour?.resetsAtSeconds, account.weekly?.resetsAtSeconds]
                .compactMap { $0 }
                .map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
        .filter { $0 > now && $0 <= horizon }
        .sorted()

        var dates = [now]
        for reset in resetDates where reset.timeIntervalSince(dates.last!) >= minimumSpacing {
            dates.append(reset)
        }
        let state: WidgetLoadState = snapshot == nil ? .missing : .loaded
        return WidgetTimelineResult(
            entries: dates.map { CodexWidgetEntry(date: $0, snapshot: snapshot, loadState: state) },
            reloadDate: now.addingTimeInterval(normalRefresh)
        )
    }
}
```

`WidgetPresentation` derives effective percentages at the entry date, freshness, account limit by family, hidden count, and nearest reset. It never logs or exposes snapshot JSON.

- [ ] **Step 4: Replace placeholder provider with production App Group reader**

```swift
struct CodexWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexWidgetEntry {
        .preview(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexWidgetEntry) -> Void) {
        completion(context.isPreview ? .preview(date: .now) : loadEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = loadSnapshot()
        let result = WidgetTimelineBuilder.build(snapshot: snapshot, now: now)
        completion(Timeline(entries: result.entries, policy: .after(result.reloadDate)))
    }
}
```

Resolve the group container only through `CodexWidgetContract.appGroup`. Missing/invalid/future snapshots map to explicit load states.

- [ ] **Step 5: Run widget and full tests**

```bash
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthWidget \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
swift test --package-path src/Packages/CodexAuthCore
```

Expected: timeline tests pass with no live network or App Group dependency.

- [ ] **Step 6: Commit the timeline slice**

```bash
git add src/CodexAuthWidget src/CodexAuthWidgetTests CodexAuthBar.xcodeproj
git commit -m "feat: build reset-aware widget timelines"
```

---

### Task 6: Precision Ledger radial-gauge views and localization

**Files:**
- Create: `src/CodexAuthWidget/Views/LimitRing.swift`
- Create: `src/CodexAuthWidget/Views/CodexAuthWidgetView.swift`
- Create: `src/CodexAuthWidget/Views/SmallWidgetView.swift`
- Create: `src/CodexAuthWidget/Views/MediumWidgetView.swift`
- Create: `src/CodexAuthWidget/Views/LargeWidgetView.swift`
- Create: `src/CodexAuthWidget/Views/WidgetPreviewHarness.swift`
- Create: `src/CodexAuthWidget/Resources/Localizable.xcstrings`
- Modify: `src/CodexAuthWidget/App/CodexAuthWidgetBundle.swift`
- Modify: `src/CodexAuthWidgetTests/CodexAuthWidgetTests.swift`
- Modify: `CodexAuthBar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CodexWidgetEntry`, `WidgetPresentation`.
- Produces: exact selected Precision Ledger views for three families and reusable `LimitRing`/`DualLimitRing`.

- [ ] **Step 1: Add semantic/accessibility tests before views**

```swift
func testRingSemanticsUseWarningAndCriticalThresholds() {
    XCTAssertEqual(LimitSeverity(remaining: nil), .unavailable)
    XCTAssertEqual(LimitSeverity(remaining: 20), .normal)
    XCTAssertEqual(LimitSeverity(remaining: 19), .warning)
    XCTAssertEqual(LimitSeverity(remaining: 10), .warning)
    XCTAssertEqual(LimitSeverity(remaining: 9), .critical)
}

func testAccessibilityValueIncludesNumberResetAndStaleness() {
    let value = LimitAccessibility.value(
        title: "5h",
        remaining: 72,
        reset: Date(timeIntervalSince1970: 7_200),
        now: Date(timeIntervalSince1970: 0),
        freshness: .aging,
        locale: Locale(identifier: "en")
    )
    XCTAssertTrue(value.contains("72"))
    XCTAssertTrue(value.localizedCaseInsensitiveContains("remaining"))
    XCTAssertTrue(value.localizedCaseInsensitiveContains("out of date"))
}
```

- [ ] **Step 2: Verify RED**

```bash
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthWidget \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: compile failure for view-semantic types.

- [ ] **Step 3: Implement the reusable rings**

Use real SwiftUI vector primitives, which are the native functional UI—not decorative image assets:

```swift
enum LimitSeverity: Equatable {
    case normal, warning, critical, unavailable

    init(remaining: Double?) {
        guard let remaining else { self = .unavailable; return }
        if remaining < 10 { self = .critical }
        else if remaining < 20 { self = .warning }
        else { self = .normal }
    }

    var color: Color {
        switch self {
        case .normal: .indigo
        case .warning: .orange
        case .critical: .red
        case .unavailable: .secondary
        }
    }
}

enum LimitAccessibility {
    static func value(
        title: String,
        remaining: Double?,
        reset: Date?,
        now: Date,
        freshness: WidgetFreshness?,
        locale: Locale = .current
    ) -> String {
        guard let remaining else {
            return String(localized: "\(title) limit unavailable", locale: locale)
        }
        let format = String(localized: "%@ limit, %d percent remaining", locale: locale)
        var result = String(format: format, locale: locale, title, Int(remaining))
        if let reset {
            let relative = RelativeDateTimeFormatter()
            relative.locale = locale
            result += ", " + String(
                format: String(localized: "resets %@", locale: locale),
                locale: locale,
                relative.localizedString(for: reset, relativeTo: now)
            )
        }
        if freshness == .aging || freshness == .stale {
            result += ", " + String(localized: "data out of date", locale: locale)
        }
        return result
    }
}

struct LimitRing: View {
    let title: LocalizedStringKey
    let remaining: Double?
    let diameter: CGFloat
    let lineWidth: CGFloat

    private var severity: LimitSeverity { LimitSeverity(remaining: remaining) }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            if let remaining {
                Circle()
                    .trim(from: 0, to: remaining / 100)
                    .stroke(severity.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle().stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            VStack(spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(remaining.map { "\(Int($0))%" } ?? "—")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}
```

`DualLimitRing` uses two concentric trimmed circles and a compact numeric legend for `.systemSmall`.

- [ ] **Step 4: Implement family-specific layouts**

Root routing:

```swift
struct CodexAuthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallWidgetView(entry: entry)
            case .systemMedium: MediumWidgetView(entry: entry)
            case .systemLarge: LargeWidgetView(entry: entry)
            default: SmallWidgetView(entry: entry)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "codexauthbar://accounts"))
    }
}
```

Follow the approved mock exactly:

- small: header/freshness, safe name/plan, dominant dual ring, reset footer;
- medium: header plus three ledger rows with 32–40 pt paired rings;
- large: header/summary plus six fixed-column rows and hidden-count footer;
- no nested rounded cards, custom opaque backgrounds, buttons, or decorative gradients;
- account text truncates at 30 characters before line layout.

- [ ] **Step 5: Add complete EN/RU string catalog**

Include at least:

```text
Codex Accounts / Аккаунты Codex
5h / 5 ч
Weekly / Неделя
Resets %@ / Сброс %@
Updated %@ / Обновлено %@
Stale / Устарело
Unavailable / Недоступно
No managed accounts / Нет сохранённых аккаунтов
Open Codex Auth Bar to set up the widget / Откройте Codex Auth Bar для настройки виджета
+ %d more in Codex Auth Bar / Ещё %d в Codex Auth Bar
%d percent remaining / Осталось %d процентов
```

Use localized format strings, not manual word concatenation.

- [ ] **Step 6: Add previews and deterministic render fixtures**

`WidgetPreviewHarness` exposes sample entries for all three families and states: healthy, warning, critical, unavailable, empty, and stale. Add `#Preview(as:)` declarations for Light/Dark and increased contrast.

- [ ] **Step 7: Run widget tests and compile previews**

```bash
jq empty src/CodexAuthWidget/Resources/Localizable.xcstrings
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthWidget \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project CodexAuthBar.xcodeproj -scheme CodexAuthBar \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all three family code paths compile and semantic tests pass.

- [ ] **Step 8: Commit the visual implementation**

```bash
git add src/CodexAuthWidget src/CodexAuthWidgetTests CodexAuthBar.xcodeproj
git commit -m "feat: render Precision Ledger account widgets"
```

---

### Task 7: Visual QA, keyboard/VoiceOver regression, and preview artifacts

**Files:**
- Create: `script/render_widget_previews.sh`
- Modify: `src/CodexAuthWidgetTests/CodexAuthWidgetTests.swift`
- Create during QA: `docs/qa/widget-small.png`
- Create during QA: `docs/qa/widget-medium.png`
- Create during QA: `docs/qa/widget-large.png`
- Create: `docs/qa/widget-design-qa.md`

**Interfaces:**
- Consumes: exact production widget views and approved image `docs/assets/codex-auth-widget-precision-ledger.png`.
- Produces: deterministic render attachments and a passed visual QA report.

- [ ] **Step 1: Add render tests using production views**

For each family, instantiate the exact view with `WidgetPreviewHarness.healthy`, set the matching reference size, render via `ImageRenderer`, assert non-empty PNG data, and attach it to the XCTest result:

```swift
@MainActor
func testRenderMediumPrecisionLedger() throws {
    let view = WidgetPreviewHarness.view(
        family: .systemMedium,
        colorScheme: .dark
    )
    let renderer = ImageRenderer(content: view.frame(width: 338, height: 158))
    renderer.scale = 2
    let image = try XCTUnwrap(renderer.nsImage)
    let attachment = XCTAttachment(image: image)
    attachment.name = "widget-medium-dark"
    attachment.lifetime = .keepAlways
    add(attachment)
}
```

Use dimensions returned by a single centralized fixture, not scattered literals.

- [ ] **Step 2: Add a preview export script**

The script runs only the three render tests into a deterministic result bundle, exports attachments with `xcresulttool`, normalizes filenames, and fails if any expected PNG is missing. It must use the bundled Xcode command-line tools and never touch live auth data.

- [ ] **Step 3: Render and inspect all three families**

```bash
./script/render_widget_previews.sh
```

Expected files:

```text
docs/qa/widget-small.png
docs/qa/widget-medium.png
docs/qa/widget-large.png
```

Open the approved reference and all three outputs. Check hierarchy, ring proportions, type scale, alignment, row separators, semantic colors, truncation, material behavior, and clipping.

- [ ] **Step 4: Write and pass visual QA**

Create `docs/qa/widget-design-qa.md` with:

```markdown
# Codex Auth Widget Design QA

Reference: `docs/assets/codex-auth-widget-precision-ledger.png`

## Findings

- Small hierarchy and dual-ring proportions: pass
- Medium three-row ledger spacing and alignment: pass
- Large six-row fixed-column alignment and truncation: pass
- Light, dark, and increased-contrast rendering: pass
- VoiceOver and numeric redundancy: pass

final result: passed
```

Write those `pass` lines only after direct comparison proves them. If any P0/P1/P2 visual issue exists, write the measured discrepancy and `final result: blocked`, fix it, rerender, and replace the blocked finding with the verified result. Do not mark passed from build output alone.

- [ ] **Step 5: Run localization and accessibility regressions**

```bash
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthWidget \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthBarUITests \
  -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

Expected: widget semantics and existing menu-bar keyboard/VoiceOver tests pass.

- [ ] **Step 6: Commit verified preview artifacts**

```bash
git add script/render_widget_previews.sh docs/qa \
  src/CodexAuthWidgetTests
git commit -m "test: verify widget visual and accessibility contracts"
```

---

### Task 8: CI, universal packaging, signed release checks, and OSS docs

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `script/package_release.sh`
- Modify: `README.md`
- Modify: `README.ru.md`
- Modify: `docs/architecture.md`
- Modify: `docs/implementation-status.md`

**Interfaces:**
- Consumes: embedded widget extension, entitlements, widget test scheme.
- Produces: CI and release gates that prove extension architecture, sandbox boundary, universal binary, nested signature, and disclosure.

- [ ] **Step 1: Extend CI tests and secret scan**

Add after app tests:

```yaml
- name: Widget tests
  run: >-
    xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthWidget
    -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Extend fixture scanning to `src/CodexAuthWidgetTests` and verify the shared snapshot model has no forbidden coding keys:

```bash
! rg -n 'access_token|refresh_token|openai_api_key|chatgpt_account_id|chatgpt_user_id|email|auth_mode' \
  src/Packages/CodexAuthCore/Sources/CodexAuthCore/WidgetSnapshot.swift
```

- [ ] **Step 2: Extend build-contract and universal checks**

Check host and widget settings independently:

```bash
xcodebuild -project CodexAuthBar.xcodeproj -target CodexAuthWidget \
  -configuration Release -showBuildSettings > build/widget-settings.txt
grep -q 'ENABLE_APP_SANDBOX = YES' build/widget-settings.txt
grep -q 'APPLICATION_EXTENSION_API_ONLY = YES' build/widget-settings.txt
grep -q 'MACOSX_DEPLOYMENT_TARGET = 14.0' build/widget-settings.txt
grep -q 'SWIFT_STRICT_CONCURRENCY = complete' build/widget-settings.txt

APP=build/ci-derived/Build/Products/Release/CodexAuthBar.app
WIDGET="$APP/Contents/PlugIns/CodexAuthWidget.appex"
test -d "$WIDGET"
ARCHS="$(lipo -archs "$WIDGET/Contents/MacOS/CodexAuthWidget")"
test "$ARCHS" = 'x86_64 arm64' || test "$ARCHS" = 'arm64 x86_64'
```

Lint both entitlement files and assert that the widget entitlement contains App Sandbox/App Group but no network client key.

- [ ] **Step 3: Harden signed packaging checks**

After archive creation, add:

```bash
WIDGET="$APP/Contents/PlugIns/CodexAuthWidget.appex"
codesign --verify --strict --verbose=2 "$WIDGET"
codesign -d --entitlements :- "$APP" >"$DIST/app-entitlements.plist"
codesign -d --entitlements :- "$WIDGET" >"$DIST/widget-entitlements.plist"
plutil -extract com.apple.security.application-groups xml1 -o - \
  "$DIST/app-entitlements.plist" | grep -q 'group.com.mesteriis.CodexAuthBar'
plutil -extract com.apple.security.application-groups xml1 -o - \
  "$DIST/widget-entitlements.plist" | grep -q 'group.com.mesteriis.CodexAuthBar'
plutil -extract com.apple.security.app-sandbox raw \
  "$DIST/widget-entitlements.plist" | grep -q '^true$'
! plutil -p "$DIST/widget-entitlements.plist" | grep -q 'network.client'
```

Keep `codesign --verify --deep --strict`, notarization, stapling, Gatekeeper, and SHA-256 checks already present.

- [ ] **Step 4: Update public documentation**

Document:

- adding small/medium/large widgets after launching the containing app once;
- safe shared snapshot contents and explicit absence of credentials/email;
- 15-minute automatic coalescing and 30-minute normal timeline;
- stale/offline behavior and disabled Usage API behavior;
- App Group signing prerequisite for contributors;
- widget read-only behavior and custom deep link;
- selected visual reference and QA artifacts.

Update architecture and implementation-status traceability tables with the new extension/process boundary.

- [ ] **Step 5: Run all mandatory gates**

```bash
swift test --package-path src/Packages/CodexAuthCore

xcodebuild test \
  -project CodexAuthBar.xcodeproj \
  -scheme CodexAuthBar \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -project CodexAuthBar.xcodeproj \
  -scheme CodexAuthWidget \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -project CodexAuthBar.xcodeproj \
  -scheme CodexAuthBarUITests \
  -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=

xcodebuild analyze \
  -project CodexAuthBar.xcodeproj \
  -scheme CodexAuthBar \
  CODE_SIGNING_ALLOWED=NO

./script/build_and_run.sh --verify
./script/render_widget_previews.sh
```

Build and inspect universal release output:

```bash
rm -rf build/WidgetUniversal
xcodebuild build -project CodexAuthBar.xcodeproj -scheme CodexAuthBar \
  -configuration Release -derivedDataPath build/WidgetUniversal \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO
lipo -archs build/WidgetUniversal/Build/Products/Release/CodexAuthBar.app/Contents/MacOS/CodexAuthBar
lipo -archs build/WidgetUniversal/Build/Products/Release/CodexAuthBar.app/Contents/PlugIns/CodexAuthWidget.appex/Contents/MacOS/CodexAuthWidget
```

Expected: both commands report `x86_64 arm64` or `arm64 x86_64`; no code or test source exists outside `src/`; `git diff --check` is clean.

- [ ] **Step 6: Commit integration and push for remote CI**

```bash
git add .github/workflows/ci.yml script/package_release.sh \
  README.md README.ru.md docs
git commit -m "docs: document Codex account limits widget"
git push origin main
gh run watch --exit-status
```

Expected: core, app, widget, UI, analyze, build-contract, universal, artifact, and secret-scan steps all succeed. Do not create a GitHub Release before Apple credentials and App Group provisioning exist.

## Plan self-review result

- Every approved requirement in `docs/superpowers/specs/2026-07-11-codex-auth-widget-design.md` maps to a task above.
- Snapshot, publisher, timeline, and view interfaces use consistent names across tasks.
- The widget has no network or switching path and receives only sanitized derived data.
- Runtime App Group verification is explicitly left inside the existing signed-release gate; compile/test coverage uses injected container URLs.
- No task requires a third-party dependency, raw credential fixture, or source file outside `src/`.
