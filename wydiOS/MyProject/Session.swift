import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: AuthUser?
    @Published var profile: Profile?
    @Published var isRestoring = true

    private let api = APIClient.shared
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let token = "wyd_token"
        static let userID = "wyd_user_id"
        static let email = "wyd_email"
    }

    init() {
        restore()
    }

    // MARK: - Restore

    private func restore() {
        guard let token = defaults.string(forKey: Keys.token),
              let idString = defaults.string(forKey: Keys.userID),
              let id = UUID(uuidString: idString),
              let email = defaults.string(forKey: Keys.email) else {
            isRestoring = false
            return
        }
        api.userToken = token
        user = AuthUser(id: id, email: email)
        Task {
            do {
                profile = try await fetchProfile(id: id)
                isRestoring = false
            } catch {
                signOut()
                isRestoring = false
            }
        }
    }

    private func fetchProfile(id: UUID) async throws -> Profile {
        let profiles: [Profile] = try await api.select("profiles", filter: ["id": id.uuidString], as: Profile.self)
        guard let profile = profiles.first else { throw APIError.server("Profile not found") }
        return profile
    }

    // MARK: - Sign in / up / out

    func signIn(email: String, password: String) async throws {
        let response = try await api.signIn(email: email, password: password)
        api.userToken = response.token
        let profile = try await fetchProfile(id: response.user.id)
        self.user = response.user
        self.profile = profile
        persist(token: response.token, user: response.user)
    }

    func signUp(email: String, password: String, username: String, displayName: String) async throws {
        let cleanUsername = username.lowercased().trimmingCharacters(in: .whitespaces)
        guard !cleanUsername.isEmpty else { throw APIError.server("Pick a username") }

        let existing: [Profile] = try await api.select(
            "profiles", filter: ["username": cleanUsername], as: Profile.self)
        guard existing.isEmpty else { throw APIError.server("Username \"\(cleanUsername)\" is taken") }

        let response = try await api.signUp(email: email, password: password)
        api.userToken = response.token
        try await api.insert("profiles", row: [
            "id": response.user.id.uuidString,
            "username": cleanUsername,
            "display_name": displayName.isEmpty ? cleanUsername : displayName
        ])
        let profile = try await fetchProfile(id: response.user.id)
        self.user = response.user
        self.profile = profile
        persist(token: response.token, user: response.user)
    }

    func signOut() {
        user = nil
        profile = nil
        api.userToken = nil
        defaults.removeObject(forKey: Keys.token)
        defaults.removeObject(forKey: Keys.userID)
        defaults.removeObject(forKey: Keys.email)
    }

    private func persist(token: String, user: AuthUser) {
        defaults.set(token, forKey: Keys.token)
        defaults.set(user.id.uuidString, forKey: Keys.userID)
        defaults.set(user.email, forKey: Keys.email)
    }
}
