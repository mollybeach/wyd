import Foundation

struct ParsedICSEvent {
    let uid: String
    let title: String
    let location: String?
    let description: String?
    let startsAt: Date
    let endsAt: Date
}

/// Universal calendar importer: fetches an ICS feed (Google Calendar secret iCal
/// address, Luma calendar feed, Outlook, any .ics link) and imports events into
/// the user's private calendar. Dedupes by ICS UID.
enum ICSImporter {

    /// Returns the number of newly imported events.
    static func sync(feed: CalendarFeed, userID: UUID) async throws -> Int {
        guard let url = URL(string: feed.url.replacingOccurrences(of: "webcal://", with: "https://")) else {
            throw APIError.server("Invalid feed URL")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let ics = String(data: data, encoding: .utf8) else {
            throw APIError.server("Feed wasn't valid calendar data")
        }
        let parsed = parse(ics: ics)
        guard !parsed.isEmpty else { throw APIError.server("No events found in feed") }

        // Dedupe against already-imported events
        let existing: [MyCalendarEvent] = try await APIClient.shared.select(
            "events", filter: ["owner_id": userID.uuidString], limit: 1000, as: MyCalendarEvent.self)
        let existingUIDs = Set(existing.compactMap { $0.externalUid })

        var imported = 0
        for event in parsed where !existingUIDs.contains(event.uid) {
            try await APIClient.shared.insert("events", row: [
                "id": UUID().uuidString,
                "title": event.title,
                "description": event.description as Any,
                "category": "personal",
                "venue": event.location as Any,
                "starts_at": event.startsAt.wydISOString,
                "ends_at": event.endsAt.wydISOString,
                "owner_id": userID.uuidString,
                "visibility": "private",
                "source": "ics",
                "external_uid": event.uid
            ])
            imported += 1
        }
        try await APIClient.shared.update(
            "calendar_feeds",
            filter: ["id": feed.id.uuidString],
            patch: ["last_synced_at": Date().wydISOString])
        return imported
    }

    // MARK: - ICS parsing

    static func parse(ics: String) -> [ParsedICSEvent] {
        // Unfold continuation lines (lines starting with space/tab). Normalize CRLF first:
        // splitting on .newlines turns "\r\n" into an extra empty line, which breaks unfolding.
        var lines: [String] = []
        let normalized = ics.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.components(separatedBy: "\n") {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else {
                lines.append(line)
            }
        }

        var events: [ParsedICSEvent] = []
        var inEvent = false
        var uid = "", summary = "", location: String?, description: String?
        var dtstart: (value: String, params: [String: String])?
        var dtend: (value: String, params: [String: String])?

        func flush() {
            guard let startRaw = dtstart, let start = parseDate(startRaw.value, params: startRaw.params) else { return }
            let end: Date
            if let endRaw = dtend, let parsedEnd = parseDate(endRaw.value, params: endRaw.params) {
                end = parsedEnd
            } else {
                end = start.addingTimeInterval(3600)
            }
            events.append(ParsedICSEvent(
                uid: uid.isEmpty ? "\(summary)-\(start.timeIntervalSince1970)" : uid,
                title: unescape(summary.isEmpty ? "Untitled event" : summary),
                location: location.map(unescape),
                description: description.map(unescape),
                startsAt: start, endsAt: end))
        }

        for line in lines {
            if line == "BEGIN:VEVENT" {
                inEvent = true
                uid = ""; summary = ""; location = nil; description = nil; dtstart = nil; dtend = nil
            } else if line == "END:VEVENT" {
                if inEvent { flush() }
                inEvent = false
            } else if inEvent {
                let (name, params, value) = splitProperty(line)
                switch name {
                case "UID": uid = value
                case "SUMMARY": summary = value
                case "LOCATION": location = value
                case "DESCRIPTION": description = value
                case "DTSTART": dtstart = (value, params)
                case "DTEND": dtend = (value, params)
                default: break
                }
            }
        }
        return events
    }

    private static func splitProperty(_ line: String) -> (String, [String: String], String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, [:], "") }
        let head = String(line[line.startIndex..<colon])
        let value = String(line[line.index(after: colon)...])
        var name = head
        var params: [String: String] = [:]
        if let semicolon = head.firstIndex(of: ";") {
            name = String(head[head.startIndex..<semicolon])
            for part in head[head.index(after: semicolon)...].components(separatedBy: ";") {
                let kv = part.components(separatedBy: "=")
                if kv.count == 2 { params[kv[0]] = kv[1] }
            }
        }
        return (name, params, value)
    }

    private static func parseDate(_ value: String, params: [String: String]) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if params["VALUE"] == "DATE" {
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = TimeZone(identifier: params["TZID"] ?? "") ?? .current
            return formatter.date(from: value)
        }
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        if value.hasSuffix("Z") {
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter.date(from: String(value.dropLast()))
        }
        formatter.timeZone = TimeZone(identifier: params["TZID"] ?? "") ?? .current
        return formatter.date(from: value)
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
