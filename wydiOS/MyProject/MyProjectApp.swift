import SwiftUI

@main
struct MyProjectApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(locationManager)
        }
    }
}
