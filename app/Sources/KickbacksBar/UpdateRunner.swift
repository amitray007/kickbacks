import AppKit
import Foundation

/// Runs `brew upgrade kickbacks` (or `--cask`) detached, streaming output line-by-line, then
/// relaunches the menu-bar app. All callbacks are delivered on the main queue.
enum UpdateRunner {
  /// Whether the `ai.kickbacks.bar` launchd agent is installed (file check — no spawn).
  static func barAgentInstalled() -> Bool {
    let p = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents/ai.kickbacks.bar.plist")
    return FileManager.default.fileExists(atPath: p)
  }

  /// `brew update && brew upgrade [--cask] kickbacks` via a login shell.
  /// `onLine` fires per output line; `completion(true)` on exit status 0.
  static func upgrade(brewPath: String, isCask: Bool = false,
                      onLine: @escaping @Sendable (String) -> Void,
                      completion: @escaping @Sendable (Bool) -> Void) {
    let brew = "'" + brewPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
    let upgradeTarget = isCask ? "--cask kickbacks" : "kickbacks"
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/sh")
    proc.arguments = ["-lc", "\(brew) update && \(brew) upgrade \(upgradeTarget)"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = pipe
    pipe.fileHandleForReading.readabilityHandler = { h in
      let d = h.availableData
      guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
      for line in s.split(separator: "\n", omittingEmptySubsequences: true) {
        let str = String(line)
        DispatchQueue.main.async { onLine(str) }
      }
    }
    proc.terminationHandler = { p in
      pipe.fileHandleForReading.readabilityHandler = nil
      let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
      if !remaining.isEmpty, let s = String(data: remaining, encoding: .utf8) {
        for line in s.split(separator: "\n", omittingEmptySubsequences: true) {
          let str = String(line)
          DispatchQueue.main.async { onLine(str) }
        }
      }
      let ok = p.terminationStatus == 0
      DispatchQueue.main.async { completion(ok) }
    }
    do { try proc.run() } catch { DispatchQueue.main.async { completion(false) } }
  }

  /// Kickstart the launchd bar agent: it atomically terminates this process and starts the
  /// new binary in one launchd operation, so no separate NSApp.terminate is needed (which
  /// would double-restart given KeepAlive=true). Only called when the agent is loaded.
  static func relaunch() {
    let label = "gui/\(getuid())/ai.kickbacks.bar"
    let helper = Process()
    helper.executableURL = URL(fileURLWithPath: "/bin/sh")
    helper.arguments = ["-c", "sleep 0.5; launchctl kickstart -k \(label)"]
    try? helper.run()   // detached; kickstart -k will terminate + relaunch us
  }

  /// Relaunch after a cask upgrade: open the updated .app bundle and exit.
  /// Used when running as Kickbacks.app (not a launchd agent).
  static func relaunchCask() {
    let helper = Process()
    helper.executableURL = URL(fileURLWithPath: "/bin/sh")
    helper.arguments = ["-c", "sleep 0.5; open /Applications/Kickbacks.app"]
    try? helper.run()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
  }
}
