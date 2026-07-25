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
    var body: some View {
        TabView {
            ConciergeView()
                .tabItem { Label("wyd?", systemImage: "bubble.left.and.bubble.right.fill") }
            EventMapView()
                .tabItem { Label("Map", systemImage: "map.fill") }
            EventsView()
                .tabItem { Label("Events", systemImage: "calendar") }
            CirclesView()
                .tabItem { Label("Circles", systemImage: "person.2.fill") }
            ProfileView()
                .tabItem { Label("You", systemImage: "person.crop.circle.fill") }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionStore())
        .environmentObject(LocationManager())
}
