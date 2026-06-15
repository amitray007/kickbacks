// app/Sources/KickbackBar/ShareView.swift
import SwiftUI
import AppKit
import KickbackKit
import Charts
import UniformTypeIdentifiers

enum ShareMetric: String, CaseIterable, Identifiable {
  case today, weekly, lifetime
  var id: String { rawValue }
  var title: String { self == .today ? "Today" : self == .weekly ? "Weekly" : "Lifetime" }
}

/// The Share window: pick a metric (Today / Weekly / Lifetime) → an adaptive card you can
/// Copy / Save / Post to X. The card renders to a PNG locally (ImageRenderer); the app never
/// posts anything itself. Demo mode flows through, so you can share sample numbers.
struct ShareView: View {
  @ObservedObject var vm: MenuVM
  @State private var metric: ShareMetric = .today

  private var card: some View {
    ShareCard(metric: metric, model: vm.effModel, history: vm.effHistory)
  }

  var body: some View {
    VStack(spacing: 16) {
      Picker("", selection: $metric) {
        ForEach(ShareMetric.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented).labelsHidden().frame(width: 300)

      card
        .frame(width: 600, height: 340)
        .scaleEffect(0.82, anchor: .center)
        .frame(width: 492, height: 279)   // reserve the scaled footprint

      HStack(spacing: 10) {
        Button { copyImage() } label: { Label("Copy image", systemImage: "doc.on.doc") }
        Button { saveImage() } label: { Label("Save…", systemImage: "square.and.arrow.down") }
        Button { postToX() } label: { Label("Post to X", systemImage: "arrow.up.forward.app") }
      }

      Text(vm.demoMode
           ? "Demo mode is on — sharing sample numbers."
           : "Sharing your real numbers. Turn on Demo mode to share sample numbers instead.")
        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
    .padding(20)
    .frame(width: 540)
  }

  @MainActor private func render() -> NSImage? {
    let r = ImageRenderer(content: card.frame(width: 600, height: 340))
    r.scale = 2   // retina-crisp PNG
    return r.nsImage
  }

  @MainActor private func copyImage() {
    guard let img = render() else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([img])
  }

  @MainActor private func saveImage() {
    guard let img = render(), let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "kickbacks-\(metric.rawValue).png"
    panel.allowedContentTypes = [.png]
    if panel.runModal() == .OK, let url = panel.url { try? png.write(to: url) }
  }

  @MainActor private func postToX() {
    copyImage()   // X compose URLs can't attach an image, so put it on the clipboard to paste
    let text = "My Kickbacks earnings 💸 (via Kickback)"
    let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    if let u = URL(string: "https://x.com/intent/post?text=\(encoded)") { NSWorkspace.shared.open(u) }
  }
}

/// The shareable card — fancy, metric-driven. Pure of side effects so the preview and the
/// rendered image are identical.
struct ShareCard: View {
  let metric: ShareMetric
  let model: MenuModel
  let history: HistoryModel?

  var body: some View {
    ZStack(alignment: .topLeading) {
      LinearGradient(colors: [Color(0x0E3B2A), Color(0x050F0B)], startPoint: .topLeading, endPoint: .bottomTrailing)
      RadialGradient(colors: [Color(0x34D399).opacity(0.28), .clear], center: .init(x: 0.22, y: 0.42), startRadius: 0, endRadius: 360)

      VStack(alignment: .leading, spacing: 0) {
        header
        Spacer().frame(height: 16)
        Text(label).font(.system(size: 14, weight: .bold)).kerning(2).foregroundStyle(.white.opacity(0.55))
        Text(heroValue)
          .font(.system(size: metric == .lifetime ? 64 : 56, weight: .heavy))
          .foregroundStyle(LinearGradient(colors: [Color(0xA7F3D0), .white], startPoint: .top, endPoint: .bottom))
          .lineLimit(1).minimumScaleFactor(0.5)
        viz
        Spacer(minLength: 0)
        footer
      }
      .padding(.horizontal, 40).padding(.vertical, 28)
    }
    .frame(width: 600, height: 340)
    .clipShape(RoundedRectangle(cornerRadius: 28))
    .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.07)))
  }

  // MARK: header

  private var header: some View {
    HStack {
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 12)
          .fill(LinearGradient(colors: [Color(0x2AA44F), Color(0x147A34)], startPoint: .top, endPoint: .bottom))
          .frame(width: 42, height: 42)
          .overlay(Text("K$").font(.system(size: 20, weight: .heavy)).foregroundStyle(.white))
          .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.18)))
        Text("Kickbacks").font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
      }
      Spacer()
      badgeView
    }
  }

  // Smart badge: a trend arrow (Today/Weekly), a "best ever" star, or a streak flame (Lifetime).
  private struct Badge { let icon: String; let text: String; let tint: Color }

  private var badgeView: some View {
    let b = badge
    return HStack(spacing: 6) {
      Image(systemName: b.icon).font(.system(size: 12, weight: .bold))
      Text(b.text).font(.system(size: 14, weight: .semibold))
    }
    .foregroundStyle(b.tint)
    .padding(.horizontal, 12).padding(.vertical, 7)
    .background(b.tint.opacity(0.16), in: Capsule())
  }

  private var badge: Badge {
    switch metric {
    case .today:
      if model.todayUsd > 0, let mx = history?.daily.map(\.usd).max(), model.todayUsd >= mx {
        return Badge(icon: "star.fill", text: "Best day yet", tint: Color(0xFBBF24))
      }
      return trendBadge
    case .weekly:
      return trendBadge
    case .lifetime:
      let s = streakDays
      if s >= 2 { return Badge(icon: "flame.fill", text: "\(s)-day streak", tint: Color(0xFB923C)) }
      return Badge(icon: "infinity", text: "all-time", tint: Color(0x6EE7B7))
    }
  }

  private var trendBadge: Badge {
    guard let p = trendPct else { return Badge(icon: "bolt.fill", text: "live", tint: Color(0x6EE7B7)) }
    return p >= 0
      ? Badge(icon: "arrow.up.right", text: "+\(p)%", tint: Color(0x34D399))
      : Badge(icon: "arrow.down.right", text: "\(p)%", tint: Color(0xF87171))
  }

  private var streakDays: Int {
    var n = 0
    for b in (history?.daily ?? []).reversed() {
      if b.usd > 0 { n += 1 } else { break }
    }
    return n
  }

  // MARK: viz

  @ViewBuilder private var viz: some View {
    switch metric {
    case .today, .weekly:
      VStack(alignment: .leading, spacing: 6) {
        Text(metric == .today ? "LAST 7 DAYS" : "MON – SUN")
          .font(.system(size: 12, weight: .bold)).kerning(1).foregroundStyle(.white.opacity(0.45))
        areaChart(chartValues).frame(height: 86)
      }.padding(.top, 8)
    case .lifetime:
      milestoneView.padding(.top, 18)
    }
  }

  private func areaChart(_ values: [Double]) -> some View {
    let maxV = max(values.max() ?? 1, 0.01)
    return Chart(Array(values.enumerated()), id: \.offset) { item in
      AreaMark(x: .value("d", item.offset), y: .value("v", item.element))
        .interpolationMethod(.catmullRom)
        .foregroundStyle(LinearGradient(colors: [Color(0x34D399).opacity(0.5), Color(0x34D399).opacity(0)],
                                        startPoint: .top, endPoint: .bottom))
      LineMark(x: .value("d", item.offset), y: .value("v", item.element))
        .interpolationMethod(.catmullRom)
        .foregroundStyle(Color(0x6EE7B7))
        .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }
    .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
    .chartYScale(domain: 0...(maxV * 1.3))
  }

  private var milestoneView: some View {
    let goal = MilestoneAlert.thresholds.first(where: { $0 > model.lifetimeUsd })
      ?? (ceil(model.lifetimeUsd / 1000) * 1000)
    let pct = goal > 0 ? min(1, model.lifetimeUsd / goal) : 0
    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("NEXT MILESTONE").font(.system(size: 12, weight: .bold)).kerning(1).foregroundStyle(.white.opacity(0.5))
        Spacer()
        Text(money(goal)).font(.system(size: 12, weight: .bold)).foregroundStyle(Color(0x6EE7B7))
      }
      GeometryReader { g in
        ZStack(alignment: .leading) {
          Capsule().fill(.white.opacity(0.12))
          Capsule().fill(LinearGradient(colors: [Color(0x10B981), Color(0x6EE7B7)], startPoint: .leading, endPoint: .trailing))
            .frame(width: g.size.width * pct)
        }
      }.frame(height: 12)
    }
  }

  // MARK: footer

  private var footer: some View {
    VStack(spacing: 12) {
      Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
      HStack(alignment: .bottom) {
        HStack(spacing: 40) {
          miniStat(footStats.0.0, footStats.0.1)
          miniStat(footStats.1.0, footStats.1.1)
        }
        Spacer()
        Text("kickbacks.ai").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(0x6EE7B7))
      }
    }
  }

  private func miniStat(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.system(size: 10, weight: .bold)).kerning(1).foregroundStyle(.white.opacity(0.45))
      Text(value).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
    }
  }

  // MARK: per-metric data

  private var label: String { metric == .today ? "TODAY" : metric == .weekly ? "THIS WEEK" : "LIFETIME" }

  private var heroValue: String {
    switch metric {
    case .today:    return model.today
    case .weekly:   return money(history?.thisWeekUsd ?? 0)
    case .lifetime: return model.lifetime
    }
  }

  private var chartValues: [Double] {
    let d = (history?.daily ?? []).suffix(7).map(\.usd)
    return d.isEmpty ? [0, 0] : Array(d)
  }

  private var trendPct: Int? {
    guard let h = history, h.avgPerDayUsd > 0 else { return nil }
    switch metric {
    case .today:    return Int((model.todayUsd / h.avgPerDayUsd - 1) * 100)
    case .weekly:   return Int((h.thisWeekUsd / (h.avgPerDayUsd * 7) - 1) * 100)
    case .lifetime: return nil
    }
  }

  private var footStats: ((String, String), (String, String)) {
    let week = money(history?.thisWeekUsd ?? 0)
    switch metric {
    case .today:    return (("LIFETIME", model.lifetime), ("THIS WEEK", week))
    case .weekly:   return (("TODAY", model.today), ("LIFETIME", model.lifetime))
    case .lifetime: return (("TODAY", model.today), ("THIS WEEK", week))
    }
  }

  private func money(_ d: Double) -> String { "$" + String(format: "%.2f", d) }
}

private extension Color {
  init(_ hex: UInt) {
    self.init(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: 1)
  }
}
