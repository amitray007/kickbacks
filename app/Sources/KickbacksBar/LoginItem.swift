import Foundation
import ServiceManagement

/// "Start at login" via the OS (no launchd plist needed for the GUI app).
enum LoginItem {
  static func isEnabled() -> Bool { SMAppService.mainApp.status == .enabled }
  static func setEnabled(_ on: Bool) {
    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
    catch { NSLog("LoginItem toggle failed: \(error)") }
  }
}
