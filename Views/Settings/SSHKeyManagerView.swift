//
//  SSHKeyManagerView.swift
//  Mobile Terminal
//
//  UI for managing SSH keys
//

import SwiftUI
import UniformTypeIdentifiers

struct SSHKeyManagerView: View {
    @State private var showingImportSheet = false
    @State private var showingKeyDetail: SSHKey?
    @State private var showingDeleteConfirmation = false
    @State private var keyToDelete: SSHKey?
    @State private var keys: [SSHKey] = []

    var body: some View {
        List {
            if keys.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No SSH Keys", systemImage: "key")
                    } description: {
                        Text("Import your SSH keys to use for authentication")
                    } actions: {
                        Button("Import Key") {
                            showingImportSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Section("Your Keys") {
                    ForEach(keys) { key in
                        SSHKeyRowView(key: key) {
                            showingKeyDetail = key
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                keyToDelete = key
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showingImportSheet = true
                    } label: {
                        Label("Import SSH Key", systemImage: "square.and.arrow.down")
                    }
                }
            }

            Section("About SSH Keys") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SSH keys provide secure, passwordless authentication to your servers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("To create a new key pair, use your computer's terminal:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("ssh-keygen -t ed25519 -C \"your@email.com\"")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(6)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("SSH Keys")
        .onAppear {
            refreshKeys()
        }
        .sheet(isPresented: $showingImportSheet, onDismiss: {
            refreshKeys()
        }) {
            SSHKeyImportView()
        }
        .sheet(item: $showingKeyDetail) { key in
            NavigationStack {
                SSHKeyDetailView(key: key)
            }
        }
        .confirmationDialog(
            "Delete SSH Key?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let key = keyToDelete {
                    SSHKeyManager.shared.deleteKey(key)
                    refreshKeys()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let key = keyToDelete {
                Text("Delete \"\(key.name)\"? This cannot be undone.")
            }
        }
    }

    private func refreshKeys() {
        keys = SSHKeyManager.shared.keys
    }
}

// MARK: - SSH Key Row View

struct SSHKeyRowView: View {
    let key: SSHKey
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: "key.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(key.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text(key.keyType.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)

                        if let comment = key.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if key.hasPrivateKey {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SSH Key Import View

struct SSHKeyImportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var keyName = ""
    @State private var publicKey = ""
    @State private var privateKey = ""
    @State private var passphrase = ""
    @State private var showPassphrase = false
    @State private var importError: String?
    @State private var showingFilePicker = false
    @State private var isImportingPublic = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Key Name") {
                    TextField("My SSH Key", text: $keyName)
                }

                Section("Public Key") {
                    TextEditor(text: $publicKey)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 100)

                    Button {
                        isImportingPublic = true
                        showingFilePicker = true
                    } label: {
                        Label("Import from File", systemImage: "doc")
                    }

                    if !publicKey.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Public key loaded")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Private Key (Optional)") {
                    TextEditor(text: $privateKey)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 100)

                    Button {
                        isImportingPublic = false
                        showingFilePicker = true
                    } label: {
                        Label("Import from File", systemImage: "doc")
                    }

                    if !privateKey.isEmpty {
                        HStack {
                            if showPassphrase {
                                TextField("Passphrase", text: $passphrase)
                            } else {
                                SecureField("Passphrase (if encrypted)", text: $passphrase)
                            }

                            Button {
                                showPassphrase.toggle()
                            } label: {
                                Image(systemName: showPassphrase ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Private key loaded (stored securely)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = importError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("Your private key will be stored securely in the device Keychain and never leaves your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import SSH Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importKey()
                    }
                    .disabled(keyName.isEmpty || publicKey.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.text, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }

    private func importKey() {
        importError = nil

        do {
            _ = try SSHKeyManager.shared.importKey(
                name: keyName,
                publicKey: publicKey,
                privateKey: privateKey,
                passphrase: passphrase.isEmpty ? nil : passphrase
            )
            dismiss()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                if isImportingPublic {
                    publicKey = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if keyName.isEmpty {
                        keyName = url.deletingPathExtension().lastPathComponent
                    }
                } else {
                    privateKey = content
                }
            } catch {
                importError = "Failed to read file: \(error.localizedDescription)"
            }

        case .failure(let error):
            importError = "Failed to select file: \(error.localizedDescription)"
        }
    }
}

// MARK: - SSH Key Detail View

struct SSHKeyDetailView: View {
    let key: SSHKey

    @Environment(\.dismiss) private var dismiss
    @State private var showingCopiedToast = false

    var body: some View {
        List {
            Section("Key Information") {
                LabeledContent("Name", value: key.name)
                LabeledContent("Type", value: key.keyType.rawValue)
                LabeledContent("Created", value: key.createdAt.formatted(date: .abbreviated, time: .shortened))

                if let lastUsed = key.lastUsed {
                    LabeledContent("Last Used", value: lastUsed.formatted(date: .abbreviated, time: .shortened))
                }

                if let comment = key.comment, !comment.isEmpty {
                    LabeledContent("Comment", value: comment)
                }
            }

            Section("Fingerprint") {
                Text(SSHKeyManager.shared.getFingerprint(for: key))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section("Public Key") {
                Text(key.publicKey)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                Button {
                    UIPasteboard.general.string = key.publicKey
                    showingCopiedToast = true
                    HapticManager.shared.success()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showingCopiedToast = false
                    }
                } label: {
                    Label("Copy Public Key", systemImage: "doc.on.doc")
                }
            }

            Section("Status") {
                HStack {
                    Text("Private Key")
                    Spacer()
                    if key.hasPrivateKey {
                        Label("Stored Securely", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Available", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if key.hasPrivateKey {
                    HStack {
                        Text("Passphrase")
                        Spacer()
                        if SSHKeyManager.shared.hasPassphrase(for: key.id) {
                            Label("Protected", systemImage: "lock.fill")
                                .foregroundStyle(.blue)
                        } else {
                            Text("None")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Text("Add this public key to your server's ~/.ssh/authorized_keys file to enable passwordless authentication.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Key Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showingCopiedToast {
                Text("Copied to clipboard")
                    .font(.subheadline)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: showingCopiedToast)
    }
}

#Preview {
    NavigationStack {
        SSHKeyManagerView()
    }
}
