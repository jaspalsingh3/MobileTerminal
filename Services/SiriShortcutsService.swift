//
//  SiriShortcutsService.swift
//  Mobile Terminal
//
//  Siri Shortcuts integration for hands-free terminal access
//

import SwiftUI
#if os(iOS)
import Intents
import IntentsUI
#endif

final class SiriShortcutsService: ObservableObject {
    static let shared = SiriShortcutsService()

    @Published var donatedShortcuts: [String] = []

    // Shortcut identifiers - updated to use mobileterminal bundle
    enum ShortcutType: String, CaseIterable {
        case openTerminal = "com.mobileterminal.openTerminal"
        case connectServer = "com.mobileterminal.connectServer"
        case clearTerminal = "com.mobileterminal.clearTerminal"
        case customCommand = "com.mobileterminal.customCommand"

        var title: String {
            switch self {
            case .openTerminal: return "Open Terminal"
            case .connectServer: return "Connect to Server"
            case .clearTerminal: return "Clear Terminal"
            case .customCommand: return "Run Command"
            }
        }

        var suggestedPhrase: String {
            switch self {
            case .openTerminal: return "Open my terminal"
            case .connectServer: return "Connect to server"
            case .clearTerminal: return "Clear terminal"
            case .customCommand: return "Run terminal command"
            }
        }

        var icon: String {
            switch self {
            case .openTerminal: return "terminal"
            case .connectServer: return "server.rack"
            case .clearTerminal: return "trash"
            case .customCommand: return "command"
            }
        }
    }

    private init() {
        loadDonatedShortcuts()
    }

    // MARK: - Shortcut Donation

    /// Donate a shortcut to Siri
    func donateShortcut(_ type: ShortcutType, command: String? = nil, serverName: String? = nil) {
        #if os(iOS)
        let activity = NSUserActivity(activityType: type.rawValue)
        activity.title = type.title
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = type.rawValue
        activity.suggestedInvocationPhrase = type.suggestedPhrase

        // Add command parameter for custom commands
        var userInfo: [String: Any] = [:]
        if let command = command {
            userInfo["command"] = command
        }
        if let serverName = serverName {
            userInfo["serverName"] = serverName
        }
        if !userInfo.isEmpty {
            activity.userInfo = userInfo
        }

        activity.becomeCurrent()

        if !donatedShortcuts.contains(type.rawValue) {
            donatedShortcuts.append(type.rawValue)
            saveDonatedShortcuts()
        }
        #endif
    }

    /// Donate all default shortcuts
    func donateAllShortcuts() {
        for type in ShortcutType.allCases {
            donateShortcut(type)
        }
    }

    /// Donate a shortcut for a specific server
    func donateServerShortcut(serverName: String) {
        donateShortcut(.connectServer, serverName: serverName)
    }

    // MARK: - Shortcut Handling

    /// Handle incoming shortcut activity
    func handleActivity(_ activity: NSUserActivity) -> ShortcutAction? {
        guard let typeString = ShortcutType(rawValue: activity.activityType) else {
            return nil
        }

        switch typeString {
        case .openTerminal:
            return .openTerminal

        case .connectServer:
            if let serverName = activity.userInfo?["serverName"] as? String {
                return .connectToServer(serverName)
            }
            return .openTerminal

        case .clearTerminal:
            return .runCommand("clear")

        case .customCommand:
            if let command = activity.userInfo?["command"] as? String {
                return .runCommand(command)
            }
            return .openTerminal
        }
    }

    enum ShortcutAction {
        case openTerminal
        case connectToServer(String)
        case runCommand(String)
    }

    // MARK: - Custom Command Shortcuts

    struct CustomShortcut: Identifiable, Codable {
        let id: UUID
        var name: String
        var command: String
        var phrase: String

        init(name: String, command: String, phrase: String) {
            self.id = UUID()
            self.name = name
            self.command = command
            self.phrase = phrase
        }
    }

    @Published var customShortcuts: [CustomShortcut] = [] {
        didSet {
            saveCustomShortcuts()
        }
    }

    func addCustomShortcut(name: String, command: String, phrase: String) {
        let shortcut = CustomShortcut(name: name, command: command, phrase: phrase)
        customShortcuts.append(shortcut)

        #if os(iOS)
        // Donate to Siri
        let activity = NSUserActivity(activityType: ShortcutType.customCommand.rawValue)
        activity.title = name
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.suggestedInvocationPhrase = phrase
        activity.userInfo = ["command": command]
        activity.becomeCurrent()
        #endif
    }

    func removeCustomShortcut(_ shortcut: CustomShortcut) {
        customShortcuts.removeAll { $0.id == shortcut.id }
    }

    // MARK: - Persistence

    private func loadDonatedShortcuts() {
        if let data = UserDefaults.standard.array(forKey: "donatedShortcuts") as? [String] {
            donatedShortcuts = data
        }
        loadCustomShortcuts()
    }

    private func saveDonatedShortcuts() {
        UserDefaults.standard.set(donatedShortcuts, forKey: "donatedShortcuts")
    }

    private func loadCustomShortcuts() {
        if let data = UserDefaults.standard.data(forKey: "customShortcuts"),
           let shortcuts = try? JSONDecoder().decode([CustomShortcut].self, from: data) {
            customShortcuts = shortcuts
        }
    }

    private func saveCustomShortcuts() {
        if let data = try? JSONEncoder().encode(customShortcuts) {
            UserDefaults.standard.set(data, forKey: "customShortcuts")
        }
    }
}

// MARK: - Siri Shortcuts Settings View

#if os(iOS)
struct SiriShortcutsSettingsView: View {
    @StateObject private var service = SiriShortcutsService.shared
    @State private var showingAddShortcut = false
    @State private var newName = ""
    @State private var newCommand = ""
    @State private var newPhrase = ""

    var body: some View {
        List {
            Section("Built-in Shortcuts") {
                ForEach(SiriShortcutsService.ShortcutType.allCases, id: \.rawValue) { type in
                    ShortcutRow(
                        icon: type.icon,
                        title: type.title,
                        phrase: type.suggestedPhrase,
                        isDonated: service.donatedShortcuts.contains(type.rawValue)
                    ) {
                        service.donateShortcut(type)
                    }
                }
            }

            Section("Custom Shortcuts") {
                ForEach(service.customShortcuts) { shortcut in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(shortcut.name)
                            .font(.headline)
                        Text(shortcut.command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("\"\(shortcut.phrase)\"")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            service.removeCustomShortcut(shortcut)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    showingAddShortcut = true
                } label: {
                    Label("Add Custom Shortcut", systemImage: "plus.circle")
                }
            }

            Section {
                Button("Add All to Siri") {
                    service.donateAllShortcuts()
                    HapticManager.shared.success()
                }
            }
        }
        .navigationTitle("Siri Shortcuts")
        .sheet(isPresented: $showingAddShortcut) {
            NavigationStack {
                Form {
                    TextField("Name", text: $newName)
                    TextField("Command", text: $newCommand)
                        .font(.system(.body, design: .monospaced))
                    TextField("Siri Phrase", text: $newPhrase)
                }
                .navigationTitle("New Shortcut")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingAddShortcut = false
                            clearForm()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            service.addCustomShortcut(
                                name: newName,
                                command: newCommand,
                                phrase: newPhrase
                            )
                            showingAddShortcut = false
                            clearForm()
                        }
                        .disabled(newName.isEmpty || newCommand.isEmpty || newPhrase.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func clearForm() {
        newName = ""
        newCommand = ""
        newPhrase = ""
    }
}

struct ShortcutRow: View {
    let icon: String
    let title: String
    let phrase: String
    let isDonated: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text("\"\(phrase)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isDonated {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Add") {
                    onAdd()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        SiriShortcutsSettingsView()
    }
}
#endif
