import XCTest
@testable import MyProject

final class ICSImporterTests: XCTestCase {
    func testParsesCRLFFeedWithEscapesAndFoldedLines() throws {
        let ics = "BEGIN:VCALENDAR\r\n"
            + "BEGIN:VEVENT\r\n"
            + "UID:abc-123@luma\r\n"
            + "SUMMARY:Builder Breakfast\\, Day 2\r\n"
            + "LOCATION:Time Out Market\\; Lisbon\r\n"
            + "DESCRIPTION:Coffee and\\nbagels with a long description that gets\r\n"
            + "  folded onto a second line\r\n"
            + "DTSTART:20260726T071100Z\r\n"
            + "DTEND:20260726T081100Z\r\n"
            + "END:VEVENT\r\n"
            + "END:VCALENDAR\r\n"
        let events = ICSImporter.parse(ics: ics)
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.uid, "abc-123@luma")
        XCTAssertEqual(event.title, "Builder Breakfast, Day 2")
        XCTAssertEqual(event.location, "Time Out Market; Lisbon")
        XCTAssertEqual(event.description, "Coffee and\nbagels with a long description that gets folded onto a second line")
        XCTAssertEqual(event.startsAt, ISO8601DateFormatter().date(from: "2026-07-26T07:11:00Z"))
        XCTAssertEqual(event.endsAt.timeIntervalSince(event.startsAt), 3600)
    }

    func testTZIDIsRespected() throws {
        let ics = """
        BEGIN:VEVENT
        UID:tz
        SUMMARY:Fado
        DTSTART;TZID=Europe/Lisbon:20260726T213000
        END:VEVENT
        """
        let event = try XCTUnwrap(ICSImporter.parse(ics: ics).first)
        // Lisbon is UTC+1 in July; a missing DTEND defaults to one hour.
        XCTAssertEqual(event.startsAt, ISO8601DateFormatter().date(from: "2026-07-26T20:30:00Z"))
        XCTAssertEqual(event.endsAt.timeIntervalSince(event.startsAt), 3600)
    }

    func testAllDayEventAndMissingUIDFallback() throws {
        let ics = """
        BEGIN:VEVENT
        SUMMARY:Hackathon
        DTSTART;VALUE=DATE:20260725
        DTEND;VALUE=DATE:20260727
        END:VEVENT
        """
        let event = try XCTUnwrap(ICSImporter.parse(ics: ics).first)
        XCTAssertTrue(event.uid.hasPrefix("Hackathon-"))
        XCTAssertEqual(event.endsAt.timeIntervalSince(event.startsAt), 2 * 86400, accuracy: 3600)
    }

    func testSkipsEventsWithoutStart() {
        let ics = """
        BEGIN:VEVENT
        UID:nope
        SUMMARY:No start
        END:VEVENT
        """
        XCTAssertTrue(ICSImporter.parse(ics: ics).isEmpty)
    }
}

final class ConciergeIntentTests: XCTestCase {
    func testDefaultSuggestionsMapToDistinctIntents() {
        XCTAssertEqual(ConciergeEngine.parse("wyd tonight?"), .wydTonight)
        XCTAssertEqual(ConciergeEngine.parse("Where is everyone?"), .friendsNow)
        XCTAssertEqual(ConciergeEngine.parse("What's trending?"), .trending)
        XCTAssertEqual(ConciergeEngine.parse("Find an event everyone can make"), .everyone)
        XCTAssertEqual(ConciergeEngine.parse("Networking events nearby"), .nearby(category: "networking"))
    }

    func testWhoIsGoingExtractsEventName() {
        XCTAssertEqual(ConciergeEngine.parse("Who's going to Sunset Boat Party?"), .whoGoing("sunset boat party"))
    }

    func testSideEventCategory() {
        XCTAssertEqual(ConciergeEngine.parse("side event close by"), .nearby(category: "side_event"))
    }

    func testGibberishFallsBackToHelp() {
        XCTAssertEqual(ConciergeEngine.parse("qwerty"), .help)
    }
}

final class ModelDecodingTests: XCTestCase {
    func testRecommendationDecodesPostgresStringNumbers() throws {
        let json = """
        {"id":"70eae53d-1027-4fea-a224-4ee053b82183","title":"AI x Crypto Happy Hour","description":null,
         "category":"side_event","venue":"Pensão Amor","lat":38.711,"lng":-9.143,
         "starts_at":"2026-07-25T06:11:32.323Z","ends_at":"2026-07-25T09:11:32Z","popularity":95,
         "friends_going":"5","friend_names":["Alice Chen"],"total_rsvps":"6","score":150.2}
        """.data(using: .utf8)!
        let rec = try JSONDecoder.wyd.decode(Recommendation.self, from: json)
        XCTAssertEqual(rec.friendsGoing.value, 5)
        XCTAssertEqual(rec.totalRsvps.value, 6)
        XCTAssertEqual(rec.score.value, 150.2, accuracy: 0.001)
        XCTAssertLessThan(rec.startsAt, rec.endsAt)
    }

    func testEnvelopeSurfacesObjectErrors() throws {
        let json = #"{"ok":false,"error":{"message":"relation does not exist"}}"#.data(using: .utf8)!
        let envelope = try JSONDecoder.wyd.decode(Envelope<[Profile]>.self, from: json)
        XCTAssertEqual(envelope.error, "relation does not exist")
        XCTAssertNil(envelope.data)
    }

    func testEnvelopePrefersCloudErrorMessage() throws {
        let json = #"{"ok":false,"error":"cloud_error","message":"table not found","status":404}"#.data(using: .utf8)!
        let envelope = try JSONDecoder.wyd.decode(Envelope<[Profile]>.self, from: json)
        XCTAssertEqual(envelope.error, "table not found")
    }

    func testCircleMemberDecodesShareFlags() throws {
        let json = """
        {"circle_id":"aaaaaaaa-0000-0000-0000-000000000001","user_id":"11111111-1111-1111-1111-111111111111",
         "sharing_level":"public_events","share_busy":true,"share_public_events":true,
         "share_approx_location":false,"share_live_location":false}
        """.data(using: .utf8)!
        let member = try JSONDecoder.wyd.decode(CircleMember.self, from: json)
        XCTAssertTrue(ShareField.busy.value(in: member))
        XCTAssertFalse(ShareField.liveLocation.value(in: member))
    }
}

final class HelperTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: WYDClock.enabledKey)
        super.tearDown()
    }

    func testConferenceClockStartsAtKeynote() {
        WYDClock.isConferenceMode = true
        let offset = WYDClock.now.timeIntervalSince(WYDClock.conferenceStart)
        XCTAssertGreaterThan(offset, -1)
        XCTAssertLessThan(offset, 3600, "clock should tick from launch, not jump")
    }

    func testRealClockWhenConferenceModeOff() {
        WYDClock.isConferenceMode = false
        XCTAssertEqual(WYDClock.now.timeIntervalSinceNow, 0, accuracy: 1)
    }

    func testUsernameNormalization() {
        XCTAssertEqual(CirclesView.normalizeUsername("  @Alice "), "alice")
    }
}
