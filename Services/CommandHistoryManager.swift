//
//  CommandHistoryManager.swift
//  Mobile Terminal
//
//  Offline command history storage using SQLite
//

import SwiftUI
import SQLite3

final class CommandHistoryManager: ObservableObject {
    static let shared = CommandHistoryManager()

    @Published var commands: [CommandEntry] = []

    private var db: OpaquePointer?
    private let maxEntries = 500

    struct CommandEntry: Identifiable, Hashable {
        let id: Int64
        let command: String
        let timestamp: Date
        let sessionId: String
    }

    private init() {
        openDatabase()
        createTable()
        loadCommands()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    private func getDatabasePath() -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("command_history.sqlite").path
    }

    private func openDatabase() {
        let path = getDatabasePath()
        if sqlite3_open(path, &db) != SQLITE_OK {
            print("Error opening database")
        }
    }

    private func createTable() {
        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS commands (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                command TEXT NOT NULL,
                timestamp REAL NOT NULL,
                session_id TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_timestamp ON commands(timestamp DESC);
        """

        if sqlite3_exec(db, createTableSQL, nil, nil, nil) != SQLITE_OK {
            print("Error creating table")
        }
    }

    func addCommand(_ command: String, sessionId: String = "default") {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Don't add duplicates of the most recent command
        if let lastCommand = commands.first, lastCommand.command == trimmed {
            return
        }

        let insertSQL = "INSERT INTO commands (command, timestamp, session_id) VALUES (?, ?, ?);"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (trimmed as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
            sqlite3_bind_text(statement, 3, (sessionId as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_DONE {
                let id = sqlite3_last_insert_rowid(db)
                let entry = CommandEntry(id: id, command: trimmed, timestamp: Date(), sessionId: sessionId)
                commands.insert(entry, at: 0)

                // Enforce max entries
                pruneOldEntries()
            }
        }
        sqlite3_finalize(statement)
    }

    private func loadCommands() {
        let selectSQL = "SELECT id, command, timestamp, session_id FROM commands ORDER BY timestamp DESC LIMIT \(maxEntries);"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            var loaded: [CommandEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let command = String(cString: sqlite3_column_text(statement, 1))
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                let sessionId = String(cString: sqlite3_column_text(statement, 3))

                loaded.append(CommandEntry(id: id, command: command, timestamp: timestamp, sessionId: sessionId))
            }
            commands = loaded
        }
        sqlite3_finalize(statement)
    }

    private func pruneOldEntries() {
        // Keep only the most recent maxEntries
        let deleteSQL = """
            DELETE FROM commands WHERE id NOT IN (
                SELECT id FROM commands ORDER BY timestamp DESC LIMIT \(maxEntries)
            );
        """
        sqlite3_exec(db, deleteSQL, nil, nil, nil)

        // Also prune in-memory list
        if commands.count > maxEntries {
            commands = Array(commands.prefix(maxEntries))
        }
    }

    func searchCommands(_ query: String) -> [CommandEntry] {
        guard !query.isEmpty else { return commands }

        let searchSQL = "SELECT id, command, timestamp, session_id FROM commands WHERE command LIKE ? ORDER BY timestamp DESC LIMIT 50;"
        var statement: OpaquePointer?
        var results: [CommandEntry] = []

        if sqlite3_prepare_v2(db, searchSQL, -1, &statement, nil) == SQLITE_OK {
            let pattern = "%\(query)%"
            sqlite3_bind_text(statement, 1, (pattern as NSString).utf8String, -1, nil)

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let command = String(cString: sqlite3_column_text(statement, 1))
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                let sessionId = String(cString: sqlite3_column_text(statement, 3))

                results.append(CommandEntry(id: id, command: command, timestamp: timestamp, sessionId: sessionId))
            }
        }
        sqlite3_finalize(statement)

        return results
    }

    func clearHistory() {
        let deleteSQL = "DELETE FROM commands;"
        sqlite3_exec(db, deleteSQL, nil, nil, nil)
        commands = []
    }

    func deleteCommand(_ entry: CommandEntry) {
        let deleteSQL = "DELETE FROM commands WHERE id = ?;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, entry.id)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        commands.removeAll { $0.id == entry.id }
    }
}
