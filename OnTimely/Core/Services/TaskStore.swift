import Foundation
import SwiftData

enum TaskStoreError: LocalizedError {
    case invalidPlan(String), emptyTitle

    var errorDescription: String? {
        switch self {
        case .invalidPlan(let message): message
        case .emptyTitle: "Give the task a name."
        }
    }
}

/// All UI and notification actions share this context, with explicit saves before scheduling.
@MainActor
final class TaskStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        context.autosaveEnabled = false
    }

    func allTasks() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\TaskItem.createdAt)]))
    }

    func task(id: UUID) throws -> TaskItem? {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func capture(title: String, now: Date = .now) throws -> TaskItem {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TaskStoreError.emptyTitle }
        let task = TaskItem(title: title, createdAt: now)
        context.insert(task)
        try save()
        return task
    }

    func rename(_ task: TaskItem, title: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TaskStoreError.emptyTitle }
        task.title = title
        task.reminderRevision = UUID()
        try save()
    }

    func activate(_ task: TaskItem, plan: TaskPlan, now: Date = .now) throws {
        let editingOverdueImport = task.isCalendarTask && task.status == .active && task.dueDate == plan.dueDate
        if let error = plan.validationMessage(at: now, allowOverdue: editingOverdueImport) { throw TaskStoreError.invalidPlan(error) }
        let scheduleChanged = task.status != .active || task.dueDate != plan.dueDate
            || task.estimatedDuration != TimeInterval(plan.estimatedMinutes) * 60
            || task.safetyBuffer != TimeInterval(plan.safetyBufferMinutes) * 60
            || task.suggestedStartDate != plan.suggestedStartDate
            || task.latestSafeStartOverride != plan.latestSafeStartOverride
            || task.submissionReminderLeadTime != TimeInterval(plan.submissionLeadMinutes) * 60
            || task.reminderInterval != TimeInterval(plan.reminderIntervalMinutes) * 60
        if task.isCalendarTask {
            if scheduleChanged { task.calendarReminderOverrides = true }
            task.calendarDeadlineOverridden = plan.dueDate != task.calendarSourceDueDate
        }
        task.title = plan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.dueDate = plan.dueDate
        task.estimatedDuration = TimeInterval(plan.estimatedMinutes) * 60
        task.safetyBuffer = TimeInterval(plan.safetyBufferMinutes) * 60
        task.suggestedStartDate = plan.suggestedStartDate
        task.latestSafeStartOverride = plan.latestSafeStartOverride
        task.submissionReminderLeadTime = TimeInterval(plan.submissionLeadMinutes) * 60
        task.reminderInterval = TimeInterval(plan.reminderIntervalMinutes) * 60
        task.status = .active
        task.completedAt = nil
        task.reminderRevision = UUID()
        if scheduleChanged {
            // Gives a newly activated, already-due phase one immediate reminder.
            task.activatedAt = now.addingTimeInterval(2)
            task.hasConfirmedWorking = false
            task.hasConfirmedLatestStart = false
            clearSnooze(task)
        }
        try save()
    }

    func confirmWorking(_ task: TaskItem, now: Date = .now) throws {
        guard task.status == .active else { return }
        task.hasConfirmedWorking = true
        // Confirming early must not suppress the separate latest-start checkpoint.
        if let latest = task.latestSafeStartDate, now >= latest { task.hasConfirmedLatestStart = true }
        if task.snoozedPhaseRawValue != ReminderPhase.submission.rawValue { clearSnooze(task) }
        try save()
    }

    func snooze(_ task: TaskItem, minutes: Int = 10, now: Date = .now) throws {
        guard task.status == .active, let phase = task.snapshot.phase(at: now) else { return }
        var until = now.addingTimeInterval(TimeInterval(max(1, minutes)) * 60)
        switch phase {
        case .suggestedStart:
            if let latest = task.latestSafeStartDate { until = min(until, latest) }
            if let submission = task.snapshot.submissionStartDate { until = min(until, submission) }
        case .latestStart:
            if let submission = task.snapshot.submissionStartDate { until = min(until, submission) }
        case .submission:
            // The actual deadline always breaks through a pre-deadline snooze.
            if let due = task.dueDate, due > now { until = min(until, due) }
        }
        task.snoozedUntil = until
        task.snoozedPhaseRawValue = phase.rawValue
        try save()
    }

    func complete(_ task: TaskItem, now: Date = .now) throws {
        guard task.status != .completed else { return }
        task.status = .completed
        task.completedAt = now
        task.reminderRevision = UUID()
        clearSnooze(task)
        try save()
    }

    func moveToInbox(_ task: TaskItem) throws {
        task.status = .inbox
        task.completedAt = nil
        task.activatedAt = nil
        task.hasConfirmedWorking = false
        task.hasConfirmedLatestStart = false
        task.reminderRevision = UUID()
        clearSnooze(task)
        try save()
    }

    func delete(_ task: TaskItem) throws {
        if let fingerprint = task.calendarFeedFingerprint, let eventID = task.calendarEventID,
           let subscription = try calendarSubscriptions().first(where: { $0.feedFingerprint == fingerprint }),
           !subscription.dismissedEventIDs.contains(eventID) {
            subscription.dismissedEventIDs.append(eventID)
        }
        context.delete(task)
        try save()
    }

    func calendarSubscriptions() throws -> [CalendarSubscription] {
        try context.fetch(FetchDescriptor<CalendarSubscription>(sortBy: [SortDescriptor(\CalendarSubscription.createdAt)]))
    }

    /// Subscription changes and imported tasks are committed together before any notifications are scheduled.
    func importCalendar(_ feed: ImportedCalendarFeed, subscription: CalendarSubscription,
                        isNewSubscription: Bool = false, selectedEventIDs: Set<String>? = nil,
                        submissionLeadMinutes: Int = 30, reminderIntervalMinutes: Int = 10,
                        now: Date = .now) throws -> CalendarImportResult {
        if isNewSubscription { context.insert(subscription) }
        let zone = TimeZone(identifier: subscription.timeZoneIdentifier) ?? .current
        var existing: [String: TaskItem] = [:]
        for task in try allTasks() where task.calendarFeedFingerprint == subscription.feedFingerprint {
            if let id = task.calendarEventID { existing[id] = task }
        }
        if let selectedEventIDs {
            let omitted = feed.events.filter {
                !$0.isCancelled && ($0.dueDate ?? .distantPast) > now && !selectedEventIDs.contains($0.id)
            }.map(\.id)
            subscription.dismissedEventIDs = Array(Set(subscription.dismissedEventIDs).union(omitted)).sorted()
        }
        let dismissed = Set(subscription.dismissedEventIDs)
        var result = CalendarImportResult()
        for event in feed.events {
            if let task = existing[event.id] {
                if event.isCancelled {
                    if !task.calendarIsCancelled {
                        task.calendarIsCancelled = true
                        if task.status == .active { task.status = .inbox; task.activatedAt = nil }
                        task.reminderRevision = UUID()
                        clearSnooze(task)
                        result.updated += 1
                    }
                    continue
                }
                guard let due = event.dueDate else { continue }
                let deadlineChanged = task.calendarSourceDueDate != due
                let titleChanged = task.calendarSourceTitle != event.title
                let restored = task.calendarIsCancelled
                if titleChanged && task.title == task.calendarSourceTitle { task.title = event.title }
                task.calendarSourceTitle = event.title
                task.calendarSourceDueDate = due
                task.calendarIsCancelled = false
                if deadlineChanged {
                    if !task.calendarDeadlineOverridden { task.dueDate = due }
                    if !task.calendarReminderOverrides, let actualDue = task.dueDate {
                        let times = CalendarReminderRules.times(dueDate: actualDue, timeZone: zone)
                        task.suggestedStartDate = times.suggestedStart
                        task.latestSafeStartOverride = times.latestStart
                    }
                    // Completed and Inbox tasks retain their status on every refresh.
                    if task.status == .active {
                        task.activatedAt = now.addingTimeInterval(2)
                        task.hasConfirmedWorking = false
                        task.hasConfirmedLatestStart = false
                        clearSnooze(task)
                    }
                }
                if deadlineChanged || titleChanged || restored {
                    task.reminderRevision = UUID()
                    result.updated += 1
                }
            } else {
                guard !event.isCancelled, let due = event.dueDate else { continue }
                guard due > now else { result.skippedPastDue += 1; continue }
                guard !dismissed.contains(event.id), selectedEventIDs?.contains(event.id) != false else { continue }
                let times = CalendarReminderRules.times(dueDate: due, timeZone: zone)
                let task = TaskItem(title: event.title, createdAt: now)
                task.calendarFeedFingerprint = subscription.feedFingerprint
                task.calendarEventID = event.id
                task.calendarSourceTitle = event.title
                task.calendarSourceDueDate = due
                task.dueDate = due
                task.suggestedStartDate = times.suggestedStart
                task.latestSafeStartOverride = times.latestStart
                // The event's display duration is never used as an estimate.
                task.safetyBuffer = 0
                task.submissionReminderLeadTime = TimeInterval(submissionLeadMinutes) * 60
                task.reminderInterval = TimeInterval(reminderIntervalMinutes) * 60
                task.status = .active
                task.activatedAt = now.addingTimeInterval(2)
                context.insert(task)
                existing[event.id] = task
                result.added += 1
            }
        }
        subscription.lastSyncedAt = now
        subscription.lastSyncError = nil
        try save()
        return result
    }

    func recordCalendarError(_ subscription: CalendarSubscription, message: String) throws {
        subscription.lastSyncError = message
        try save()
    }

    func disconnectCalendar(_ subscription: CalendarSubscription) throws {
        // Keep imported tasks and their plans when the subscription is disconnected.
        context.delete(subscription)
        try save()
    }

    /// Stale banners are harmless after an edit, completion, or deletion.
    @discardableResult
    func applyReminderAction(
        taskID: UUID, revision: UUID, action: ReminderAction, now: Date = .now
    ) throws -> TaskItem? {
        guard let task = try task(id: taskID), task.status == .active,
              task.reminderRevision == revision else { return nil }
        switch action {
        case .working: try confirmWorking(task, now: now)
        case .snooze: try snooze(task, now: now)
        case .done: try complete(task, now: now)
        case .open: break
        }
        return task
    }

    private func clearSnooze(_ task: TaskItem) {
        task.snoozedUntil = nil
        task.snoozedPhaseRawValue = nil
    }

    private func save() throws {
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
}
