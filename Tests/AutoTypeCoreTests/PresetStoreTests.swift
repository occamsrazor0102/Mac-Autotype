import Foundation
import Testing
@testable import AutoTypeCore

@Test func storePersistsOnlyExplicitUpserts() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let fileURL = temporaryDirectory.appendingPathComponent("presets.json")
    let store = PresetStore(fileURL: fileURL)

    #expect(try await store.load() == [])
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))

    let preset = Preset(name: "Greeting", text: "Hello {{name}}")
    _ = try await store.upsert(preset)

    let reloaded = PresetStore(fileURL: fileURL)
    let saved = try await reloaded.load()
    #expect(saved.count == 1)
    #expect(saved.first?.id == preset.id)
    #expect(saved.first?.text == preset.text)
    let filePermissions = try #require(
        FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
    )
    let directoryPermissions = try #require(
        FileManager.default.attributesOfItem(atPath: temporaryDirectory.path)[.posixPermissions] as? NSNumber
    )
    #expect(filePermissions.intValue & 0o777 == 0o600)
    #expect(directoryPermissions.intValue & 0o777 == 0o700)
}

@Test func exportImportRoundTripAndConflictDuplication() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let sourceStore = PresetStore(fileURL: temporaryDirectory.appendingPathComponent("source.json"))
    let original = Preset(name: "Form", text: "Original")
    _ = try await sourceStore.upsert(original)
    let exported = try await sourceStore.exportData()

    let destinationStore = PresetStore(fileURL: temporaryDirectory.appendingPathComponent("destination.json"))
    let firstImport = try await destinationStore.importData(exported)
    #expect(firstImport.imported == 1)
    let identical = try await destinationStore.importData(exported)
    #expect(identical == ImportResult(imported: 0, skippedIdentical: 1, duplicatedConflicts: 0))

    var changed = try #require(try await sourceStore.load().first)
    changed.text = "Changed"
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let changedData = try encoder.encode(PresetCollection(presets: [changed]))
    let conflict = try await destinationStore.importData(changedData, now: Date(timeIntervalSince1970: 10))

    #expect(conflict.imported == 1)
    #expect(conflict.duplicatedConflicts == 1)
    let presets = try await destinationStore.load()
    #expect(presets.count == 2)
    #expect(presets.contains { $0.name == "Form (Imported)" && $0.text == "Changed" })
}

@Test func rejectsUnsupportedSchemaAndPreservesCorruptFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let fileURL = temporaryDirectory.appendingPathComponent("presets.json")
    let unsupported = Data(#"{"schemaVersion":99,"presets":[]}"#.utf8)
    try unsupported.write(to: fileURL)
    let store = PresetStore(fileURL: fileURL)

    await #expect(throws: PresetStoreError.unsupportedSchema(99)) {
        _ = try await store.load()
    }
    #expect(try Data(contentsOf: fileURL) == unsupported)
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AutoTypeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
