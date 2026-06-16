import Foundation

/// A published GitHub release, normalized for display + comparison.
public struct Release: Equatable, Sendable {
  public let version: String      // numeric, no leading "v" — e.g. "0.2.0"
  public let notes: String        // GitHub release body (markdown)
  public let htmlURL: String
  public let publishedAt: String  // ISO-8601, for display

  public init(version: String, notes: String, htmlURL: String, publishedAt: String) {
    self.version = version; self.notes = notes; self.htmlURL = htmlURL; self.publishedAt = publishedAt
  }
}

/// How this build was installed — decides whether `brew upgrade` is the update path.
public enum InstallMethod: Equatable, Sendable {
  case homebrew(brewPath: String)         // formula install: bare CLI binaries via launchd
  case homebrewCask(brewPath: String)     // cask install: .app bundle in /Applications
  case appBundle                          // manual .app install — release-page fallback
  case unknown                            // dev / other — release-page fallback
}

/// Update engine. Pure helpers (`parseVersion`/`isNewer`/`parseRelease`/`classify`) are
/// unit-tested; the impure wrappers (`currentVersion`/`fetchLatest`/`installMethod`) are
/// thin shells over them and are exercised manually.
public enum Updater {
  static let repoSlug = "amitray007/kickbacks"

  /// Parse "v1.2.3" / "1.2" / "0.2.0-beta" into numeric components. Suffixes after the
  /// first '-' or '+' are dropped. Returns nil if any present component isn't an integer.
  static func parseVersion(_ s: String) -> (Int, Int, Int)? {
    var str = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if str.hasPrefix("v") || str.hasPrefix("V") { str.removeFirst() }
    if let i = str.firstIndex(where: { $0 == "-" || $0 == "+" }) { str = String(str[..<i]) }
    guard !str.isEmpty else { return nil }
    let parsed = str.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
    guard !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) else { return nil }
    let nums = parsed.compactMap { $0 }
    return (nums.count > 0 ? nums[0] : 0, nums.count > 1 ? nums[1] : 0, nums.count > 2 ? nums[2] : 0)
  }

  /// True only when `latest` is strictly greater by numeric semver. Parse failure → false.
  public static func isNewer(_ latest: String, than current: String) -> Bool {
    guard let l = parseVersion(latest), let c = parseVersion(current) else { return false }
    return l > c   // Swift compares (Int,Int,Int) tuples lexicographically by element
  }

  /// Strip a leading "v" from a tag for display/comparison.
  static func normalize(_ tag: String) -> String {
    var s = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
    return s
  }

  /// Map GitHub's release JSON to a `Release`. nil on bad JSON or a missing tag.
  static func parseRelease(_ data: Data) -> Release? {
    struct GHRelease: Decodable { let tag_name: String; let body: String?; let html_url: String; let published_at: String? }
    guard let r = try? JSONDecoder().decode(GHRelease.self, from: data) else { return nil }
    let v = normalize(r.tag_name)
    guard !v.isEmpty else { return nil }
    return Release(version: v, notes: r.body ?? "", htmlURL: r.html_url, publishedAt: r.published_at ?? "")
  }

  /// Pure install-method classifier (paths + an existence probe are injected for tests).
  /// Prefers a `brew` sibling of the resolved CLI; else a brew prefix on the running binary;
  /// else an `.app` bundle; else unknown.
  static func classify(executablePath: String, cliPath: String?, exists: (String) -> Bool) -> InstallMethod {
    if let cli = cliPath {
      let dir = (cli as NSString).deletingLastPathComponent
      let brew = (dir as NSString).appendingPathComponent("brew")
      if exists(brew) { return .homebrew(brewPath: brew) }
    }
    if executablePath.contains("/Cellar/") || executablePath.hasPrefix("/opt/homebrew/") || executablePath.hasPrefix("/usr/local/") {
      for b in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where exists(b) { return .homebrew(brewPath: b) }
    }
    if executablePath.contains(".app/Contents/MacOS/") {
      for b in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where exists(b) { return .homebrewCask(brewPath: b) }
      return .appBundle
    }
    return .unknown
  }

  /// The installed version, via `kickbacks --version`; falls back to the .app Info.plist.
  /// nil only if neither is available (no CLI + no bundle version).
  public static func currentVersion() -> String? {
    if let bin = ModelClient.binaryPath() {
      let proc = Process()
      proc.executableURL = URL(fileURLWithPath: bin)
      proc.arguments = ["--version"]
      let out = Pipe(); proc.standardOutput = out; proc.standardError = Pipe()
      if (try? proc.run()) != nil {
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        if proc.terminationStatus == 0,
           let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
          return s
        }
      }
    }
    return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
  }

  /// Anonymous, read-only GET of this repo's latest stable release. nil on any failure.
  public static func fetchLatest() async -> Release? {
    guard let url = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest") else { return nil }
    var req = URLRequest(url: url)
    req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    req.setValue("kickbacks-bar", forHTTPHeaderField: "User-Agent")   // GitHub rejects UA-less requests
    req.timeoutInterval = 15
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
      return parseRelease(data)
    } catch { return nil }
  }

  /// Real install-method detection from the running binary + resolved CLI.
  public static func installMethod() -> InstallMethod {
    let exe = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? ""
    return classify(executablePath: exe, cliPath: ModelClient.binaryPath()) {
      FileManager.default.isExecutableFile(atPath: $0)
    }
  }
}
