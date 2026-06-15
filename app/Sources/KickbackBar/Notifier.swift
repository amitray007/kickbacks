import UserNotifications
import KickbackKit

/// Fires native notifications for earning-state changes. Foreground presentation is
/// enabled by the AppDelegate's UNUserNotificationCenterDelegate. A fixed identifier
/// means a newer alert replaces the previous one rather than stacking.
enum Notifier {
  static func fire(_ note: StateAlert.Note) {
    let content = UNMutableNotificationContent()
    content.title = note.title
    content.body = note.body
    let req = UNNotificationRequest(identifier: "ai.kickback.alert", content: content, trigger: nil)
    UNUserNotificationCenter.current().add(req)
  }
}
