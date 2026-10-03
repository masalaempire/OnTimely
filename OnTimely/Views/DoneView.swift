import SwiftUI

struct DoneView: View {
    @Environment(AppRuntime.self) private var runtime
    let tasks: [TaskItem]
    let onRename: (TaskItem) -> Void

    var body: some View {
        TaskPage(title: "Done", subtitle: "A little room for finished things.") {
            if tasks.isEmpty {
                TaskEmptyState(symbol: "checkmark.circle", title: "Your finished tasks will be here.",
                               message: "Mark a task done in Inbox or Active to make room for what’s next.",
                               actionTitle: "Go to Inbox") { runtime.section = .inbox }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(tasks.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }) { task in
                        DoneTaskRow(task: task, onRename: onRename)
                        TaskSeparator()
                    }
                }
            }
        }
    }
}

private struct DoneTaskRow: View {
    @Environment(AppRuntime.self) private var runtime
    let task: TaskItem
    let onRename: (TaskItem) -> Void
    @State private var detailsExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 21, weight: .light))
                .foregroundStyle(.secondary).frame(width: 28, height: 28)
                .accessibilityLabel("Completed")
            VStack(alignment: .leading, spacing: 8) {
                Text(task.title).font(TaskStyle.title).foregroundStyle(.secondary)
                    .lineLimit(2).textSelection(.enabled)
                if let completed = task.completedAt {
                    Text("Completed \(TaskFormatting.date(completed))").font(TaskStyle.metadata).foregroundStyle(.secondary)
                }
                if let due = task.dueDate {
                    DisclosureGroup("Details", isExpanded: $detailsExpanded) {
                        TimingDetail(label: "Original deadline", value: TaskFormatting.date(due)).padding(.top, 8)
                    }
                    .font(TaskStyle.metadata).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TaskOverflowMenu(title: task.title) { actions }
        }
        .taskRowSurface().contextMenu { actions }
    }

    @ViewBuilder private var actions: some View {
        Button("Reopen in Inbox") { runtime.perform { try $0.moveToInbox(task) } }
        Button("Rename") { onRename(task) }
        Divider()
        Button("Delete", role: .destructive) { runtime.perform { try $0.delete(task) } }
    }
}
