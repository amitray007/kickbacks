// app/Sources/KickbacksBar/MenuContent.swift
import SwiftUI
import AppKit
import KickbacksKit

private struct ContentHeightKey: PreferenceKey {
  static var defaultValue: CGFloat { 0 }
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Grabs the hosting NSWindow (the MenuBarExtra panel) so we can dismiss it programmatically.
private struct WindowAccessor: NSViewRepresentable {
  let onResolve: (NSWindow?) -> Void
  func makeNSView(context: Context) -> NSView {
    let v = NSView()
    DispatchQueue.main.async { onResolve(v.window) }
    return v
  }
  func updateNSView(_ nsView: NSView, context: Context) {}
}

struct MenuContent: View {
  @ObservedObject var vm: MenuVM
  @Environment(\.openWindow) private var openWindow
  @State private var contentHeight: CGFloat = 0
  @State private var now = Date()            // ticked every second so "Updated Nm ago" counts up live
  @State private var panelWindow: NSWindow?  // the MenuBarExtra panel — collapsed when Settings/Share opens
  private var m: MenuModel { vm.effModel }   // demo data when Fake-data is on

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        header
        Divider()
        if vm.loading && !vm.demoMode {
          loadingView
        } else {
          switch vm.effPhase {
          case .signedOut: signedOut
          case .signingIn: signingIn
          case .signedIn:  signedIn
          }
        }
        Divider()
        bottomBar
      }
      .padding(12)
      .background(GeometryReader { g in Color.clear.preference(key: ContentHeightKey.self, value: g.size.height) })
    }
    // Size to content, but cap below the screen so a tall panel scrolls instead of clipping.
    .frame(width: 300, height: contentHeight > 0 ? min(contentHeight, maxPanelHeight) : nil)
    .onPreferenceChange(ContentHeightKey.self) { h in
      // Ignore spurious 0-height passes (they collapse then re-grow the window — the "zoom"
      // on menu/Settings open) and sub-pixel jitter from the 1s tick; snap, don't animate.
      guard h > 0, abs(h - contentHeight) > 0.5 else { return }
      var t = Transaction(); t.disablesAnimations = true
      withTransaction(t) { contentHeight = h }
    }
    .onAppear { now = Date(); vm.refresh() }   // re-fetch + reset the clock each time the panel opens
    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    .background(WindowAccessor { panelWindow = $0 })
  }

  private var maxPanelHeight: CGFloat { (NSScreen.main?.visibleFrame.height ?? 760) - 80 }

  // MARK: header (brand + status + refresh + gear)

  private var header: some View {
    HStack(spacing: 8) {
      HStack(spacing: 0) {
        Text("K$ ").foregroundStyle(.green).fontWeight(.bold)
        Text("Kickbacks").fontWeight(.bold)
      }
      Spacer()
      if vm.effPhase == .signedIn {
        statusPill
      }
      overflowMenu(showData: vm.effPhase == .signedIn)
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
      .help("Refresh")
      .onHover(perform: pointer)
    }
  }

  // Quick feature toggles + app actions. Full preferences live in the bottom-bar Settings button.
  private func overflowMenu(showData: Bool) -> some View {
    Menu {
      Button { openShare() } label: { Label("Share…", systemImage: "square.and.arrow.up") }
      Divider()
      Toggle("Privacy mode", isOn: Binding(get: { vm.hideAmounts }, set: { vm.setHideAmounts($0) }))
      Toggle("Demo mode", isOn: Binding(get: { vm.demoMode }, set: { vm.setDemoMode($0) }))
      Toggle("Floating window", isOn: Binding(get: { vm.pinned }, set: { vm.setPinned($0) }))
      Divider()
      if showData {
        Button { vm.signOut() } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
      }
      Button { showAbout() } label: { Label("About", systemImage: "info.circle") }
      Divider()
      Button { NSApplication.shared.terminate(nil) } label: { Label("Quit", systemImage: "xmark.circle") }
    } label: {
      Image(systemName: "switch.2")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .foregroundStyle(.secondary)
  }

  // MARK: states

  private var signedOut: some View {
    VStack(spacing: 10) {
      Text("See your earnings").font(.title3.weight(.semibold))
      Text("Today, lifetime, and stall alerts — live in your menu bar.")
        .font(.caption).foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      Button(action: vm.signIn) {
        Text("Sign in with Google").frame(maxWidth: .infinity)
      }.buttonStyle(.borderedProminent).tint(.green).controlSize(.large)
    }.frame(maxWidth: .infinity).padding(.vertical, 10)
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

  private var loadingView: some View {
    VStack(spacing: 10) {
      ProgressView()
      Text("Loading…").font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity).padding(.vertical, 16)
  }

  private var signedIn: some View {
    VStack(alignment: .leading, spacing: 11) {
      bannerView
      HStack(alignment: .top, spacing: 10) {
        statCard(bg: tint.opacity(0.12)) {        // Today tile, faintly state-tinted
          VStack(alignment: .leading, spacing: 2) {
            Text("TODAY").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).kerning(0.6)
            Text(mask(m.today)).font(.system(size: 28, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Text(m.rate.isEmpty ? " " : mask(m.rate)).font(.caption2).foregroundStyle(.secondary)
          }
        }
        statCard(bg: Color.secondary.opacity(0.10)) {   // Lifetime tile, neutral
          VStack(alignment: .leading, spacing: 2) {
            Text("LIFETIME").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).kerning(0.6)
            Text(mask(m.lifetime)).font(.system(size: 28, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Text("all-time").font(.caption2).foregroundStyle(.secondary)
          }
        }
      }
      Divider()
      capsSection
      if let ago = m.lastEarnedAgoSeconds, m.state == .killed {
        Text("Last earned \(agoText(ago))").font(.caption).foregroundStyle(.secondary)
      }
      if !m.recentAds.isEmpty { Divider(); recentAdsSection }
      Divider()
      statsSection
    }
  }

  // MARK: sections

  @ViewBuilder private var bannerView: some View {
    switch m.state {
    case .cap:     banner("✓ Daily cap reached — \(mask(m.today)). Resets in \(m.resets).", .green)
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

  // Your personal caps (set in Settings), text only. Hourly = trailing-60-min earnings.
  private var capsSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      capRow("Hourly cap", earned: m.hourUsd, limit: vm.hourlyCapUsd)
      capRow("Daily cap", earned: m.todayUsd, limit: vm.dailyCapUsd)
    }.font(.caption)
  }

  private func capRow(_ label: String, earned: Double, limit: Double) -> some View {
    let pct = limit > 0 ? min(100, Int((earned / limit) * 100)) : 0
    return HStack {
      Text(label).foregroundStyle(.secondary)
      Spacer()
      Text("\(mask(usd(earned))) / \(mask(usd(limit))) · \(pct)%").monospacedDigit()
    }
  }

  // Recent ads: current first (full opacity), the prior couple dimmed. Capped to 3 by the CLI.
  private var recentAdsSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("RECENT ADS").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).kerning(0.6)
      ForEach(Array(m.recentAds.enumerated()), id: \.offset) { idx, ad in
        adRow(ad).opacity(idx == 0 ? 1 : 0.5)
      }
    }
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
      if let h = vm.effHistory, !h.isEmpty {
        HStack(spacing: 10) {
          statCell("This week", mask(usd(h.thisWeekUsd)))
          statCell("This month", mask(usd(h.thisMonthUsd)))
        }
        HStack(spacing: 10) {
          statCell("Best day", mask(h.bestDay.map { usd($0.usd) } ?? "—"))
          statCell("Avg / day", mask(usd(h.avgPerDayUsd)))
        }
        if h.hasEnough {
          HStack(spacing: 10) {
            statCell("Proj. week", mask(usd(h.avgPerDayUsd * 7)))
            statCell("Proj. month", mask(usd(h.avgPerDayUsd * 30)))
          }
        }
        Text("Since install \(mask(usd(h.sinceInstallUsd))) · \(h.daysTracked) day\(h.daysTracked == 1 ? "" : "s")")
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

  // Bottom bar: Settings on the left; freshness + refresh on the right (signed-in only).
  // The "Updated" time counts up live (driven by `now`).
  private var bottomBar: some View {
    HStack(spacing: 8) {
      Button { openSettings() } label: { Image(systemName: "gearshape") }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .help("Settings").onHover(perform: pointer)
      Spacer()
      if vm.effPhase == .signedIn {
        Text(updatedText)
          .font(.caption2)
          .foregroundStyle(isStale ? Color.orange : Color.secondary)
        refreshControl
      }
    }
  }

  private func openSettings() {
    panelWindow?.orderOut(nil)   // collapse the menu-bar panel so the window has focus
    NSApp.activate(ignoringOtherApps: true)
    openWindow(id: "settings")
  }

  private func openShare() {
    panelWindow?.orderOut(nil)   // collapse the menu-bar panel so the window has focus
    NSApp.activate(ignoringOtherApps: true)
    openWindow(id: "share")
  }

  private var updatedText: String {
    if vm.demoMode { return "Demo mode" }
    guard let t = vm.lastUpdated else { return "Updating…" }
    return "Updated \(agoText(max(0, Int(now.timeIntervalSince(t)))))"
  }

  private var isStale: Bool {
    guard !vm.demoMode, let t = vm.lastUpdated else { return false }
    return now.timeIntervalSince(t) > 180
  }

  // MARK: helpers

  private func statCard<C: View>(bg: Color, @ViewBuilder _ content: () -> C) -> some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(bg)
      .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private var shortStatus: String {
    switch m.state {
    case .earning: return "Earning"
    case .stalled: return "Earning"   // stalled removed — treat as earning
    case .cap:     return "Capped"
    case .killed:  return "Stopped"
    case .noServe: return "Idle"
    case .signedOut: return "—"
    }
  }

  private var tint: Color {
    switch MenuPresentation.tint(state: m.state, phase: vm.effPhase) {
    case .amber: return .orange
    case .green: return .green
    case .red: return .red
    case .primary: return .green
    case .muted: return .secondary
    }
  }

  private func mask(_ s: String) -> String { vm.hideAmounts ? "•••" : s }

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
