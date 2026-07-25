import Foundation

// MARK: - Flexible decoding (Postgres returns bigint/numeric as strings)

struct FlexibleInt: Decodable {
    let value: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i }
        else if let s = try? c.decode(String.self), let i = Int(s) { value = i }
        else if let d = try? c.decode(Double.self) { value = Int(d) }
        else { value = 0 }
    }
}

struct FlexibleDouble: Decodable {
    let value: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self), let d = Double(s) { value = d }
        else { value = 0 }
    }
}

// MARK: - Auth

struct AuthUser: Decodable {
    let id: UUID
    let email: String
}

struct AuthResponse: Decodable {
    let user: AuthUser
    let token: String
}

// MARK: - Domain models

struct Profile: Identifiable, Decodable {
    let id: UUID
    let username: String
    let displayName: String
}

struct Circle: Identifiable, Decodable {
    let id: UUID
    let name: String
    let ownerId: UUID
}

struct CircleMember: Decodable {
    let circleId: UUID
    let userId: UUID
    let sharingLevel: String
}

struct WYDEvent: Identifiable, Decodable {
    let id: UUID
    let title: String
    let description: String?
    let category: String
    let venue: String?
    let lat: Double?
    let lng: Double?
    let startsAt: Date
    let endsAt: Date
    let popularity: Int
    let ownerId: UUID?
    let visibility: String
}

struct RSVP: Decodable {
    let eventId: UUID
    let userId: UUID
    let status: String
}

struct Recommendation: Identifiable, Decodable {
    let id: UUID
    let title: String
    let description: String?
    let category: String
    let venue: String?
    let lat: Double?
    let lng: Double?
    let startsAt: Date
    let endsAt: Date
    let popularity: Int
    let friendsGoing: FlexibleInt
    let friendNames: [String]
    let totalRsvps: FlexibleInt
    let score: FlexibleDouble
}

struct FriendNow: Identifiable, Decodable {
    var id: UUID { userId }
    let userId: UUID
    let displayName: String
    let username: String
    let eventId: UUID?
    let eventTitle: String?
    let venue: String?
    let startsAt: Date?
    let endsAt: Date?
    let state: String
}

struct FriendLocation: Identifiable, Decodable {
    var id: UUID { userId }
    let userId: UUID
    let displayName: String
    let lat: Double
    let lng: Double
    let updatedAt: Date
}

struct TrendingEvent: Identifiable, Decodable {
    let id: UUID
    let title: String
    let category: String
    let venue: String?
    let lat: Double?
    let lng: Double?
    let startsAt: Date
    let endsAt: Date
    let popularity: Int
    let totalRsvps: FlexibleInt
    let trendScore: FlexibleDouble
}

struct CalendarFeed: Identifiable, Decodable {
    let id: UUID
    let userId: UUID
    let name: String
    let url: String
    let lastSyncedAt: Date?
}

struct MyCalendarEvent: Identifiable, Decodable {
    let id: UUID
    let title: String
    let description: String?
    let category: String
    let venue: String?
    let lat: Double?
    let lng: Double?
    let startsAt: Date
    let endsAt: Date
    let visibility: String
    let source: String
    let externalUid: String?
}

// MARK: - Sharing levels

enum SharingLevel: String, CaseIterable, Identifiable {
    case busy
    case publicEvents = "public_events"
    case approxLocation = "approx_location"
    case liveLocation = "live_location"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .busy: return "Free / Busy"
        case .publicEvents: return "Public Events"
        case .approxLocation: return "Approximate Location"
        case .liveLocation: return "Live Location"
        }
    }
}

// MARK: - Event category helpers

import SwiftUI

extension WYDEvent {
    var categoryColor: Color { EventCategory.color(for: category) }
    var categoryIcon: String { EventCategory.icon(for: category) }
}

extension Recommendation {
    var categoryColor: Color { EventCategory.color(for: category) }
    var categoryIcon: String { EventCategory.icon(for: category) }
}

enum EventCategory {
    static func color(for category: String) -> Color {
        switch category {
        case "talk": return .blue
        case "workshop": return .purple
        case "side_event": return .orange
        case "booth": return .teal
        case "networking": return .pink
        case "meetup": return .green
        case "party": return .red
        default: return .gray
        }
    }

    static func icon(for category: String) -> String {
        switch category {
        case "talk": return "mic.fill"
        case "workshop": return "hammer.fill"
        case "side_event": return "sparkles"
        case "booth": return "storefront.fill"
        case "networking": return "person.2.fill"
        case "meetup": return "cup.and.saucer.fill"
        case "party": return "party.popper.fill"
        default: return "calendar"
        }
    }

    static func label(for category: String) -> String {
        category.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Formatting helpers

extension Date {
    var wydTime: String {
        formatted(date: .omitted, time: .shortened)
    }

    var wydDay: String {
        formatted(date: .abbreviated, time: .omitted)
    }

    var wydRelative: String {
        let now = Date()
        if self < now { return "now" }
        let interval = self.timeIntervalSince(now)
        let hours = Int(interval / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if hours >= 24 { return "in \(hours / 24)d \(hours % 24)h" }
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes)m"
    }
}
