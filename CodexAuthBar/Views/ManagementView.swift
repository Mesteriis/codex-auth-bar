import AppKit
import CodexAuthCore
import SwiftUI

struct ManagementView: View {
    @Bindable var model: AppModel
    @State private var selection: AccountKey?
    @State private var alias = ""
    @State private var confirmRemoval = false

    var body: some View {
        NavigationSplitView {
            List(model.accounts, selection: $selection) { account in
                VStack(alignment: .leading) {
                    Text(account.displayName)
                    Text(account.email).font(.caption).foregroundStyle(.secondary)
                }
                .tag(account.accountKey)
            }
            .navigationTitle("Accounts")
            .toolbar {
                Button { importAccount() } label: { Label("Import", systemImage: "square.and.arrow.down") }
                Menu {
                    Button("Browser login") { Task { await model.login(deviceCode: false) } }
                    Button("Device-code login") { Task { await model.login(deviceCode: true) } }
                } label: { Label("Add", systemImage: "plus") }
            }
        } detail: {
            if let account = model.accounts.first(where: { $0.accountKey == selection }) {
                accountDetail(account)
            } else {
                ContentUnavailableView("Select an account", systemImage: "person.crop.circle")
            }
        }
        .task { await model.reload() }
        .alert("Remove account?", isPresented: $confirmRemoval) {
            Button("Remove", role: .destructive) { if let selection { Task { await model.remove(selection) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The managed auth snapshot will be deleted.") }
    }

    private func accountDetail(_ account: AccountRecord) -> some View {
        Form {
            Section("Identity") {
                LabeledContent("Email", value: account.email)
                LabeledContent("Account ID", value: account.chatGPTAccountID)
                LabeledContent("Plan", value: account.resolvedPlan?.label ?? "Unknown")
                LabeledContent("Authentication", value: account.authMode?.rawValue ?? "Unknown")
            }
            Section("Display") {
                TextField("Alias", text: $alias)
                    .onAppear { alias = account.alias }
                Button("Save alias") { Task { await model.updateAlias(alias, for: account.accountKey) } }
            }
            Section("Actions") {
                HStack {
                    Button("Switch & Restart") { Task { await model.switchAccount(account.accountKey) } }
                    Button("Switch only") { Task { await model.switchAccount(account.accountKey, restart: false) } }
                    Spacer()
                    Button("Remove", role: .destructive) { confirmRemoval = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(account.displayName)
    }

    private func importAccount() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.importFile(url) }
    }
}
