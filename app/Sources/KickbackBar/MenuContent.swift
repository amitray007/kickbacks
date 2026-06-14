import SwiftUI
import AppKit
import KickbackKit

/// The dropdown (design §15.1). Rows hide themselves when their value is empty, so the
/// same view renders every state (earning / cap / stalled / no-serve / signed-out).
struct MenuContent: View {
  @ObservedObject var vm: MenuVM
  private var m: MenuModel { vm.model }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Kickback").bold()
        Spacer()
        Text(m.status).foregroundStyle(statusColor)
      }
      Divider()
      row("Today", m.today)
      row("Lifetime", m.lifetime)
      if !m.rate.isEmpty { row("Rate", "\(m.rate) \(arrow)") }
      if !m.spark.isEmpty { row("Last 24h", m.spark) }
      if !m.cap.isEmpty {
        Divider()
        row("Daily cap", "\(m.cap)  (\(m.capPct)%)")
        if !m.resets.isEmpty { row("Resets in", m.resets) }
        if !m.projection.isEmpty { row("Hits cap", m.projection) }
      }
      if !m.ad.isEmpty {
        Divider()
        Text("Now showing").font(.caption).foregroundStyle(.secondary)
        Button(action: openAd) { Text(m.ad).lineLimit(1) }.buttonStyle(.link)
      }
      Divider()
      HStack {
        Button("Refresh") { vm.refresh() }
        Spacer()
        Button("Quit") { NSApplication.shared.terminate(nil) }
      }
    }
    .padding(12)
    .frame(width: 320)
  }

  private var arrow: String { m.trend == "up" ? "▴" : m.trend == "down" ? "▾" : "—" }

  private var statusColor: Color {
    switch m.state {
    case .earning: return .green
    case .stalled, .cap: return .orange
    case .killed: return .red
    default: return .secondary
    }
  }

  private func row(_ key: String, _ value: String) -> some View {
    HStack { Text(key).foregroundStyle(.secondary); Spacer(); Text(value) }
  }

  private func openAd() {
    if !m.adUrl.isEmpty, let u = URL(string: m.adUrl) { NSWorkspace.shared.open(u) }
  }
}
