import SwiftUI
import AppKit
import KickbackKit

@main
struct KickbackBarApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var vm = MenuVM()

  var body: some Scene {
    MenuBarExtra {
      MenuContent(vm: vm)
    } label: {
      Text(MenuPresentation.menuBarLabel(phase: vm.phase, menuValue: vm.model.menuValue))
        .foregroundStyle(labelColor(vm))
    }
    .menuBarExtraStyle(.window)
    Window("Kickback — History", id: "history") {
      HistoryWindow()
    }
    .windowResizability(.contentSize)
  }
}

/// Menu-bar-only app: no Dock icon, no main window.
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}

@MainActor private func labelColor(_ vm: MenuVM) -> Color {
  switch MenuPresentation.tint(state: vm.model.state, phase: vm.phase) {
  case .amber: return .orange
  case .green: return .green
  case .red: return .red
  case .primary, .muted: return .primary
  }
}
