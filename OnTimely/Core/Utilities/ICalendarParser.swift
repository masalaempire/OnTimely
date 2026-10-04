import Foundation

enum CalendarFeedError: LocalizedError {
    case invalidLink, invalidCalendar, unsupportedTimeZone(String), alreadyConnected
    case unavailable, unauthorized, server(Int), tooLarge, missingCredential, credentialStorage

    var errorDescription: String? {
        switch self {
        case .invalidLink: "Paste a webcal:// or https:// calendar subscription link."
        case .invalidCalendar: "This link didn’t return a readable calendar. Copy the subscription link from ManageBac and try again."
        case .unsupportedTimeZone(let zone): "The calendar uses an unrecognized time zone (\(zone))."
        case .alreadyConnected: "This calendar is already connected. Use Refresh to get its latest tasks."
        case .unavailable: "The calendar couldn’t be reached. Check your connection and try again."
        case .unauthorized: "This calendar link has expired or isn’t accessible. Copy a new subscription link from ManageBac."
        case .server(let status): "The calendar server returned an error (\(status)). Try again later."
        case .tooLarge: "This calendar is too large to import. Try subscribing to a more specific calendar."
        case .missingCredential: "The saved calendar link isn’t available. Disconnect this calendar and connect it again."
        case .credentialStorage: "The calendar link couldn’t be saved securely. Try again."
        }
    }
}

enum CalendarEventDeadlineSource: String, Sendable {
    case start = "DTSTART"
    case end = "DTEND"
}

/// Reads explicit, timed assignment deadlines. All-day school events and unexpanded
/// recurring series are excluded rather than silently inventing submission times.
enum ICalendarParser {
    private struct Property {
        let name: String
        let parameters: [String: String]
        let value: String
    }

    private struct Component {
        let kind: String
        let properties: [Property]

        func first(_ name: String) -> Property? { properties.first { $0.name == name } }
    }

    static func parse(_ data: Data, defaultTimeZone: TimeZone,
                      eventDeadlineSource: CalendarEventDeadlineSource = .end) throws -> ImportedCalendarFeed {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16), text.uppercased().contains("BEGIN:VCALENDAR") else {
            throw CalendarFeedError.invalidCalendar
        }
        let lines = unfold(text)
        var stack: [String] = []
        var calendarProperties: [Property] = []
        var components: [Component] = []
        var currentProperties: [Property] = []
        var timezoneProperties: [Property] = []
        var fixedZones: [String: TimeZone] = [:]
        var timezoneHasDaylight = false
        var foundCalendar = false
        var endedCalendar = false

        for line in lines {
            guard let property = parseProperty(line) else { continue }
            if property.name == "BEGIN" {
                let kind = property.value.uppercased()
                stack.append(kind)
                if kind == "VCALENDAR" { foundCalendar = true }
                if kind == "VEVENT" || kind == "VTODO" { currentProperties = [] }
                if kind == "VTIMEZONE" { timezoneProperties = []; timezoneHasDaylight = false }
                if kind == "DAYLIGHT", stack.contains("VTIMEZONE") { timezoneHasDaylight = true }
            } else if property.name == "END" {
                let kind = property.value.uppercased()
                guard stack.last == kind else { throw CalendarFeedError.invalidCalendar }
                if kind == "VEVENT" || kind == "VTODO" {
                    components.append(Component(kind: kind, properties: currentProperties))
                } else if kind == "VTIMEZONE", !timezoneHasDaylight,
                          let id = timezoneProperties.first(where: { $0.name == "TZID" })?.value,
                          let offset = timezoneProperties.first(where: { $0.name == "TZOFFSETTO" })?.value,
                          let seconds = offsetSeconds(offset), let zone = TimeZone(secondsFromGMT: seconds) {
                    fixedZones[id] = zone
                } else if kind == "VCALENDAR" { endedCalendar = true }
                stack.removeLast()
            } else if stack.last == "VCALENDAR" {
                calendarProperties.append(property)
            } else if stack.last == "VEVENT" || stack.last == "VTODO" {
                currentProperties.append(property)
            } else if stack.contains("VTIMEZONE") {
                timezoneProperties.append(property)
            }
        }
        guard foundCalendar, endedCalendar, stack.isEmpty else { throw CalendarFeedError.invalidCalendar }
        let floatingZone: TimeZone
        if let identifier = calendarProperties.first(where: { $0.name == "X-WR-TIMEZONE" })?.value {
            floatingZone = try timeZone(identifier, fixedZones: fixedZones)
        } else { floatingZone = defaultTimeZone }

        var events: [String: ImportedCalendarEvent] = [:]
        var excluded = 0
        for component in components {
            guard let uid = component.first("UID")?.value, !uid.isEmpty else { excluded += 1; continue }
            let recurrenceID = component.first("RECURRENCE-ID")?.value
            let id = recurrenceID.map { "\(uid)|\($0)" } ?? uid
            let cancelled = component.first("STATUS")?.value.uppercased() == "CANCELLED"
            let title = unescape(component.first("SUMMARY")?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if cancelled {
                events[id] = ImportedCalendarEvent(id: id, title: title, dueDate: nil, isCancelled: true)
                continue
            }
            // A series master is not a single assignment. Explicit recurrence instances are supported.
            guard component.first("RRULE") == nil, !title.isEmpty else { excluded += 1; continue }
            // ManageBac task events begin at the submission deadline. Their display
            // block ends later; that end is neither a deadline nor a work estimate.
            // VTODO feeds provide an explicit DUE independent of event display times.
            let deadline = component.first(component.kind == "VTODO" ? "DUE" : eventDeadlineSource.rawValue)
            guard let deadline, deadline.parameters["VALUE"]?.uppercased() != "DATE",
                  let due = try date(deadline, floatingZone: floatingZone, fixedZones: fixedZones) else {
                excluded += 1
                continue
            }
            events[id] = ImportedCalendarEvent(id: id, title: title, dueDate: due, isCancelled: false)
        }
        return ImportedCalendarFeed(name: calendarProperties.first(where: { $0.name == "X-WR-CALNAME" }).map { unescape($0.value) },
                                    events: events.values.sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) },
                                    excludedEntryCount: excluded)
    }

    private static func unfold(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for raw in normalized.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    private static func parseProperty(_ line: String) -> Property? {
        var quoted = false
        var separator: String.Index?
        for index in line.indices {
            if line[index] == "\"" { quoted.toggle() }
            if line[index] == ":", !quoted { separator = index; break }
        }
        guard let separator else { return nil }
        let header = String(line[..<separator])
        var parts: [String] = []
        var part = ""
        quoted = false
        for character in header {
            if character == "\"" { quoted.toggle() }
            if character == ";", !quoted { parts.append(part); part = "" }
            else { part.append(character) }
        }
        parts.append(part)
        guard let name = parts.first else { return nil }
        var parameters: [String: String] = [:]
        for parameter in parts.dropFirst() {
            guard let equals = parameter.firstIndex(of: "=") else { continue }
            parameters[String(parameter[..<equals]).uppercased()] = String(parameter[parameter.index(after: equals)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return Property(name: name.uppercased(), parameters: parameters, value: String(line[line.index(after: separator)...]))
    }

    private static func date(_ property: Property, floatingZone: TimeZone, fixedZones: [String: TimeZone]) throws -> Date? {
        let value = property.value
        guard value.contains("T") else { return nil }
        let zone: TimeZone
        if value.hasSuffix("Z") { zone = TimeZone(secondsFromGMT: 0)! }
        else if let identifier = property.parameters["TZID"] { zone = try timeZone(identifier, fixedZones: fixedZones) }
        else { zone = floatingZone }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.isLenient = false
        let localValue = value.hasSuffix("Z") ? String(value.dropLast()) : value
        formatter.dateFormat = localValue.count == 13 ? "yyyyMMdd'T'HHmm" : "yyyyMMdd'T'HHmmss"
        return formatter.date(from: localValue)
    }

    private static func timeZone(_ identifier: String, fixedZones: [String: TimeZone]) throws -> TimeZone {
        let aliases = ["Beijing": "Asia/Shanghai", "China Standard Time": "Asia/Shanghai", "Etc/UTC": "UTC"]
        if let zone = TimeZone(identifier: aliases[identifier] ?? identifier) ?? fixedZones[identifier] { return zone }
        throw CalendarFeedError.unsupportedTimeZone(identifier)
    }

    private static func offsetSeconds(_ value: String) -> Int? {
        let digits = Array(value)
        guard (digits.count == 5 || digits.count == 7), let sign = digits.first, sign == "+" || sign == "-",
              let hours = Int(String(digits[1...2])), let minutes = Int(String(digits[3...4])),
              hours <= 23, minutes < 60 else { return nil }
        let seconds = digits.count == 7 ? Int(String(digits[5...6])) : 0
        guard let seconds, seconds < 60 else { return nil }
        return (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60 + seconds)
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var escaping = false
        for character in value {
            if escaping { result.append(character == "n" || character == "N" ? "\n" : character); escaping = false }
            else if character == "\\" { escaping = true }
            else { result.append(character) }
        }
        if escaping { result.append("\\") }
        return result
    }
}
