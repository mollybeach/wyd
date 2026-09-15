import Foundation

/// The app's notion of "now".
///
/// The demo backend is seeded for ETHGlobal Lisbon (July 24–27, 2026). Once the
/// conference is over, every time-based query (recommendations, "where is everyone",
/// the calendar strip) would come back empty. Conference mode replays the event:
/// the clock starts at the opening keynote and ticks forward in real time from launch.
enum WYDClock {
    static let enabledKey = "wyd_conference_clock"

    /// Opening keynote, ETHGlobal Lisbon — 23:30 local (WEST) on July 24, 2026.
    static let conferenceStart = ISO8601DateFormatter().date(from: "2026-07-24T22:30:00Z")!
    static let conferenceEnd = ISO8601DateFormatter().date(from: "2026-07-28T00:00:00Z")!

    private static let launchedAt = Date()

    /// Defaults to on once the real conference has ended, so the demo always has data.
    static var isConferenceMode: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return Date() > conferenceEnd
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var now: Date {
        guard isConferenceMode else { return Date() }
        return conferenceStart.addingTimeInterval(Date().timeIntervalSince(launchedAt))
    }
}
