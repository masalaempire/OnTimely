import Foundation
import UserNotifications

struct NotificationPayload: Sendable {
    var taskID: UUID
    var revision: UUID
    var phase: ReminderPhase
    var action: ReminderAction

    init?(content: UNNotificationContent, actionIdentifier: String = "") {
        guard let taskID = (content.userInfo["taskID"] as? String).flatMap(UUID.init(uuidString:)),
              let revision = (content.userInfo["revision"] as? String).flatMap(UUID.init(uuidString:)),
              let phase = (content.userInfo["phase"] as? String).flatMap(ReminderPhase.init(rawValue:)) else { return nil }
        self.taskID = taskID
        self.revision = revision
        self.phase = phase
        action = ReminderAction(rawValue: actionIdentifier) ?? .open
    }
}

enum NotificationPermission: Equatable {
    case unknown, notRequested, denied, allowed
}

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    var onAction: (@MainActor @Sendable (NotificationPayload) async -> Void)?
    var shouldPresent: (@MainActor @Sendable (NotificationPayload) -> Bool)?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
        let working = UNNotificationAction(identifier: ReminderAction.working.rawValue, title: "I'm Working")
        let latestWorking = UNNotificationAction(identifier: ReminderAction.working.rawValue, title: "Yes, I'm Working")
        let snooze = UNNotificationAction(identifier: ReminderAction.snooze.rawValue, title: "Snooze 10m")
        let done = UNNotificationAction(identifier: ReminderAction.done.rawValue, title: "Submitted / Done")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ReminderPhase.suggestedStart.rawValue, actions: [working, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: ReminderPhase.latestStart.rawValue, actions: [latestWorking, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: ReminderPhase.submission.rawValue, actions: [done, snooze], intentIdentifiers: [])
        ])
    }

    func permission() async -> NotificationPermission {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notRequested
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .allowed
        @unknown default: return .denied
        }
    }

    func requestPermission() async throws -> NotificationPermission {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        return await permission()
    }

    func synchronize(events: [ReminderEvent], stillValid: @MainActor @Sendable (NotificationPayload) -> Bool) async throws {
        let desired = Set(events.map(\.id))
        let pending = await center.pendingNotificationRequests()
        let existing = Set(pending.map(\.identifier))
        let obsolete = pending.filter { request in
            guard !desired.contains(request.identifier) else { return false }
            // Let the system finish delivering a just-due request instead of racing its delivery.
            if let timestamp = request.content.userInfo["fireTimestamp"] as? Double,
               let payload = NotificationPayload(content: request.content), stillValid(payload) {
                let age = Date.now.timeIntervalSince1970 - timestamp
                if (0...60).contains(age) { return false }
            }
            return true
        }.map(\.identifier)
        if !obsolete.isEmpty { center.removePendingNotificationRequests(withIdentifiers: Array(obsolete)) }
        for event in events where !existing.contains(event.id) {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            content.categoryIdentifier = event.phase.rawValue
            content.threadIdentifier = event.taskID.uuidString
            content.userInfo = ["taskID": event.taskID.uuidString, "revision": event.revision.uuidString,
                                "phase": event.phase.rawValue, "fireTimestamp": event.fireDate.timeIntervalSince1970]
            // Use absolute instants so a wall-clock or time-zone change cannot shift the deadline.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let date = max(event.fireDate, Date.now.addingTimeInterval(1))
            let rounded = Date(timeIntervalSince1970: ceil(date.timeIntervalSince1970))
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: rounded)
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(UNNotificationRequest(identifier: event.id, content: content, trigger: trigger))
        }
    }

    func removeObsoleteDelivered(valid: @MainActor @Sendable (NotificationPayload) -> Bool) async {
        let delivered = await center.deliveredNotifications()
        let obsolete = delivered.filter { notification in
            guard let payload = NotificationPayload(content: notification.request.content) else { return true }
            return !valid(payload)
        }.map { $0.request.identifier }
        if !obsolete.isEmpty { center.removeDeliveredNotifications(withIdentifiers: obsolete) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier,
              let payload = NotificationPayload(content: response.notification.request.content,
                                                actionIdentifier: response.actionIdentifier) else { return }
        await onAction?(payload)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard let payload = NotificationPayload(content: notification.request.content) else { return [] }
        let valid = await shouldPresent?(payload) ?? false
        return valid ? [.banner, .sound, .list] : []
    }
}
