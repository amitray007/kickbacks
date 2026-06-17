// app/Sources/KickbacksBar/SettingsView.swift
import SwiftUI
import KickbacksKit

/// The Preferences window, opened from the panel's bottom-bar Settings button. Reads/writes
/// the persisted settings on MenuVM so the menu bar + panel react live.
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

      Section("Caps") {
        HStack {
          Text("Hourly")
          Spacer()
          TextField("", value: Binding(get: { vm.hourlyCapUsd }, set: { vm.setHourlyCap($0) }), format: .number)
            .multilineTextAlignment(.trailing).frame(width: 80)
        }
        HStack {
          Text("Daily")
          Spacer()
          TextField("", value: Binding(get: { vm.dailyCapUsd }, set: { vm.setDailyCap($0) }), format: .number)
            .multilineTextAlignment(.trailing).frame(width: 80)
        }
        Text("Your personal targets in $ (not enforced). Hourly tracks your last 60 minutes.")
          .font(.caption).foregroundStyle(.secondary)
      }

      Section("Menu bar") {
        Picker("Show", selection: Binding(get: { vm.menuBarStyle }, set: { vm.setMenuBarStyle($0) })) {
          Text("Today $").tag(MenuBarStyle.today)
          Text("This week $").tag(MenuBarStyle.week)
          Text("Lifetime $").tag(MenuBarStyle.lifetime)
          Text("Per hour").tag(MenuBarStyle.rate)
          Text("Icon only").tag(MenuBarStyle.iconOnly)
        }
      }

      Section("Privacy & demo") {
        Toggle("Privacy mode", isOn: Binding(get: { vm.hideAmounts }, set: { vm.setHideAmounts($0) }))
        Text("Mask every $ value — handy when screen sharing.")
          .font(.caption).foregroundStyle(.secondary)

        Toggle("Demo mode", isOn: Binding(get: { vm.demoMode }, set: { vm.setDemoMode($0) }))
        Text("Show believable sample numbers instead of your real earnings.")
          .font(.caption).foregroundStyle(.secondary)

        Toggle("Show \"Demo mode\" label", isOn: Binding(get: { vm.showDemoLabel }, set: { vm.setShowDemoLabel($0) }))
          .disabled(!vm.demoMode)
        Text("Hide the label to share screenshots without giving it away.")
          .font(.caption).foregroundStyle(.secondary)
      }

      Section("General") {
        Toggle("Start at login", isOn: Binding(get: { LoginItem.isEnabled() }, set: { LoginItem.setEnabled($0) }))
        Toggle("Background monitoring", isOn: Binding(get: { ModelClient.pollerInstalled() }, set: { ModelClient.setPoller($0) }))
        Text("Checks periodically and alerts on cap — even when the panel is closed.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("Updates") {
        HStack {
          Text("Version")
          Spacer()
          Text(vm.currentVersionString).foregroundStyle(.secondary).monospacedDigit()
        }
        Toggle("Automatically check for updates",
               isOn: Binding(get: { vm.autoCheckUpdates }, set: { vm.setAutoCheckUpdates($0) }))
        Picker("Check every", selection: Binding(get: { vm.updateCheckHours }, set: { vm.setUpdateCheckHours($0) })) {
          Text("6 hours").tag(6)
          Text("12 hours").tag(12)
          Text("Daily").tag(24)
          Text("Weekly").tag(168)
        }.disabled(!vm.autoCheckUpdates)
        Button("Check now") { Task { await vm.checkForUpdates(manual: true) } }
        if let r = vm.updateCheckResult {
          Text(r).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 380, height: 620)
  }
}
