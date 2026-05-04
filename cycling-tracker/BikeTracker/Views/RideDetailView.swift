import SwiftUI
import MapKit

struct RideDetailView: View {
    let ride: Ride
    @EnvironmentObject var store: RideStore
    @EnvironmentObject var strava: StravaUploader

    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var showShareSheet = false
    @State private var shareURL: URL?

    private var coordinates: [CLLocationCoordinate2D] {
        ride.points.map { $0.coordinate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MapView(coordinates: coordinates)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 16) {
                    HStack {
                        statBlock("Distance", String(format: "%.2f km", ride.distanceMeters / 1000))
                        Divider()
                        statBlock("Durée", durationString)
                        Divider()
                        statBlock("Moyenne", String(format: "%.1f km/h", ride.averageSpeedKmh))
                    }
                    .frame(height: 60)

                    HStack {
                        statBlock("Dénivelé", String(format: "%.0f m", ride.elevationGainMeters))
                        Divider()
                        statBlock("Points", "\(ride.points.count)")
                        Divider()
                        statBlock("Date", shortDate)
                    }
                    .frame(height: 60)
                }
                .padding()
                .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                stravaSection

                Button {
                    if let url = try? GPXExporter.writeGPX(for: ride) {
                        shareURL = url
                        showShareSheet = true
                    }
                } label: {
                    Label("Exporter le GPX", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(ride.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
    }

    @ViewBuilder
    private var stravaSection: some View {
        if ride.uploadedToStrava {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.orange)
                Text("Envoyé vers Strava")
                Spacer()
                if let id = ride.stravaActivityID,
                   let url = URL(string: "https://www.strava.com/activities/\(id)") {
                    Link("Ouvrir", destination: url)
                }
            }
            .padding()
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        } else {
            Button {
                Task { await upload() }
            } label: {
                HStack {
                    if isUploading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    Text(isUploading ? "Envoi en cours…" : "Envoyer vers Strava")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isUploading || !strava.isAuthorized)

            if !strava.isAuthorized {
                Text("Connectez votre compte Strava dans Réglages.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let uploadError {
                Text(uploadError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func upload() async {
        isUploading = true
        uploadError = nil
        defer { isUploading = false }
        do {
            let result = try await strava.upload(ride: ride)
            var updated = ride
            updated.uploadedToStrava = true
            updated.stravaUploadID = result.uploadID
            updated.stravaActivityID = result.activityID
            store.update(updated)
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func statBlock(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var durationString: String {
        let s = Int(ride.duration)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%02d:%02d", m, sec)
    }

    private var shortDate: String {
        let f = DateFormatter()
        f.dateStyle = .short
        return f.string(from: ride.startDate)
    }
}

struct MapView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isUserInteractionEnabled = true
        map.showsUserLocation = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        guard coordinates.count > 1 else { return }
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        map.addOverlay(polyline)
        if let rect = map.overlays.first?.boundingMapRect {
            map.setVisibleMapRect(rect, edgePadding: .init(top: 24, left: 24, bottom: 24, right: 24), animated: false)
        }
        map.delegate = context.coordinator
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = .systemOrange
            renderer.lineWidth = 4
            return renderer
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
