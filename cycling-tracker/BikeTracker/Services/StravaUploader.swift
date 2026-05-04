import Foundation
import AuthenticationServices
import Security
import UIKit

// MARK: - Configuration
//
// Configurez votre app Strava sur https://www.strava.com/settings/api
// puis renseignez les valeurs ci-dessous (ou via Info.plist).
struct StravaConfig {
    static let clientID: String = Bundle.main.object(forInfoDictionaryKey: "StravaClientID") as? String ?? "YOUR_CLIENT_ID"
    static let clientSecret: String = Bundle.main.object(forInfoDictionaryKey: "StravaClientSecret") as? String ?? "YOUR_CLIENT_SECRET"
    static let redirectURI: String = "biketracker://strava/callback"
    static let scope: String = "activity:write,read"
}

struct StravaUploadResult {
    let uploadID: Int64
    let activityID: Int64?
}

enum StravaError: Error, LocalizedError {
    case notAuthorized
    case authFailed(String)
    case uploadFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Pas connecté à Strava."
        case .authFailed(let m): return "Authentification Strava: \(m)"
        case .uploadFailed(let m): return "Upload Strava: \(m)"
        case .timeout: return "Strava n'a pas confirmé la création de l'activité."
        }
    }
}

@MainActor
final class StravaUploader: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var athleteName: String?

    private let keychainKey = "strava.tokens.v1"
    private var session: ASWebAuthenticationSession?
    private var pendingAuthContinuation: CheckedContinuation<Void, Error>?

    private struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var athleteName: String?
    }

    private var tokens: Tokens? {
        didSet {
            isAuthorized = tokens != nil
            athleteName = tokens?.athleteName
            saveTokens()
        }
    }

    override init() {
        super.init()
        loadTokens()
    }

    // MARK: - OAuth

    func connect() async throws {
        var comps = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: StravaConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: StravaConfig.redirectURI),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: StravaConfig.scope)
        ]
        let authURL = comps.url!

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.pendingAuthContinuation = cont
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "biketracker"
            ) { [weak self] callback, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.pendingAuthContinuation?.resume(throwing: StravaError.authFailed(error.localizedDescription))
                        self.pendingAuthContinuation = nil
                        return
                    }
                    if let callback {
                        self.handleCallback(url: callback)
                    } else {
                        self.pendingAuthContinuation?.resume(throwing: StravaError.authFailed("no callback"))
                        self.pendingAuthContinuation = nil
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    func disconnect() {
        tokens = nil
    }

    func handleCallback(url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value else {
            pendingAuthContinuation?.resume(throwing: StravaError.authFailed("no code"))
            pendingAuthContinuation = nil
            return
        }
        Task {
            do {
                try await exchangeCode(code)
                pendingAuthContinuation?.resume(returning: ())
            } catch {
                pendingAuthContinuation?.resume(throwing: error)
            }
            pendingAuthContinuation = nil
        }
    }

    private func exchangeCode(_ code: String) async throws {
        var req = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        req.httpMethod = "POST"
        let body = [
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]
        req.httpBody = formEncoded(body).data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw StravaError.authFailed("token exchange failed")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let expiresAt = json["expires_at"] as? TimeInterval else {
            throw StravaError.authFailed("invalid token payload")
        }
        let athlete = json["athlete"] as? [String: Any]
        let firstName = athlete?["firstname"] as? String
        let lastName = athlete?["lastname"] as? String
        let name = [firstName, lastName].compactMap { $0 }.joined(separator: " ")

        tokens = Tokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date(timeIntervalSince1970: expiresAt),
            athleteName: name.isEmpty ? nil : name
        )
    }

    private func refreshIfNeeded() async throws {
        guard let t = tokens else { throw StravaError.notAuthorized }
        if t.expiresAt.timeIntervalSinceNow > 60 { return }

        var req = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        req.httpMethod = "POST"
        let body = [
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": t.refreshToken
        ]
        req.httpBody = formEncoded(body).data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let expiresAt = json["expires_at"] as? TimeInterval else {
            throw StravaError.authFailed("refresh failed")
        }
        tokens = Tokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date(timeIntervalSince1970: expiresAt),
            athleteName: t.athleteName
        )
    }

    // MARK: - Upload

    func upload(ride: Ride) async throws -> StravaUploadResult {
        try await refreshIfNeeded()
        guard let access = tokens?.accessToken else { throw StravaError.notAuthorized }

        let gpxURL = try GPXExporter.writeGPX(for: ride)
        let gpxData = try Data(contentsOf: gpxURL)

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }

        for (name, value) in [
            ("name", ride.name),
            ("description", "Enregistré automatiquement par BikeTracker"),
            ("data_type", "gpx"),
            ("activity_type", "ride"),
            ("external_id", ride.id.uuidString)
        ] {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"ride.gpx\"\r\n")
        append("Content-Type: application/gpx+xml\r\n\r\n")
        body.append(gpxData)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown error"
            throw StravaError.uploadFailed(msg)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let uploadID = (json["id"] as? Int64) ?? (json["id"] as? NSNumber)?.int64Value else {
            throw StravaError.uploadFailed("no upload id")
        }

        // Strava processes uploads asynchronously; poll until activity_id appears.
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            if let activityID = try await pollUpload(uploadID: uploadID) {
                try? FileManager.default.removeItem(at: gpxURL)
                return StravaUploadResult(uploadID: uploadID, activityID: activityID)
            }
        }
        try? FileManager.default.removeItem(at: gpxURL)
        return StravaUploadResult(uploadID: uploadID, activityID: nil)
    }

    private func pollUpload(uploadID: Int64) async throws -> Int64? {
        try await refreshIfNeeded()
        guard let access = tokens?.accessToken else { throw StravaError.notAuthorized }
        var req = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads/\(uploadID)")!)
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        if let error = json["error"] as? String, !error.isEmpty {
            throw StravaError.uploadFailed(error)
        }
        if let activityID = json["activity_id"] as? Int64 {
            return activityID
        }
        if let n = json["activity_id"] as? NSNumber {
            return n.int64Value
        }
        return nil
    }

    // MARK: - Persistence

    private func saveTokens() {
        guard let tokens else {
            try? KeychainHelper.delete(key: keychainKey)
            return
        }
        if let data = try? JSONEncoder().encode(tokens) {
            try? KeychainHelper.save(key: keychainKey, data: data)
        }
    }

    private func loadTokens() {
        guard let data = try? KeychainHelper.load(key: keychainKey),
              let t = try? JSONDecoder().decode(Tokens.self, from: data) else { return }
        self.tokens = t
    }

    // MARK: - Helpers

    private func formEncoded(_ params: [String: String]) -> String {
        params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
              .joined(separator: "&")
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

// MARK: - Keychain

enum KeychainHelper {
    static func save(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func load(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return data
    }

    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
