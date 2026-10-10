import Foundation

/// Handles persistent local storage of abbreviation snippets.
public final class LibraryStorage {
    public static let shared = LibraryStorage()

    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let customURL = fileURL {
            self.fileURL = customURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            let folderURL = appSupport.appendingPathComponent("AbbrEx", isDirectory: true)
            self.fileURL = folderURL.appendingPathComponent("library.json")
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder = JSONDecoder()

    /// Loads persisted abbreviations from disk.
    /// If the file does not exist yet, initializes with `AppConfig.defaultSnippets` and saves to disk.
    public func load() -> [ExpansionPayload] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            let defaults = AppConfig.defaultSnippets
            try? save(items: defaults)
            return defaults
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let items = try Self.decoder.decode([ExpansionPayload].self, from: data)
            return items
        } catch {
            print("Warning: Failed to load library from \(fileURL.path): \(error). Falling back to defaults.")
            return AppConfig.defaultSnippets
        }
    }

    /// Saves the current library of abbreviation payloads to disk atomically.
    public func save(items: [ExpansionPayload]) throws {
        let parentDir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        }
        let data = try Self.encoder.encode(items)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Deletes the persistent file from disk (useful for testing or cache resets).
    public func removeStorageFile() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
}
