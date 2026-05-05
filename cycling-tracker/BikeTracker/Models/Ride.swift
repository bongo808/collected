import Foundation
import CoreLocation

struct RidePoint: Codable, Hashable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double
    let horizontalAccuracy: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Ride: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var startDate: Date
    var endDate: Date
    var points: [RidePoint]
    var uploadedToStrava: Bool
    var stravaActivityID: Int64?
    var stravaUploadID: Int64?

    init(id: UUID = UUID(),
         name: String = "Sortie vélo",
         startDate: Date,
         endDate: Date,
         points: [RidePoint] = [],
         uploadedToStrava: Bool = false,
         stravaActivityID: Int64? = nil,
         stravaUploadID: Int64? = nil) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.points = points
        self.uploadedToStrava = uploadedToStrava
        self.stravaActivityID = stravaActivityID
        self.stravaUploadID = stravaUploadID
    }

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    var distanceMeters: Double {
        guard points.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<points.count {
            let a = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let b = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            total += b.distance(from: a)
        }
        return total
    }

    var averageSpeedKmh: Double {
        guard duration > 0 else { return 0 }
        return (distanceMeters / 1000) / (duration / 3600)
    }

    var elevationGainMeters: Double {
        guard points.count > 1 else { return 0 }
        var gain: Double = 0
        for i in 1..<points.count {
            let delta = points[i].altitude - points[i-1].altitude
            if delta > 0 { gain += delta }
        }
        return gain
    }
}
