import SwiftUI
import AppKit
import KickbacksKit
import UserNotifications

@main
struct KickbacksBarApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var vm = MenuVM()

  var body: some Scene {
    MenuBarExtra {
      MenuContent(vm: vm)
    } label: {
      Text((vm.loading && !vm.demoMode) ? "K$ …" : MenuPresentation.menuBarLabel(
             phase: vm.effPhase, style: vm.menuBarStyle, hideAmounts: vm.hideAmounts,
             today: vm.effModel.menuValue,
             week: vm.effHistory.map { String(format: "%.2f", $0.thisWeekUsd) } ?? "—",
             lifetime: vm.effModel.lifetime.replacingOccurrences(of: "$", with: ""),
             rate: vm.effModel.rate.replacingOccurrences(of: "$", with: "")))
        .foregroundStyle(labelColor(vm))
    }
    .menuBarExtraStyle(.window)

    Window("Kickbacks Settings", id: "settings") {
      SettingsView(vm: vm)
    }
    .windowResizability(.contentSize)

    Window("Share", id: "share") {
      ShareView(vm: vm)
    }
    .windowResizability(.contentSize)

    Window("Kickbacks Update", id: "update") {
      UpdateView(vm: vm)
    }
    .windowResizability(.contentSize)
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
  switch MenuPresentation.tint(state: vm.effModel.state, phase: vm.effPhase) {
  case .amber: return .orange
  case .green: return .green
  case .red: return .red
  case .primary, .muted: return .primary
  }
}
