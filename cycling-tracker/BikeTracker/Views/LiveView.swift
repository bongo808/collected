import SwiftUI
import CoreLocation

struct LiveView: View {
    @EnvironmentObject var recorder: RideRecorder

    var body: some View {
        VStack(spacing: 24) {
            statusBadge

            VStack(spacing: 8) {
                Text(formattedDuration)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("Durée").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 32) {
                stat("Distance", value: distanceString)
                stat("Vitesse", value: speedString)
                stat("Points", value: "\(recorder.currentPoints.count)")
            }

            Spacer()

            actionButton

            HStack {
                Image(systemName: activityIcon)
                Text("Activité détectée: \(recorder.activity.current.rawValue)")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("BikeTracker")
        .onAppear { recorder.location.requestAuthorization() }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch recorder.state {
        case .idle:
            Label("En attente", systemImage: "moon.zzz")
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.gray.opacity(0.15), in: Capsule())
        case .recording:
            Label("Enregistrement", systemImage: "record.circle")
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.red.opacity(0.15), in: Capsule())
                .foregroundStyle(.red)
        }
    }

    private var actionButton: some View {
        Group {
            switch recorder.state {
            case .idle:
                Button {
                    recorder.startRideManually()
                } label: {
                    Label("Démarrer une sortie", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            case .recording:
                Button(role: .destructive) {
                    recorder.stopRideManually()
                } label: {
                    Label("Terminer la sortie", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack {
            Text(value).font(.title3).bold().monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var formattedDuration: String {
        guard case .recording(let start) = recorder.state else { return "00:00" }
        let s = Int(Date().timeIntervalSince(start))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%02d:%02d", m, sec)
    }

    private var distanceString: String {
        let meters = currentDistance()
        return meters > 1000
            ? String(format: "%.2f km", meters / 1000)
            : String(format: "%.0f m", meters)
    }

    private var speedString: String {
        guard let last = recorder.currentPoints.last else { return "—" }
        return String(format: "%.1f km/h", last.speed * 3.6)
    }

    private func currentDistance() -> Double {
        let pts = recorder.currentPoints
        guard pts.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<pts.count {
            let a = CLLocation(latitude: pts[i-1].latitude, longitude: pts[i-1].longitude)
            let b = CLLocation(latitude: pts[i].latitude, longitude: pts[i].longitude)
            total += b.distance(from: a)
        }
        return total
    }

    private var activityIcon: String {
        switch recorder.activity.current {
        case .cycling: return "bicycle"
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .automotive: return "car.fill"
        case .stationary: return "pause.circle"
        case .unknown: return "questionmark.circle"
        }
    }
}
