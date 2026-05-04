import Foundation
import CoreLocation
import Combine

@MainActor
final class RideRecorder: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(start: Date)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var currentPoints: [RidePoint] = []
    @Published var autoDetectEnabled = true
    @Published var autoUploadEnabled = true

    let location = LocationTracker()
    let activity = ActivityDetector()

    private weak var store: RideStore?
    private weak var strava: StravaUploader?
    private var bag = Set<AnyCancellable>()

    // Auto-stop: if no cycling detected for this long, finish the ride.
    private let inactivityTimeout: TimeInterval = 5 * 60
    private var lastCyclingSeen: Date?

    func attach(store: RideStore, strava: StravaUploader) {
        self.store = store
        self.strava = strava
    }

    func start() {
        location.requestAuthorization()
        activity.start()

        location.locationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in
                MainActor.assumeIsolated { self?.handleLocation(loc) }
            }
            .store(in: &bag)

        activity.activityPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] act in
                MainActor.assumeIsolated { self?.handleActivity(act) }
            }
            .store(in: &bag)

        // Significant location monitoring keeps the app alive while idle.
        location.startSignificantLocationMonitoring()
    }

    func startRideManually() {
        beginRide()
    }

    func stopRideManually() {
        finishRide()
    }

    private func handleActivity(_ activity: DetectedActivity) {
        guard autoDetectEnabled else { return }
        switch (state, activity) {
        case (.idle, .cycling):
            beginRide()
            lastCyclingSeen = Date()
        case (.recording, .cycling):
            lastCyclingSeen = Date()
        case (.recording, _):
            if let last = lastCyclingSeen,
               Date().timeIntervalSince(last) > inactivityTimeout {
                finishRide()
            }
        default:
            break
        }
    }

    private func handleLocation(_ loc: CLLocation) {
        guard case .recording = state else { return }
        let point = RidePoint(
            timestamp: loc.timestamp,
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            altitude: loc.altitude,
            speed: max(0, loc.speed),
            horizontalAccuracy: loc.horizontalAccuracy
        )
        currentPoints.append(point)
    }

    private func beginRide() {
        guard case .idle = state else { return }
        currentPoints = []
        state = .recording(start: Date())
        location.startPreciseTracking()
    }

    private func finishRide() {
        guard case .recording(let start) = state else { return }
        let end = Date()
        location.stopPreciseTracking()
        state = .idle

        guard currentPoints.count >= 10,
              end.timeIntervalSince(start) > 60 else {
            currentPoints = []
            return
        }

        let ride = Ride(
            name: defaultRideName(at: start),
            startDate: start,
            endDate: end,
            points: currentPoints
        )
        currentPoints = []
        store?.add(ride)

        if autoUploadEnabled, let strava, strava.isAuthorized {
            Task { await uploadAndUpdate(ride: ride) }
        }
    }

    private func uploadAndUpdate(ride: Ride) async {
        guard let strava, var stored = store?.rides.first(where: { $0.id == ride.id }) else { return }
        do {
            let result = try await strava.upload(ride: ride)
            stored.uploadedToStrava = true
            stored.stravaUploadID = result.uploadID
            stored.stravaActivityID = result.activityID
            store?.update(stored)
        } catch {
            // Leave ride flagged as not uploaded; user can retry from detail view.
        }
    }

    private func defaultRideName(at date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM, HH:mm"
        let label = hourLabel(for: date)
        return "\(label) à vélo - \(f.string(from: date))"
    }

    private func hourLabel(for date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 5..<12: return "Matin"
        case 12..<14: return "Midi"
        case 14..<18: return "Après-midi"
        case 18..<22: return "Soir"
        default: return "Nuit"
        }
    }
}
