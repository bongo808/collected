import SwiftUI

@main
struct BikeTrackerApp: App {
    @StateObject private var recorder = RideRecorder()
    @StateObject private var store = RideStore()
    @StateObject private var strava = StravaUploader()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recorder)
                .environmentObject(store)
                .environmentObject(strava)
                .onOpenURL { url in strava.handleCallback(url: url) }
                .task {
                    recorder.attach(store: store, strava: strava)
                    recorder.start()
                }
        }
    }
}
