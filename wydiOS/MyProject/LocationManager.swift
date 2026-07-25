import Foundation
import CoreLocation
import SwiftUI

/// Opt-in location sharing: only pushes to the backend when `sharingEnabled` is true
/// and the user granted when-in-use authorization.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var sharingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(sharingEnabled, forKey: "wyd_share_location")
            if sharingEnabled { start() }
        }
    }

    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return manager
    }()
    private var lastPush = Date.distantPast
    private var started = false

    override init() {
        sharingEnabled = UserDefaults.standard.bool(forKey: "wyd_share_location")
        super.init()
        if sharingEnabled { start() }
    }

    /// Requests permission (if needed) and starts updates. Called lazily —
    /// when the user enables sharing, not at app launch.
    func start() {
        guard !started else { return }
        started = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.location = latest
            await self.pushIfNeeded(latest)
        }
    }

    private func pushIfNeeded(_ location: CLLocation) async {
        guard sharingEnabled, Date().timeIntervalSince(lastPush) > 60 else { return }
        lastPush = Date()
        // Upsert the location row via delete + insert (no upsert needed for a demo-scale table).
        guard let userID = UserDefaults.standard.string(forKey: "wyd_user_id") else { return }
        do {
            try await APIClient.shared.delete("locations", filter: ["user_id": userID])
            try await APIClient.shared.insert("locations", row: [
                "user_id": userID,
                "lat": location.coordinate.latitude,
                "lng": location.coordinate.longitude
            ])
        } catch {
            // Location sharing is best-effort; ignore failures.
        }
    }
}
