import Foundation

/// Runs the `kickback` CLI's `model` command and decodes its JSON.
///
/// Returns `nil` on a *transient* failure (spawn error, non-zero exit, bad JSON) so the
/// caller can keep its last good model instead of flashing a wrong state. Returns
/// `.signedOut` only when there is no CLI to call (an actionable first-run state).
public enum ModelClient {
  /// Resolve the kickback binary: $KICKBACK_BIN, then the common Homebrew paths.
  public static func binaryPath() -> String? {
    if let b = ProcessInfo.processInfo.environment["KICKBACK_BIN"], !b.isEmpty { return b }
    // Bundled next to the app's own executable (Kickback.app/Contents/MacOS/kickback) →
    // makes the .app self-contained, no brew required.
    if let exe = Bundle.main.executableURL {
      let sibling = exe.deletingLastPathComponent().appendingPathComponent("kickback").path
      if FileManager.default.isExecutableFile(atPath: sibling) { return sibling }
    }
    for p in ["/opt/homebrew/bin/kickback", "/usr/local/bin/kickback"]
    where FileManager.default.isExecutableFile(atPath: p) { return p }
    return nil
  }

  public static func fetch() -> MenuModel? {
    guard let bin = binaryPath() else { return .signedOut } // no CLI installed → actionable signed-out
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: bin)
    proc.arguments = ["model"]
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = Pipe()
    do { try proc.run() } catch { return nil }              // spawn failed → keep last
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    if proc.terminationStatus != 0 { return nil }           // transient (CLI exit 1) → keep last
    return MenuModel.decode(data)                           // parse failure → nil → keep last
  }

  /// Runs `kickback history` and decodes it. nil on any transient failure.
  public static func history() -> HistoryModel? {
    guard let bin = binaryPath() else { return nil }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: bin)
    proc.arguments = ["history"]
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = Pipe()
    do { try proc.run() } catch { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    if proc.terminationStatus != 0 { return nil }
    return HistoryModel.decode(data)
  }

  /// Spawns `kickback login` in the background (opens the browser + runs the local
  /// callback server). Returns the running process so the caller can cancel it; nil if
  /// no CLI is available. Caller polls `fetch()` for `signedIn` to know it finished.
  public static func startLogin() -> Process? {
    guard let bin = binaryPath() else { return nil }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: bin)
    proc.arguments = ["login"]
    // Long-running + unwaited: discard output to /dev/null so the child can't block on a
    // full pipe buffer (an unread Pipe would deadlock it after ~64KB).
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    do { try proc.run() } catch { return nil }
    return proc
  }

  /// Runs `kickback logout` and waits for it (revokes the server session + clears tokens).
  public static func logout() {
    guard let bin = binaryPath() else { return }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: bin)
    proc.arguments = ["logout"]
    proc.standardOutput = Pipe()
    proc.standardError = Pipe()
    try? proc.run()
    proc.waitUntilExit()
  }
}
