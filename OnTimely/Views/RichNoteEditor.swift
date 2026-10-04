import AppKit
import Combine
import SwiftUI

struct RichNoteEditor: NSViewRepresentable {
    @Binding var content: RichNoteContent
    @ObservedObject var formatting: NoteFormattingController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NoteEditorScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let text = NoteTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        text.isRichText = true
        text.isEditable = true
        text.isSelectable = true
        text.allowsUndo = true
        text.importsGraphics = false
        text.drawsBackground = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 14, height: 14)
        text.font = NoteMarkdownCodec.bodyFont
        text.textColor = .labelColor
        text.typingAttributes = NoteMarkdownCodec.bodyAttributes
        text.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        text.setAccessibilityLabel("Note editor")
        text.textStorage?.setAttributedString(NoteMarkdownCodec.document(content))
        if let storage = text.textStorage, storage.length > 0 {
            text.typingAttributes = storage.attributes(at: 0, effectiveRange: nil)
        }
        text.delegate = context.coordinator
        text.formatting = formatting
        scroll.documentView = text
        formatting.textView = text
        context.coordinator.lastContent = content
        formatting.scheduleSelectionUpdate()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let text = scroll.documentView as? NoteTextView else { return }
        formatting.textView = text
        text.formatting = formatting
        // Local edits are already applied in NSTextView; do not replace its text or move its caret.
        if content != context.coordinator.lastContent && !text.hasMarkedText() {
            context.coordinator.updating = true
            let selected = text.selectedRange()
            text.textStorage?.setAttributedString(NoteMarkdownCodec.document(content))
            text.setSelectedRange(NSRange(location: min(selected.location, text.string.utf16.count), length: 0))
            context.coordinator.lastContent = content
            context.coordinator.updating = false
            formatting.scheduleSelectionUpdate()
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let text = scroll.documentView as? NoteTextView else { return }
        text.delegate = nil
        if coordinator.parent.formatting.textView === text { coordinator.parent.formatting.textView = nil }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichNoteEditor
        var lastContent: RichNoteContent
        var updating = false

        init(_ parent: RichNoteEditor) { self.parent = parent; lastContent = parent.content }

        func textDidChange(_ notification: Notification) {
            guard !updating, let text = notification.object as? NoteTextView,
                  !text.hasMarkedText(), let storage = text.textStorage else { return }
            updating = true
            if !text.isFormatting && text.undoManager?.isUndoing != true && text.undoManager?.isRedoing != true {
                parent.formatting.convertTypedMarkdown()
            }
            let content = NoteMarkdownCodec.content(from: storage)
            lastContent = content
            parent.content = content
            updating = false
            parent.formatting.scheduleSelectionUpdate()
        }

        func textViewDidChangeSelection(_ notification: Notification) { parent.formatting.scheduleSelectionUpdate() }
        func textViewDidChangeTypingAttributes(_ notification: Notification) { parent.formatting.scheduleSelectionUpdate() }
    }
}

@MainActor
private final class NoteEditorScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let text = documentView as? NSTextView else { return }
        let viewport = contentView.bounds.size
        text.minSize = NSSize(width: 0, height: viewport.height)
        if text.frame.width != viewport.width || text.frame.height < viewport.height {
            text.setFrameSize(NSSize(width: viewport.width, height: max(text.frame.height, viewport.height)))
        }
    }
}

@MainActor
final class NoteFormattingController: ObservableObject {
    weak var textView: NoteTextView?
    @Published private(set) var fontSize: CGFloat = 15
    @Published private(set) var isBold = false
    @Published private(set) var isItalic = false
    @Published private(set) var isUnderlined = false
    @Published private(set) var isStruckThrough = false
    @Published private(set) var isCode = false
    @Published private(set) var blockStyle: NoteBlockStyle = .body
    @Published private(set) var blockKind = "body"

    var selectedText: String {
        guard let textView else { return "" }
        return (textView.string as NSString).substring(with: textView.selectedRange())
    }

    func scheduleSelectionUpdate() {
        DispatchQueue.main.async { [weak self] in self?.updateSelection() }
    }

    private var currentAttributes: [NSAttributedString.Key: Any] {
        guard let textView else { return NoteMarkdownCodec.bodyAttributes }
        let range = textView.selectedRange()
        if range.length > 0, range.location < textView.string.utf16.count {
            return textView.textStorage?.attributes(at: range.location, effectiveRange: nil) ?? NoteMarkdownCodec.bodyAttributes
        }
        return textView.typingAttributes
    }

    private func updateSelection() {
        guard textView != nil else { return }
        let attributes = currentAttributes
        let font = attributes[.font] as? NSFont ?? NoteMarkdownCodec.bodyFont
        let traits = NSFontManager.shared.traits(of: font)
        let block = attributes[NoteMarkdownCodec.blockKey] as? String ?? "body"
        if fontSize != font.pointSize { fontSize = font.pointSize }
        let bold = traits.contains(.boldFontMask)
        let italic = traits.contains(.italicFontMask)
        let underlined = (attributes[.underlineStyle] as? Int ?? 0) > 0
        let struckThrough = (attributes[.strikethroughStyle] as? Int ?? 0) > 0
        let code = attributes[NoteMarkdownCodec.inlineCodeKey] as? Bool ?? false
        if isBold != bold { isBold = bold }
        if isItalic != italic { isItalic = italic }
        if isUnderlined != underlined { isUnderlined = underlined }
        if isStruckThrough != struckThrough { isStruckThrough = struckThrough }
        if isCode != code { isCode = code }
        if blockKind != block { blockKind = block }
        let style: NoteBlockStyle
        switch block {
        case "heading:1": style = .title
        case "heading:2": style = .heading
        case "heading:3", "heading:4", "heading:5", "heading:6": style = .subheading
        default: style = .body
        }
        if blockStyle != style { blockStyle = style }
    }

    func setFontSize(_ size: CGFloat) {
        transformCharacters("Change text size") { attributes in
            let font = attributes[.font] as? NSFont ?? NoteMarkdownCodec.bodyFont
            attributes[.font] = NSFontManager.shared.convert(font, toSize: size)
        }
    }

    func toggleBold() { toggleTrait(.boldFontMask, name: "Bold") }
    func toggleItalic() { toggleTrait(.italicFontMask, name: "Italic") }

    private func toggleTrait(_ trait: NSFontTraitMask, name: String) {
        let font = currentAttributes[.font] as? NSFont ?? NoteMarkdownCodec.bodyFont
        let remove = NSFontManager.shared.traits(of: font).contains(trait)
        transformCharacters(name) { attributes in
            let font = attributes[.font] as? NSFont ?? NoteMarkdownCodec.bodyFont
            attributes[.font] = remove ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(font, toHaveTrait: trait)
        }
    }

    func toggleUnderline() { toggleDecoration(.underlineStyle, name: "Underline") }
    func toggleStrikethrough() { toggleDecoration(.strikethroughStyle, name: "Strikethrough") }

    private func toggleDecoration(_ key: NSAttributedString.Key, name: String) {
        let remove = (currentAttributes[key] as? Int ?? 0) > 0
        transformCharacters(name) { attributes in
            if remove { attributes.removeValue(forKey: key) }
            else { attributes[key] = NSUnderlineStyle.single.rawValue }
        }
    }

    func toggleCode() {
        let remove = currentAttributes[NoteMarkdownCodec.inlineCodeKey] as? Bool ?? false
        transformCharacters("Code") { attributes in
            let size = (attributes[.font] as? NSFont)?.pointSize ?? 15
            if remove {
                attributes.removeValue(forKey: NoteMarkdownCodec.inlineCodeKey)
                attributes[.font] = NSFont.systemFont(ofSize: size)
            } else {
                attributes[NoteMarkdownCodec.inlineCodeKey] = true
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            }
        }
    }

    func setBlockStyle(_ style: NoteBlockStyle) {
        setParagraphKind(style.level == 0 ? "body" : "heading:\(style.level)")
    }

    func toggleList(_ style: NoteListStyle) {
        let block = currentAttributes[NoteMarkdownCodec.blockKey] as? String
        setParagraphKind(block == style.rawValue ? "body" : style.rawValue)
    }

    func setCodeBlock() {
        let block = currentAttributes[NoteMarkdownCodec.blockKey] as? String
        setParagraphKind(block == "codeBlock" ? "body" : "codeBlock")
    }

    func toggleChecklistItem() {
        guard let text = textView, let storage = text.textStorage else { return }
        let paragraph = (text.string as NSString).paragraphRange(for: text.selectedRange())
        let line = (text.string as NSString).substring(with: paragraph)
        guard line.hasPrefix("☐\t") || line.hasPrefix("☑\t") else { return }
        perform("Check item") {
            storage.replaceCharacters(in: NSRange(location: paragraph.location, length: 1),
                                      with: line.hasPrefix("☐") ? "☑" : "☐")
        }
    }

    private func setParagraphKind(_ kind: String) {
        guard let text = textView, let storage = text.textStorage else { return }
        let original = text.string as NSString
        let selection = text.selectedRange()
        let range = original.paragraphRange(for: NSRange(location: selection.location,
                                                         length: max(0, selection.length - 1)))
        var paragraphs: [NSRange] = []
        var location = range.location
        while location < NSMaxRange(range) {
            let paragraph = original.paragraphRange(for: NSRange(location: location, length: 0))
            paragraphs.append(paragraph)
            location = NSMaxRange(paragraph)
        }
        if paragraphs.isEmpty { paragraphs = [NSRange(location: selection.location, length: 0)] }
        var selectionStart = selection.location
        var selectionEnd = NSMaxRange(selection)
        perform("Paragraph format") {
            for (index, paragraph) in paragraphs.enumerated().reversed() {
                let raw = (storage.string as NSString).substring(with: paragraph)
                let oldPrefix = NoteMarkdownCodec.listPrefix(raw)?.length ?? 0
                let prefix: String
                switch kind {
                case "bullet": prefix = "•\t"
                case "numbered": prefix = "\(index + 1).\t"
                case "checklist": prefix = "☐\t"
                default: prefix = ""
                }
                let attributes = NoteMarkdownCodec.attributes(for: kind)
                if oldPrefix > 0 { storage.deleteCharacters(in: NSRange(location: paragraph.location, length: oldPrefix)) }
                if !prefix.isEmpty { storage.insert(NSAttributedString(string: prefix, attributes: attributes), at: paragraph.location) }
                let length = paragraph.length - oldPrefix + (prefix as NSString).length
                if length > 0 { storage.addAttributes(attributes, range: NSRange(location: paragraph.location, length: length)) }
                let delta = (prefix as NSString).length - oldPrefix
                if paragraph.location <= selectionStart { selectionStart = max(paragraph.location, selectionStart + delta) }
                if paragraph.location <= selectionEnd { selectionEnd = max(paragraph.location, selectionEnd + delta) }
            }
            selectionStart = min(selectionStart, storage.length)
            selectionEnd = min(max(selectionStart, selectionEnd), storage.length)
            text.setSelectedRange(NSRange(location: selectionStart, length: selectionEnd - selectionStart))
            text.typingAttributes = NoteMarkdownCodec.attributes(for: kind)
        }
    }

    func insertLink(label: String, url: URL) {
        guard let text = textView else { return }
        var attributes = currentAttributes
        attributes[.link] = url
        text.window?.makeFirstResponder(text)
        text.isFormatting = true
        text.insertText(NSAttributedString(string: label, attributes: attributes), replacementRange: text.selectedRange())
        attributes.removeValue(forKey: .link)
        text.typingAttributes = attributes
        text.isFormatting = false
        updateSelection()
    }

    private func transformCharacters(_ name: String, transform: (inout [NSAttributedString.Key: Any]) -> Void) {
        guard let text = textView, let storage = text.textStorage else { return }
        let range = text.selectedRange()
        perform(name) {
            if range.length > 0 {
                var changes: [(NSRange, [NSAttributedString.Key: Any])] = []
                storage.enumerateAttributes(in: range) { attributes, run, _ in
                    var attributes = attributes
                    transform(&attributes)
                    changes.append((run, attributes))
                }
                for (run, attributes) in changes { storage.setAttributes(attributes, range: run) }
            }
            var typing = text.typingAttributes
            transform(&typing)
            text.typingAttributes = typing
        }
    }

    private func perform(_ name: String, changes: () -> Void) {
        guard let text = textView, let storage = text.textStorage, !text.hasMarkedText() else { return }
        text.window?.makeFirstResponder(text)
        guard text.shouldChangeText(in: NSRange(location: 0, length: storage.length), replacementString: nil) else { return }
        text.registerFormattingUndo(name)
        text.isFormatting = true
        storage.beginEditing()
        changes()
        storage.endEditing()
        text.didChangeText()
        text.isFormatting = false
        updateSelection()
    }

    /// Familiar Markdown shortcuts still work, while all formatting is also available in the toolbar.
    func convertTypedMarkdown() {
        guard let text = textView, let storage = text.textStorage, text.selectedRange().length == 0 else { return }
        let caret = text.selectedRange().location
        let source = text.string as NSString
        let paragraph = source.paragraphRange(for: NSRange(location: caret, length: 0))
        let beforeCaret = source.substring(with: NSRange(location: paragraph.location, length: caret - paragraph.location))
        if let marker = beforeCaret.range(of: #"^(#{1,6}|[-+*]|\d+[.)]|>) $"#, options: .regularExpression) {
            let prefix = String(beforeCaret[marker])
            text.isFormatting = true
            text.insertText("", replacementRange: NSRange(location: paragraph.location, length: (prefix as NSString).length))
            text.isFormatting = false
            if prefix.hasPrefix("#") {
                setParagraphKind("heading:\(prefix.filter { $0 == "#" }.count)")
            } else if prefix.hasPrefix(">") { setParagraphKind("quote") }
            else if prefix.first?.isNumber == true { setParagraphKind("numbered") }
            else { setParagraphKind("bullet") }
            return
        }
        let patterns = [#"\*\*[^*\n]+\*\*$"#, #"(?<!\*)\*[^*\n]+\*$"#, #"__[^_\n]+__$"#,
                        #"(?<!_)_[^_\n]+_$"#, #"~~[^~\n]+~~$"#, #"`[^`\n]+`$"#, #"\[[^\]\n]+\]\([^\s)]+\)$"#]
        for pattern in patterns {
            guard let range = beforeCaret.range(of: pattern, options: .regularExpression) else { continue }
            let matched = String(beforeCaret[range])
            let localRange = NSRange(range, in: beforeCaret)
            let documentRange = NSRange(location: paragraph.location + localRange.location, length: localRange.length)
            let attributes = storage.attributes(at: documentRange.location, effectiveRange: nil)
            let formatted = NoteMarkdownCodec.inline(matched, attributes: attributes)
            let typing = text.typingAttributes
            text.isFormatting = true
            text.insertText(formatted, replacementRange: documentRange)
            text.typingAttributes = typing
            text.isFormatting = false
            return
        }
    }
}

@MainActor
final class NoteTextView: NSTextView {
    weak var formatting: NoteFormattingController?
    var isFormatting = false

    private struct Snapshot {
        let document: NSAttributedString
        let selection: NSRange
        let typing: [NSAttributedString.Key: Any]
    }

    func registerFormattingUndo(_ name: String) {
        guard let storage = textStorage else { return }
        let snapshot = Snapshot(document: NSAttributedString(attributedString: storage), selection: selectedRange(), typing: typingAttributes)
        undoManager?.registerUndo(withTarget: self) { view in view.restore(snapshot, name: name) }
        undoManager?.setActionName(name)
    }

    private func restore(_ snapshot: Snapshot, name: String) {
        registerFormattingUndo(name)
        isFormatting = true
        textStorage?.setAttributedString(snapshot.document)
        setSelectedRange(snapshot.selection)
        typingAttributes = snapshot.typing
        didChangeText()
        isFormatting = false
        formatting?.scheduleSelectionUpdate()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "b": formatting?.toggleBold(); return true
            case "i": formatting?.toggleItalic(); return true
            case "u": formatting?.toggleUnderline(); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), selectedRange().length == 0 else { super.insertNewline(sender); return }
        let source = string as NSString
        let paragraph = source.paragraphRange(for: selectedRange())
        let line = source.substring(with: paragraph).trimmingCharacters(in: .newlines)
        let kind = typingAttributes[NoteMarkdownCodec.blockKey] as? String ?? "body"
        if let marker = NoteMarkdownCodec.listPrefix(line), ["bullet", "numbered", "checklist"].contains(kind) {
            if (line as NSString).length == marker.length {
                isFormatting = true
                insertText("", replacementRange: NSRange(location: paragraph.location, length: marker.length))
                typingAttributes = NoteMarkdownCodec.bodyAttributes
                didChangeText()
                isFormatting = false
                return
            }
            let prefix: String
            if kind == "numbered" {
                let number = Int(line.prefix { $0.isNumber }) ?? 1
                prefix = "\(number + 1).\t"
            } else { prefix = kind == "checklist" ? "☐\t" : "•\t" }
            isFormatting = true
            super.insertNewline(sender)
            insertText(NSAttributedString(string: prefix, attributes: NoteMarkdownCodec.attributes(for: kind)), replacementRange: selectedRange())
            isFormatting = false
        } else {
            isFormatting = true
            super.insertNewline(sender)
            if kind.hasPrefix("heading:") { typingAttributes = NoteMarkdownCodec.bodyAttributes }
            isFormatting = false
        }
        formatting?.scheduleSelectionUpdate()
    }
}
