import AppKit
import AutoTypeCore
import SwiftUI
import UniformTypeIdentifiers

struct QuickPanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AutoType", systemImage: "keyboard")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(model.accessibilityTrusted ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .help(model.accessibilityTrusted ? "Accessibility enabled" : "Accessibility required")
            }

            Text(model.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Target: \(model.activeTarget?.name ?? "Choose in Editor")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let progress = model.progress, model.state.isActive {
                ProgressView(value: progress.fractionCompleted)
            }

            HStack {
                Button("Open Editor") {
                    WindowCoordinator.shared.showEditor(model: model)
                }
                .keyboardShortcut(.defaultAction)

                Spacer()

                if model.state.isActive {
                    Button("Pause / Resume") { model.pauseOrResume() }
                        .disabled(!model.canPauseOrResume)
                    Button("Stop", role: .destructive) { model.stop() }
                } else {
                    Button("Start") {
                        model.prepareStart()
                        if model.placeholderRequest != nil {
                            WindowCoordinator.shared.showEditor(model: model)
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.draftText.isEmpty)
                }
            }

            Divider()

            HStack {
                Button("Settings…") {
                    WindowCoordinator.shared.showSettings(model: model)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 310)
        .onAppear { model.refreshAccessibilityStatus() }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }
}

struct EditorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSavePreset = false
    @State private var showingDeleteConfirmation = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument = PresetExportDocument(data: Data())

    var body: some View {
        HSplitView {
            presetSidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 290)
            editor
                .frame(minWidth: 480)
        }
        .frame(minWidth: 720, minHeight: 540)
        .onAppear {
            model.refreshAccessibilityStatus()
            model.targetTracker.refresh()
        }
        .onChange(of: model.configuration) { _ in model.saveSettings() }
        .sheet(isPresented: $showingSavePreset) {
            SavePresetView(isPresented: $showingSavePreset)
                .environmentObject(model)
        }
        .sheet(isPresented: Binding(
            get: { model.placeholderRequest != nil },
            set: { if !$0 { model.cancelPlaceholders() } }
        )) {
            PlaceholderValuesView()
                .environmentObject(model)
        }
        .sheet(isPresented: Binding(
            get: { model.importPreview != nil },
            set: { if !$0 { model.importPreview = nil } }
        )) {
            ImportPreviewView()
                .environmentObject(model)
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog(
            "Delete this preset?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Preset", role: .destructive) { model.deleteSelectedPreset() }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case let .success(url):
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                    if let fileSize, fileSize > PresetStore.maximumImportBytes {
                        throw PresetStoreError.fileTooLarge
                    }
                    model.prepareImport(data: try Data(contentsOf: url, options: .mappedIfSafe))
                } catch {
                    model.alert = AppAlert(title: "Import failed", message: error.localizedDescription)
                }
            case let .failure(error):
                model.alert = AppAlert(title: "Import failed", message: error.localizedDescription)
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "AutoType-Presets"
        ) { result in
            if case let .failure(error) = result {
                model.alert = AppAlert(title: "Export failed", message: error.localizedDescription)
            }
        }
    }

    private var presetSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Presets")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Import…") { showingImporter = true }
                    Button("Export All…") { exportPresets(selectedOnly: false) }
                    Button("Export Selected…") { exportPresets(selectedOnly: true) }
                        .disabled(model.selectedPresetID == nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
            .padding(12)

            TextField("Search presets", text: $model.searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.filteredPresets) { preset in
                        PresetRow(
                            preset: preset,
                            selected: model.selectedPresetID == preset.id,
                            select: { model.selectPreset(preset.id) },
                            toggleFavorite: { model.toggleFavorite(preset) }
                        )
                    }
                }
                .padding(8)
            }

            Divider()

            HStack {
                Button {
                    showingSavePreset = true
                } label: {
                    Label("Save As", systemImage: "plus")
                }
                Button("Update") { model.updateSelectedPreset() }
                    .disabled(model.selectedPresetID == nil)
                Spacer()
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(model.selectedPresetID == nil)
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedPreset?.name ?? "Unsaved Draft")
                        .font(.title2.weight(.semibold))
                    Text("Draft text stays in memory unless you explicitly save it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                targetPicker
            }

            if !model.accessibilityTrusted {
                AccessibilityBanner()
                    .environmentObject(model)
            }

            TextEditor(text: $model.draftText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .frame(minHeight: 230)

            Text("Templates: {{name}} prompts once. Built-ins: {{date}}, {{time}}, {{datetime}}. Escape with \\{{.")
                .font(.caption)
                .foregroundStyle(.secondary)

            typingControls

            Divider()

            runControls
        }
        .padding(16)
    }

    private var targetPicker: some View {
        Picker("Target", selection: $model.selectedTargetProcessIdentifier) {
            Text(model.targetTracker.lastExternalTarget.map { "Last active: \($0.name)" } ?? "Last active application")
                .tag(Int32?.none)
            Divider()
            ForEach(model.targetTracker.availableTargets) { target in
                Text(target.name).tag(Optional(target.processIdentifier))
            }
        }
        .frame(maxWidth: 260)
        .disabled(model.state.isActive)
    }

    private var typingControls: some View {
        GroupBox("Typing") {
            VStack(spacing: 10) {
                HStack {
                    Picker("Mode", selection: $model.configuration.inputMode) {
                        ForEach(InputMode.allCases) { mode in Text(mode.displayName).tag(mode) }
                    }
                    Spacer()
                    Picker("Tabs", selection: tabKindBinding) {
                        Text("Spaces").tag("spaces")
                        Text("Tab key").tag("physical")
                        Text("Skip").tag("skip")
                    }
                    if case let .spaces(count) = model.configuration.tabBehavior {
                        Stepper("\(count)", value: tabSpacesBinding, in: 1...8)
                            .frame(width: 82)
                    }
                }

                HStack {
                    Stepper("Speed: \(Int(model.configuration.charactersPerSecond)) chars/sec", value: $model.configuration.charactersPerSecond, in: 1...100, step: 1)
                    Spacer()
                    Stepper("Start: \(Int(model.configuration.startDelay))s", value: $model.configuration.startDelay, in: 0...30, step: 1)
                }

                HStack {
                    Stepper("Line delay: \(model.configuration.lineDelay, specifier: "%.1f")s", value: $model.configuration.lineDelay, in: 0...5, step: 0.1)
                    Spacer()
                    Stepper("Repeat: \(model.configuration.repeatCount)×", value: $model.configuration.repeatCount, in: 1...100)
                    if model.configuration.repeatCount > 1 {
                        Stepper("Every \(Int(model.configuration.repeatInterval))s", value: $model.configuration.repeatInterval, in: 0...60, step: 1)
                    }
                }
            }
            .padding(.top, 4)
        }
        .disabled(model.state.isActive)
    }

    private var runControls: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.statusText)
                    .font(.headline)
                if let remaining = model.estimatedSecondsRemaining, model.state.isActive {
                    Text("About \(Int(ceil(remaining))) seconds remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let progress = model.progress, model.state.isActive {
                ProgressView(value: progress.fractionCompleted)
                    .frame(width: 120)
            }

            Button("Pause / Resume") { model.pauseOrResume() }
                .disabled(!model.canPauseOrResume)
            Button("Stop", role: .destructive) { model.stop() }
                .disabled(!model.state.isActive)
            Button("Start Typing") { model.prepareStart() }
                .buttonStyle(.borderedProminent)
                .disabled(model.state.isActive || model.draftText.isEmpty)
        }
    }

    private var tabKindBinding: Binding<String> {
        Binding(
            get: {
                switch model.configuration.tabBehavior {
                case .spaces: "spaces"
                case .physical: "physical"
                case .skip: "skip"
                }
            },
            set: { value in
                switch value {
                case "physical": model.configuration.tabBehavior = .physical
                case "skip": model.configuration.tabBehavior = .skip
                default: model.configuration.tabBehavior = .spaces(4)
                }
            }
        )
    }

    private var tabSpacesBinding: Binding<Int> {
        Binding(
            get: { if case let .spaces(count) = model.configuration.tabBehavior { count } else { 4 } },
            set: { model.configuration.tabBehavior = .spaces($0) }
        )
    }

    private func exportPresets(selectedOnly: Bool) {
        Task {
            guard let data = await model.makeExportData(selectedOnly: selectedOnly) else { return }
            exportDocument = PresetExportDocument(data: data)
            showingExporter = true
        }
    }
}

private struct PresetRow: View {
    let preset: Preset
    let selected: Bool
    let select: () -> Void
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleFavorite) {
                Image(systemName: preset.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(preset.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: select) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .lineLimit(1)
                    if !preset.tags.isEmpty {
                        Text(preset.tags.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct AccessibilityBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
            Text("Accessibility permission is required to send keystrokes.")
                .font(.callout)
            Spacer()
            Button("Request Access") { model.requestAccessibility() }
            Button("Open Settings") { model.openAccessibilitySettings() }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SavePresetView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var tags = ""
    @State private var includeConfiguration = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Preset")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $name)
            TextField("Tags, separated by commas", text: $tags)
            Toggle("Save the current typing settings with this preset", isOn: $includeConfiguration)
            Text("Saved presets are stored as local plaintext. Do not save passwords, API keys, or other secrets.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Save") {
                    model.saveNewPreset(
                        name: name,
                        tags: tags.split(separator: ",").map(String.init),
                        includeConfiguration: includeConfiguration
                    )
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct PlaceholderValuesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Template Values")
                .font(.title2.weight(.semibold))
            Text("Values are used for this run only and are not saved automatically.")
                .foregroundStyle(.secondary)

            if let request = model.placeholderRequest {
                ForEach(request.parsedTemplate.promptedPlaceholders, id: \.self) { identifier in
                    TextField(identifier, text: Binding(
                        get: { model.placeholderRequest?.values[identifier] ?? "" },
                        set: { model.setPlaceholderValue($0, for: identifier) }
                    ))
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { model.cancelPlaceholders() }
                Button("Continue") { model.confirmPlaceholders() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct ImportPreviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Presets")
                .font(.title2.weight(.semibold))
            if let preview = model.importPreview {
                Text("\(preview.collection.presets.count) preset(s) passed validation.")
                List(preview.collection.presets.prefix(20)) { preset in
                    VStack(alignment: .leading) {
                        Text(preset.name)
                        Text(preset.tags.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 220)
                Text("Conflicting IDs are imported as new presets; existing presets are never overwritten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.importPreview = nil }
                Button("Import") { model.confirmImport() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    HStack {
                        Text(model.accessibilityTrusted ? "Enabled" : "Required")
                            .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                        if !model.accessibilityTrusted {
                            Button("Request") { model.requestAccessibility() }
                            Button("Open Settings") { model.openAccessibilitySettings() }
                        }
                    }
                }
                Toggle("Launch AutoType at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            Section("Global Shortcuts") {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorderView(
                            shortcut: model.shortcuts[action],
                            onRecord: { model.updateShortcut($0, for: action) }
                        )
                        .frame(width: 150, height: 28)
                    }
                }
                Text("Every shortcut must include Control, Option, Shift, or Command. Conflicting shortcuts are rejected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("AutoType has no telemetry or network client. Draft text remains in memory, and only explicitly saved presets are written to disk as plaintext JSON.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 520, height: 480)
        .onAppear { model.refreshAccessibilityStatus() }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }
}

struct StatusHUDView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: hudIcon)
                    .foregroundStyle(hudColor)
                Text(model.statusText)
                    .font(.headline)
                Spacer()
            }
            if let progress = model.progress {
                ProgressView(value: progress.fractionCompleted)
            }
            Text("Target: \(model.activeTarget?.name ?? "None") · Stop: \(model.shortcuts.stop.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12)))
    }

    private var hudIcon: String {
        switch model.state {
        case .paused: "pause.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .completed: "checkmark.circle.fill"
        default: "keyboard.fill"
        }
    }

    private var hudColor: Color {
        switch model.state {
        case .paused: .orange
        case .failed: .red
        case .completed: .green
        default: .accentColor
        }
    }
}

struct PresetExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let onRecord: (GlobalShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onRecord = onRecord
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onRecord = onRecord
        button.shortcut = shortcut
    }
}

private final class ShortcutRecorderButton: NSButton {
    var onRecord: ((GlobalShortcut) -> Void)?
    var shortcut: GlobalShortcut = .init(keyCode: 0, carbonModifiers: 0) {
        didSet { if !recording { title = shortcut.displayName } }
    }
    private var recording = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc private func beginRecording() {
        recording = true
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            finishRecording()
            return
        }
        guard let captured = GlobalShortcut.from(event: event) else {
            NSSound.beep()
            return
        }
        onRecord?(captured)
        finishRecording(with: captured)
    }

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }

    private func finishRecording(with recorded: GlobalShortcut? = nil) {
        recording = false
        title = (recorded ?? shortcut).displayName
    }
}
