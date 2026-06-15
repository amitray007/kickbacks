import UserNotifications
import KickbackKit

/// Fires native notifications for earning-state changes. Foreground presentation is
/// enabled by the AppDelegate's UNUserNotificationCenterDelegate. A fixed identifier
/// means a newer alert replaces the previous one rather than stacking.
enum Notifier {
  static func fire(title: String, body: String, id: String = "ai.kickback.alert") {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(req)
  }
  static func fire(_ note: StateAlert.Note) { fire(title: note.title, body: note.body) }
}
