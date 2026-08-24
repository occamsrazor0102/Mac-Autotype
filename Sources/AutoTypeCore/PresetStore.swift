import Foundation

public enum PresetStoreError: LocalizedError, Equatable, Sendable {
    case unsupportedSchema(Int)
    case fileTooLarge
    case invalidPreset(String)
    case corruptStore

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "This preset file uses unsupported schema version \(version)."
        case .fileTooLarge:
            "The preset file is larger than the 10 MB import limit."
        case let .invalidPreset(reason):
            "A preset is invalid: \(reason)"
        case .corruptStore:
            "The local preset store could not be read. The original file was left untouched."
        }
    }
}

public actor PresetStore {
    public static let maximumImportBytes = 10 * 1_024 * 1_024
    public static let maximumPresetTextBytes = 1 * 1_024 * 1_024

    public let fileURL: URL
    private var cache: [Preset]?

    public init(fileURL: URL = PresetStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("io.github.occamsrazor0102.autotype", isDirectory: true)
            .appendingPathComponent("presets.json", isDirectory: false)
    }

    public func load() throws -> [Preset] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = []
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let collection = try decodeCollection(from: data)
            cache = collection.presets
            return collection.presets
        } catch let error as PresetStoreError {
            throw error
        } catch {
            throw PresetStoreError.corruptStore
        }
    }

    @discardableResult
    public func upsert(_ preset: Preset) throws -> [Preset] {
        try Self.validate(preset)
        var presets = try load()
        var normalized = preset
        normalized.updatedAt = Date()

        if let index = presets.firstIndex(where: { $0.id == normalized.id }) {
            normalized.createdAt = presets[index].createdAt
            presets[index] = normalized
        } else {
            presets.append(normalized)
        }

        try persist(presets)
        return presets
    }

    @discardableResult
    public func delete(id: UUID) throws -> [Preset] {
        var presets = try load()
        presets.removeAll { $0.id == id }
        try persist(presets)
        return presets
    }

    public func exportData(presetIDs: Set<UUID>? = nil) throws -> Data {
        let presets = try load()
        let selected: [Preset]
        if let presetIDs {
            selected = presets.filter { presetIDs.contains($0.id) }
        } else {
            selected = presets
        }

        return try Self.encoder(prettyPrinted: true).encode(PresetCollection(presets: selected))
    }

    public func previewImport(_ data: Data) throws -> PresetCollection {
        try decodeCollection(from: data)
    }

    @discardableResult
    public func importData(_ data: Data, now: Date = Date()) throws -> ImportResult {
        let incoming = try decodeCollection(from: data).presets
        var existing = try load()
        var imported = 0
        var skipped = 0
        var conflicts = 0

        for preset in incoming {
            if let existingPreset = existing.first(where: { $0.id == preset.id }) {
                if existingPreset == preset {
                    skipped += 1
                    continue
                }

                var duplicate = preset
                duplicate.id = UUID()
                duplicate.name = Self.importedName(for: duplicate.name, existing: existing)
                duplicate.createdAt = now
                duplicate.updatedAt = now
                existing.append(duplicate)
                imported += 1
                conflicts += 1
            } else {
                existing.append(preset)
                imported += 1
            }
        }

        try persist(existing)
        return ImportResult(imported: imported, skippedIdentical: skipped, duplicatedConflicts: conflicts)
    }

    @discardableResult
    public func recoverCorruptStore(now: Date = Date()) throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = []
            return nil
        }

        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("presets.corrupt-\(stamp).json")
        try FileManager.default.moveItem(at: fileURL, to: backupURL)
        cache = []
        try persist([])
        return backupURL
    }

    private func decodeCollection(from data: Data) throws -> PresetCollection {
        guard data.count <= Self.maximumImportBytes else { throw PresetStoreError.fileTooLarge }

        let collection: PresetCollection
        do {
            collection = try Self.decoder().decode(PresetCollection.self, from: data)
        } catch {
            throw PresetStoreError.corruptStore
        }

        guard collection.schemaVersion == PresetCollection.currentSchemaVersion else {
            throw PresetStoreError.unsupportedSchema(collection.schemaVersion)
        }
        try collection.presets.forEach(Self.validate)
        return collection
    }

    private func persist(_ presets: [Preset]) throws {
        try presets.forEach(Self.validate)
        let collection = PresetCollection(presets: presets.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        })
        let data = try Self.encoder(prettyPrinted: true).encode(collection)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        cache = collection.presets
    }

    private static func validate(_ preset: Preset) throws {
        guard !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PresetStoreError.invalidPreset("the name is empty")
        }
        guard preset.name.count <= 120 else {
            throw PresetStoreError.invalidPreset("the name exceeds 120 characters")
        }
        guard preset.text.lengthOfBytes(using: .utf8) <= maximumPresetTextBytes else {
            throw PresetStoreError.invalidPreset("the text exceeds 1 MB")
        }
        guard preset.tags.count <= 50, preset.tags.allSatisfy({ $0.count <= 50 }) else {
            throw PresetStoreError.invalidPreset("tags exceed the supported limits")
        }
    }

    private static func importedName(for requestedName: String, existing: [Preset]) -> String {
        let names = Set(existing.map { $0.name.lowercased() })
        let base = "\(requestedName) (Imported)"
        guard names.contains(base.lowercased()) else { return base }

        var suffix = 2
        while names.contains("\(base) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }

    private static func encoder(prettyPrinted: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
