//
//  FileManager+Extensions.swift
//  Mobile Terminal
//
//  FileManager extensions for common directory paths
//

import Foundation

extension FileManager {
    /// Returns the temporary directory URL (static accessor)
    static var appTemporaryDirectory: URL {
        URL(filePath: NSTemporaryDirectory())
    }

    /// Returns the documents directory URL
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Returns the caches directory URL
    static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    }

    /// Creates the SanatanStories output directory if needed
    static func ensureOutputDirectory() throws -> URL {
        let outputDir = documentsDirectory.appendingPathComponent("SanatanStories", isDirectory: true)

        if !FileManager.default.fileExists(atPath: outputDir.path) {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }

        return outputDir
    }

    /// Creates a unique temporary file URL with the given extension
    static func uniqueTemporaryFile(withExtension ext: String) -> URL {
        appTemporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }

    /// Removes all temporary files created by the app
    static func cleanupTemporaryFiles() {
        let tempDir = appTemporaryDirectory

        do {
            let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        } catch {
            print("Failed to cleanup temporary files: \(error)")
        }
    }
}

