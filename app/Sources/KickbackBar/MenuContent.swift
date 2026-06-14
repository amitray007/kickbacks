// app/Sources/KickbackBar/MenuContent.swift
import SwiftUI
import AppKit
import KickbackKit

struct MenuContent: View {
  @ObservedObject var vm: MenuVM
  @Environment(\.openWindow) private var openWindow
  private var m: MenuModel { vm.model }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      Divider()
      switch vm.phase {
      case .signedOut: signedOut
      case .signingIn: signingIn
      case .signedIn:  signedIn
      }
    }
    .padding(12)
    .frame(width: 300)
  }

  private var header: some View {
    HStack {
      HStack(spacing: 0) {
        Text("K$ ").foregroundStyle(.green).fontWeight(.bold)
        Text("Kickback").fontWeight(.bold)
      }
      Spacer()
      if vm.phase == .signedIn {
        HStack(spacing: 5) {
          Circle().fill(dotColor).frame(width: 8, height: 8)
          Text(m.status).foregroundStyle(.secondary).font(.caption)
        }
      }
    }
  }

  private var signedOut: some View {
    VStack(spacing: 10) {
      Text("See your Kickbacks earnings").font(.headline)
      Text("Read-only · your own account only").font(.caption).foregroundStyle(.secondary)
      Button(action: vm.signIn) {
        Text("Sign in with Google").frame(maxWidth: .infinity)
      }.buttonStyle(.borderedProminent).tint(.green)
      footer(showData: false)
    }.frame(maxWidth: .infinity)
  }

  private var signingIn: some View {
    VStack(spacing: 10) {
      ProgressView()
      Text("Opening your browser…").font(.headline)
      Text("Finish signing in with Google, then come back.")
        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Button("Cancel", action: vm.cancelLogin)
    }.frame(maxWidth: .infinity).padding(.vertical, 6)
  }

  private var signedIn: some View {
    VStack(alignment: .leading, spacing: 6) {
      bannerView
      row("Today", m.today, big: true)
      if m.collecting {
        Text("Collecting your trend… charts appear within the hour")
          .font(.caption).foregroundStyle(.secondary)
          .padding(8).frame(maxWidth: .infinity)
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
      } else if !m.spark.isEmpty {
        HStack { Text(m.spark).foregroundStyle(.green); Spacer(); Text("last 24h").font(.caption).foregroundStyle(.secondary) }
      }
      row("Lifetime", m.lifetime)
      if !m.rate.isEmpty { row("Rate", "\(m.rate) \(arrow)") }
      if !m.cap.isEmpty { row("Daily cap", "\(m.cap) · \(m.capPct)%") }
      if let ago = m.lastEarnedAgoSeconds, m.state == .stalled || m.state == .killed {
        row("Last earned", agoText(ago))
      }
      if !m.ad.isEmpty {
        Divider()
        Text("Now showing").font(.caption).foregroundStyle(.secondary)
        Button(action: openAd) {
          HStack(spacing: 6) {
            if let icon = m.ads.first?.icon, !icon.isEmpty, let u = URL(string: icon) {
              AsyncImage(url: u) { phase in
                if let img = phase.image { img.resizable().frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 3)) }
                else { Color.clear.frame(width: 16, height: 16) }
              }
            }
            Text(m.ad).lineLimit(1)
          }
        }.buttonStyle(.link)
        if let t = m.viewThresholdSeconds {
          Text("Earn after \(t)s of viewing" + (m.ads.count > 1 ? " · \(m.ads.count) ads in rotation" : ""))
            .font(.caption2).foregroundStyle(.secondary)
        }
      }
      if m.ageSeconds > 180 {
        Text("⚠ Couldn't refresh · showing data from \(agoText(m.ageSeconds))")
          .font(.caption).foregroundStyle(.secondary)
      }
      footer(showData: true)
    }
  }

  @ViewBuilder private var bannerView: some View {
    switch m.state {
    case .stalled: banner("⚠ Earnings flat while you're active — VS Code may have stopped serving.", .orange)
    case .cap:     banner("✓ Daily cap reached — \(m.today). Resets in \(m.resets).", .green)
    case .killed:  banner("✕ Not earning — stopped or signed out in VS Code.", .red)
    case .noServe: banner("No ad serving right now — you'll earn again when one shows.", .gray)
    default:       EmptyView()
    }
  }

  private func banner(_ text: String, _ color: Color) -> some View {
    Text(text).font(.caption).foregroundStyle(color)
      .padding(8).frame(maxWidth: .infinity, alignment: .leading)
      .background(color.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private func footer(showData: Bool) -> some View {
    HStack {
      if showData {
        Button("📊 History") {
          NSApp.activate(ignoringOtherApps: true)  // .accessory app: bring the window forward
          openWindow(id: "history")
        }.buttonStyle(.link)
        Spacer()
        Button("↻ Refresh") { vm.refresh() }.buttonStyle(.link)
      } else {
        Spacer()
      }
      Menu("⋯") {
        if showData { Button("Sign out", action: vm.signOut) }
        Toggle("Start at login", isOn: Binding(get: { LoginItem.isEnabled() }, set: { LoginItem.setEnabled($0) }))
        Button("Quit") { NSApplication.shared.terminate(nil) }
      }.menuStyle(.borderlessButton).fixedSize()
    }
  }

  private func row(_ key: String, _ value: String, big: Bool = false) -> some View {
    HStack {
      Text(key).foregroundStyle(.secondary)
      Spacer()
      Text(value).font(big ? .title2.bold() : .body)
    }
  }

  private var arrow: String { m.trend == "up" ? "▴" : m.trend == "down" ? "▾" : "—" }
  private var dotColor: Color {
    switch MenuPresentation.tint(state: m.state, phase: vm.phase) {
    case .amber: return .orange
    case .green: return .green
    case .red: return .red
    case .primary: return .green
    case .muted: return .secondary
    }
  }
  private func agoText(_ sec: Int) -> String {
    sec >= 3600 ? "\(sec / 3600)h ago" : sec >= 60 ? "\(sec / 60)m ago" : "\(sec)s ago"
  }
  private func openAd() { if let u = URL(string: m.adUrl), !m.adUrl.isEmpty { NSWorkspace.shared.open(u) } }
}
