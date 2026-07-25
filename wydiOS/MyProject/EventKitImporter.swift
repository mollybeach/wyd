import Foundation
import EventKit

/// Imports events from the device's Apple Calendar via EventKit.
enum EventKitImporter {

    enum ImportError: LocalizedError {
        case denied
        var errorDescription: String? {
            switch self {
            case .denied: return "Calendar access was denied. Enable it in Settings → Privacy → Calendars."
            }
        }
    }

    /// Returns the number of newly imported events.
    static func importEvents(userID: UUID, daysAhead: Int = 30) async throws -> Int {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw ImportError.denied }

        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: now)!
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-86400), end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        let existing: [MyCalendarEvent] = try await APIClient.shared.select(
            "events", filter: ["owner_id": userID.uuidString], limit: 1000, as: MyCalendarEvent.self)
        let existingUIDs = Set(existing.compactMap { $0.externalUid })

        var imported = 0
        for event in ekEvents {
            let uid = "eventkit-\(event.eventIdentifier ?? UUID().uuidString)"
            guard !existingUIDs.contains(uid) else { continue }
            try await APIClient.shared.insert("events", row: [
                "id": UUID().uuidString,
                "title": event.title ?? "Untitled event",
                "category": "personal",
                "venue": event.location as Any,
                "starts_at": event.startDate.wydISOString,
                "ends_at": (event.endDate ?? event.startDate.addingTimeInterval(3600)).wydISOString,
                "owner_id": userID.uuidString,
                "visibility": "private",
                "source": "eventkit",
                "external_uid": uid
            ])
            imported += 1
        }
        return imported
    }
}
