// app/Sources/KickbackBar/ShareView.swift
import SwiftUI
import AppKit
import KickbackKit
import UniformTypeIdentifiers

/// The Share window: a preview of the earnings card + Copy / Save / Post-to-X actions.
/// The card renders to a PNG locally (ImageRenderer); the app never posts anything itself.
/// Demo mode flows through (vm.effModel), so you can share sample numbers instead of real ones.
struct ShareView: View {
  @ObservedObject var vm: MenuVM

  private var card: some View {
    ShareCard(today: vm.effModel.today,
              lifetime: vm.effModel.lifetime,
              week: vm.effHistory.map { "$" + String(format: "%.2f", $0.thisWeekUsd) },
              demo: vm.demoMode)
      .frame(width: 360, height: 190)
  }

  var body: some View {
    VStack(spacing: 14) {
      card
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))

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
    .padding(18)
    .frame(width: 420)
  }

  @MainActor private func render() -> NSImage? {
    let r = ImageRenderer(content: card)
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
    panel.nameFieldStringValue = "kickbacks.png"
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

/// The shareable card itself — kept separate + pure so the preview and the rendered image
/// are guaranteed identical.
struct ShareCard: View {
  let today: String
  let lifetime: String
  let week: String?
  let demo: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 0) {
        Text("K$ ").foregroundStyle(.green).fontWeight(.bold)
        Text("Kickbacks").fontWeight(.bold)
      }.font(.title3)

      HStack(alignment: .top, spacing: 28) {
        stat("TODAY", today)
        stat("LIFETIME", lifetime)
      }

      if let week { Text("\(week) this week").font(.callout).foregroundStyle(.white.opacity(0.75)) }
      Spacer(minLength: 0)
      Text("earned passively with Kickback\(demo ? " · demo" : "")")
        .font(.caption).foregroundStyle(.white.opacity(0.6))
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(
      LinearGradient(colors: [Color(red: 0.06, green: 0.18, blue: 0.12),
                              Color(red: 0.02, green: 0.09, blue: 0.07)],
                     startPoint: .topLeading, endPoint: .bottomTrailing)
    )
    .foregroundStyle(.white)
  }

  private func stat(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6)).kerning(0.6)
      Text(value).font(.system(size: 30, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
    }
  }
}
