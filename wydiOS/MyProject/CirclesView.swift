import SwiftUI

struct CircleWithMembers: Identifiable {
    let circle: Circle
    var members: [(profile: Profile, sharingLevel: String)]
    var mySharingLevel: String
    var id: UUID { circle.id }
}

struct CirclesView: View {
    @EnvironmentObject var session: SessionStore
    @State private var circles: [CircleWithMembers] = []
    @State private var sharingStates: [UUID: Bool] = [:] // friend id → may see my events
    @State private var isLoading = true
    @State private var showCreate = false
    @State private var newCircleName = ""

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
                                ForEach(item.members, id: \.profile.id) { member in
                                    if member.profile.id == session.profile?.id {
                                        HStack {
                                            Image(systemName: "person.circle.fill")
                                                .foregroundStyle(.secondary)
                                            VStack(alignment: .leading) {
                                                Text(member.profile.displayName)
                                                Text("@\(member.profile.username)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text("you share: \(SharingLevel(rawValue: member.sharingLevel)?.label ?? member.sharingLevel)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        Toggle(isOn: sharingBinding(for: member.profile.id)) {
                                            HStack {
                                                Image(systemName: "person.circle.fill")
                                                    .foregroundStyle(.secondary)
                                                VStack(alignment: .leading) {
                                                    Text(member.profile.displayName)
                                                    Text(sharingStates[member.profile.id, default: true]
                                                         ? "@\(member.profile.username) · sees your events"
                                                         : "@\(member.profile.username) · hidden from them")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        .toggleStyle(.switch)
                                    }
                                }
                            } header: {
                                Text(item.circle.name)
                            } footer: {
                                HStack {
                                    Text("You share:")
                                    Picker("You share", selection: Binding(
                                        get: { SharingLevel(rawValue: item.mySharingLevel) ?? .publicEvents },
                                        set: { updateSharing(circleID: item.id, level: $0) }
                                    )) {
                                        ForEach(SharingLevel.allCases) { level in
                                            Text(level.label).tag(level)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .font(.caption)
                                }
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
            .task { await load() }
            .refreshable { await load() }
        }
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
                var members: [(Profile, String)] = []
                for memberRow in memberRows {
                    let profiles: [Profile] = try await APIClient.shared.select(
                        "profiles", filter: ["id": memberRow.userId.uuidString], as: Profile.self)
                    if let profile = profiles.first {
                        members.append((profile, memberRow.sharingLevel))
                    }
                }
                members.sort { $0.0.id == userID && $1.0.id != userID }
                result.append(CircleWithMembers(
                    circle: circle, members: members, mySharingLevel: membership.sharingLevel))
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
            try await APIClient.shared.insert("circle_members", row: [
                "circle_id": circleID.uuidString, "user_id": userID.uuidString,
                "sharing_level": SharingLevel.publicEvents.rawValue])
            for username in usernames {
                let clean = username.lowercased().trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                guard !clean.isEmpty else { continue }
                let profiles: [Profile] = try await APIClient.shared.select(
                    "profiles", filter: ["username": clean], as: Profile.self)
                guard let profile = profiles.first, profile.id != userID else { continue }
                try await APIClient.shared.insert("circle_members", row: [
                    "circle_id": circleID.uuidString, "user_id": profile.id.uuidString,
                    "sharing_level": SharingLevel.publicEvents.rawValue])
            }
            await load()
        } catch { /* surfaced via empty refresh */ }
    }

    private func updateSharing(circleID: UUID, level: SharingLevel) {
        guard let userID = session.profile?.id else { return }
        if let index = circles.firstIndex(where: { $0.id == circleID }) {
            circles[index].mySharingLevel = level.rawValue
        }
        Task {
            try? await APIClient.shared.update(
                "circle_members",
                filter: ["circle_id": circleID.uuidString, "user_id": userID.uuidString],
                patch: ["sharing_level": level.rawValue])
        }
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
