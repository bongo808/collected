import SwiftUI

struct RideListView: View {
    @EnvironmentObject var store: RideStore

    var body: some View {
        Group {
            if store.rides.isEmpty {
                ContentUnavailableView(
                    "Aucune sortie",
                    systemImage: "bicycle",
                    description: Text("Vos trajets enregistrés apparaîtront ici.")
                )
            } else {
                List {
                    ForEach(store.rides) { ride in
                        NavigationLink(value: ride) {
                            RideRow(ride: ride)
                        }
                    }
                    .onDelete { indices in
                        for i in indices { store.delete(store.rides[i]) }
                    }
                }
                .navigationDestination(for: Ride.self) { ride in
                    RideDetailView(ride: ride)
                }
            }
        }
        .navigationTitle("Historique")
    }
}

struct RideRow: View {
    let ride: Ride

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.name).font(.headline).lineLimit(1)
                HStack(spacing: 12) {
                    Label(distanceString, systemImage: "ruler")
                    Label(durationString, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if ride.uploadedToStrava {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Envoyé vers Strava")
            }
        }
        .padding(.vertical, 4)
    }

    private var distanceString: String {
        let km = ride.distanceMeters / 1000
        return String(format: "%.2f km", km)
    }

    private var durationString: String {
        let s = Int(ride.duration)
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m)min"
    }
}
