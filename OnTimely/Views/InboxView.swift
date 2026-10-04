import SwiftUI

struct InboxView: View {
    @Environment(AppRuntime.self) private var runtime
    let tasks: [TaskItem]
    @Binding var composerVisible: Bool
    let focusRequest: UUID
    let onPlan: (TaskItem) -> Void
    let onRename: (TaskItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            TaskPage(title: "Inbox", subtitle: "Capture first. Plan when you’re ready.") {
                LazyVStack(spacing: 0) {
                    ForEach(tasks) { task in
                        InboxTaskRow(task: task, onPlan: onPlan, onRename: onRename)
                        TaskSeparator()
                    }
                    Group {
                        if composerVisible {
                            QuickAddView(isPresented: $composerVisible, focusRequest: focusRequest)
                                .padding(.top, 16)
                        } else {
                            Button { runtime.focusQuickAdd() } label: {
                                Label("Add task", systemImage: "plus").font(.system(size: 14))
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16).padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain).foregroundStyle(TaskStyle.coral)
                        }
                    }
                    .id("inbox-composer")
                }
            }
            .onChange(of: focusRequest) { _, _ in proxy.scrollTo("inbox-composer", anchor: .bottom) }
            .onChange(of: tasks.count) { _, _ in
                if composerVisible { proxy.scrollTo("inbox-composer", anchor: .bottom) }
            }
            .onAppear {
                if composerVisible { proxy.scrollTo("inbox-composer", anchor: .bottom) }
            }
        }
    }
}

private struct InboxTaskRow: View {
    @Environment(AppRuntime.self) private var runtime
    let task: TaskItem
    let onPlan: (TaskItem) -> Void
    let onRename: (TaskItem) -> Void
    @State private var confirmingDelete = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CompletionButton(title: task.title) { runtime.perform { try $0.complete(task) } }
            Text(task.title).font(TaskStyle.title).lineLimit(2).textSelection(.enabled)
            Spacer(minLength: 12)
            Button("Plan") { onPlan(task) }.buttonStyle(QuietButtonStyle())
                .accessibilityLabel("Plan \(task.title)")
            TaskOverflowMenu(title: task.title) { actions }
        }
        .taskRowSurface()
        .contextMenu {
            Button("Plan") { onPlan(task) }
            actions
        }
        .confirmTaskDeletion(task, isPresented: $confirmingDelete)
    }

    @ViewBuilder private var actions: some View {
        Button("Rename") { onRename(task) }
        Divider()
        Button("Delete", role: .destructive) { confirmingDelete = true }
    }
}
