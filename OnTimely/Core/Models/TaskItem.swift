import Foundation
import SwiftData

enum TaskStatus: String, Codable, Sendable {
    case inbox, active, completed
}

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var statusRawValue: String

    var dueDate: Date?
    /// Durations are stored in seconds.
    var estimatedDuration: TimeInterval
    var suggestedStartDate: Date?
    var latestSafeStartOverride: Date?
    var safetyBuffer: TimeInterval
    var submissionReminderLeadTime: TimeInterval
    var reminderInterval: TimeInterval

    var hasConfirmedWorking: Bool
    var hasConfirmedLatestStart: Bool
    var completedAt: Date?
    var activatedAt: Date?
    var snoozedUntil: Date?
    var snoozedPhaseRawValue: String?
    /// Old notification actions cannot mutate a newly edited plan.
    var reminderRevision: UUID

    // Optional metadata lets existing local tasks migrate without losing their plans.
    var calendarFeedFingerprint: String?
    var calendarEventID: String?
    var calendarSourceTitle: String?
    var calendarSourceDueDate: Date?
    var calendarReminderOverrides: Bool = false
    var calendarDeadlineOverridden: Bool = false
    var calendarIsCancelled: Bool = false

    init(title: String, createdAt: Date = .now) {
        id = UUID()
        self.title = title
        self.createdAt = createdAt
        statusRawValue = TaskStatus.inbox.rawValue
        estimatedDuration = 60 * 60
        safetyBuffer = 30 * 60
        submissionReminderLeadTime = 30 * 60
        reminderInterval = 10 * 60
        hasConfirmedWorking = false
        hasConfirmedLatestStart = false
        reminderRevision = UUID()
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRawValue) ?? .inbox }
        set { statusRawValue = newValue.rawValue }
    }

    var latestSafeStartDate: Date? {
        guard let dueDate else { return nil }
        return latestSafeStartOverride ?? DeadlineCalculator.latestSafeStart(
            dueDate: dueDate, estimatedDuration: estimatedDuration, safetyBuffer: safetyBuffer
        )
    }

    var isCalendarTask: Bool { calendarEventID != nil }

    var latestStartLabel: String { isCalendarTask ? "Latest start" : "Latest safe start" }

    var calendarPlanNeedsReview: Bool {
        guard isCalendarTask, let dueDate, let suggestedStartDate, let latest = latestSafeStartDate else { return false }
        return suggestedStartDate >= dueDate || latest >= dueDate || suggestedStartDate > latest
    }

    var snapshot: TaskSnapshot {
        TaskSnapshot(
            id: id, title: title, status: status, dueDate: dueDate,
            suggestedStartDate: suggestedStartDate, latestSafeStartDate: latestSafeStartDate,
            submissionLeadTime: submissionReminderLeadTime, reminderInterval: reminderInterval,
            hasConfirmedWorking: hasConfirmedWorking, hasConfirmedLatestStart: hasConfirmedLatestStart,
            activatedAt: activatedAt, snoozedUntil: snoozedUntil,
            snoozedPhase: snoozedPhaseRawValue.flatMap(ReminderPhase.init(rawValue:)),
            revision: reminderRevision
        )
    }
}
