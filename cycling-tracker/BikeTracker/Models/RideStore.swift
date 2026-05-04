import Foundation
import Combine

@MainActor
final class RideStore: ObservableObject {
    @Published private(set) var rides: [Ride] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("rides.json")
    }()

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Ride].self, from: data) {
            rides = decoded.sorted { $0.startDate > $1.startDate }
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(rides) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(_ ride: Ride) {
        rides.insert(ride, at: 0)
        save()
    }

    func update(_ ride: Ride) {
        if let idx = rides.firstIndex(where: { $0.id == ride.id }) {
            rides[idx] = ride
            save()
        }
    }

    func delete(_ ride: Ride) {
        rides.removeAll { $0.id == ride.id }
        save()
    }
}
