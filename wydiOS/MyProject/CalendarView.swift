import SwiftUI

/// Day timeline with positioned time blocks — the "real calendar" view.
/// Pass `friend` to view a friend's shared calendar (privacy-filtered server-side).
struct CalendarView: View {
    var friend: Profile? = nil

    @EnvironmentObject var session: SessionStore
    @State private var events: [MyCalendarEvent] = []
    @State private var selectedDay = Calendar.current.startOfDay(for: WYDClock.now)
    @State private var isLoading = true
    @State private var selectedEvent: MyCalendarEvent?

    private let hourHeight: CGFloat = 56
    private let startHour = 7
    private let endHour = 25 // 1 AM next day

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: WYDClock.now)
        return (0..<4).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// The visible window: startHour of the selected day through endHour (early next morning).
    private var windowStart: Date {
        Calendar.current.date(bySettingHour: startHour, minute: 0, second: 0, of: selectedDay)!
    }

    private var windowEnd: Date {
        Calendar.current.date(byAdding: .hour, value: endHour - startHour, to: windowStart)!
    }

    private var dayEvents: [MyCalendarEvent] {
        events.filter { $0.endsAt > windowStart && $0.startsAt < windowEnd }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Day strip
            HStack(spacing: 10) {
                ForEach(days, id: \.self) { day in
                    Button {
                        selectedDay = day
                    } label: {
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption2)
                            Text(day.formatted(.dateTime.day()))
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(day == selectedDay ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundStyle(day == selectedDay ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isLoading {
                Spacer()
                ProgressView("Loading calendar…")
                Spacer()
            } else if dayEvents.isEmpty {
                ContentUnavailableView {
                    Label("Free day", systemImage: "sun.max")
                } description: {
                    if let friend {
                        Text("Nothing shared this day. \(friend.displayName) controls what you can see.")
                    } else {
                        Text("No events this day. Join events from Browse, or sync a calendar from the You tab.")
                    }
                }
            } else {
                timeline
            }
        }
        .task { await load() }
        .sheet(item: $selectedEvent) { event in
            CalendarEventDetail(event: event)
        }
    }

    private var timeline: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                // Hour grid
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(startHour..<endHour, id: \.self) { hour in
                        HStack(alignment: .top, spacing: 8) {
                            Text(hourLabel(hour))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                            Rectangle()
                                .fill(Color(.separator))
                                .frame(height: 0.5)
                        }
                        .frame(height: hourHeight, alignment: .top)
                    }
                }

                // Event blocks
                ForEach(layoutBlocks(), id: \.event.id) { block in
                    blockView(block)
                }
            }
            .padding(.bottom, 40)
        }
        .refreshable { await load() }
    }

    private struct Block {
        let event: MyCalendarEvent
        let y: CGFloat
        let height: CGFloat
        let x: CGFloat      // fraction 0...1 of the lane area
        let width: CGFloat  // fraction 0...1
    }

    private func layoutBlocks() -> [Block] {
        let dayStart = windowStart
        let sorted = dayEvents.sorted { $0.startsAt < $1.startsAt }

        return sorted.compactMap { event in
            let start = max(event.startsAt, dayStart)
            let end = min(event.endsAt, windowEnd)
            guard end > start else { return nil }
            let y = CGFloat(start.timeIntervalSince(dayStart) / 3600) * hourHeight
            let height = max(CGFloat(end.timeIntervalSince(start) / 3600) * hourHeight, 24)

            // Naive overlap handling: count events overlapping this one and index among them
            let overlapping = sorted.filter {
                $0.startsAt < event.endsAt && $0.endsAt > event.startsAt
            }
            let index = overlapping.firstIndex(where: { $0.id == event.id }) ?? 0
            let count = max(overlapping.count, 1)
            let width = 1.0 / CGFloat(count)
            return Block(event: event, y: y, height: height, x: width * CGFloat(index), width: width)
        }
    }

    private func blockView(_ block: Block) -> some View {
        GeometryReader { geo in
            let laneWidth = geo.size.width - 52
            Button {
                selectedEvent = block.event
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(block.event.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(block.height > 44 ? 2 : 1)
                    if block.height > 40 {
                        Text("\(block.event.startsAt.wydTime) – \(block.event.endsAt.wydTime)")
                            .font(.caption2)
                            .opacity(0.85)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(width: laneWidth * block.width, height: block.height, alignment: .topLeading)
                .background(blockColor(for: block.event).opacity(0.85))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .offset(x: 52 + laneWidth * block.x, y: block.y)
        }
    }

    private func blockColor(for event: MyCalendarEvent) -> Color {
        if event.category == "busy" { return Color(.systemGray3) }
        if event.source == "ics" || event.source == "eventkit" { return .indigo }
        if event.category == "personal" { return .gray }
        return EventCategory.color(for: event.category)
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0 { return "12 AM" }
        if h < 12 { return "\(h) AM" }
        if h == 12 { return "12 PM" }
        return "\(h - 12) PM"
    }

    private func load() async {
        guard let userID = session.profile?.id else { return }
        isLoading = events.isEmpty
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -1, to: WYDClock.now)!
        let to = calendar.date(byAdding: .day, value: 5, to: WYDClock.now)!
        do {
            if let friend {
                events = try await APIClient.shared.rpc(
                    "wyd_friend_calendar",
                    args: ["p_viewer": userID.uuidString, "p_friend": friend.id.uuidString,
                           "p_from": from.wydISOString, "p_to": to.wydISOString],
                    as: MyCalendarEvent.self)
            } else {
                events = try await APIClient.shared.rpc(
                    "wyd_my_calendar",
                    args: ["p_user": userID.uuidString, "p_from": from.wydISOString, "p_to": to.wydISOString],
                    as: MyCalendarEvent.self)
            }
        } catch { /* keep stale */ }
        isLoading = false
    }
}

struct CalendarEventDetail: View {
    let event: MyCalendarEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(event.title).font(.headline)
                    if let description = event.description, !description.isEmpty {
                        Text(description).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Label("\(event.startsAt.wydDay), \(event.startsAt.wydTime) – \(event.endsAt.wydTime)", systemImage: "clock")
                    if let venue = event.venue, !venue.isEmpty {
                        Label(venue, systemImage: "mappin.and.ellipse")
                    }
                    Label(sourceLabel, systemImage: "calendar.badge.clock")
                }
            }
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var sourceLabel: String {
        switch event.source {
        case "ics": return "Synced calendar"
        case "eventkit": return "Apple Calendar"
        case "personal": return "Personal event"
        case "friend": return "Shared with you"
        default: return "WYD directory"
        }
    }
}
