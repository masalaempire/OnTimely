import AppKit
import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @State private var planningTask: TaskItem?
    @State private var renamingTask: TaskItem?
    @State private var composerVisible = false
    @State private var composerFocusRequest = UUID()

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                Text("OnTimely").font(.system(size: 20, weight: .semibold))
                    .padding(.horizontal, 12)
                VStack(spacing: 4) {
                    ForEach(AppSection.allCases) { section in
                        SidebarSectionButton(section: section,
                                             count: tasks.filter { matches($0, section: section) }.count,
                                             selected: runtime.section == section) {
                            runtime.section = section
                        }
                    }
                }
                Spacer(minLength: 24)
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Settings (⌘,)")
            }
            .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(TaskStyle.text).background(TaskStyle.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            switch runtime.section {
            case .inbox:
                InboxView(tasks: tasks.filter { $0.status == .inbox },
                          composerVisible: $composerVisible, focusRequest: composerFocusRequest,
                          onPlan: { planningTask = $0 }, onRename: { renamingTask = $0 })
            case .active:
                ActiveView(tasks: tasks.filter { $0.status == .active },
                           onPlan: { planningTask = $0 }, onRename: { renamingTask = $0 })
            case .done:
                DoneView(tasks: tasks.filter { $0.status == .completed }, onRename: { renamingTask = $0 })
            }
        }
        .tint(TaskStyle.coral)
        .environment(\.showsNotificationNotice, tasks.contains { $0.status == .active })
        .frame(minWidth: 720, minHeight: 420)
        .sheet(item: $planningTask) { task in TaskPlanningView(task: task) }
        .sheet(item: $renamingTask) { task in RenameTaskView(task: task) }
        .alert("OnTimely", isPresented: Binding(get: { runtime.errorMessage != nil }, set: { if !$0 { runtime.errorMessage = nil } })) {
            Button("OK") { runtime.errorMessage = nil }
        } message: { Text(runtime.errorMessage ?? "") }
        .onChange(of: runtime.section) { _, section in
            if section != .inbox { composerVisible = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in openWindow(id: "main") }
        .onReceive(NotificationCenter.default.publisher(for: .focusQuickAdd)) { _ in
            composerVisible = true
            composerFocusRequest = UUID()
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .task { runtime.start() }
    }

    private func matches(_ task: TaskItem, section: AppSection) -> Bool {
        switch section {
        case .inbox: task.status == .inbox
        case .active: task.status == .active
        case .done: task.status == .completed
        }
    }
}

private struct SidebarSectionButton: View {
    let section: AppSection
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.symbol).frame(width: 20)
                Text(section.rawValue)
                Spacer(minLength: 8)
                if count > 0 { Text("\(count)").font(TaskStyle.metadata).foregroundStyle(.secondary).monospacedDigit() }
            }
            .font(.system(size: 14, weight: selected ? .medium : .regular))
            .padding(12)
            .foregroundStyle(selected ? TaskStyle.coral : TaskStyle.text)
            .background(selected ? TaskStyle.selection : hovering ? TaskStyle.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .accessibilityLabel("\(section.rawValue), \(count) tasks")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct NotificationNotice: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "bell.slash").foregroundStyle(TaskStyle.coral).accessibilityHidden(true)
            Text(runtime.permission == .denied ? "Reminders are off in System Settings." : "Enable notifications to receive reminders.")
                .font(.system(size: 12)).foregroundStyle(TaskStyle.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(runtime.permission == .denied ? "Open Settings" : "Enable") {
                if runtime.permission == .denied { runtime.openNotificationSettings() }
                else { Task { await runtime.enableNotifications() } }
            }
            .buttonStyle(.link).font(.system(size: 12, weight: .medium))
            .disabled(runtime.isEnablingNotifications)
        }
        .padding(12)
        .background(TaskStyle.selection, in: RoundedRectangle(cornerRadius: 6))
    }
}
