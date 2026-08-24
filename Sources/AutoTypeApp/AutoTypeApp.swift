import SwiftUI

@main
struct AutoTypeApplication: App {
    @StateObject private var model: AppModel

    init() {
        _model = StateObject(wrappedValue: AppModel())
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
