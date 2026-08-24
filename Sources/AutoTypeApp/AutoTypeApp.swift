import AppKit
import SwiftUI

@MainActor
private enum ApplicationContext {
    static weak var model: AppModel?

    static func showEditor() {
        guard let model else { return }
        WindowCoordinator.shared.showEditor(model: model)
    }
}

@MainActor
private final class AutoTypeApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ApplicationContext.showEditor()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ApplicationContext.showEditor()
        return true
    }
}

@main
struct AutoTypeApplication: App {
    @NSApplicationDelegateAdaptor(AutoTypeApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        ApplicationContext.model = model
    }

    var body: some Scene {
        MenuBarExtra {
            QuickPanelView()
                .environmentObject(model)
        } label: {
            Label("AutoType", systemImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        switch model.state {
        case .countdown: "timer"
        case .typing: "keyboard.fill"
        case .paused: "pause.circle.fill"
        case .failed: "exclamationmark.triangle"
        default: "keyboard"
        }
    }
}
