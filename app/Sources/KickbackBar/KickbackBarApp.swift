import SwiftUI
import AppKit

@main
struct KickbackBarApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var vm = MenuVM()

  var body: some Scene {
    MenuBarExtra {
      MenuContent(vm: vm)
    } label: {
      Text(vm.model.title)
    }
    .menuBarExtraStyle(.window)
  }
}

/// Menu-bar-only app: no Dock icon, no main window.
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}
