import Foundation
import CoreLocation
import Combine

final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isTracking = false

    let locationPublisher = PassthroughSubject<CLLocation, Never>()

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        authorization = manager.authorizationStatus
    }

    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func startSignificantLocationMonitoring() {
        manager.startMonitoringSignificantLocationChanges()
    }

    func startPreciseTracking() {
        guard !isTracking else { return }
        manager.startUpdatingLocation()
        isTracking = true
    }

    func stopPreciseTracking() {
        manager.stopUpdatingLocation()
        isTracking = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedAlways {
            startSignificantLocationMonitoring()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations where loc.horizontalAccuracy > 0 && loc.horizontalAccuracy < 50 {
            currentLocation = loc
            locationPublisher.send(loc)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silently ignore transient errors; CL will keep delivering updates.
    }
}
