import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: SessionStore

    var body: some View {
        Group {
            if session.isRestoring {
                ProgressView("Loading WYD…")
            } else if session.profile != nil {
                MainTabView()
            } else {
                AuthView()
            }
        }
    }
}

struct MainTabView: View {
    @State private var tab = 0
    @AppStorage(WYDClock.enabledKey) private var conferenceMode = WYDClock.isConferenceMode

    var body: some View {
        TabView(selection: $tab) {
            ConciergeView()
                .tabItem { Label("wyd?", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(0)
            EventMapView()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(1)
            EventsView()
                .tabItem { Label("Events", systemImage: "calendar") }
                .tag(2)
            CirclesView()
                .tabItem { Label("Circles", systemImage: "person.2.fill") }
                .tag(3)
            ProfileView()
                .tabItem { Label("You", systemImage: "person.crop.circle.fill") }
                .tag(4)
        }
        // Switching clocks changes every time-based query, so rebuild the tabs to reload.
        .id(conferenceMode)
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionStore())
        .environmentObject(LocationManager())
}
