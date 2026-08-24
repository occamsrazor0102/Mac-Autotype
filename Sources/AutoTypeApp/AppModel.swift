import AppKit
import AutoTypeCore
import Combine
import Foundation
import OSLog

struct PersistedSettings: Codable {
    var configuration: TypingConfiguration
    var shortcuts: ShortcutSet

    static let `default` = PersistedSettings(configuration: .default, shortcuts: .default)
}

private enum SettingsStore {
    static let key = "AutoType.settings.v2"

    static func load(defaults: UserDefaults = .standard) -> PersistedSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(PersistedSettings.self, from: data)
        else {
            return .default
        }
        var normalized = settings
        normalized.configuration.normalize()
        return normalized
    }

    static func save(_ settings: PersistedSettings, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct PlaceholderRequest: Identifiable {
    let id = UUID()
    let parsedTemplate: ParsedTemplate
    var values: [String: String]
}

struct ImportPreview: Identifiable {
    let id = UUID()
    let data: Data
    let collection: PresetCollection
}

@MainActor
final class AppModel: ObservableObject {
    @Published var draftText = ""
    @Published private(set) var presets: [Preset] = []
    @Published var selectedPresetID: UUID?
    @Published var searchQuery = ""
    @Published var configuration: TypingConfiguration
    @Published private(set) var state: TypingState = .idle
    @Published var selectedTargetProcessIdentifier: Int32?
    @Published private(set) var accessibilityTrusted = AccessibilityAuthorizer.isTrusted
    @Published var shortcuts: ShortcutSet
    @Published private(set) var launchAtLoginEnabled = LaunchAtLoginController.isEnabled
    @Published var placeholderRequest: PlaceholderRequest?
    @Published var importPreview: ImportPreview?
    @Published var alert: AppAlert?

    let targetTracker: TargetTracker

    private let presetStore: PresetStore
    private let templateRenderer = TemplateRenderer()
    private let eventSink = SystemEventSink()
    private let safetyMonitor = SystemSafetyMonitor()
    private let hotKeyManager = HotKeyManager()
    private let logger = Logger(subsystem: "io.github.occamsrazor0102.autotype", category: "state")

    private lazy var typingEngine = TypingEngine(
        eventSink: eventSink,
        safetyMonitor: safetyMonitor,
        stateHandler: { [weak self] state in
            await self?.receive(state)
        }
    )

    init(presetStore: PresetStore = PresetStore(), targetTracker: TargetTracker? = nil) {
        let settings = SettingsStore.load()
        configuration = settings.configuration
        shortcuts = settings.shortcuts
        self.presetStore = presetStore
        self.targetTracker = targetTracker ?? TargetTracker()

        hotKeyManager.handler = { [weak self] action in self?.handleHotKey(action) }
        do {
            try hotKeyManager.register(shortcuts)
        } catch {
            alert = AppAlert(title: "Shortcut unavailable", message: error.localizedDescription)
            shortcuts = .default
            try? hotKeyManager.register(shortcuts)
        }

        loadPresets()
    }

    var filteredPresets: [Preset] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return presets }
        return presets.filter { preset in
            preset.name.localizedCaseInsensitiveContains(query)
                || preset.text.localizedCaseInsensitiveContains(query)
                || preset.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var selectedPreset: Preset? {
        guard let selectedPresetID else { return nil }
        return presets.first { $0.id == selectedPresetID }
    }

    var activeTarget: TargetApplication? {
        targetTracker.target(processIdentifier: selectedTargetProcessIdentifier)
    }

    var progress: TypingProgress? {
        switch state {
        case let .typing(progress), let .paused(_, progress), let .completed(progress): progress
        case let .cancelled(progress), let .failed(_, progress): progress
        default: nil
        }
    }

    var canPauseOrResume: Bool {
        switch state {
        case .typing, .paused: true
        default: false
        }
    }

    var statusText: String {
        switch state {
        case .idle: "Ready"
        case let .countdown(seconds): "Starting in \(seconds)…"
        case let .typing(progress):
            "Typing \(Int(progress.fractionCompleted * 100))%"
        case let .paused(reason, _):
            pauseMessage(reason)
        case let .completed(progress):
            progress.unicodeFallbacks > 0
                ? "Complete · \(progress.unicodeFallbacks) Unicode fallback(s)"
                : "Complete"
        case .cancelled: "Stopped"
        case let .failed(message, _): "Failed: \(message)"
        }
    }

    var estimatedSecondsRemaining: TimeInterval? {
        guard let progress else { return nil }
        let remaining = max(progress.totalUnits - progress.completedUnits, 0)
        return Double(remaining) / configuration.normalized.charactersPerSecond
    }

    func loadPresets() {
        Task {
            do {
                presets = try await presetStore.load()
            } catch {
                alert = AppAlert(title: "Preset store unavailable", message: error.localizedDescription)
            }
        }
    }

    func selectPreset(_ id: UUID?) {
        selectedPresetID = id
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        draftText = preset.text
        if let override = preset.configurationOverride {
            configuration = override
        }
    }

    func saveNewPreset(name: String, tags: [String], includeConfiguration: Bool) {
        let preset = Preset(
            name: name,
            text: draftText,
            tags: tags,
            configurationOverride: includeConfiguration ? configuration : nil
        )
        persist(preset, selectingAfterSave: true)
    }

    func updateSelectedPreset() {
        guard var preset = selectedPreset else {
            alert = AppAlert(title: "No preset selected", message: "Use Save As to create a preset first.")
            return
        }
        preset.text = draftText
        if preset.configurationOverride != nil {
            preset.configurationOverride = configuration
        }
        persist(preset, selectingAfterSave: true)
    }

    func toggleFavorite(_ preset: Preset) {
        var updated = preset
        updated.isFavorite.toggle()
        persist(updated, selectingAfterSave: selectedPresetID == preset.id)
    }

    func deleteSelectedPreset() {
        guard let id = selectedPresetID else { return }
        Task {
            do {
                presets = try await presetStore.delete(id: id)
                selectedPresetID = nil
            } catch {
                alert = AppAlert(title: "Could not delete preset", message: error.localizedDescription)
            }
        }
    }

    func prepareStart() {
        guard !state.isActive else { return }
        guard !draftText.isEmpty else {
            alert = AppAlert(title: "Nothing to type", message: "Enter text or select a preset before starting.")
            return
        }

        do {
            let parsed = try templateRenderer.parse(draftText)
            if parsed.promptedPlaceholders.isEmpty {
                try startRenderedText(templateRenderer.render(parsed, values: [:]))
            } else {
                placeholderRequest = PlaceholderRequest(
                    parsedTemplate: parsed,
                    values: Dictionary(uniqueKeysWithValues: parsed.promptedPlaceholders.map { ($0, "") })
                )
            }
        } catch {
            alert = AppAlert(title: "Template error", message: error.localizedDescription)
        }
    }

    func confirmPlaceholders() {
        guard let request = placeholderRequest else { return }
        do {
            let rendered = try templateRenderer.render(request.parsedTemplate, values: request.values)
            placeholderRequest = nil
            try startRenderedText(rendered)
        } catch {
            alert = AppAlert(title: "Template error", message: error.localizedDescription)
        }
    }

    func setPlaceholderValue(_ value: String, for identifier: String) {
        guard var request = placeholderRequest else { return }
        request.values[identifier] = value
        placeholderRequest = request
    }

    func cancelPlaceholders() {
        placeholderRequest = nil
    }

    func pauseOrResume() {
        Task {
            switch state {
            case .typing:
                await typingEngine.pause()
            case .paused:
                if await !typingEngine.resume() {
                    alert = AppAlert(title: "Cannot resume", message: "Return focus to the selected target and ensure it is not a secure field.")
                }
            default:
                break
            }
        }
    }

    func stop() {
        Task { await typingEngine.stop() }
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityAuthorizer.isTrusted
    }

    func requestAccessibility() {
        _ = AccessibilityAuthorizer.requestAccess()
        refreshAccessibilityStatus()
    }

    func openAccessibilitySettings() {
        AccessibilityAuthorizer.openSystemSettings()
    }

    func saveSettings() {
        configuration.normalize()
        SettingsStore.save(PersistedSettings(configuration: configuration, shortcuts: shortcuts))
    }

    func updateShortcut(_ shortcut: GlobalShortcut, for action: ShortcutAction) {
        var candidate = shortcuts
        candidate[action] = shortcut
        do {
            try hotKeyManager.register(candidate)
            shortcuts = candidate
            saveSettings()
        } catch {
            alert = AppAlert(title: "Shortcut unavailable", message: error.localizedDescription)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginController.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLoginController.isEnabled
        } catch {
            launchAtLoginEnabled = LaunchAtLoginController.isEnabled
            alert = AppAlert(title: "Launch at login failed", message: error.localizedDescription)
        }
    }

    func makeExportData(selectedOnly: Bool) async -> Data? {
        do {
            let ids = selectedOnly ? selectedPresetID.map { Set([$0]) } : nil
            return try await presetStore.exportData(presetIDs: ids)
        } catch {
            alert = AppAlert(title: "Export failed", message: error.localizedDescription)
            return nil
        }
    }

    func prepareImport(data: Data) {
        Task {
            do {
                let collection = try await presetStore.previewImport(data)
                importPreview = ImportPreview(data: data, collection: collection)
            } catch {
                alert = AppAlert(title: "Import failed", message: error.localizedDescription)
            }
        }
    }

    func confirmImport() {
        guard let preview = importPreview else { return }
        Task {
            do {
                let result = try await presetStore.importData(preview.data)
                presets = try await presetStore.load()
                importPreview = nil
                alert = AppAlert(
                    title: "Import complete",
                    message: "Imported \(result.imported), skipped \(result.skippedIdentical), duplicated \(result.duplicatedConflicts) conflict(s)."
                )
            } catch {
                alert = AppAlert(title: "Import failed", message: error.localizedDescription)
            }
        }
    }

    private func startRenderedText(_ text: String) throws {
        refreshAccessibilityStatus()
        guard accessibilityTrusted else {
            throw AppStartError.accessibilityRequired
        }
        guard let target = activeTarget else {
            throw AppStartError.targetRequired
        }

        let job = TypingJob(text: text, target: target, configuration: configuration)
        Task {
            do {
                try await typingEngine.start(job)
            } catch {
                alert = AppAlert(title: "Could not start", message: error.localizedDescription)
            }
        }
    }

    private func persist(_ preset: Preset, selectingAfterSave: Bool) {
        Task {
            do {
                presets = try await presetStore.upsert(preset)
                if selectingAfterSave { selectedPresetID = preset.id }
            } catch {
                alert = AppAlert(title: "Could not save preset", message: error.localizedDescription)
            }
        }
    }

    private func receive(_ newState: TypingState) {
        state = newState
        logger.info("Typing state changed: \(self.logLabel(for: newState), privacy: .public)")
        WindowCoordinator.shared.updateHUD(model: self)
    }

    private func handleHotKey(_ action: ShortcutAction) {
        switch action {
        case .showApp:
            WindowCoordinator.shared.showEditor(model: self)
        case .start:
            prepareStart()
            if placeholderRequest != nil {
                WindowCoordinator.shared.showEditor(model: self)
            }
        case .pauseResume:
            pauseOrResume()
        case .stop:
            stop()
        }
    }

    private func pauseMessage(_ reason: PauseReason) -> String {
        switch reason {
        case .user: "Paused"
        case let .focusChanged(expected): "Paused · Return to \(expected)"
        case .secureField: "Paused · Secure field detected"
        case .accessibilityPermissionLost: "Paused · Accessibility permission required"
        case .targetTerminated: "Paused · Target app closed"
        }
    }

    private func logLabel(for state: TypingState) -> String {
        switch state {
        case .idle: "idle"
        case .countdown: "countdown"
        case .typing: "typing"
        case .paused: "paused"
        case .completed: "completed"
        case .cancelled: "cancelled"
        case .failed: "failed"
        }
    }
}

private enum AppStartError: LocalizedError {
    case accessibilityRequired
    case targetRequired

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            "Accessibility permission is required before AutoType can send keystrokes."
        case .targetRequired:
            "Choose a running target application before starting."
        }
    }
}
