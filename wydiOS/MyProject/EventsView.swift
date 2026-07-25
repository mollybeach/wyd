import SwiftUI

struct EventsView: View {
    @EnvironmentObject var session: SessionStore
    @State private var recommendations: [Recommendation] = []
    @State private var myRsvps: Set<UUID> = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var categoryFilter: String?
    @State private var mode: EventMode = .browse

    private enum EventMode: String, CaseIterable {
        case browse = "Browse"
        case calendar = "My Calendar"
    }

    private var filtered: [Recommendation] {
        guard let categoryFilter else { return recommendations }
        return recommendations.filter { $0.category == categoryFilter }
    }

    private var groupedByDay: [(String, [Recommendation])] {
        let grouped = Dictionary(grouping: filtered.sorted { $0.startsAt < $1.startsAt }) { $0.startsAt.wydDay }
        return grouped.sorted { lhs, rhs in
            (lhs.value.first?.startsAt ?? .distantFuture) < (rhs.value.first?.startsAt ?? .distantFuture)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(EventMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if mode == .calendar {
                    CalendarView()
                } else {
                    browseContent
                }
            }
            .navigationTitle("Events")
            .toolbar {
                if mode == .browse {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("All categories") { categoryFilter = nil }
                            ForEach(["talk", "workshop", "side_event", "booth", "networking", "meetup", "party"], id: \.self) { c in
                                Button(EventCategory.label(for: c)) { categoryFilter = c }
                            }
                        } label: {
                            Image(systemName: categoryFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        }
                    }
                }
            }
        }
    }

    private var browseContent: some View {
        Group {
                if isLoading {
                    ProgressView("Loading events…")
                } else if let error {
                    ContentUnavailableView("Couldn't load events", systemImage: "wifi.exclamationmark", description: Text(error))
                } else {
                    List {
                        if !recommendations.isEmpty {
                            Section("Recommended for you") {
                                ForEach(recommendations.prefix(3)) { rec in
                                    NavigationLink(value: rec.id) {
                                        EventRow(event: rec, isGoing: myRsvps.contains(rec.id))
                                    }
                                }
                            }
                        }
                        ForEach(groupedByDay, id: \.0) { day, events in
                            Section(day) {
                                ForEach(events) { rec in
                                    NavigationLink(value: rec.id) {
                                        EventRow(event: rec, isGoing: myRsvps.contains(rec.id))
                                    }
                                }
                            }
                        }
                    }
                    .navigationDestination(for: UUID.self) { id in
                        if let rec = recommendations.first(where: { $0.id == id }) {
                            EventDetailView(event: rec, isGoing: myRsvps.contains(id), onToggleRSVP: { toggleRSVP(rec) })
                        }
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
    }

    private func load() async {
        guard let userID = session.profile?.id else { return }
        isLoading = recommendations.isEmpty
        error = nil
        do {
            async let recsTask = APIClient.shared.rpc(
                "wyd_recommend",
                args: ["p_user": userID.uuidString, "p_now": Date().wydISOString, "p_limit": 50],
                as: Recommendation.self)
            async let rsvpsTask = APIClient.shared.select(
                "rsvps", filter: ["user_id": userID.uuidString], as: RSVP.self)
            let (recs, rsvps) = try await (recsTask, rsvpsTask)
            recommendations = recs
            myRsvps = Set(rsvps.filter { $0.status == "going" }.map { $0.eventId })
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleRSVP(_ event: Recommendation) {
        guard let userID = session.profile?.id else { return }
        Task {
            do {
                if myRsvps.contains(event.id) {
                    try await APIClient.shared.delete("rsvps", filter: [
                        "event_id": event.id.uuidString, "user_id": userID.uuidString])
                    myRsvps.remove(event.id)
                } else {
                    try await APIClient.shared.insert("rsvps", row: [
                        "event_id": event.id.uuidString,
                        "user_id": userID.uuidString,
                        "status": "going"])
                    myRsvps.insert(event.id)
                }
            } catch { /* keep UI state on failure */ }
        }
    }
}

struct EventRow: View {
    let event: Recommendation
    let isGoing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.categoryIcon)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(event.categoryColor)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.headline).lineLimit(1)
                Text("\(event.venue ?? "TBD") · \(event.startsAt.wydTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if event.friendsGoing.value > 0 {
                    Text("👥 \(event.friendsGoing.value) friend\(event.friendsGoing.value == 1 ? "" : "s") going")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isGoing {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
}

struct EventDetailView: View {
    let event: Recommendation
    let isGoing: Bool
    let onToggleRSVP: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: event.categoryIcon)
                        .font(.title)
                        .foregroundStyle(event.categoryColor)
                    VStack(alignment: .leading) {
                        Text(event.title).font(.title2).bold()
                        Text(EventCategory.label(for: event.category))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if let description = event.description {
                    Text(description).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(event.startsAt.wydDay), \(event.startsAt.wydTime) – \(event.endsAt.wydTime)", systemImage: "clock")
                    Label(event.venue ?? "Venue TBD", systemImage: "mappin.and.ellipse")
                    Label("Starts \(event.startsAt.wydRelative)", systemImage: "timer")
                    if event.friendsGoing.value > 0 {
                        Label("\(event.friendNames.joined(separator: ", ")) going", systemImage: "person.2.fill")
                    }
                    Label("\(event.totalRsvps.value) attending", systemImage: "person.3.fill")
                }
                .font(.subheadline)

                Button(isGoing ? "Leave event" : "Join event", action: onToggleRSVP)
                    .buttonStyle(.borderedProminent)
                    .tint(isGoing ? .red : .accentColor)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
