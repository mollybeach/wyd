import SwiftUI
import MapKit

struct EventMapView: View {
    @EnvironmentObject var session: SessionStore
    @State private var events: [Recommendation] = []
    @State private var friendLocations: [FriendLocation] = []
    @State private var friendsOnly = false
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: WYDConfig.conferenceLat, longitude: WYDConfig.conferenceLng),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))

    private var visibleEvents: [Recommendation] {
        friendsOnly ? events.filter { $0.friendsGoing.value > 0 } : events
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(visibleEvents) { event in
                    if let lat = event.lat, let lng = event.lng {
                        Annotation(event.title, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                            VStack(spacing: 2) {
                                Image(systemName: event.categoryIcon)
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(event.categoryColor)
                                    .clipShape(SwiftUI.Circle())
                                if event.friendsGoing.value > 0 {
                                    Text("\(event.friendsGoing.value)👥")
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .background(.white.opacity(0.9))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                ForEach(friendLocations) { friend in
                    Annotation(friend.displayName, coordinate: CLLocationCoordinate2D(latitude: friend.lat, longitude: friend.lng)) {
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.blue)
                            .clipShape(SwiftUI.Circle())
                            .overlay(SwiftUI.Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $friendsOnly) {
                        Image(systemName: friendsOnly ? "person.2.fill" : "person.2")
                    }
                    .toggleStyle(.button)
                }
            }
            .navigationTitle("Live Map")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
    }

    private func load() async {
        guard let userID = session.profile?.id else { return }
        async let eventsTask = APIClient.shared.rpc(
            "wyd_recommend",
            args: ["p_user": userID.uuidString, "p_now": Date().wydISOString, "p_limit": 50],
            as: Recommendation.self)
        async let friendsTask = APIClient.shared.rpc(
            "wyd_friend_locations",
            args: ["p_user": userID.uuidString],
            as: FriendLocation.self)
        events = (try? await eventsTask) ?? []
        friendLocations = (try? await friendsTask) ?? []
    }
}
