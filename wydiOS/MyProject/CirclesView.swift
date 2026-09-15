import SwiftUI

struct CircleWithMembers: Identifiable {
    let circle: Circle
    var members: [Profile]
    var myShares: CircleMember
    var id: UUID { circle.id }
}

enum ShareField: String, CaseIterable, Identifiable {
    case busy = "share_busy"
    case publicEvents = "share_public_events"
    case approxLocation = "share_approx_location"
    case liveLocation = "share_live_location"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .busy: return "Free / Busy"
        case .publicEvents: return "Public Events"
        case .approxLocation: return "Approximate Location"
        case .liveLocation: return "Live Location"
        }
    }

    var icon: String {
        switch self {
        case .busy: return "clock"
        case .publicEvents: return "calendar"
        case .approxLocation: return "location"
        case .liveLocation: return "location.fill"
        }
    }

    func value(in member: CircleMember) -> Bool {
        switch self {
        case .busy: return member.shareBusy
        case .publicEvents: return member.sharePublicEvents
        case .approxLocation: return member.shareApproxLocation
        case .liveLocation: return member.shareLiveLocation
        }
    }
}

struct CirclesView: View {
    @EnvironmentObject var session: SessionStore
    @State private var circles: [CircleWithMembers] = []
    @State private var sharingStates: [UUID: Bool] = [:] // friend id → may see my events
    @State private var calendarFriend: Profile? = nil
    @State private var isLoading = true
    @State private var showCreate = false
    @State private var newCircleName = ""
    @State private var addingTo: Circle? = nil
    @State private var addUsername = ""
    @State private var addError: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading circles…")
                } else if circles.isEmpty {
                    ContentUnavailableView {
                        Label("No circles yet", systemImage: "person.2.slash")
                    } description: {
                        Text("Create a circle and add friends by username.\nTry the demo users: alice, bob, priya, diego, sofia.")
                    } actions: {
                        Button("Create a circle") { showCreate = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(circles) { item in
                            Section {
                                ForEach(item.members) { member in
                                    memberRow(member, circleID: item.id)
                                }
                                Button {
                                    addUsername = ""
                                    addingTo = item.circle
                                } label: {
                                    Label("Add friend", systemImage: "person.badge.plus")
                                        .font(.subheadline)
                                }

                                Text("WHAT YOU SHARE")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                ForEach(ShareField.allCases) { field in
                                    Toggle(isOn: shareBinding(circleID: item.id, field: field)) {
                                        Label(field.label, systemImage: field.icon)
                                            .font(.subheadline)
                                    }
                                    .toggleStyle(.switch)
                                }
                            } header: {
                                Text(item.circle.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Circles")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateCircleSheet(name: $newCircleName) { addUsernames in
                    await createCircle(name: newCircleName, usernames: addUsernames)
                }
            }
            .sheet(item: $calendarFriend) { friend in
                NavigationStack {
                    CalendarView(friend: friend)
                        .navigationTitle("\(friend.displayName)'s calendar")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { calendarFriend = nil }
                            }
                        }
                }
            }
            .alert("Add to \(addingTo?.name ?? "circle")", isPresented: Binding(
                get: { addingTo != nil },
                set: { if !$0 { addingTo = nil } }
            )) {
                TextField("username", text: $addUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    guard let circle = addingTo else { return }
                    Task { await addMember(username: addUsername, to: circle.id) }
                }
            } message: {
                Text("Demo users: alice, bob, priya, diego, sofia")
            }
            .alert("Couldn't add friend", isPresented: Binding(
                get: { addError != nil },
                set: { if !$0 { addError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(addError ?? "")
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private func memberRow(_ member: Profile, circleID: UUID) -> some View {
        if member.id == session.profile?.id {
            HStack {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text(member.displayName)
                    Text("@\(member.username) · you")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(spacing: 4) {
                Button {
                    calendarFriend = member
                } label: {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(member.displayName)
                                .foregroundStyle(.primary)
                            Text(sharingStates[member.id, default: true]
                                 ? "@\(member.username) · sees your events"
                                 : "@\(member.username) · hidden from them")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                Toggle(isOn: sharingBinding(for: member.id)) {}
                    .labelsHidden()
            }
        }
    }

    // MARK: - Sharing bindings

    private func shareBinding(circleID: UUID, field: ShareField) -> Binding<Bool> {
        Binding(
            get: {
                circles.first(where: { $0.id == circleID }).map { field.value(in: $0.myShares) } ?? false
            },
            set: { newValue in
                guard let index = circles.firstIndex(where: { $0.id == circleID }) else { return }
                var shares = circles[index].myShares
                switch field {
                case .busy: shares.shareBusy = newValue
                case .publicEvents: shares.sharePublicEvents = newValue
                case .approxLocation: shares.shareApproxLocation = newValue
                case .liveLocation: shares.shareLiveLocation = newValue
                }
                circles[index].myShares = shares
                Task { await persistShare(circleID: circleID, field: field, value: newValue) }
            }
        )
    }

    private func persistShare(circleID: UUID, field: ShareField, value: Bool) async {
        guard let userID = session.profile?.id else { return }
        try? await APIClient.shared.update(
            "circle_members",
            filter: ["circle_id": circleID.uuidString, "user_id": userID.uuidString],
            patch: [field.rawValue: value])
    }

    private func sharingBinding(for friendID: UUID) -> Binding<Bool> {
        Binding(
            get: { sharingStates[friendID, default: true] },
            set: { newValue in
                sharingStates[friendID] = newValue
                Task { await persistSharing(friendID: friendID, share: newValue) }
            }
        )
    }

    private func persistSharing(friendID: UUID, share: Bool) async {
        guard let userID = session.profile?.id else { return }
        do {
            try await APIClient.shared.delete("friend_sharing", filter: [
                "owner_id": userID.uuidString, "friend_id": friendID.uuidString])
            try await APIClient.shared.insert("friend_sharing", row: [
                "owner_id": userID.uuidString,
                "friend_id": friendID.uuidString,
                "share_events": share])
        } catch { /* best-effort */ }
    }

    // MARK: - Loading

    private func load() async {
        guard let userID = session.profile?.id else { return }
        isLoading = circles.isEmpty
        do {
            struct SharingRow: Decodable {
                let ownerId: UUID
                let friendId: UUID
                let shareEvents: Bool
            }
            let sharingRows: [SharingRow] = try await APIClient.shared.select(
                "friend_sharing", filter: ["owner_id": userID.uuidString], as: SharingRow.self)
            sharingStates = Dictionary(uniqueKeysWithValues: sharingRows.map { ($0.friendId, $0.shareEvents) })

            let memberships: [CircleMember] = try await APIClient.shared.select(
                "circle_members", filter: ["user_id": userID.uuidString], as: CircleMember.self)
            var result: [CircleWithMembers] = []
            for membership in memberships {
                let circleRows: [Circle] = try await APIClient.shared.select(
                    "circles", filter: ["id": membership.circleId.uuidString], as: Circle.self)
                guard let circle = circleRows.first else { continue }
                let memberRows: [CircleMember] = try await APIClient.shared.select(
                    "circle_members", filter: ["circle_id": membership.circleId.uuidString], as: CircleMember.self)
                var members: [Profile] = []
                for memberRow in memberRows {
                    let profiles: [Profile] = try await APIClient.shared.select(
                        "profiles", filter: ["id": memberRow.userId.uuidString], as: Profile.self)
                    if let profile = profiles.first {
                        members.append(profile)
                    }
                }
                members.sort { $0.id == userID && $1.id != userID }
                result.append(CircleWithMembers(circle: circle, members: members, myShares: membership))
            }
            circles = result
        } catch { /* keep stale data */ }
        isLoading = false
    }

    private func createCircle(name: String, usernames: [String]) async {
        guard let userID = session.profile?.id, !name.isEmpty else { return }
        do {
            let circleID = UUID()
            try await APIClient.shared.insert("circles", row: [
                "id": circleID.uuidString, "name": name, "owner_id": userID.uuidString])
            try await insertMember(circleID: circleID, userID: userID)
            for username in usernames {
                let clean = Self.normalizeUsername(username)
                guard !clean.isEmpty else { continue }
                let profiles: [Profile] = try await APIClient.shared.select(
                    "profiles", filter: ["username": clean], as: Profile.self)
                guard let profile = profiles.first, profile.id != userID else { continue }
                try await insertMember(circleID: circleID, userID: profile.id)
            }
            newCircleName = ""
            await load()
        } catch { /* surfaced via empty refresh */ }
    }

    private func addMember(username: String, to circleID: UUID) async {
        let clean = Self.normalizeUsername(username)
        guard !clean.isEmpty else { return }
        do {
            let profiles: [Profile] = try await APIClient.shared.select(
                "profiles", filter: ["username": clean], as: Profile.self)
            guard let profile = profiles.first else {
                addError = "No one goes by @\(clean)."
                return
            }
            if circles.first(where: { $0.id == circleID })?.members.contains(where: { $0.id == profile.id }) == true {
                addError = "@\(clean) is already in this circle."
                return
            }
            try await insertMember(circleID: circleID, userID: profile.id)
            await load()
        } catch {
            addError = error.localizedDescription
        }
    }

    /// New members start sharing free/busy + public events; locations stay off until they opt in.
    private func insertMember(circleID: UUID, userID: UUID) async throws {
        try await APIClient.shared.insert("circle_members", row: [
            "circle_id": circleID.uuidString, "user_id": userID.uuidString,
            "share_busy": true, "share_public_events": true,
            "share_approx_location": false, "share_live_location": false])
    }

    static func normalizeUsername(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
    }
}

struct CreateCircleSheet: View {
    @Binding var name: String
    let onCreate: ([String]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var usernames = ""
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Circle") {
                    TextField("Name (e.g. Hackathon Team)", text: $name)
                }
                Section("Members (comma-separated usernames)") {
                    TextField("alice, bob, priya", text: $usernames)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Demo users: alice, bob, priya, diego, sofia")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        isBusy = true
                        let list = usernames.split(separator: ",").map(String.init)
                        Task {
                            await onCreate(list)
                            isBusy = false
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                }
            }
        }
    }
}
