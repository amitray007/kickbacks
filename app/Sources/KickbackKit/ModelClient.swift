import Foundation

/// Runs the `kickback` CLI's `model` command and decodes its JSON. Any failure
/// (no binary, spawn error, bad JSON) degrades to `.signedOut` so the UI never crashes.
public enum ModelClient {
  /// Resolve the kickback binary: $KICKBACK_BIN, then the common Homebrew paths.
  public static func binaryPath() -> String? {
    if let b = ProcessInfo.processInfo.environment["KICKBACK_BIN"], !b.isEmpty { return b }
    for p in ["/opt/homebrew/bin/kickback", "/usr/local/bin/kickback"]
    where FileManager.default.isExecutableFile(atPath: p) { return p }
    return nil
  }

  public static func fetch() -> MenuModel {
    guard let bin = binaryPath() else { return .signedOut }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: bin)
    proc.arguments = ["model"]
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = Pipe()
    do { try proc.run() } catch { return .signedOut }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    return MenuModel.decode(data) ?? .signedOut
  }
}
