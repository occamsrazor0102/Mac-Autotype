import AppKit
import Carbon
import Foundation

enum ShortcutAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case showApp
    case start
    case pauseResume
    case stop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .showApp: "Show AutoType"
        case .start: "Start typing"
        case .pauseResume: "Pause or resume"
        case .stop: "Emergency stop"
        }
    }

    var numericID: UInt32 {
        switch self {
        case .showApp: 1
        case .start: 2
        case .pauseResume: 3
        case .stop: 4
        }
    }

    init?(numericID: UInt32) {
        guard let action = Self.allCases.first(where: { $0.numericID == numericID }) else { return nil }
        self = action
    }
}

struct GlobalShortcut: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    var displayName: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    static func from(event: NSEvent) -> GlobalShortcut? {
        let deviceIndependent = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if deviceIndependent.contains(.control) { modifiers |= UInt32(controlKey) }
        if deviceIndependent.contains(.option) { modifiers |= UInt32(optionKey) }
        if deviceIndependent.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if deviceIndependent.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers != 0 else { return nil }
        return GlobalShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
    }

    private static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
            50: "`", 51: "⌫", 53: "Esc", 96: "F5", 97: "F6", 98: "F7",
            99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
            118: "F4", 120: "F2", 122: "F1"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

struct ShortcutSet: Codable, Equatable {
    var showApp: GlobalShortcut
    var start: GlobalShortcut
    var pauseResume: GlobalShortcut
    var stop: GlobalShortcut

    static let `default` = ShortcutSet(
        showApp: GlobalShortcut(keyCode: 0, carbonModifiers: UInt32(controlKey | optionKey)),
        start: GlobalShortcut(keyCode: 36, carbonModifiers: UInt32(controlKey | optionKey)),
        pauseResume: GlobalShortcut(keyCode: 49, carbonModifiers: UInt32(controlKey | optionKey)),
        stop: GlobalShortcut(keyCode: 53, carbonModifiers: UInt32(controlKey | optionKey))
    )

    subscript(action: ShortcutAction) -> GlobalShortcut {
        get {
            switch action {
            case .showApp: showApp
            case .start: start
            case .pauseResume: pauseResume
            case .stop: stop
            }
        }
        set {
            switch action {
            case .showApp: showApp = newValue
            case .start: start = newValue
            case .pauseResume: pauseResume = newValue
            case .stop: stop = newValue
            }
        }
    }
}

enum HotKeyError: LocalizedError {
    case duplicateShortcut
    case registrationFailed(action: ShortcutAction, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .duplicateShortcut:
            "Each global shortcut must be unique."
        case let .registrationFailed(action, _):
            "The shortcut for “\(action.title)” is already used by macOS or another application."
        }
    }
}

@MainActor
final class HotKeyManager {
    typealias Handler = (ShortcutAction) -> Void

    var handler: Handler?
    private var references: [ShortcutAction: SendableHotKeyReference] = [:]
    private var eventHandlerReference: SendableEventHandlerReference?
    private var registeredShortcuts: ShortcutSet?

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var reference: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            autoTypeHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &reference
        )
        eventHandlerReference = reference.map { SendableEventHandlerReference(value: $0) }
    }

    deinit {
        references.values.forEach { _ = UnregisterEventHotKey($0.value) }
        if let eventHandlerReference { RemoveEventHandler(eventHandlerReference.value) }
    }

    func register(_ shortcuts: ShortcutSet) throws {
        let allShortcuts = ShortcutAction.allCases.map { shortcuts[$0] }
        guard Set(allShortcuts).count == allShortcuts.count else { throw HotKeyError.duplicateShortcut }

        let previous = registeredShortcuts
        unregisterAll()

        do {
            for action in ShortcutAction.allCases {
                var reference: EventHotKeyRef?
                let identifier = EventHotKeyID(signature: 0x41545632, id: action.numericID) // ATV2
                let shortcut = shortcuts[action]
                let status = RegisterEventHotKey(
                    shortcut.keyCode,
                    shortcut.carbonModifiers,
                    identifier,
                    GetApplicationEventTarget(),
                    0,
                    &reference
                )
                guard status == noErr, let reference else {
                    throw HotKeyError.registrationFailed(action: action, status: status)
                }
                references[action] = SendableHotKeyReference(value: reference)
            }
            registeredShortcuts = shortcuts
        } catch {
            unregisterAll()
            if let previous { try? register(previous) }
            throw error
        }
    }

    private func unregisterAll() {
        references.values.forEach { _ = UnregisterEventHotKey($0.value) }
        references.removeAll()
        registeredShortcuts = nil
    }

    fileprivate func handle(numericID: UInt32) {
        guard let action = ShortcutAction(numericID: numericID) else { return }
        handler?(action)
    }
}

private struct SendableHotKeyReference: @unchecked Sendable {
    let value: EventHotKeyRef
}

private struct SendableEventHandlerReference: @unchecked Sendable {
    let value: EventHandlerRef
}

private func autoTypeHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr, identifier.signature == 0x41545632 else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { manager.handle(numericID: identifier.id) }
    return noErr
}
