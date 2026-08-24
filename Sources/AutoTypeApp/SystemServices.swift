import AppKit
import ApplicationServices
import AutoTypeCore
import Carbon
import Combine
import Foundation
import ServiceManagement

enum SystemEventError: LocalizedError {
    case eventSourceUnavailable
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .eventSourceUnavailable: "macOS could not create a keyboard event source."
        case .eventCreationFailed: "macOS could not create a keyboard event."
        }
    }
}

private struct PhysicalKey {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

actor SystemEventSink: TypingEventSink {
    private var cachedInputSourceID: String?
    private var physicalKeys: [String: PhysicalKey] = [:]

    func sendUnicode(_ text: String) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw SystemEventError.eventSourceUnavailable
        }
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            throw SystemEventError.eventCreationFailed
        }

        var unicode = Array(text.utf16)
        keyDown.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: &unicode)
        keyUp.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: &unicode)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    func sendPhysical(_ text: String) throws -> Bool {
        try refreshPhysicalMapIfNeeded()
        guard let key = physicalKeys[text] else { return false }
        try postKey(key.keyCode, flags: key.flags)
        return true
    }

    func sendSpecialKey(_ key: SpecialKey) throws {
        switch key {
        case .returnKey:
            try postKey(0x24, flags: [])
        case .tab:
            try postKey(0x30, flags: [])
        }
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw SystemEventError.eventSourceUnavailable
        }
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            throw SystemEventError.eventCreationFailed
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func refreshPhysicalMapIfNeeded() throws {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            physicalKeys = [:]
            cachedInputSourceID = nil
            return
        }

        let inputSourceID = Self.stringProperty(kTISPropertyInputSourceID, source: source)
        guard inputSourceID != cachedInputSourceID else { return }

        cachedInputSourceID = inputSourceID
        physicalKeys = Self.makePhysicalMap(source: source)
    }

    private static func makePhysicalMap(source: TISInputSource) -> [String: PhysicalKey] {
        guard let rawLayoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return [:]
        }
        let layoutData = unsafeBitCast(rawLayoutData, to: CFData.self) as Data
        let modifierOptions: [(UInt32, CGEventFlags)] = [
            (0, []),
            (UInt32(shiftKey), .maskShift),
            (UInt32(optionKey), .maskAlternate),
            (UInt32(shiftKey | optionKey), [.maskShift, .maskAlternate])
        ]

        return layoutData.withUnsafeBytes { buffer -> [String: PhysicalKey] in
            guard let baseAddress = buffer.baseAddress else { return [:] }
            let layout = baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self)
            var result: [String: PhysicalKey] = [:]

            for keyCode in UInt16(0)..<UInt16(128) {
                for (carbonModifiers, eventFlags) in modifierOptions {
                    var deadKeyState: UInt32 = 0
                    var outputLength = 0
                    var characters = [UniChar](repeating: 0, count: 8)
                    let status = UCKeyTranslate(
                        layout,
                        keyCode,
                        UInt16(kUCKeyActionDown),
                        carbonModifiers >> 8,
                        UInt32(LMGetKbdType()),
                        OptionBits(kUCKeyTranslateNoDeadKeysMask),
                        &deadKeyState,
                        characters.count,
                        &outputLength,
                        &characters
                    )
                    guard status == noErr, outputLength > 0 else { continue }
                    let text = String(utf16CodeUnits: characters, count: outputLength)
                    guard text.count == 1, result[text] == nil else { continue }
                    result[text] = PhysicalKey(keyCode: CGKeyCode(keyCode), flags: eventFlags)
                }
            }

            return result
        }
    }

    private static func stringProperty(_ property: CFString, source: TISInputSource) -> String? {
        guard let rawValue = TISGetInputSourceProperty(source, property) else { return nil }
        return unsafeBitCast(rawValue, to: CFString.self) as String
    }
}

final class SystemSafetyMonitor: TypingSafetyMonitoring, @unchecked Sendable {
    func status(for target: TargetApplication) async -> TargetSafetyStatus {
        await MainActor.run {
            guard AXIsProcessTrusted() else { return .accessibilityPermissionLost }
            guard let running = NSRunningApplication(processIdentifier: target.processIdentifier), !running.isTerminated else {
                return .targetTerminated
            }
            if let expectedBundleIdentifier = target.bundleIdentifier,
               running.bundleIdentifier != expectedBundleIdentifier {
                return .targetTerminated
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                return .focusChanged
            }
            return Self.focusedElementIsSecure(processIdentifier: target.processIdentifier) ? .secureField : .safe
        }
    }

    private static func focusedElementIsSecure(processIdentifier: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue
        else {
            return false
        }

        let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var subroleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXSubroleAttribute as CFString, &subroleValue) == .success,
              let subrole = subroleValue as? String
        else {
            return false
        }
        return subrole == (kAXSecureTextFieldSubrole as String)
    }
}

enum AccessibilityAuthorizer {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestAccess() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class TargetTracker: ObservableObject {
    @Published private(set) var availableTargets: [TargetApplication] = []
    @Published private(set) var lastExternalTarget: TargetApplication?

    private let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    private var observers: [SendableObserverReference] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(SendableObserverReference(value: center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.record(application) }
        }))
        observers.append(SendableObserverReference(value: center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }))
        observers.append(SendableObserverReference(value: center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }))

        refresh()
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            record(frontmost)
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0.value) }
    }

    func refresh() {
        availableTargets = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ownProcessIdentifier }
            .compactMap(Self.target(from:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func target(processIdentifier: Int32?) -> TargetApplication? {
        guard let processIdentifier else { return lastExternalTarget }
        return availableTargets.first { $0.processIdentifier == processIdentifier }
    }

    private func record(_ application: NSRunningApplication) {
        guard application.processIdentifier != ownProcessIdentifier, application.activationPolicy == .regular else { return }
        lastExternalTarget = Self.target(from: application)
        refresh()
    }

    private static func target(from application: NSRunningApplication) -> TargetApplication? {
        guard !application.isTerminated else { return nil }
        return TargetApplication(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            name: application.localizedName ?? application.bundleIdentifier ?? "Application"
        )
    }
}

private struct SendableObserverReference: @unchecked Sendable {
    let value: NSObjectProtocol
}

enum LaunchAtLoginController {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
