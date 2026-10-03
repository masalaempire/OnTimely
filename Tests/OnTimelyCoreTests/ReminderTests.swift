import Foundation
import SwiftData
import Testing
@testable import OnTimelyCore

private let origin = Date(timeIntervalSince1970: 1_800_000_000)

private func sample() -> TaskSnapshot {
    TaskSnapshot(id: UUID(), title: "AP Lang essay", status: .active,
                 dueDate: origin.addingTimeInterval(4 * 3600),
                 suggestedStartDate: origin.addingTimeInterval(3600),
                 latestSafeStartDate: origin.addingTimeInterval(2 * 3600),
                 submissionLeadTime: 1800, reminderInterval: 600,
                 hasConfirmedWorking: false, hasConfirmedLatestStart: false,
                 activatedAt: origin, snoozedUntil: nil, snoozedPhase: nil, revision: UUID())
}

struct ReminderTests {
    @Test func latestStartSubtractsEstimateAndBuffer() {
        let due = origin.addingTimeInterval(23 * 3600 + 59 * 60)
        let latest = DeadlineCalculator.latestSafeStart(dueDate: due, estimatedDuration: 2 * 3600, safetyBuffer: 30 * 60)
        #expect(latest == origin.addingTimeInterval(21 * 3600 + 29 * 60))
    }

    @Test func phasesAndAttentionChangeAtExactBoundaries() {
        let task = sample()
        #expect(task.phase(at: origin) == nil)
        #expect(task.phase(at: task.suggestedStartDate!) == .suggestedStart)
        #expect(task.phase(at: task.latestSafeStartDate!) == .latestStart)
        #expect(task.phase(at: task.submissionStartDate!) == .submission)
        #expect(task.attention(at: task.dueDate!) == .overdue)
        #expect(task.attention(at: task.submissionStartDate!) == .submission)
    }

    @Test func inboxAndCompletedTasksNeverSchedule() {
        var task = sample()
        task.status = .inbox
        #expect(ReminderScheduler.events(for: task, now: origin).isEmpty)
        task.status = .completed
        #expect(ReminderScheduler.events(for: task, now: origin).isEmpty)
    }

    @Test func repeatsStayInsideTheirOwnPhase() {
        let task = sample()
        let events = ReminderScheduler.events(for: task, now: origin)
        let suggested = events.filter { $0.phase == .suggestedStart }
        #expect(suggested.count == 6)
        #expect(suggested.first?.fireDate == task.suggestedStartDate)
        #expect(suggested.allSatisfy { $0.fireDate < task.latestSafeStartDate! })
        let latest = events.filter { $0.phase == .latestStart }
        #expect(latest.first?.fireDate == task.latestSafeStartDate)
        #expect(latest.allSatisfy { $0.fireDate < task.submissionStartDate! })
    }

    @Test func workingDoesNotSilenceLatestOrSubmission() {
        var task = sample()
        task.hasConfirmedWorking = true
        let events = ReminderScheduler.events(for: task, now: origin)
        #expect(!events.contains { $0.phase == .suggestedStart })
        #expect(events.contains { $0.phase == .latestStart })
        #expect(events.contains { $0.phase == .submission })
        task.hasConfirmedLatestStart = true
        let confirmed = ReminderScheduler.events(for: task, now: origin)
        #expect(confirmed.allSatisfy { $0.phase == .submission })
        #expect(task.status == .active)
    }

    @Test func submissionIncludesMilestonesAndOverdueRepeatsWithoutDuplicates() {
        let task = sample()
        let events = ReminderScheduler.events(for: task, now: origin)
        for lead: TimeInterval in [1800, 900, 300, 0] {
            #expect(events.contains { $0.phase == .submission && $0.fireDate == task.dueDate!.addingTimeInterval(-lead) })
        }
        #expect(events.contains { $0.fireDate > task.dueDate! && $0.phase == .submission })
        #expect(Set(events.map(\.fireDate)).count == events.count)
        #expect(Set(events.map(\.id)).count == events.count)
    }

    @Test func shortTasksStillHaveIndependentLatestCheckpoint() {
        var task = sample()
        task.latestSafeStartDate = task.dueDate!.addingTimeInterval(-10 * 60)
        task.hasConfirmedWorking = true
        let events = ReminderScheduler.events(for: task, now: origin)
        #expect(events.contains { $0.phase == .latestStart && $0.fireDate == task.latestSafeStartDate })
        #expect(events.contains { $0.phase == .submission && $0.fireDate == task.dueDate })
    }

    @Test func simultaneousLatestAndSubmissionCheckpointsBothSurvive() {
        var task = sample()
        task.latestSafeStartDate = task.submissionStartDate
        let events = ReminderScheduler.events(for: task, now: origin)
        let boundary = events.filter { $0.fireDate == task.submissionStartDate }
        #expect(boundary.count == 2)
        #expect(Set(boundary.map(\.phase)) == [.latestStart, .submission])
    }

    @Test func queueIsBoundedGloballyAndOrderedByTime() {
        let tasks = (0..<10).map { _ in sample() }
        let queue = ReminderScheduler.queue(for: tasks, now: origin)
        #expect(queue.events.count == 64)
        #expect(queue.isLimited)
        #expect(queue.events.map(\.fireDate) == queue.events.map(\.fireDate).sorted())
    }

    @Test func refreshDoesNotMoveExistingReminderDates() {
        let task = sample()
        let first = ReminderScheduler.queue(for: [task], now: origin).events
        let second = ReminderScheduler.queue(for: [task], now: origin.addingTimeInterval(30)).events
        #expect(first.map(\.id) == second.map(\.id))
    }

    @Test func refillingAfterDeliveryOnlyAddsLaterEvents() {
        let task = sample()
        let queue = ReminderScheduler.queue(for: [task], now: task.dueDate!.addingTimeInterval(1))
        #expect(queue.events.count == 64)
        #expect(queue.events.allSatisfy { $0.phase == .submission && $0.fireDate > task.dueDate! })
    }

    @Test func snoozeAnchorIsStableAndOtherPhasesStillArrive() {
        var task = sample()
        task.snoozedPhase = .suggestedStart
        task.snoozedUntil = origin.addingTimeInterval(75 * 60)
        let events = ReminderScheduler.events(for: task, now: origin.addingTimeInterval(65 * 60))
        #expect(events.first?.fireDate == task.snoozedUntil)
        #expect(events.contains { $0.phase == .latestStart && $0.fireDate == task.latestSafeStartDate })
    }

    @Test func newlyActivatedPastLatestStartsImmediatelyInCurrentPhase() {
        var task = sample()
        let now = origin.addingTimeInterval(150 * 60)
        task.activatedAt = now.addingTimeInterval(2)
        let events = ReminderScheduler.events(for: task, now: now)
        #expect(events.first?.phase == .latestStart)
        #expect(events.first?.fireDate == task.activatedAt)
    }
}

@MainActor
@Suite(.serialized)
struct TaskStoreTests {
    private func makeStore() throws -> TaskStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: configuration)
        return TaskStore(context: ModelContext(container))
    }

    private func plan(title: String = "Essay") -> TaskPlan {
        TaskPlan(title: title, dueDate: origin.addingTimeInterval(4 * 3600), estimatedMinutes: 90,
                 safetyBufferMinutes: 30, suggestedStartDate: origin.addingTimeInterval(3600),
                 latestSafeStartOverride: nil, submissionLeadMinutes: 30, reminderIntervalMinutes: 10)
    }

    @Test func fullCapturePlanWorkConfirmSubmitFlow() throws {
        let store = try makeStore()
        let task = try store.capture(title: "  Essay  ", now: origin)
        #expect(task.status == .inbox)
        #expect(task.title == "Essay")
        try store.activate(task, plan: plan(), now: origin)
        #expect(task.status == .active)
        #expect(task.latestSafeStartDate == origin.addingTimeInterval(2 * 3600))
        try store.confirmWorking(task, now: origin.addingTimeInterval(3600))
        #expect(task.hasConfirmedWorking)
        #expect(!task.hasConfirmedLatestStart)
        #expect(task.status == .active)
        #expect(ReminderScheduler.events(for: task.snapshot, now: origin).contains { $0.phase == .latestStart })
        try store.confirmWorking(task, now: task.latestSafeStartDate!)
        #expect(task.hasConfirmedLatestStart)
        #expect(ReminderScheduler.events(for: task.snapshot, now: origin).allSatisfy { $0.phase == .submission })
        let completed = origin.addingTimeInterval(230 * 60)
        try store.complete(task, now: completed)
        #expect(task.status == .completed)
        #expect(task.completedAt == completed)
        #expect(ReminderScheduler.queue(for: [task.snapshot], now: completed).events.isEmpty)
        #expect(try store.task(id: task.id)?.status == .completed)
    }

    @Test func snoozeCannotHideLatestSubmissionOrDeadlineBoundaries() throws {
        let store = try makeStore()
        let task = try store.capture(title: "Essay", now: origin)
        try store.activate(task, plan: plan(), now: origin)
        try store.snooze(task, minutes: 60, now: origin.addingTimeInterval(110 * 60))
        #expect(task.snoozedUntil == task.latestSafeStartDate)
        try store.snooze(task, minutes: 60, now: origin.addingTimeInterval(200 * 60))
        #expect(task.snoozedUntil == task.snapshot.submissionStartDate)
        try store.snooze(task, minutes: 60, now: origin.addingTimeInterval(235 * 60))
        #expect(task.snoozedUntil == task.dueDate)
        #expect(ReminderScheduler.events(for: task.snapshot, now: origin.addingTimeInterval(235 * 60)).first?.fireDate == task.dueDate)
    }

    @Test func editingTimingResetsConfirmationsButRenamingDoesNot() throws {
        let store = try makeStore()
        let task = try store.capture(title: "Essay", now: origin)
        try store.activate(task, plan: plan(), now: origin)
        try store.confirmWorking(task, now: origin.addingTimeInterval(2 * 3600))
        let revision = task.reminderRevision
        try store.rename(task, title: "AP Lang essay")
        #expect(task.hasConfirmedWorking && task.hasConfirmedLatestStart)
        #expect(task.reminderRevision != revision)
        var revised = plan(title: task.title)
        revised.dueDate = revised.dueDate.addingTimeInterval(3600)
        try store.activate(task, plan: revised, now: origin)
        #expect(!task.hasConfirmedWorking && !task.hasConfirmedLatestStart)
    }

    @Test func invalidPlansLeaveInboxUntouched() throws {
        let store = try makeStore()
        let task = try store.capture(title: "Essay", now: origin)
        var invalid = plan()
        invalid.estimatedMinutes = 0
        #expect(throws: TaskStoreError.self) { try store.activate(task, plan: invalid, now: origin) }
        #expect(task.status == .inbox)
        #expect(task.dueDate == nil)
        invalid = plan()
        invalid.suggestedStartDate = invalid.dueDate
        #expect(invalid.validationMessage(at: origin) != nil)
        invalid.dueDate = origin
        #expect(invalid.validationMessage(at: origin) != nil)
    }

    @Test func notificationActionsPersistAndRejectStaleRevisions() throws {
        let store = try makeStore()
        let task = try store.capture(title: "Essay", now: origin)
        try store.activate(task, plan: plan(), now: origin)
        let revision = task.reminderRevision
        try store.applyReminderAction(taskID: task.id, revision: revision, action: .working,
                                      now: origin.addingTimeInterval(3600))
        #expect(task.hasConfirmedWorking && !task.hasConfirmedLatestStart)
        try store.rename(task, title: "Revised essay")
        let result = try store.applyReminderAction(taskID: task.id, revision: revision, action: .done, now: origin)
        #expect(result == nil)
        #expect(task.status == .active)
        try store.applyReminderAction(taskID: task.id, revision: task.reminderRevision, action: .done, now: origin)
        #expect(task.status == .completed)
        #expect(ReminderScheduler.events(for: task.snapshot, now: origin).isEmpty)
    }

    @Test func movingToInboxAndDeletionRemoveReminderCandidates() throws {
        let store = try makeStore()
        let task = try store.capture(title: "Essay", now: origin)
        try store.activate(task, plan: plan(), now: origin)
        try store.moveToInbox(task)
        #expect(ReminderScheduler.events(for: task.snapshot, now: origin).isEmpty)
        try store.delete(task)
        #expect(try store.allTasks().isEmpty)
    }

    @Test func diskPersistenceSurvivesContainerRecreation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OnTimelyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tasks.store")
        let id: UUID
        do {
            let container = try ModelContainer(for: TaskItem.self, configurations: ModelConfiguration(url: url))
            let store = TaskStore(context: ModelContext(container))
            let task = try store.capture(title: "Persistent essay", now: origin)
            var taskPlan = plan(title: task.title)
            taskPlan.latestSafeStartOverride = origin.addingTimeInterval(130 * 60)
            try store.activate(task, plan: taskPlan, now: origin)
            try store.confirmWorking(task, now: origin.addingTimeInterval(80 * 60))
            try store.snooze(task, now: origin.addingTimeInterval(132 * 60))
            id = task.id
        }
        do {
            let container = try ModelContainer(for: TaskItem.self, configurations: ModelConfiguration(url: url))
            let store = TaskStore(context: ModelContext(container))
            let fetched = try store.task(id: id)
            let restored = try #require(fetched)
            #expect(restored.title == "Persistent essay")
            #expect(restored.status == .active)
            #expect(restored.hasConfirmedWorking)
            #expect(!restored.hasConfirmedLatestStart)
            #expect(restored.latestSafeStartOverride == origin.addingTimeInterval(130 * 60))
            #expect(restored.snoozedUntil != nil)
        }
    }
}
