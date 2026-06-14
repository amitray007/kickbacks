// app/Sources/KickbackBar/MenuContent.swift
import SwiftUI
import AppKit
import KickbackKit

struct MenuContent: View {
  @ObservedObject var vm: MenuVM
  @Environment(\.openWindow) private var openWindow
  private var m: MenuModel { vm.model }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
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

  // MARK: header

  private var header: some View {
    HStack {
      HStack(spacing: 0) {
        Text("K$ ").foregroundStyle(.green).fontWeight(.bold)
        Text("Kickback").fontWeight(.bold)
      }
      Spacer()
      if vm.phase == .signedIn { statusPill }
    }
  }

  private var statusPill: some View {
    HStack(spacing: 5) {
      Circle().fill(tint).frame(width: 7, height: 7)
      Text(m.status).font(.caption2.weight(.semibold))
    }
    .padding(.horizontal, 8).padding(.vertical, 3)
    .background(tint.opacity(0.16)).clipShape(Capsule())
    .foregroundStyle(tint)
  }

  // MARK: states

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
    VStack(alignment: .leading, spacing: 11) {
      bannerView
      // Hero: today's live value gets the emphasis.
      VStack(alignment: .leading, spacing: 1) {
        Text("TODAY").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).kerning(0.6)
        HStack(alignment: .center, spacing: 7) {
          Text(m.today).font(.system(size: 34, weight: .heavy)).monospacedDigit()
          trendBadge
        }
      }
      Text(secondaryLine).font(.caption).foregroundStyle(.secondary)
      if !m.cap.isEmpty { capSection }
      if let ago = m.lastEarnedAgoSeconds, m.state == .stalled || m.state == .killed {
        Text("Last earned \(agoText(ago))").font(.caption).foregroundStyle(.secondary)
      }
      if !m.ads.isEmpty { adsSection }
      if m.ageSeconds > 180 {
        Text("Couldn't refresh · showing data from \(agoText(m.ageSeconds))")
          .font(.caption2).foregroundStyle(.secondary)
      }
      Divider()
      footer(showData: true)
    }
  }

  // MARK: sections

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

  private var capSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Daily cap").foregroundStyle(.secondary)
        Spacer()
        Text("\(m.cap) · \(m.capPct)%")
      }.font(.caption)
      ProgressView(value: Double(min(max(m.capPct, 0), 100)), total: 100).tint(.green)
      if !m.resets.isEmpty {
        Text("resets in \(m.resets)").font(.caption2).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }

  private var adsSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("NOW SHOWING\(m.ads.count > 1 ? " · \(m.ads.count)" : "")")
        .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).kerning(0.6)
      ForEach(Array(m.ads.enumerated()), id: \.offset) { _, ad in
        Button { openURL(ad.url) } label: {
          HStack(spacing: 8) {
            adIcon(ad.icon)
            Text(ad.text).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.secondary)
          }
        }.buttonStyle(.plain)
      }
      if let t = m.viewThresholdSeconds {
        Text("Earn after \(t)s of viewing\(m.ads.count > 1 ? " each" : "")")
          .font(.caption2).foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder private func adIcon(_ icon: String) -> some View {
    if !icon.isEmpty, let u = URL(string: icon) {
      AsyncImage(url: u) { phase in
        if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
        else { Color.secondary.opacity(0.18) }
      }
      .frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 4))
    } else {
      RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.18)).frame(width: 18, height: 18)
    }
  }

  // MARK: footer

  private func footer(showData: Bool) -> some View {
    HStack {
      if showData {
        Button {
          NSApp.activate(ignoringOtherApps: true)  // .accessory app: bring the window forward
          openWindow(id: "history")
        } label: { Label("History", systemImage: "clock.arrow.circlepath") }
          .buttonStyle(.plain)
        Spacer()
        if vm.refreshing {
          HStack(spacing: 5) { ProgressView().controlSize(.small); Text("Refreshing…") }
        } else {
          Button { vm.refresh(showSpinner: true) } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            .buttonStyle(.plain)
        }
        Spacer()
      } else {
        Spacer()
      }
      overflowMenu(showData: showData)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private func overflowMenu(showData: Bool) -> some View {
    Menu {
      if showData {
        Button { vm.signOut() } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
      }
      Toggle("Start at login", isOn: Binding(get: { LoginItem.isEnabled() }, set: { LoginItem.setEnabled($0) }))
      Button { showAbout() } label: { Label("About Kickback", systemImage: "info.circle") }
      Divider()
      Button { NSApplication.shared.terminate(nil) } label: { Label("Quit", systemImage: "xmark.circle") }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
  }

  // MARK: helpers

  @ViewBuilder private var trendBadge: some View {
    switch m.trend {
    case "up":   Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 16, weight: .bold)).foregroundStyle(.green)
    case "down": Image(systemName: "chart.line.downtrend.xyaxis").font(.system(size: 16, weight: .bold)).foregroundStyle(.red)
    default:     EmptyView()   // flat/neutral: show nothing
    }
  }

  private var secondaryLine: String {
    var s = "Lifetime \(m.lifetime)"
    if !m.rate.isEmpty { s += "  ·  \(m.rate)" }
    return s
  }

  private var tint: Color {
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

  private func openURL(_ s: String) {
    if !s.isEmpty, let u = URL(string: s) { NSWorkspace.shared.open(u) }
  }

  private func showAbout() {
    NSApp.activate(ignoringOtherApps: true)
    NSApplication.shared.orderFrontStandardAboutPanel(nil)
  }
}
