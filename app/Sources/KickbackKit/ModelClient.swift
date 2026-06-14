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
}
