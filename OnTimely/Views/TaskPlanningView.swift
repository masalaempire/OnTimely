import SwiftUI

struct TaskPlanningView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    @State private var draft: PlanningDraft
    @State private var screen: PlanningScreen
    @State private var returningToReview = false
    @State private var customDuration: Bool
    @State private var adjustReminders = false
    @State private var overrideInitialized: Bool
    @State private var renaming = false
    @State private var saveError: String?
    @FocusState private var titleFocused: Bool

    init(task: TaskItem) {
        self.task = task
        let draft = PlanningDraft(task: task)
        _draft = State(initialValue: draft)
        _screen = State(initialValue: task.status == .active ? .review : .due)
        _customDuration = State(initialValue: ![15, 30, 60, 120].contains(MinuteText.value(draft.estimatedText) ?? 0))
        _overrideInitialized = State(initialValue: draft.overridesLatest)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(screen.title).font(.system(size: 24, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        switch screen {
                        case .due: dueQuestion
                        case .duration: durationQuestion
                        case .start: startQuestion(now: timeline.date)
                        case .review: review(now: timeline.date)
                        }
                        if let error = stepError(now: timeline.date) {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(TaskStyle.metadata).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
                }
                TaskSeparator()
                footer(now: timeline.date)
            }
        }
        .frame(width: 520, height: 440)
        .foregroundStyle(TaskStyle.text).background(TaskStyle.content).tint(TaskStyle.coral)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if renaming && screen == .review {
                    TextField("Task name", text: $draft.title)
                        .textFieldStyle(.roundedBorder).font(TaskStyle.title)
                        .focused($titleFocused).accessibilityLabel("Task name")
                        .onSubmit { renaming = false }
                } else {
                    Text(draft.title).font(.system(size: 15, weight: .medium)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if screen == .review {
                    Button(renaming ? "Done" : "Rename") {
                        renaming.toggle()
                        titleFocused = renaming
                    }
                    .buttonStyle(.link).font(TaskStyle.metadata)
                    .accessibilityLabel(renaming ? "Finish renaming" : "Rename task")
                }
            }
            HStack(spacing: 12) {
                Text(screen == .review ? "Review" : "Step \(screen.rawValue + 1) of 3")
                    .font(TaskStyle.metadata).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Capsule().fill(index <= screen.rawValue ? TaskStyle.coral : TaskStyle.separator)
                            .frame(width: 24, height: 3)
                    }
                }
                .accessibilityHidden(true)
                Spacer()
                Text(task.status == .active ? "Edit plan" : "Plan task")
                    .font(TaskStyle.metadata).foregroundStyle(.secondary)
            }
        }
        .padding(24).padding(.bottom, -8)
    }

    private var dueQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose the date and time you need to be finished.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            TaskDateTimePicker(label: "Deadline", selection: $draft.dueDate)
        }
    }

    private var durationQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("An estimate is enough. Your safety buffer adds a little room.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach([15, 30, 60, 120], id: \.self) { minutes in
                    durationOption(durationLabel(minutes), selected: !customDuration && MinuteText.value(draft.estimatedText) == minutes) {
                        draft.estimatedText = String(minutes)
                        customDuration = false
                    }
                }
                durationOption("Custom", selected: customDuration) { customDuration = true }
            }
            if customDuration {
                MinuteInput(label: "Estimated work", text: $draft.estimatedText, range: 1...10_080,
                            errorMessage: "Estimated work must be between 1 minute and 7 days.")
            }
        }
    }

    @ViewBuilder private func startQuestion(now: Date) -> some View {
        Text("Choose a starting point for your reminders.").font(.system(size: 13)).foregroundStyle(.secondary)
        VStack(spacing: 8) {
            ForEach(PlanningStartChoice.allCases) { choice in
                PlanningChoiceButton(title: choice.rawValue, subtitle: startDescription(choice), selected: draft.startChoice == choice) {
                    draft.selectStart(choice)
                }
            }
        }
        if draft.startChoice == .chosen {
            TaskDateTimePicker(label: "Suggested start", selection: $draft.chosenStartDate)
            Text("This time stays as you edit other answers. If it becomes too late, choose an earlier time.")
                .font(TaskStyle.metadata).foregroundStyle(.secondary)
        }
        if let latest = draft.latestSafeStart {
            Text("Latest safe start: \(TaskFormatting.date(latest))").font(TaskStyle.metadata).foregroundStyle(.secondary)
            if latest <= now { immediateReminderNotice }
        }
    }

    @ViewBuilder private func review(now: Date) -> some View {
        VStack(spacing: 12) {
            PlanningReviewAnswer(label: "Deadline", value: TaskFormatting.date(draft.dueDate), editLabel: "Edit deadline") { edit(.due) }
            PlanningReviewAnswer(label: "Estimated work", value: durationSummary, editLabel: "Edit duration") { edit(.duration) }
            PlanningReviewAnswer(label: "Suggested start", value: draft.suggestedStart.map(TaskFormatting.date) ?? "Needs correction",
                                 editLabel: "Edit suggested start") { edit(.start) }
            TimingDetail(label: "Latest safe start", value: draft.latestSafeStart.map(TaskFormatting.date) ?? "Needs correction")
        }
        if let latest = draft.latestSafeStart, latest <= now { immediateReminderNotice }
        DisclosureGroup("Adjust reminders", isExpanded: $adjustReminders) {
            VStack(alignment: .leading, spacing: 16) {
                MinuteInput(label: "Safety buffer", text: $draft.bufferText, range: 0...10_080,
                            errorMessage: "The safety buffer must be between 0 minutes and 7 days.")
                MinuteInput(label: "Repeat reminders every", text: $draft.intervalText, range: 1...60,
                            errorMessage: "The reminder interval must be between 1 and 60 minutes.")
                MinuteInput(label: "Submission reminders before due", text: $draft.submissionLeadText, range: 1...1_440,
                            errorMessage: "Submission reminders must begin 1 minute to 24 hours before due.")
                Toggle("Override latest safe start", isOn: $draft.overridesLatest)
                    .onChange(of: draft.overridesLatest) { _, enabled in
                        if enabled && !overrideInitialized, let calculated = draft.calculatedLatest {
                            draft.overrideDate = calculated
                            overrideInitialized = true
                        }
                    }
                if draft.overridesLatest {
                    TaskDateTimePicker(label: "Latest safe start", selection: $draft.overrideDate)
                    if let calculated = draft.calculatedLatest, draft.overrideDate > calculated {
                        Text("This override leaves less time than your estimate and buffer.")
                            .font(TaskStyle.metadata).foregroundStyle(TaskStyle.coral)
                    }
                }
                Text("Latest safe start = deadline − estimated work − safety buffer.")
                    .font(TaskStyle.metadata).foregroundStyle(.secondary)
            }
            .padding(.top, 12)
        }
        .font(.system(size: 13))
        if !adjustReminders {
            Text(reminderSummary).font(TaskStyle.metadata).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("Working confirmation stops current start reminders. A separate latest-start check can still occur. Submission reminders continue until you mark the task Done.")
            .font(TaskStyle.metadata).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var immediateReminderNotice: some View {
        Label("Latest safe start has passed. Reminders will begin immediately when you activate this plan.", systemImage: "bell")
            .font(TaskStyle.metadata).foregroundStyle(TaskStyle.coral)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func footer(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let saveError {
                Text(saveError).font(TaskStyle.metadata).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer(minLength: 8)
                Button("Back", action: goBack).buttonStyle(QuietButtonStyle()).disabled(screen == .due && !returningToReview)
                if screen == .review {
                    Button(task.status == .active ? "Save plan" : "Activate reminders", action: save)
                        .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                        .disabled(draft.validationMessage(at: now) != nil)
                } else {
                    Button("Continue", action: advanceQuestion)
                        .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                        .disabled(stepError(now: now) != nil)
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private func durationOption(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: selected ? .medium : .regular))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(selected ? TaskStyle.coral : TaskStyle.text)
                .background(selected ? TaskStyle.selection : TaskStyle.hover, in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? TaskStyle.coral : TaskStyle.separator, lineWidth: 1) }
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func durationLabel(_ minutes: Int) -> String {
        switch minutes {
        case 60: "1 hour"
        case 120: "2 hours"
        default: "\(minutes) min"
        }
    }

    private var durationSummary: String {
        guard draft.durationError == nil, let minutes = MinuteText.value(draft.estimatedText) else { return "Needs correction" }
        return "\(minutes) min"
    }

    private var reminderSummary: String {
        guard draft.bufferError == nil, draft.intervalError == nil, draft.submissionLeadError == nil else {
            return "Check your values in Adjust reminders."
        }
        let override = draft.overridesLatest ? " · Latest start overridden" : ""
        return "\(draft.bufferText) min buffer · Repeat every \(draft.intervalText) min · Submit reminders \(draft.submissionLeadText) min before due\(override)"
    }

    private func startDescription(_ choice: PlanningStartChoice) -> String {
        switch choice {
        case .now: "Reminders can begin as soon as you activate."
        case .latest: draft.latestSafeStart.map(TaskFormatting.date) ?? "Calculated from your estimate and buffer."
        case .chosen: "Pick your own date and time."
        }
    }

    private func stepError(now: Date) -> String? {
        switch screen {
        case .due: draft.dueDate <= now ? "Choose a due time in the future." : nil
        case .duration: draft.durationError
        case .start: draft.startError()
        case .review: draft.validationMessage(at: now)
        }
    }

    private func edit(_ question: PlanningScreen) {
        returningToReview = true
        renaming = false
        screen = question
    }

    private func advanceQuestion() {
        guard screen != .review, stepError(now: .now) == nil else { return }
        if returningToReview {
            returningToReview = false
            screen = .review
        } else if let next = PlanningScreen(rawValue: screen.rawValue + 1) {
            screen = next
        }
    }

    private func goBack() {
        renaming = false
        if returningToReview {
            returningToReview = false
            screen = .review
        } else if let previous = PlanningScreen(rawValue: screen.rawValue - 1) {
            screen = previous
        }
    }

    private func save() {
        guard screen == .review, draft.validationMessage(at: .now) == nil, let plan = draft.plan else { return }
        saveError = nil
        if runtime.activate(task, plan: plan) { dismiss() }
        else { saveError = runtime.errorMessage ?? "Your plan couldn’t be saved. Try again." }
    }
}

private struct PlanningChoiceButton: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(subtitle).font(TaskStyle.metadata).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? TaskStyle.coral : Color.secondary).accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? TaskStyle.selection : TaskStyle.hover, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? TaskStyle.coral : TaskStyle.separator, lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct PlanningReviewAnswer: View {
    let label: String
    let value: String
    let editLabel: String
    let edit: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(TaskStyle.metadata).foregroundStyle(.secondary)
                Text(value).font(.system(size: 13, weight: .medium))
            }
            Spacer(minLength: 8)
            Button("Edit", action: edit).buttonStyle(.link).font(TaskStyle.metadata).accessibilityLabel(editLabel)
        }
    }
}

struct RenameTaskView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    @State private var title: String
    @State private var saveError: String?
    @FocusState private var focused: Bool

    init(task: TaskItem) {
        self.task = task
        _title = State(initialValue: task.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(title: "Rename task", subtitle: "Give it a name that makes the next step clear.")
            TextField("Task name", text: $title).textFieldStyle(.roundedBorder).font(TaskStyle.title)
                .focused($focused).accessibilityLabel("Task name")
            if let saveError { Text(saveError).font(TaskStyle.metadata).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    if runtime.perform({ try $0.rename(task, title: title) }) { dismiss() }
                    else { saveError = runtime.errorMessage ?? "The name couldn’t be saved. Try again." }
                }
                .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 440)
        .foregroundStyle(TaskStyle.text).background(TaskStyle.content).tint(TaskStyle.coral)
        .onAppear { focused = true }
    }
}
