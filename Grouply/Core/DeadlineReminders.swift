import Foundation
import UserNotifications

/// Local H-1 deadline reminders for the signed-in user's own open tasks. Device-only; no server push.
enum DeadlineReminders {
  static let prefix = "deadline-"

  /// Tasks the assignee still has to act on, in active projects, whose H-1 moment is in the future.
  static func plan(tasks: [GLTask], activeProjectIDs: Set<String>, now: Date) -> [(id: String, title: String, fireAt: Date)] {
    tasks.compactMap { t in
      let fireAt = t.dueAt.addingTimeInterval(-86400)
      guard [.todo, .inProgress, .needsRevision].contains(t.status),
        activeProjectIDs.contains(t.projectID), fireAt > now
      else { return nil }
      return (prefix + t.id, t.title, fireAt)
    }
  }

  @MainActor private static var generation = 0

  /// Replaces every pending deadline reminder with the given plan. An empty plan (e.g. logout) clears them.
  /// A newer call supersedes an older one still in flight, so a previous account's plan can't land late.
  @MainActor static func sync(_ plan: [(id: String, title: String, fireAt: Date)]) async {
    generation += 1
    let mine = generation
    let center = UNUserNotificationCenter.current()
    let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
    guard mine == generation else { return }
    center.removePendingNotificationRequests(withIdentifiers: old)
    guard !plan.isEmpty,
      (try? await center.requestAuthorization(options: [.alert, .sound])) == true
    else { return }
    // ponytail: iOS keeps max 64 pending requests; take the nearest 60 if a user ever has more open tasks.
    for item in plan.sorted(by: { $0.fireAt < $1.fireAt }).prefix(60) {
      guard mine == generation else { return }
      let content = UNMutableNotificationContent()
      content.title = "Deadline besok"
      content.body = item.title
      content.sound = .default
      let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireAt)
      try? await center.add(
        UNNotificationRequest(
          identifier: item.id, content: content,
          trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }
  }
}
