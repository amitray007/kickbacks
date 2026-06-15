import SwiftUI
import AppKit
import KickbackKit
import UserNotifications

@main
struct KickbackBarApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var vm = MenuVM()

  var body: some Scene {
    MenuBarExtra {
      MenuContent(vm: vm)
    } label: {
      Text(vm.loading ? "K$ …" : MenuPresentation.menuBarLabel(phase: vm.phase, menuValue: vm.model.menuValue))
        .foregroundStyle(labelColor(vm))
    }
    .menuBarExtraStyle(.window)
  }
}

/// Menu-bar-only app: no Dock icon, no main window.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  // Present alerts even though the (accessory) app is always running.
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .sound])
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
