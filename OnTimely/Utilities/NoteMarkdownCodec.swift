import AppKit
import Foundation

struct RichNoteContent: Equatable {
    var markdown: String
    var richTextData: Data?
}

enum NoteBlockStyle: String, CaseIterable, Identifiable {
    case body = "Body", title = "Title", heading = "Heading", subheading = "Subheading"
    var id: String { rawValue }
    var level: Int {
        switch self { case .body: 0; case .title: 1; case .heading: 2; case .subheading: 3 }
    }
}

enum NoteListStyle: String {
    case bullet, numbered, checklist, quote
}

/// Markdown remains the text representation; a small Codable archive retains the exact editor formatting.
@MainActor
enum NoteMarkdownCodec {
    static let blockKey = NSAttributedString.Key("OnTimelyNoteBlock")
    static let inlineCodeKey = NSAttributedString.Key("OnTimelyNoteInlineCode")
    static let bodyFont = NSFont.systemFont(ofSize: 15)

    static func paragraphStyle(level: Int = 0, indented: Bool = false) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.headerLevel = level
        style.lineSpacing = 4
        style.paragraphSpacing = level > 0 ? 10 : 6
        if indented {
            style.headIndent = 24
            style.tabStops = [NSTextTab(textAlignment: .left, location: 24, options: [:])]
            style.defaultTabInterval = 24
        }
        return style
    }

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.labelColor,
         .paragraphStyle: paragraphStyle(), blockKey: "body"]
    }

    static func attributes(for block: String) -> [NSAttributedString.Key: Any] {
        var attributes = bodyAttributes
        attributes[blockKey] = block
        if block.hasPrefix("heading:"), let level = Int(block.dropFirst(8)) {
            let sizes: [CGFloat] = [28, 23, 19, 17, 15, 15]
            attributes[.font] = NSFont.systemFont(ofSize: sizes[min(max(level - 1, 0), 5)], weight: .semibold)
            attributes[.paragraphStyle] = paragraphStyle(level: level)
        } else if ["bullet", "numbered", "checklist"].contains(block) {
            attributes[.paragraphStyle] = paragraphStyle(indented: true)
        } else if block == "quote" {
            let style = paragraphStyle()
            style.headIndent = 16
            style.firstLineHeadIndent = 16
            attributes[.paragraphStyle] = style
        } else if block == "codeBlock" {
            attributes[.font] = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            attributes[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.10)
        }
        return attributes
    }

    static func document(_ content: RichNoteContent) -> NSAttributedString {
        if let data = content.richTextData, let archive = try? JSONDecoder().decode(Archive.self, from: data), archive.version == 1 {
            let result = NSMutableAttributedString(string: "")
            for run in archive.runs {
                var attributes = self.attributes(for: run.block)
                var font = NSFont(name: run.fontName, size: CGFloat(run.size)) ?? NSFont.systemFont(ofSize: CGFloat(run.size))
                if run.bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if run.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                attributes[.font] = font
                if run.code { attributes[inlineCodeKey] = true }
                if run.underline > 0 { attributes[.underlineStyle] = run.underline }
                if run.strikethrough > 0 { attributes[.strikethroughStyle] = run.strikethrough }
                if let link = run.link { attributes[.link] = link }
                result.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            return result
        }
        return fromMarkdown(content.markdown)
    }

    static func content(from document: NSAttributedString) -> RichNoteContent {
        var runs: [Run] = []
        document.enumerateAttributes(in: NSRange(location: 0, length: document.length)) { attributes, range, _ in
            let font = attributes[.font] as? NSFont ?? bodyFont
            let traits = NSFontManager.shared.traits(of: font)
            let link = (attributes[.link] as? URL)?.absoluteString ?? (attributes[.link] as? String)
            runs.append(Run(text: (document.string as NSString).substring(with: range), fontName: font.fontName,
                            size: Double(font.pointSize), bold: traits.contains(.boldFontMask), italic: traits.contains(.italicFontMask),
                            code: attributes[inlineCodeKey] as? Bool ?? false,
                            underline: attributes[.underlineStyle] as? Int ?? 0,
                            strikethrough: attributes[.strikethroughStyle] as? Int ?? 0,
                            link: link, block: attributes[blockKey] as? String ?? "body"))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return RichNoteContent(markdown: markdown(from: document),
                               richTextData: try? encoder.encode(Archive(version: 1, runs: runs)))
    }

    static func inline(_ source: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        guard let parsed = try? AttributedString(markdown: source,
                                                 options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: source, attributes: attributes)
        }
        let result = NSMutableAttributedString(string: String(parsed.characters), attributes: attributes)
        var offset = 0
        for run in parsed.runs {
            let count = String(parsed[run.range].characters).utf16.count
            let range = NSRange(location: offset, length: count)
            var font = attributes[.font] as? NSFont ?? bodyFont
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    font = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                    result.addAttribute(inlineCodeKey, value: true, range: range)
                }
                if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                if intent.contains(.strikethrough) { result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            }
            result.addAttribute(.font, value: font, range: range)
            if let link = run.link { result.addAttribute(.link, value: link, range: range) }
            offset += count
        }
        return result
    }

    private static func fromMarkdown(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var fence: String?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if fence == nil { fence = marker; continue }
                if fence == marker { fence = nil; continue }
            }
            var block = "body"
            var text = line
            var prefix = ""
            if fence != nil {
                block = "codeBlock"
            } else if let range = line.range(of: #"^\s{0,3}#{1,6}\s+"#, options: .regularExpression) {
                let level = line[range].filter { $0 == "#" }.count
                block = "heading:\(level)"
                text = String(line[range.upperBound...])
            } else if let range = line.range(of: #"^\s*[-+*]\s+\[[ xX]\]\s*"#, options: .regularExpression) {
                block = "checklist"
                prefix = line[range].lowercased().contains("[x]") ? "☑\t" : "☐\t"
                text = String(line[range.upperBound...])
            } else if let range = line.range(of: #"^\s*[-+*]\s+"#, options: .regularExpression) {
                block = "bullet"; prefix = "•\t"; text = String(line[range.upperBound...])
            } else if let range = line.range(of: #"^\s*\d+[.)]\s+"#, options: .regularExpression) {
                block = "numbered"
                prefix = String(line[range]).trimmingCharacters(in: .whitespaces) + "\t"
                text = String(line[range.upperBound...])
            } else if let range = line.range(of: #"^\s*>\s?"#, options: .regularExpression) {
                block = "quote"; text = String(line[range.upperBound...])
            } else if ["---", "***", "___"].contains(trimmed) {
                block = "rule"; text = "────────"
            }
            let attributes = self.attributes(for: block)
            result.append(NSAttributedString(string: prefix, attributes: attributes))
            result.append(block == "codeBlock" ? NSAttributedString(string: text, attributes: attributes) : inline(text, attributes: attributes))
            if index < lines.count - 1 { result.append(NSAttributedString(string: "\n", attributes: attributes)) }
        }
        return result
    }

    private static func markdown(from document: NSAttributedString) -> String {
        let string = document.string as NSString
        var lines: [String] = []
        var location = 0
        var inCode = false
        while location < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            let raw = string.substring(with: paragraph).trimmingCharacters(in: .newlines)
            let block = document.attribute(blockKey, at: location, effectiveRange: nil) as? String ?? "body"
            if block == "codeBlock" {
                if !inCode { lines.append("```"); inCode = true }
                lines.append(raw)
            } else {
                if inCode { lines.append("```"); inCode = false }
                var range = NSRange(location: paragraph.location, length: (raw as NSString).length)
                var prefix = ""
                if block.hasPrefix("heading:"), let level = Int(block.dropFirst(8)) {
                    prefix = String(repeating: "#", count: min(max(level, 1), 6)) + " "
                } else if let marker = listPrefix(raw) {
                    range.location += marker.length
                    range.length -= marker.length
                    prefix = marker.markdown
                } else if block == "quote" {
                    prefix = "> "
                } else if block == "rule" {
                    lines.append("---")
                    location = NSMaxRange(paragraph)
                    continue
                }
                lines.append(prefix + inlineMarkdown(document, range: range))
            }
            location = NSMaxRange(paragraph)
        }
        if inCode { lines.append("```") }
        var result = lines.joined(separator: "\n")
        if document.string.hasSuffix("\n") { result += "\n" }
        return result
    }

    static func listPrefix(_ text: String) -> (length: Int, markdown: String)? {
        for (prefix, markdown) in [("•\t", "- "), ("☐\t", "- [ ] "), ("☑\t", "- [x] ")] {
            if text.hasPrefix(prefix) { return ((prefix as NSString).length, markdown) }
        }
        if let range = text.range(of: #"^\d+[.)]\t"#, options: .regularExpression) {
            return ((String(text[range]) as NSString).length, String(text[range]).replacingOccurrences(of: "\t", with: " "))
        }
        return nil
    }

    private static func inlineMarkdown(_ document: NSAttributedString, range: NSRange) -> String {
        var result = ""
        document.enumerateAttributes(in: range) { attributes, runRange, _ in
            let raw = (document.string as NSString).substring(with: runRange)
            let leading = String(raw.prefix { $0.isWhitespace })
            let rest = raw.dropFirst(leading.count)
            let trailing = String(rest.reversed().prefix { $0.isWhitespace }.reversed())
            let core = String(rest.dropLast(trailing.count))
            guard !core.isEmpty else { result += raw; return }
            var text = core
            if attributes[inlineCodeKey] as? Bool == true {
                let fence = core.contains("`") ? "``" : "`"
                text = fence + " " + core + " " + fence
            } else {
                for character in ["\\", "*", "_", "[", "]", "`", "~"] {
                    text = text.replacingOccurrences(of: character, with: "\\" + character)
                }
                let font = attributes[.font] as? NSFont ?? bodyFont
                let traits = NSFontManager.shared.traits(of: font)
                let block = attributes[blockKey] as? String ?? "body"
                if traits.contains(.boldFontMask) && !block.hasPrefix("heading:") { text = "**" + text + "**" }
                if traits.contains(.italicFontMask) { text = "*" + text + "*" }
                if (attributes[.strikethroughStyle] as? Int ?? 0) > 0 { text = "~~" + text + "~~" }
                if (attributes[.underlineStyle] as? Int ?? 0) > 0 && attributes[.link] == nil { text = "<u>" + text + "</u>" }
            }
            if let url = (attributes[.link] as? URL)?.absoluteString ?? (attributes[.link] as? String) {
                text = "[" + text + "](" + url.replacingOccurrences(of: ")", with: "%29") + ")"
            }
            result += leading + text + trailing
        }
        return result
    }

    private struct Archive: Codable { let version: Int; let runs: [Run] }
    private struct Run: Codable {
        let text: String
        let fontName: String
        let size: Double
        let bold: Bool
        let italic: Bool
        let code: Bool
        let underline: Int
        let strikethrough: Int
        let link: String?
        let block: String
    }
}
