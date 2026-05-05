import SwiftUI

struct ContentView: View {
    @EnvironmentObject var recorder: RideRecorder
    @EnvironmentObject var store: RideStore
    @EnvironmentObject var strava: StravaUploader

    var body: some View {
        TabView {
            NavigationStack {
                LiveView()
            }
            .tabItem { Label("En cours", systemImage: "bicycle") }

            NavigationStack {
                RideListView()
            }
            .tabItem { Label("Historique", systemImage: "list.bullet") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Réglages", systemImage: "gear") }
        }
    }
}
