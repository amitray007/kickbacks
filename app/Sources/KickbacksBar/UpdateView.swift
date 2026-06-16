import SwiftUI
import AppKit
import KickbacksKit

/// The update window: version + date, the rendered changelog, and the action buttons.
/// While updating it shows a live log; the user can close it and the upgrade continues.
struct UpdateView: View {
  @ObservedObject var vm: MenuVM
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let up = vm.availableUpdate {
        header(up)
        Divider()
        if vm.updateState == .updating || vm.updateState == .failed {
          progressPane
        } else {
          changelog(up)
        }
        Divider()
        footer(up)
      } else {
        Text("You're up to date.").padding(24)
      }
    }
    .frame(width: 460, height: 460)
  }

  private func header(_ up: Release) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "arrow.down.circle.fill").font(.title).foregroundStyle(.green)
      VStack(alignment: .leading, spacing: 2) {
        Text("Kickbacks v\(up.version)").font(.headline)
        Text(dateText(up.publishedAt).map { "Released \($0)" } ?? "A new version is available")
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
    }.padding(16)
  }

  private func changelog(_ up: Release) -> some View {
    ScrollView {
      Text(markdown(up.notes))
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
  }

  private var progressPane: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        if vm.updateState == .updating { ProgressView().controlSize(.small) }
        Text(vm.updateState == .failed ? "Update failed." : "Updating — rebuilding from source, this can take a few minutes…")
          .font(.callout).foregroundStyle(vm.updateState == .failed ? .red : .primary)
      }
      ScrollViewReader { proxy in
        ScrollView {
          Text(vm.updateLog.joined(separator: "\n"))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
          Color.clear.frame(height: 1).id("logBottom")
        }
        .onChange(of: vm.updateLog.count) { _ in
          proxy.scrollTo("logBottom", anchor: .bottom)
        }
      }
      .frame(maxHeight: .infinity)
      .background(Color.secondary.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }.padding(16)
  }

  private func footer(_ up: Release) -> some View {
    HStack {
      if vm.updateState == .failed, let u = URL(string: up.htmlURL) {
        Button("Open release page") { NSWorkspace.shared.open(u) }
        Spacer()
        Button("Close") { dismiss() }
      } else if vm.updateState == .updating {
        Spacer()
        Button("Continue in background") { dismiss() }.keyboardShortcut(.defaultAction)
      } else {
        Button("Skip this version") { vm.skipUpdate(); dismiss() }
        Spacer()
        Button("Later") { dismiss() }
        Button(vm.canBrewUpdate ? "Update & Restart" : "Open release page") { vm.startUpdate() }
          .keyboardShortcut(.defaultAction)
      }
    }.padding(16)
  }

  /// Render the release markdown; fall back to plain text if it doesn't parse.
  private func markdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(s)
  }

  /// "Jun 16, 2026" from an ISO-8601 timestamp; nil if it doesn't parse.
  private func dateText(_ iso: String) -> String? {
    let f = ISO8601DateFormatter()
    guard let d = f.date(from: iso) else { return nil }
    let out = DateFormatter(); out.dateStyle = .medium; out.timeStyle = .none
    return out.string(from: d)
  }
}
