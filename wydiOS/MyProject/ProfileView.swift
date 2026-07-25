import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var locationManager: LocationManager

    @State private var myEvents: [WYDEvent] = []
    @State private var showNewEvent = false
    @State private var feeds: [CalendarFeed] = []
    @State private var showAddFeed = false
    @State private var isSyncing = false
    @State private var syncMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let profile = session.profile {
                    Section {
                        HStack(spacing: 14) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(profile.displayName).font(.headline)
                                Text("@\(profile.username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("My schedule") {
                    if myEvents.isEmpty {
                        Text("Nothing yet — join events from the Events tab or ask the concierge.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(myEvents) { event in
                        HStack(spacing: 12) {
                            Image(systemName: event.categoryIcon)
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(event.categoryColor)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading) {
                                Text(event.title).font(.subheadline).lineLimit(1)
                                Text("\(event.startsAt.wydDay) \(event.startsAt.wydTime) · \(event.venue ?? "TBD")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button { showNewEvent = true } label: {
                        Label("Add personal event", systemImage: "plus")
                    }
                }

                Section("Connected calendars") {
                    ForEach(feeds) { feed in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(feed.name).font(.subheadline)
                                Text(feed.lastSyncedAt.map { "Synced \($0.wydDay) \($0.wydTime)" } ?? "Never synced")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await syncFeed(feed) }
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            .disabled(isSyncing)
                        }
                    }
                    .onDelete { indexSet in
                        Task { await deleteFeeds(at: indexSet) }
                    }

                    Button { showAddFeed = true } label: {
                        Label("Add feed (Google, Luma, .ics…)", systemImage: "link.badge.plus")
                    }
                    Button {
                        Task { await importAppleCalendar() }
                    } label: {
                        Label("Import Apple Calendar", systemImage: "apple.logo")
                    }
                    .disabled(isSyncing)

                    if isSyncing {
                        HStack {
                            ProgressView()
                            Text("Syncing…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let syncMessage {
                        Text(syncMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Google: Calendar settings → “Secret address in iCal format”. Luma: calendar → Subscribe feed. Partiful: paste the event’s “Add to calendar” .ics link.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Toggle(isOn: $locationManager.sharingEnabled) {
                        Label("Share my location with circles", systemImage: "location.fill")
                    }
                    Text("Only circles where your sharing level is Approximate Location or higher can see where you are.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        session.signOut()
                    }
                }
            }
            .navigationTitle("You")
            .sheet(isPresented: $showNewEvent) {
                NewEventSheet { await load() }
            }
            .sheet(isPresented: $showAddFeed) {
                AddFeedSheet { await loadFeeds() }
            }
            .task { await load(); await loadFeeds() }
            .refreshable { await load(); await loadFeeds() }
        }
    }

    // MARK: - Calendar feeds

    private func loadFeeds() async {
        guard let userID = session.profile?.id else { return }
        feeds = (try? await APIClient.shared.select(
            "calendar_feeds", filter: ["user_id": userID.uuidString], as: CalendarFeed.self)) ?? []
    }

    private func syncFeed(_ feed: CalendarFeed) async {
        guard let userID = session.profile?.id else { return }
        isSyncing = true
        syncMessage = nil
        do {
            let count = try await ICSImporter.sync(feed: feed, userID: userID)
            syncMessage = "✓ \(feed.name): imported \(count) new event\(count == 1 ? "" : "s")"
            await loadFeeds()
            await load()
        } catch {
            syncMessage = "✗ \(feed.name): \(error.localizedDescription)"
        }
        isSyncing = false
    }

    private func deleteFeeds(at indexSet: IndexSet) async {
        for index in indexSet {
            let feed = feeds[index]
            try? await APIClient.shared.delete("calendar_feeds", filter: ["id": feed.id.uuidString])
        }
        await loadFeeds()
    }

    private func importAppleCalendar() async {
        guard let userID = session.profile?.id else { return }
        isSyncing = true
        syncMessage = nil
        do {
            let count = try await EventKitImporter.importEvents(userID: userID)
            syncMessage = "✓ Apple Calendar: imported \(count) new event\(count == 1 ? "" : "s")"
            await load()
        } catch {
            syncMessage = "✗ Apple Calendar: \(error.localizedDescription)"
        }
        isSyncing = false
    }

    private func load() async {
        guard let userID = session.profile?.id else { return }
        do {
            let rsvps: [RSVP] = try await APIClient.shared.select(
                "rsvps", filter: ["user_id": userID.uuidString], as: RSVP.self)
            var events: [WYDEvent] = []
            for rsvp in rsvps where rsvp.status == "going" {
                let rows: [WYDEvent] = try await APIClient.shared.select(
                    "events", filter: ["id": rsvp.eventId.uuidString], as: WYDEvent.self)
                events.append(contentsOf: rows)
            }
            myEvents = events
                .filter { $0.endsAt > Date() }
                .sorted { $0.startsAt < $1.startsAt }
        } catch { /* keep stale */ }
    }
}

struct NewEventSheet: View {
    let onSaved: () async -> Void

    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var venue = ""
    @State private var startsAt = Date().addingTimeInterval(3600)
    @State private var endsAt = Date().addingTimeInterval(7200)
    @State private var visibility = "private"
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Venue", text: $venue)
                DatePicker("Starts", selection: $startsAt)
                DatePicker("Ends", selection: $endsAt)
                Picker("Visibility", selection: $visibility) {
                    Text("Private").tag("private")
                    Text("Circles").tag("circle")
                    Text("Public").tag("public")
                }
            }
            .navigationTitle("Personal Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isBusy = true
                        Task {
                            await save()
                            isBusy = false
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty || isBusy)
                }
            }
        }
    }

    private func save() async {
        guard let userID = session.profile?.id else { return }
        let eventID = UUID()
        do {
            try await APIClient.shared.insert("events", row: [
                "id": eventID.uuidString,
                "title": title,
                "category": "personal",
                "venue": venue,
                "starts_at": startsAt.wydISOString,
                "ends_at": endsAt.wydISOString,
                "owner_id": userID.uuidString,
                "visibility": visibility
            ])
            try await APIClient.shared.insert("rsvps", row: [
                "event_id": eventID.uuidString,
                "user_id": userID.uuidString,
                "status": "going"
            ])
            await onSaved()
        } catch { /* keep it simple: sheet closes anyway */ }
    }
}

struct AddFeedSheet: View {
    let onSaved: () async -> Void

    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var url = ""
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Calendar feed") {
                    TextField("Name (e.g. Google Calendar)", text: $name)
                    TextField("ICS / webcal URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section {
                    Text("Works with any iCalendar (.ics) feed:\n• Google Calendar → Settings → “Secret address in iCal format”\n• Luma → calendar → Subscribe / feed URL\n• Partiful → event → “Add to calendar” .ics link\n• Outlook, Meetup, and most event apps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Section {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add & Sync") {
                        isBusy = true
                        Task {
                            await save()
                            isBusy = false
                        }
                    }
                    .disabled(name.isEmpty || url.isEmpty || isBusy)
                }
            }
        }
    }

    private func save() async {
        guard let userID = session.profile?.id else { return }
        do {
            let feedID = UUID()
            try await APIClient.shared.insert("calendar_feeds", row: [
                "id": feedID.uuidString,
                "user_id": userID.uuidString,
                "name": name,
                "url": url.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
            let feed = CalendarFeed(id: feedID, userId: userID, name: name, url: url, lastSyncedAt: nil)
            _ = try await ICSImporter.sync(feed: feed, userID: userID)
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
