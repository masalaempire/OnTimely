import SwiftUI

/// Naming and planning share one sheet, so creating a calendar task goes straight into its plan.
struct CalendarTaskCreationView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    let day: Date
    @State private var title = ""
    @State private var planningTask: TaskItem?
    @State private var captureError: String?
    @FocusState private var titleFocused: Bool

    var body: some View {
        Group {
            if let planningTask {
                TaskPlanningView(task: planningTask, dueDay: day)
            } else {
                namePrompt
            }
        }
        .foregroundStyle(TaskStyle.text).background(TaskStyle.content).tint(TaskStyle.coral)
    }

    private var namePrompt: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(title: "New task", subtitle: "Plan for \(day.formatted(date: .complete, time: .omitted)).")
            TextField("What do you need to do?", text: $title)
                .textFieldStyle(.roundedBorder).font(TaskStyle.title)
                .focused($titleFocused).onSubmit(captureAndPlan)
                .accessibilityLabel("New task name")
            if let captureError {
                Text(captureError).font(TaskStyle.metadata).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 8)
                Button("Continue to plan", action: captureAndPlan).buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 520)
        .onAppear { titleFocused = true }
    }

    private func captureAndPlan() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard planningTask == nil, !name.isEmpty else { return }
        captureError = nil
        var capturedTask: TaskItem?
        if runtime.perform({ capturedTask = try $0.capture(title: name) }), let capturedTask {
            titleFocused = false
            planningTask = capturedTask
        } else {
            captureError = runtime.errorMessage ?? "Your task couldn’t be saved. Try again."
        }
    }
}
