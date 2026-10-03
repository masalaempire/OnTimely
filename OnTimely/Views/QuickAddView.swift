import SwiftUI

struct QuickAddView: View {
    @Environment(AppRuntime.self) private var runtime
    @Binding var isPresented: Bool
    let focusRequest: UUID
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("What do you need to do?", text: $title)
                .textFieldStyle(.plain).font(TaskStyle.title)
                .focused($focused).onSubmit(capture)
                .accessibilityLabel("New task name")
            HStack(spacing: 12) {
                Text("Return to add · Escape to close").font(TaskStyle.metadata).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Cancel") { isPresented = false }.buttonStyle(.plain).font(.system(size: 13))
                Button("Add task", action: capture).buttonStyle(PrimaryButtonStyle())
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(TaskStyle.content, in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(TaskStyle.coral, lineWidth: 1) }
        .onAppear { focused = true }
        .onChange(of: focusRequest) { _, _ in focused = true }
        .onExitCommand { isPresented = false }
    }

    private func capture() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if runtime.perform({ _ = try $0.capture(title: title) }) { title = ""; focused = true }
    }
}
