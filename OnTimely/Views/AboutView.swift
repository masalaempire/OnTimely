import AppKit
import SwiftUI

struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About OnTimely") { openWindow(id: AboutView.windowID) }
        }
    }
}

struct AboutView: View {
    static let windowID = "about"

    private static let repositoryURL = URL(string: "https://github.com/masalaempire/OnTimely")!
    private static let websiteURL = URL(string: "https://ontimely.simonlm.one")!

    private var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "OnTimely", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApplication.shared.applicationIconImage
    }

    private var version: String {
        let release = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (release, build) {
        case let (release?, build?): return "Version \(release) (\(build))"
        case let (release?, nil): return "Version \(release)"
        default: return "Development build"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 36) {
                VStack(spacing: 18) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 224, height: 224)
                        .accessibilityHidden(true)
                    Text(version)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(width: 224)

                VStack(alignment: .leading, spacing: 0) {
                    Text("OnTimely")
                        .font(.system(size: 40, weight: .medium))
                        .accessibilityAddTraits(.isHeader)
                    Text("Start on time. Finish before the deadline.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)

                    TaskSeparator().padding(.top, 24)

                    Text("Concept & Development")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                    Text("SimonLM")
                        .font(.system(size: 25, weight: .medium))
                        .padding(.top, 5)
                    Text("With the help of Codex + ChatGPT")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
            }
            .padding(.horizontal, 36)
            .padding(.top, 48)
            .padding(.bottom, 32)
            .frame(maxHeight: .infinity)

            TaskSeparator()
            HStack(spacing: 24) {
                AboutLink(title: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", destination: Self.repositoryURL)
                AboutLink(title: "Website", symbol: "safari", destination: Self.websiteURL)
                Spacer()
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 18)
            .background(TaskStyle.sidebar)
        }
        .frame(width: 700, height: 410)
        .foregroundStyle(TaskStyle.text)
        .background(TaskStyle.content)
        .tint(TaskStyle.coral)
    }
}

private struct AboutLink: View {
    let title: String
    let symbol: String
    let destination: URL
    @Environment(\.isFocused) private var isFocused
    @State private var hovering = false

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(hovering ? TaskStyle.selection : .clear, in: Circle())
                    .overlay { Circle().strokeBorder(isFocused ? TaskStyle.coral : TaskStyle.separator, lineWidth: isFocused ? 2 : 1) }
                    .accessibilityHidden(true)
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(hovering || isFocused ? TaskStyle.coral : TaskStyle.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(title), opens in your browser")
        .help(destination.absoluteString)
    }
}

#Preview {
    AboutView()
}
