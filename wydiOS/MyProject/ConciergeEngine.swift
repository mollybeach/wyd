import Foundation
import CoreLocation

struct ConciergeReply {
    let text: String
    var events: [Recommendation] = []
    var suggestions: [String] = ConciergeEngine.defaultSuggestions
}

/// Rule-based concierge: parses natural-language intent, queries the backend,
/// and composes a natural-language answer from real data.
enum ConciergeEngine {
    static let defaultSuggestions = [
        "wyd tonight?",
        "Where is everyone?",
        "What's trending?",
        "Find an event everyone can make",
        "Networking events nearby"
    ]

    private enum Intent {
        case wydTonight
        case friendsNow
        case trending
        case everyone
        case nearby(category: String?)
        case whoGoing(String)
        case help
    }

    static func respond(to text: String, userID: UUID, reference: CLLocation?) async -> ConciergeReply {
        let intent = parse(text)
        let now = Date()

        do {
            switch intent {
            case .wydTonight, .everyone:
                let recs = try await APIClient.shared.rpc(
                    "wyd_recommend",
                    args: ["p_user": userID.uuidString, "p_now": now.wydISOString, "p_limit": 5],
                    as: Recommendation.self)
                guard !recs.isEmpty else {
                    return ConciergeReply(text: "Nothing on the schedule right now. Check the Events tab to browse the full directory.")
                }
                let best: Recommendation
                if case .everyone = intent {
                    best = recs.max { $0.friendsGoing.value < $1.friendsGoing.value } ?? recs[0]
                    let names = best.friendNames.prefix(3).joined(separator: ", ")
                    let text = best.friendsGoing.value > 0
                        ? "Your best bet is **\(best.title)** at \(best.venue ?? "TBD") — \(best.friendsGoing.value) of your friends are going (\(names)). It starts \(best.startsAt.wydRelative) and runs until \(best.endsAt.wydTime)."
                        : "None of your friends have RSVP'd anywhere yet. The most popular pick is **\(best.title)** — starts \(best.startsAt.wydRelative). Be the one who starts the plan."
                    return ConciergeReply(text: text, events: [best])
                }
                let lines = recs.prefix(3).enumerated().map { index, rec -> String in
                    var line = "\(index + 1). **\(rec.title)** — \(rec.venue ?? "TBD"), \(rec.startsAt.wydRelative)"
                    if rec.friendsGoing.value > 0 {
                        line += " · \(rec.friendsGoing.value) friend\(rec.friendsGoing.value == 1 ? "" : "s") going"
                    }
                    return line
                }
                return ConciergeReply(
                    text: "Here's what I'd do next:\n\n" + lines.joined(separator: "\n"),
                    events: Array(recs.prefix(3)))

            case .friendsNow:
                let friends: [FriendNow] = try await APIClient.shared.rpc(
                    "wyd_friends_now",
                    args: ["p_user": userID.uuidString, "p_now": now.wydISOString],
                    as: FriendNow.self)
                guard !friends.isEmpty else {
                    return ConciergeReply(
                        text: "None of your friends have shared plans yet. Add people to a circle (try the demo users: alice, bob, priya, diego, sofia) and their plans will show up here.",
                        suggestions: ["What's trending?", "wyd tonight?"])
                }
                let lines = friends.prefix(6).map { friend -> String in
                    let title = friend.eventTitle ?? "No plans"
                    let venue = friend.venue.map { " at \($0)" } ?? ""
                    let when = friend.state == "now" ? "right now" : "next, \(friend.startsAt?.wydRelative ?? "")"
                    return "• **\(friend.displayName)** — \(title)\(venue) (\(when))"
                }
                return ConciergeReply(text: "Here's where your people are:\n\n" + lines.joined(separator: "\n"))

            case .trending:
                let trending: [TrendingEvent] = try await APIClient.shared.rpc(
                    "wyd_trending",
                    args: ["p_now": now.wydISOString, "p_limit": 5],
                    as: TrendingEvent.self)
                guard !trending.isEmpty else {
                    return ConciergeReply(text: "Nothing trending yet — the conference is just getting started.")
                }
                let lines = trending.prefix(5).enumerated().map { index, event in
                    "\(index + 1). **\(event.title)** — \(event.totalRsvps.value) going · \(event.startsAt.wydRelative)"
                }
                return ConciergeReply(text: "Trending right now:\n\n" + lines.joined(separator: "\n"))

            case .nearby(let category):
                var recs = try await APIClient.shared.rpc(
                    "wyd_recommend",
                    args: ["p_user": userID.uuidString, "p_now": now.wydISOString, "p_limit": 20],
                    as: Recommendation.self)
                if let category {
                    recs = recs.filter { $0.category == category }
                }
                let origin = reference ?? CLLocation(latitude: WYDConfig.conferenceLat, longitude: WYDConfig.conferenceLng)
                let withDistance: [(Recommendation, Int)] = recs.compactMap { rec in
                    guard let lat = rec.lat, let lng = rec.lng else { return nil }
                    let meters = origin.distance(from: CLLocation(latitude: lat, longitude: lng))
                    return (rec, Int(meters / 80)) // ~80 m per walking minute
                }.sorted { $0.1 < $1.1 }
                guard let first = withDistance.first else {
                    return ConciergeReply(text: "Couldn't find anything matching that nearby. Try browsing the Events tab.")
                }
                let lines = withDistance.prefix(3).map { rec, minutes in
                    "• **\(rec.title)** — \(rec.venue ?? "TBD"), ~\(minutes) min walk · starts \(rec.startsAt.wydRelative)"
                }
                return ConciergeReply(
                    text: "Closest matches:\n\n" + lines.joined(separator: "\n"),
                    events: withDistance.prefix(3).map { $0.0 })

            case .whoGoing(let fragment):
                let recs = try await APIClient.shared.rpc(
                    "wyd_recommend",
                    args: ["p_user": userID.uuidString, "p_now": now.wydISOString, "p_limit": 30],
                    as: Recommendation.self)
                guard let match = recs.first(where: { $0.title.lowercased().contains(fragment) }) else {
                    return ConciergeReply(text: "I couldn't find an event matching \"\(fragment)\". Try the exact name from the Events tab.")
                }
                let text: String
                if match.friendsGoing.value > 0 {
                    text = "**\(match.title)**: \(match.friendNames.joined(separator: ", ")) \(match.friendsGoing.value == 1 ? "is" : "are") going. \(match.totalRsvps.value) attendees total · \(match.startsAt.wydRelative) at \(match.venue ?? "TBD")."
                } else {
                    text = "No friends have RSVP'd to **\(match.title)** yet. \(match.totalRsvps.value) people are going total — starts \(match.startsAt.wydRelative)."
                }
                return ConciergeReply(text: text, events: [match])

            case .help:
                return ConciergeReply(text: "I didn't quite catch that. I can tell you what's happening tonight, where your friends are, what's trending, what's nearby, or who's going to a specific event.")
            }
        } catch {
            return ConciergeReply(text: "Hmm, I couldn't reach the backend (\(error.localizedDescription)). Try again in a moment.")
        }
    }

    // MARK: - Intent parsing

    private static func parse(_ raw: String) -> Intent {
        let text = raw.lowercased()

        if text.contains("who") && (text.contains("going") || text.contains("at")) {
            // Extract the event fragment after "to"/"at"
            for marker in ["going to ", "at ", "for "] {
                if let range = text.range(of: marker) {
                    let fragment = String(text[range.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "?.!"))
                    if !fragment.isEmpty { return .whoGoing(fragment) }
                }
            }
        }
        if (text.contains("everyone") || text.contains("all")) && (text.contains("make") || text.contains("event") || text.contains("can")) || text.contains("group") {
            return .everyone
        }
        if text.contains("trending") || text.contains("popular") || text.contains("hot") || text.contains("crowded") || text.contains("momentum") {
            return .trending
        }
        if text.contains("nearby") || text.contains("near me") || text.contains("walk") || text.contains("close") || text.contains("minute") {
            var category: String? = nil
            for c in ["networking", "workshop", "talk", "party", "meetup", "booth"] where text.contains(c) {
                category = c
            }
            if text.contains("side event") { category = "side_event" }
            return .nearby(category: category)
        }
        if text.contains("where") && (text.contains("friend") || text.contains("everyone") || text.contains("people") || text.contains("crew") || text.contains("team")) {
            return .friendsNow
        }
        if text.contains("where is everyone") || text.contains("where's everyone") {
            return .friendsNow
        }
        if text.contains("wyd") || text.contains("tonight") || text.contains("what should") || text.contains("what's next") || text.contains("recommend") || text.contains("now") {
            return .wydTonight
        }
        if text.contains("hi") || text.contains("hello") || text.contains("hey") {
            return .wydTonight
        }
        return .help
    }
}
