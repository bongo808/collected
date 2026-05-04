import Foundation
import CoreMotion
import Combine

enum DetectedActivity: String {
    case cycling, walking, running, automotive, stationary, unknown
}

final class ActivityDetector: ObservableObject {
    @Published private(set) var current: DetectedActivity = .unknown
    let activityPublisher = PassthroughSubject<DetectedActivity, Never>()

    private let manager = CMMotionActivityManager()
    private let queue = OperationQueue()

    var isAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

    func start() {
        guard isAvailable else { return }
        manager.startActivityUpdates(to: queue) { [weak self] activity in
            guard let self, let activity else { return }
            let detected: DetectedActivity
            if activity.cycling { detected = .cycling }
            else if activity.running { detected = .running }
            else if activity.walking { detected = .walking }
            else if activity.automotive { detected = .automotive }
            else if activity.stationary { detected = .stationary }
            else { detected = .unknown }

            DispatchQueue.main.async {
                self.current = detected
                self.activityPublisher.send(detected)
            }
        }
    }

    func stop() {
        manager.stopActivityUpdates()
    }
}
