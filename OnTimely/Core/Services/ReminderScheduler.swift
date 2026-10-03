import Foundation

struct ReminderEvent: Identifiable, Equatable, Sendable {
    var taskID: UUID
    var revision: UUID
    var title: String
    var phase: ReminderPhase
    var fireDate: Date
    var dueDate: Date
    var isMilestone: Bool

    var id: String {
        "ontimely.\(taskID.uuidString).\(revision.uuidString).\(phase.rawValue).\(Int64((fireDate.timeIntervalSince1970 * 1_000).rounded()))"
    }

    var body: String {
        switch phase {
        case .suggestedStart: return "You should start working on this."
        case .latestStart: return "Latest safe start reached. Are you working on this?"
        case .submission:
            let minutes = Int(ceil(dueDate.timeIntervalSince(fireDate) / 60))
            if minutes > 0 { return "Due in \(minutes) \(minutes == 1 ? "minute" : "minutes"). Remember to finish and submit it." }
            if minutes == 0 { return "Due now. Remember to finish and submit it." }
            return "Past due. Finish and submit it, then mark it done."
        }
    }
}

struct ReminderQueue: Sendable {
    var events: [ReminderEvent]
    var isLimited: Bool
}

/// A bounded, deterministic queue. macOS owns delivery; the running app refills it.
/// Start reminders have finite phase windows, so they cannot continue into submission.
enum ReminderScheduler {
    static let queueLimit = 64

    static func queue(for tasks: [TaskSnapshot], now: Date, limit: Int = queueLimit) -> ReminderQueue {
        let candidates = tasks.flatMap { events(for: $0, now: now, repeatCount: max(limit, 1)) }
            .sorted {
                if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
                if $0.isMilestone != $1.isMilestone { return $0.isMilestone }
                return $0.id < $1.id
            }
        return ReminderQueue(events: Array(candidates.prefix(max(limit, 0))), isLimited: candidates.count > limit)
    }

    static func events(for task: TaskSnapshot, now: Date, repeatCount: Int = queueLimit) -> [ReminderEvent] {
        guard task.status == .active,
              let due = task.dueDate, let suggested = task.suggestedStartDate,
              let latest = task.latestSafeStartDate, let activated = task.activatedAt else { return [] }
        let submission = due.addingTimeInterval(-task.submissionLeadTime)
        let interval = max(60, task.reminderInterval)
        var events: [ReminderEvent] = []

        func append(_ phase: ReminderPhase, at date: Date, milestone: Bool) {
            guard date > now, !task.isConfirmed(phase) else { return }
            // A snooze is scoped to its phase. A later phase always breaks through.
            if task.snoozedPhase == phase, let until = task.snoozedUntil, date < until { return }
            events.append(ReminderEvent(taskID: task.id, revision: task.revision, title: task.title,
                                        phase: phase, fireDate: date, dueDate: due, isMilestone: milestone))
        }

        func repeats(_ phase: ReminderPhase, from boundary: Date, until end: Date?) {
            guard !task.isConfirmed(phase) else { return }
            var anchor = max(boundary, activated)
            if task.snoozedPhase == phase, let until = task.snoozedUntil { anchor = max(anchor, until) }
            let steps = max(0, floor(now.timeIntervalSince(anchor) / interval) + 1)
            var date = anchor.addingTimeInterval(steps * interval)
            for index in 0..<max(repeatCount, 1) {
                if let end, date >= end { break }
                append(phase, at: date, milestone: index == 0 && steps == 0)
                date = date.addingTimeInterval(interval)
            }
        }

        repeats(.suggestedStart, from: suggested, until: min(latest, submission))
        repeats(.latestStart, from: latest, until: submission)
        // A short task can enter submission before latest start. Still send its independent checkpoint.
        if latest >= submission && latest >= activated { append(.latestStart, at: latest, milestone: true) }
        repeats(.submission, from: submission, until: nil)
        for lead: TimeInterval in [15 * 60, 5 * 60, 0] {
            let date = due.addingTimeInterval(-lead)
            if date >= submission && date >= activated { append(.submission, at: date, milestone: true) }
        }

        // Deduplicate repeats within a phase; simultaneous independent checkpoints both survive.
        var unique: [String: ReminderEvent] = [:]
        for event in events {
            if let previous = unique[event.id] {
                if !previous.isMilestone && event.isMilestone {
                    unique[event.id] = event
                }
            } else { unique[event.id] = event }
        }
        return unique.values.sorted {
            $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate
        }
    }
}
