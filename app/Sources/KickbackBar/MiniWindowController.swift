// app/Sources/KickbackBar/MiniWindowController.swift
import AppKit
import SwiftUI

/// A small always-on-top, borderless, draggable HUD panel hosting a SwiftUI view.
/// Non-activating (never steals focus from the editor) and visible on all Spaces.
/// SwiftUI's `Window` can't float on macOS 13, so this drops to AppKit.
@MainActor final class MiniWindowController {
  private var panel: NSPanel?
  private let makeContent: @MainActor () -> AnyView

  init(content: @escaping @MainActor () -> AnyView) { self.makeContent = content }

  func setVisible(_ visible: Bool) {
    if visible { showPanel() } else { panel?.orderOut(nil) }
  }

  private func showPanel() {
    if panel == nil {
      let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 150, height: 56),
                      styleMask: [.borderless, .nonactivatingPanel],
                      backing: .buffered, defer: false)
      p.level = .floating
      p.isMovableByWindowBackground = true     // drag anywhere on the HUD to move it
      p.isOpaque = false
      p.backgroundColor = .clear                // let the SwiftUI material show through
      p.hasShadow = true
      p.hidesOnDeactivate = false
      p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
      let host = NSHostingView(rootView: makeContent())
      host.frame = NSRect(x: 0, y: 0, width: 150, height: 56)
      host.autoresizingMask = [.width, .height]
      p.contentView = host
      p.setFrameAutosaveName("ai.kickback.mini")     // remember where the user parks it
      if !p.setFrameUsingName("ai.kickback.mini") { p.center() }
      panel = p
    }
    panel?.orderFrontRegardless()
  }
}
