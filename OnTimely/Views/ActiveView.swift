import SwiftUI

struct ActiveView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tasks: [TaskItem]
    let onPlan: (TaskItem) -> Void
    let onRename: (TaskItem) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            ScrollViewReader { proxy in
                TaskPage(title: "Active", subtitle: "A clear next step for everything you’ve planned.") {
                    if tasks.isEmpty {
                        TaskEmptyState(symbol: "clock", title: "Nothing planned yet.",
                                       message: "Choose Plan in your Inbox to set a deadline and start reminders.",
                                       actionTitle: "Go to Inbox") { runtime.section = .inbox }
                    } else {
                        let ordered = TaskFormatting.sortedActive(tasks, now: timeline.date)
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(ActiveTaskGroup.allCases) { group in
                                let grouped = ordered.filter { TaskFormatting.group($0.snapshot, now: timeline.date) == group }
                                if !grouped.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 8) {
                                            Text(group.rawValue).font(.system(size: 13, weight: .semibold))
                                                .accessibilityAddTraits(.isHeader)
                                            Text("\(grouped.count)").font(TaskStyle.metadata).foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        ForEach(grouped) { task in
                                            ActiveTaskRow(task: task, now: timeline.date, onPlan: onPlan, onRename: onRename)
                                                .id(task.id)
                                            TaskSeparator()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .task(id: runtime.highlightedTaskID) {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    scrollToHighlight(proxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in scrollToHighlight(proxy) }
            }
        }
    }

    private func scrollToHighlight(_ proxy: ScrollViewProxy) {
        guard let id = runtime.highlightedTaskID, tasks.contains(where: { $0.id == id }) else { return }
        if reduceMotion { proxy.scrollTo(id, anchor: .center) }
        else { withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) } }
    }
}

private struct ActiveTaskRow: View {
    @Environment(AppRuntime.self) private var runtime
    let task: TaskItem
    let now: Date
    let onPlan: (TaskItem) -> Void
    let onRename: (TaskItem) -> Void
    @State private var detailsExpanded = false
    private var snapshot: TaskSnapshot { task.snapshot }
    private var phase: ReminderPhase? { snapshot.phase(at: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button { onPlan(task) } label: {
                    Text(task.title).font(TaskStyle.title).fontWeight(.medium)
                        .multilineTextAlignment(.leading).lineLimit(2)
                }
                .buttonStyle(.plain).accessibilityLabel("Review plan for \(task.title)")
                Spacer(minLength: 12)
                TaskOverflowMenu(title: task.title) { actions }
            }
            Text(TaskFormatting.status(snapshot, now: now))
                .font(.system(size: 13)).foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { conciseDates }
                VStack(alignment: .leading, spacing: 4) { conciseDates }
            }
            .font(TaskStyle.metadata)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { taskActions }
                VStack(alignment: .leading, spacing: 8) { taskActions }
            }
            if snapshot.isSnoozed(at: now), let until = task.snoozedUntil {
                Label("Snoozed until \(TaskFormatting.date(until))", systemImage: "bell.slash")
                    .font(TaskStyle.metadata).foregroundStyle(.secondary)
            }
            DisclosureGroup("Timing details", isExpanded: $detailsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    if let suggested = task.suggestedStartDate { TimingDetail(label: "Suggested start", value: TaskFormatting.date(suggested)) }
                    if let latest = task.latestSafeStartDate { TimingDetail(label: "Latest safe start", value: TaskFormatting.date(latest)) }
                    if let due = task.dueDate { TimingDetail(label: "Deadline", value: TaskFormatting.date(due)) }
                    TimingDetail(label: "Estimated work", value: TaskFormatting.duration(task.estimatedDuration))
                    TimingDetail(label: "Safety buffer", value: "\(Int(task.safetyBuffer / 60)) min")
                    if let submission = snapshot.submissionStartDate { TimingDetail(label: "Submission reminders begin", value: TaskFormatting.date(submission)) }
                    TimingDetail(label: "Repeat reminders", value: "Every \(Int(task.reminderInterval / 60)) min")
                }
                .padding(.top, 8)
            }
            .font(TaskStyle.metadata).foregroundStyle(.secondary)
        }
        .taskRowSurface(highlighted: runtime.highlightedTaskID == task.id)
        .contextMenu { actions }
    }

    @ViewBuilder private var conciseDates: some View {
        if let due = task.dueDate {
            Label("Due \(TaskFormatting.date(due))", systemImage: "calendar")
                .foregroundStyle(snapshot.attention(at: now) == .overdue || phase == .submission ? statusColor : Color.secondary)
        }
        if phase == .latestStart || phase == .submission, let latest = task.latestSafeStartDate {
            Text("Latest start \(TaskFormatting.date(latest))").foregroundStyle(.secondary)
        } else if let suggested = task.suggestedStartDate {
            Text("Start \(TaskFormatting.date(suggested))").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var taskActions: some View {
        if phase == .submission {
            Button("Submitted / Done") { runtime.perform { try $0.complete(task) } }
                .buttonStyle(PrimaryButtonStyle())
        } else if !confirmed {
            Button(phase == .latestStart ? "Yes, I’m Working" : "I’m Working") {
                runtime.perform { try $0.confirmWorking(task) }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        if phase != nil && !confirmed {
            Menu {
                ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                    Button(minutes == 60 ? "1 hour" : "\(minutes) minutes") {
                        runtime.perform { try $0.snooze(task, minutes: minutes) }
                    }
                }
            } label: { Text("Snooze") }
            .fixedSize().controlSize(.small)
            .accessibilityLabel("Snooze reminders for \(task.title)")
        }
        if phase != .submission {
            Button("Submitted / Done") { runtime.perform { try $0.complete(task) } }
                .buttonStyle(QuietButtonStyle())
        }
    }

    @ViewBuilder private var actions: some View {
        Button("Edit plan") { onPlan(task) }
        Button("Rename") { onRename(task) }
        Button("Move to Inbox") { runtime.perform { try $0.moveToInbox(task) } }
        Divider()
        Button("Delete", role: .destructive) { runtime.perform { try $0.delete(task) } }
    }

    private var confirmed: Bool {
        if let phase { return snapshot.isConfirmed(phase) }
        return task.hasConfirmedWorking
    }

    private var statusColor: Color {
        switch snapshot.attention(at: now) {
        case .overdue, .mustStart: .red
        case .submission, .shouldStart: TaskStyle.coral
        default: .secondary
        }
    }
}
