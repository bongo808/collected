import SwiftUI
import CoreLocation

struct SettingsView: View {
    @EnvironmentObject var recorder: RideRecorder
    @EnvironmentObject var strava: StravaUploader

    @State private var connectError: String?
    @State private var connecting = false

    var body: some View {
        Form {
            Section("Détection automatique") {
                Toggle("Démarrer/arrêter automatiquement", isOn: $recorder.autoDetectEnabled)
                Toggle("Envoyer automatiquement vers Strava", isOn: $recorder.autoUploadEnabled)
                LabeledContent("Autorisation localisation", value: locationStatusText)
                if recorder.location.authorization != .authorizedAlways {
                    Button("Demander l'autorisation") { recorder.location.requestAuthorization() }
                }
            }

            Section("Strava") {
                if strava.isAuthorized {
                    LabeledContent("Compte", value: strava.athleteName ?? "Connecté")
                    Button("Se déconnecter", role: .destructive) {
                        strava.disconnect()
                    }
                } else {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            if connecting { ProgressView() }
                            Text("Connecter à Strava")
                        }
                    }
                    .disabled(connecting)
                    if let connectError {
                        Text(connectError).font(.caption).foregroundStyle(.red)
                    }
                }
            }

            Section("À propos") {
                LabeledContent("Version", value: appVersion)
                Link("API Strava", destination: URL(string: "https://developers.strava.com")!)
            }
        }
        .navigationTitle("Réglages")
    }

    private func connect() async {
        connecting = true
        connectError = nil
        defer { connecting = false }
        do {
            try await strava.connect()
        } catch {
            connectError = error.localizedDescription
        }
    }

    private var locationStatusText: String {
        switch recorder.location.authorization {
        case .notDetermined: return "Non demandée"
        case .restricted: return "Restreinte"
        case .denied: return "Refusée"
        case .authorizedWhenInUse: return "Pendant l'utilisation"
        case .authorizedAlways: return "Toujours"
        @unknown default: return "Inconnue"
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
