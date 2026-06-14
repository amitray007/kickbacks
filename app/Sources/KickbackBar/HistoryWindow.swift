// app/Sources/KickbackBar/HistoryWindow.swift
import SwiftUI
import KickbackKit

struct HistoryWindow: View {
  @StateObject private var vm = HistoryVM()

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let h = vm.model {
        header(h)
        if h.isEmpty { emptyState } else { chart(h); tiles(h); stats(h) }
      } else if vm.loading {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Text("Couldn't load history.").foregroundStyle(.secondary)
      }
    }
    .padding(18)
    .frame(width: 460, height: 360)
    .onAppear { vm.load() }
  }

  private func header(_ h: HistoryModel) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 22) {
      stat("LIFETIME", usd(h.lifetimeUsd))
      stat("SINCE INSTALL", usd(h.sinceInstallUsd))
      Spacer()
      Text("\(h.daysTracked) day\(h.daysTracked == 1 ? "" : "s")").foregroundStyle(.secondary).font(.caption)
      Button("↻") { vm.load() }.buttonStyle(.borderless)
    }
  }

  private func chart(_ h: HistoryModel) -> some View {
    let maxUsd = max(h.daily.map(\.usd).max() ?? 1, 0.01)
    return VStack(alignment: .leading, spacing: 4) {
      GeometryReader { geo in
        HStack(alignment: .bottom, spacing: 4) {
          ForEach(Array(h.daily.enumerated()), id: \.offset) { _, d in
            RoundedRectangle(cornerRadius: 2)
              .fill(d.hitCap ? Color.orange : Color.green)
              .frame(height: max(3, geo.size.height * CGFloat(d.usd / maxUsd)))
          }
        }
      }.frame(height: 110)
      Text("$ / day · amber = hit cap").font(.caption2).foregroundStyle(.secondary)
    }
  }

  private func tiles(_ h: HistoryModel) -> some View {
    HStack(spacing: 8) {
      tile("This week", usd(h.thisWeekUsd), dim: !h.hasEnough)
      tile("This month", usd(h.thisMonthUsd), dim: !h.hasEnough)
      tile("Best day", h.bestDay.map { usd($0.usd) } ?? "—", dim: h.bestDay == nil)
      tile("Avg/day", usd(h.avgPerDayUsd), dim: !h.hasEnough)
    }
  }

  @ViewBuilder private func stats(_ h: HistoryModel) -> some View {
    if !h.hasEnough {
      Text("Only \(h.daysTracked) day\(h.daysTracked == 1 ? "" : "s") tracked — weekly/monthly views fill in as you keep earning.")
        .font(.caption).foregroundStyle(.orange)
    } else {
      Text("● Hit cap \(h.capHitsLast7) of last 7 days   ● \(h.campaignsSeen) campaigns seen   ● \(fmt(h.activeHours))h active")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 6) {
      Text("📈 No history yet").font(.headline)
      Text("Your first full day appears tomorrow. Kickback charts your earnings as you use it.")
        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Text("Tip: keep the background poller on so days aren't missed.").font(.caption2).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 130)
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5])))
  }

  private func stat(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.title3.bold())
    }
  }
  private func tile(_ label: String, _ value: String, dim: Bool) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.headline).foregroundStyle(dim ? .secondary : .primary)
    }
    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
  }
  private func usd(_ n: Double) -> String { "$" + String(format: "%.2f", n) }
  private func fmt(_ n: Double) -> String { String(format: "%.1f", n) }
}
