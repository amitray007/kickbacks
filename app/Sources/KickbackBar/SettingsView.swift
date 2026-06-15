// app/Sources/KickbackBar/SettingsView.swift
import SwiftUI
import KickbackKit

/// The Preferences window (⌘, or gear → Settings…). Reads/writes the persisted settings
/// on MenuVM so the menu bar + panel react live.
struct SettingsView: View {
  @ObservedObject var vm: MenuVM
  private let presets = [60, 300, 600, 1800]

  var body: some View {
    Form {
      Section("Auto-refresh") {
        Picker("Refresh every", selection: Binding(get: { vm.pollSeconds }, set: { vm.setPollSeconds($0) })) {
          Text("1 min").tag(60)
          Text("5 min").tag(300)
          Text("10 min").tag(600)
          Text("30 min").tag(1800)
          if !presets.contains(vm.pollSeconds) { Text("\(vm.pollSeconds)s").tag(vm.pollSeconds) }
        }
        Stepper("Custom: every \(vm.pollSeconds)s",
                value: Binding(get: { vm.pollSeconds }, set: { vm.setPollSeconds($0) }),
                in: 15...3600, step: 15)
      }

      Section("Menu bar") {
        Picker("Show", selection: Binding(get: { vm.menuBarStyle }, set: { vm.setMenuBarStyle($0) })) {
          Text("Today $").tag(MenuBarStyle.today)
          Text("Lifetime $").tag(MenuBarStyle.lifetime)
          Text("Icon only").tag(MenuBarStyle.iconOnly)
        }.pickerStyle(.segmented)

        Toggle("Hide amounts", isOn: Binding(get: { vm.hideAmounts }, set: { vm.setHideAmounts($0) }))
        Text("Mask every $ value — handy when screen sharing.")
          .font(.caption).foregroundStyle(.secondary)

        Toggle("Fake data (demo mode)", isOn: Binding(get: { vm.demoMode }, set: { vm.setDemoMode($0) }))
        Text("Show believable sample numbers instead of your real earnings.")
          .font(.caption).foregroundStyle(.secondary)
      }

      Section("General") {
        Toggle("Start at login", isOn: Binding(get: { LoginItem.isEnabled() }, set: { LoginItem.setEnabled($0) }))
        Toggle("Background monitoring", isOn: Binding(get: { ModelClient.pollerInstalled() }, set: { ModelClient.setPoller($0) }))
        Text("Checks periodically and alerts on cap — even when the panel is closed.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 380, height: 440)
  }
}
