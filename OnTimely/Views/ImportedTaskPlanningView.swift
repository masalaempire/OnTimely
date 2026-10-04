import SwiftUI

/// Imported assignments can be edited without supplying an estimated work duration.
struct ImportedTaskPlanningView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    @State private var title: String
    @State private var dueDate: Date
    @State private var suggestedStart: Date
    @State private var latestStart: Date
    @State private var intervalText: String
    @State private var leadText: String
    @State private var saveError: String?

    init(task: TaskItem) {
        self.task = task
        let due = task.dueDate ?? .now
        _title = State(initialValue: task.title)
        _dueDate = State(initialValue: due)
        _suggestedStart = State(initialValue: task.suggestedStartDate ?? due.addingTimeInterval(-2 * 60 * 60))
        _latestStart = State(initialValue: task.latestSafeStartDate ?? due.addingTimeInterval(-60 * 60))
        _intervalText = State(initialValue: String(Int(task.reminderInterval / 60)))
        _leadText = State(initialValue: String(Int(task.submissionReminderLeadTime / 60)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeading(title: "Edit imported task", subtitle: "Your reminder times are yours to change.").padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Task name", text: $title).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Task name")
                    if let sourceDue = task.calendarSourceDueDate {
                        Text("ManageBac deadline: \(TaskFormatting.date(sourceDue))")
                            .font(TaskStyle.metadata).foregroundStyle(.secondary)
                    }
                    if task.calendarIsCancelled {
                        Text("This assignment was cancelled in ManageBac. You can keep it as a personal task.")
                            .font(TaskStyle.metadata).foregroundStyle(TaskStyle.coral)
                    }
                    TaskDateTimePicker(label: "Deadline", selection: $dueDate)
                    TaskDateTimePicker(label: "Suggested start", selection: $suggestedStart)
                    TaskDateTimePicker(label: "Latest start", selection: $latestStart)
                    MinuteInput(label: "Repeat reminders every", text: $intervalText, range: 1...60,
                                errorMessage: "The reminder interval must be between 1 and 60 minutes.")
                    MinuteInput(label: "Submission reminders before due", text: $leadText, range: 1...1_440,
                                errorMessage: "Submission reminders must begin 1 minute to 24 hours before due.")
                    Text("Calendar refreshes keep your edits. Working confirmation and submission reminders continue to work as usual.")
                        .font(TaskStyle.metadata).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message = validationMessage {
                        Text(message).font(TaskStyle.metadata).foregroundStyle(.red)
                    }
                    if let saveError { Text(saveError).font(TaskStyle.metadata).foregroundStyle(.red) }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            TaskSeparator()
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button(task.status == .active ? "Save plan" : "Activate reminders", action: save)
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(validationMessage != nil)
            }
            .padding(24)
        }
        .frame(width: 520, height: 560)
        .foregroundStyle(TaskStyle.text).background(TaskStyle.content).tint(TaskStyle.coral)
    }

    private var plan: TaskPlan? {
        guard MinuteText.error(intervalText, range: 1...60, message: "") == nil,
              MinuteText.error(leadText, range: 1...1_440, message: "") == nil,
              let interval = MinuteText.value(intervalText), let lead = MinuteText.value(leadText) else { return nil }
        return TaskPlan(title: title, dueDate: dueDate,
                        estimatedMinutes: max(1, min(10_080, Int(task.estimatedDuration / 60))),
                        safetyBufferMinutes: max(0, min(10_080, Int(task.safetyBuffer / 60))),
                        suggestedStartDate: suggestedStart, latestSafeStartOverride: latestStart,
                        submissionLeadMinutes: lead, reminderIntervalMinutes: interval)
    }

    private var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the task a name." }
        if let error = MinuteText.error(intervalText, range: 1...60,
                                         message: "The reminder interval must be between 1 and 60 minutes.") { return error }
        if let error = MinuteText.error(leadText, range: 1...1_440,
                                         message: "Submission reminders must begin 1 minute to 24 hours before due.") { return error }
        if latestStart >= dueDate { return "Latest start must be before the deadline." }
        if suggestedStart > latestStart { return "Suggested start must be at or before latest start." }
        let editingOverdue = task.status == .active && task.dueDate == dueDate
        if !editingOverdue && dueDate <= .now { return "Choose a deadline in the future." }
        return nil
    }

    private func save() {
        guard validationMessage == nil, let plan else { return }
        if runtime.activate(task, plan: plan) { dismiss() }
        else { saveError = runtime.errorMessage ?? "Your changes couldn’t be saved. Try again." }
    }
}
