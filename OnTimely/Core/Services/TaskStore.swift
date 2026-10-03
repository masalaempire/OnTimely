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
        if let error = plan.validationMessage(at: now) { throw TaskStoreError.invalidPlan(error) }
        let scheduleChanged = task.status != .active || task.dueDate != plan.dueDate
            || task.estimatedDuration != TimeInterval(plan.estimatedMinutes) * 60
            || task.safetyBuffer != TimeInterval(plan.safetyBufferMinutes) * 60
            || task.suggestedStartDate != plan.suggestedStartDate
            || task.latestSafeStartOverride != plan.latestSafeStartOverride
            || task.submissionReminderLeadTime != TimeInterval(plan.submissionLeadMinutes) * 60
            || task.reminderInterval != TimeInterval(plan.reminderIntervalMinutes) * 60
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
        context.delete(task)
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
