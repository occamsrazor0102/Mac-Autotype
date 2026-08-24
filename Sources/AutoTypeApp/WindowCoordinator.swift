import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    static let shared = WindowCoordinator()

    private var editorWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var hudPanel: NSPanel?
    private var hudHideTask: Task<Void, Never>?

    private init() {}

    func showEditor(model: AppModel) {
        if let window = editorWindowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = EditorView()
            .environmentObject(model)
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        window.title = "AutoType"
        window.setContentSize(NSSize(width: 860, height: 650))
        window.minSize = NSSize(width: 720, height: 540)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()

        let windowController = NSWindowController(window: window)
        editorWindowController = windowController
        NSApp.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
    }

    func showSettings(model: AppModel) {
        if let window = settingsWindowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = SettingsView()
            .environmentObject(model)
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        window.title = "AutoType Settings"
        window.setContentSize(NSSize(width: 520, height: 480))
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()

        let windowController = NSWindowController(window: window)
        settingsWindowController = windowController
        NSApp.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
    }

    func updateHUD(model: AppModel) {
        hudHideTask?.cancel()
        hudHideTask = nil

        if model.state.isActive {
            showHUD(model: model)
        } else if hudPanel != nil {
            hudHideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.hideHUD() }
            }
        }
    }

    private func showHUD(model: AppModel) {
        if hudPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 330, height: 92),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.contentViewController = NSHostingController(
                rootView: StatusHUDView().environmentObject(model)
            )
            hudPanel = panel
        }

        guard let panel = hudPanel else { return }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.maxY - panel.frame.height - 28
            ))
        }
        panel.orderFrontRegardless()
    }

    private func hideHUD() {
        hudPanel?.orderOut(nil)
    }
}
