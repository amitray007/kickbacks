// app/Sources/KickbacksBar/MiniView.swift
import SwiftUI
import KickbacksKit

/// The floating mini HUD: a state dot + today's earnings. Driven by the same view-model as
/// the panel, so it reflects Demo/Privacy modes live. Drag anywhere to move it.
struct MiniView: View {
  @ObservedObject var vm: MenuVM
  private var m: MenuModel { vm.effModel }

  var body: some View {
    HStack(spacing: 10) {
      Circle().fill(dotColor).frame(width: 8, height: 8)
      VStack(alignment: .leading, spacing: 0) {
        Text(value)
          .font(.system(size: 22, weight: .heavy)).monospacedDigit()
          .lineLimit(1).minimumScaleFactor(0.5)
        Text("TODAY").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).kerning(0.6)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .frame(width: 150, height: 56, alignment: .leading)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
  }

  private var value: String {
    guard vm.effPhase == .signedIn else { return "—" }
    return vm.hideAmounts ? "•••" : m.today
  }

  private var dotColor: Color {
    switch MenuPresentation.tint(state: m.state, phase: vm.effPhase) {
    case .green, .primary: return .green
    case .amber:           return .orange
    case .red:             return .red
    case .muted:           return .secondary
    }
  }
}
