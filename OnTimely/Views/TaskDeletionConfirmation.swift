import SwiftUI

private struct TaskDeletionConfirmation: ViewModifier {
    @Environment(AppRuntime.self) private var runtime
    let task: TaskItem
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert("Are you sure?", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                runtime.perform { try $0.delete(task) }
            }
        } message: {
            Text("Delete the task “\(task.title)”? This cannot be undone.")
        }
    }
}

extension View {
    func confirmTaskDeletion(_ task: TaskItem, isPresented: Binding<Bool>) -> some View {
        modifier(TaskDeletionConfirmation(task: task, isPresented: isPresented))
    }
}
