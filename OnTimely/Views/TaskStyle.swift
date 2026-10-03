import AppKit
import SwiftUI

enum TaskStyle {
    static let content = adaptive(light: 0xFFFFFF, dark: 0x211F1D)
    static let sidebar = adaptive(light: 0xFAF8F5, dark: 0x292622)
    static let text = adaptive(light: 0x282624, dark: 0xEEEAE5, highLight: 0x111111, highDark: 0xFFFFFF)
    static let coral = adaptive(light: 0xC44437, dark: 0xED8879, highLight: 0xA43226, highDark: 0xFFA99B)
    static let onCoral = adaptive(light: 0xFFFFFF, dark: 0x211F1D)
    static let selection = adaptive(light: 0xFCEBE5, dark: 0x472923)
    static let hover = adaptive(light: 0xF5F2EE, dark: 0x302C28)
    static let separator = adaptive(light: 0xE9E4DE, dark: 0x413B35, highLight: 0x8A8178, highDark: 0x9B9187)
    static let heading = Font.system(size: 28, weight: .semibold)
    static let title = Font.system(size: 15)
    static let metadata = Font.system(size: 12)

    private static func adaptive(light: UInt32, dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            let hex: UInt32
            if match == .accessibilityHighContrastAqua { hex = highLight ?? light }
            else if match == .accessibilityHighContrastDarkAqua { hex = highDark ?? dark }
            else if match == .darkAqua { hex = dark }
            else { hex = light }
            return NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                           green: Double((hex >> 8) & 0xFF) / 255,
                           blue: Double(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

struct TaskPage<Content: View>: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.showsNotificationNotice) private var showsNotificationNotice
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeading(title: title, subtitle: subtitle)
                    if showsNotificationNotice && runtime.permission != .allowed && runtime.permission != .unknown {
                        NotificationNotice()
                    }
                    content()
                }
                .frame(maxWidth: 780, alignment: .leading)
                .padding(.horizontal, geometry.size.width < 620 ? 24 : 32)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .foregroundStyle(TaskStyle.text)
        .background(TaskStyle.content)
    }
}

private struct NotificationNoticeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var showsNotificationNotice: Bool {
        get { self[NotificationNoticeKey.self] }
        set { self[NotificationNoticeKey.self] = newValue }
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(TaskStyle.heading).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}

struct TaskEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(TaskStyle.coral)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 17, weight: .medium))
            Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action).buttonStyle(QuietButtonStyle())
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .foregroundStyle(TaskStyle.onCoral)
            .background(isEnabled ? TaskStyle.coral : Color.secondary, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if isFocused { RoundedRectangle(cornerRadius: 8).strokeBorder(TaskStyle.coral, lineWidth: 2).padding(-4) }
            }
            .opacity(configuration.isPressed ? 0.8 : isEnabled ? 1 : 0.5)
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(isEnabled ? TaskStyle.text : Color.secondary)
            .background(configuration.isPressed ? TaskStyle.selection : TaskStyle.hover, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(isFocused ? TaskStyle.coral : TaskStyle.separator, lineWidth: isFocused ? 2 : 1) }
            .opacity(isEnabled ? 1 : 0.5)
    }
}

struct CompletionButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: hovering ? "checkmark.circle" : "circle")
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(hovering ? TaskStyle.coral : Color.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Complete \(title)")
        .help("Mark as done")
    }
}

struct TaskOverflowMenu<Actions: View>: View {
    let title: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        Menu(content: actions) {
            Image(systemName: "ellipsis").font(.system(size: 16))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .accessibilityLabel("Actions for \(title)")
    }
}

private struct TaskRowSurface: ViewModifier {
    let highlighted: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(highlighted ? TaskStyle.selection : hovering ? TaskStyle.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

extension View {
    func taskRowSurface(highlighted: Bool = false) -> some View {
        modifier(TaskRowSurface(highlighted: highlighted))
    }
}

struct TaskSeparator: View {
    var body: some View { Rectangle().fill(TaskStyle.separator).frame(height: 1).accessibilityHidden(true) }
}

struct TimingDetail: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(TaskStyle.metadata)
    }
}

enum MinuteText {
    static func value(_ text: String) -> Int? { Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) }

    static func error(_ text: String, range: ClosedRange<Int>, message: String) -> String? {
        guard let value = value(text), range.contains(value) else { return message }
        return nil
    }
}

struct MinuteInput: View {
    let label: String
    @Binding var text: String
    let range: ClosedRange<Int>
    let errorMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(label).font(.system(size: 13))
                Spacer(minLength: 8)
                TextField("Minutes", text: $text)
                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                    .frame(width: 72).accessibilityLabel(label)
                    .accessibilityHint("Enter whole minutes, from \(range.lowerBound) to \(range.upperBound).")
                Text("min").font(TaskStyle.metadata).foregroundStyle(.secondary)
            }
            if let error = MinuteText.error(text, range: range, message: errorMessage) {
                Text(error).font(TaskStyle.metadata).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
