// app/Sources/KickbackBar/MenuContent.swift
import SwiftUI
import AppKit
import KickbackKit

struct MenuContent: View {
  @ObservedObject var vm: MenuVM
  @State private var showAllAds = false
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
    .onAppear { vm.refresh() }   // re-fetch each time the panel opens, not just every 60s
  }

  // MARK: header (brand + status + refresh + overflow)

  private var header: some View {
    HStack(spacing: 8) {
      HStack(spacing: 0) {
        Text("K$ ").foregroundStyle(.green).fontWeight(.bold)
        Text("Kickback").fontWeight(.bold)
      }
      Spacer()
      if vm.phase == .signedIn {
        statusPill
        refreshControl
      }
      overflowMenu(showData: vm.phase == .signedIn)
    }
  }

  private var statusPill: some View {
    HStack(spacing: 5) {
      Circle().fill(tint).frame(width: 7, height: 7)
      Text(shortStatus).font(.caption2.weight(.semibold))
    }
    .padding(.horizontal, 7).padding(.vertical, 3)
    .background(tint.opacity(0.16)).clipShape(Capsule())
    .foregroundStyle(tint)
  }

  @ViewBuilder private var refreshControl: some View {
    if vm.refreshing {
      ProgressView().controlSize(.small)
    } else {
      Button { vm.refresh(showSpinner: true) } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .help("Refresh · updated \(agoText(m.ageSeconds))")
      .onHover(perform: pointer)
    }
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
    .foregroundStyle(.secondary)
  }

  // MARK: states

  private var signedOut: some View {
    VStack(spacing: 10) {
      Text("See your Kickbacks earnings").font(.headline)
      Text("Read-only · your own account only").font(.caption).foregroundStyle(.secondary)
      Button(action: vm.signIn) {
        Text("Sign in with Google").frame(maxWidth: .infinity)
      }.buttonStyle(.borderedProminent).tint(.green)
    }.frame(maxWidth: .infinity).padding(.vertical, 4)
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
      VStack(alignment: .leading, spacing: 1) {
        Text("TODAY").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).kerning(0.6)
        HStack(alignment: .center, spacing: 7) {
          Text(m.today).font(.system(size: 34, weight: .heavy)).monospacedDigit()
          trendBadge
        }
      }
      Text(secondaryLine).font(.caption).foregroundStyle(.secondary)
      if m.ageSeconds > 180 {
        Text("Couldn't refresh · showing data from \(agoText(m.ageSeconds))")
          .font(.caption2).foregroundStyle(.secondary)
      }
      if !m.cap.isEmpty { Divider(); capSection }
      if let ago = m.lastEarnedAgoSeconds, m.state == .stalled || m.state == .killed {
        Text("Last earned \(agoText(ago))").font(.caption).foregroundStyle(.secondary)
      }
      if !m.ads.isEmpty { Divider(); adsSection }
      Divider()
      statsSection
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

  // Cap as text only (no bar / graph).
  private var capSection: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text("Daily cap").foregroundStyle(.secondary)
        Spacer()
        Text("\(m.cap) · \(m.capPct)%").monospacedDigit()
      }
      if !m.resets.isEmpty {
        Text("resets in \(m.resets)").foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }.font(.caption)
  }

  private var adsSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("NOW SHOWING\(m.ads.count > 1 ? " · \(m.ads.count)" : "")")
        .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).kerning(0.6)
      ForEach(Array(m.ads.prefix(3).enumerated()), id: \.offset) { _, ad in adRow(ad) }
      if m.ads.count > 3 {
        Button { showAllAds.toggle() } label: {
          Text("+\(m.ads.count - 3) more").font(.caption).foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .onHover(perform: pointer)
        .popover(isPresented: $showAllAds) { allAdsPopover }
      }
    }
  }

  private var allAdsPopover: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("All ads · \(m.ads.count)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 7) {
          ForEach(Array(m.ads.enumerated()), id: \.offset) { _, ad in adRow(ad) }
        }
      }.frame(maxHeight: 320)
    }
    .padding(12).frame(width: 280)
  }

  private func adRow(_ ad: AdItem) -> some View {
    Button { openURL(ad.url) } label: {
      HStack(spacing: 8) {
        adIcon(ad.icon)
        Text(ad.text).lineLimit(1)
        Spacer(minLength: 4)
        Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.secondary)
      }
    }
    .buttonStyle(.plain)
    .help(ad.text)            // hover → full text
    .onHover(perform: pointer) // hover → pointing-hand cursor
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

  // History — inline, stats only (no graphs).
  private var statsSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("HISTORY").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).kerning(0.6)
      if let h = vm.history, !h.isEmpty {
        HStack(spacing: 10) {
          statCell("This week", usd(h.thisWeekUsd))
          statCell("This month", usd(h.thisMonthUsd))
        }
        HStack(spacing: 10) {
          statCell("Best day", h.bestDay.map { usd($0.usd) } ?? "—")
          statCell("Avg / day", usd(h.avgPerDayUsd))
        }
        Text("Since install \(usd(h.sinceInstallUsd)) · \(h.daysTracked) day\(h.daysTracked == 1 ? "" : "s")")
          .font(.caption2).foregroundStyle(.secondary)
      } else {
        Text("No history yet — fills in as you keep earning.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func statCell(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.callout.weight(.semibold)).monospacedDigit()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: helpers

  @ViewBuilder private var trendBadge: some View {
    switch m.trend {
    case "up":   Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 16, weight: .bold)).foregroundStyle(.green)
    case "down": Image(systemName: "chart.line.downtrend.xyaxis").font(.system(size: 16, weight: .bold)).foregroundStyle(.red)
    default:     EmptyView()
    }
  }

  private var secondaryLine: String {
    var s = "Lifetime \(m.lifetime)"
    if !m.rate.isEmpty { s += "  ·  \(m.rate)" }
    return s
  }

  private var shortStatus: String {
    switch m.state {
    case .earning: return "Earning"
    case .stalled: return "Stalled"
    case .cap:     return "Capped"
    case .killed:  return "Stopped"
    case .noServe: return "Idle"
    case .signedOut: return "—"
    }
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

  private func usd(_ n: Double) -> String { "$" + String(format: "%.2f", n) }

  private func pointer(_ inside: Bool) {
    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
  }

  private func openURL(_ s: String) {
    if !s.isEmpty, let u = URL(string: s) { NSWorkspace.shared.open(u) }
  }

  private func showAbout() {
    NSApp.activate(ignoringOtherApps: true)
    NSApplication.shared.orderFrontStandardAboutPanel(nil)
  }
}
