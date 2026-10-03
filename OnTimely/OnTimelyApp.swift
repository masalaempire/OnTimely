import SwiftUI
import SwiftData

@main
struct OnTimelyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var runtime: AppRuntime
    @StateObject private var updates = AppUpdater()

    init() {
        let runtime = AppRuntime()
        _runtime = State(initialValue: runtime)
        AppDelegate.runtime = runtime
    }

    var body: some Scene {
        Window("OnTimely", id: "main") {
            if let container = runtime.container {
                AppLaunchView(updates: updates)
                    .environment(runtime)
                    .modelContainer(container)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("OnTimely couldn’t open your tasks.").font(.title2)
                    Text(runtime.startupError ?? "Try opening the app again.").foregroundStyle(.secondary)
                    Text("Your saved data has been kept. Quit and reopen the app to try again.")
                }
                .padding(40)
                .frame(width: 540)
                .onAppear { updates.start() }
            }
        }
        .defaultSize(width: 1000, height: 680)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) { CheckForUpdatesButton(updates: updates) }
            CommandGroup(replacing: .newItem) {
                Button("Add Task") { runtime.focusQuickAdd() }
                    .keyboardShortcut("n")
            }
            CommandMenu("Tasks") {
                Button("Inbox") { runtime.section = .inbox }.keyboardShortcut("1")
                Button("Active") { runtime.section = .active }.keyboardShortcut("2")
                Button("Done") { runtime.section = .done }.keyboardShortcut("3")
            }
        }
        Settings {
            SettingsView(updates: updates).environment(runtime).tint(TaskStyle.coral)
        }
    }
}
