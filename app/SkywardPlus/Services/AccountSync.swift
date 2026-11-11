import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

/// The optional Skyward Plus account: "Continue with Google", then the planner,
/// done marks, goals and look stay the same on every device.
///
/// It talks to the user's own Firebase project over its REST APIs (no SDK):
/// Google sign-in with PKCE in the system sign-in sheet, Firebase Auth to turn the
/// Google token into a Firebase session, and the Realtime Database for the data. Grades never
/// leave the device.
@MainActor @Observable
final class AccountSync {
    static let shared = AccountSync()

    private(set) var email: String?
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private(set) var isSigningIn = false

    var isConfigured: Bool { config != nil }
    var isSignedIn: Bool { session != nil }

    private let config = Config.load()
    private var session: Session? {
        didSet { email = session?.email }
    }
    private var pending: Task<Void, Never>?
    private var applying = false
    private weak var model: AppModel?
    private let presenter = Presenter()

    private init() {
        session = Session.load()
        email = session?.email
    }

    // MARK: Sign in and out

    func signIn(model: AppModel) async {
        guard let config, !isSigningIn else { return }
        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }
        do {
            let google = try await googleSignIn(config: config)
            let firebase = try await firebaseSignIn(config: config, googleIDToken: google)
            session = firebase
            firebase.save()
            await sync(model: model)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Closed the sheet: nothing to report.
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        pending?.cancel()
        session = nil
        Session.clear()
        Base.clearAll()
        lastSync = nil
        lastError = nil
    }

    // MARK: Syncing

    /// Called whenever the model saves; syncs a few seconds after the last change.
    func modelChanged(_ model: AppModel) {
        self.model = model
        guard isSignedIn, !applying else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.sync(model: model)
        }
    }

    /// Pulls, merges and pushes the look and the active student's planner data.
    func sync(model: AppModel) async {
        self.model = model
        guard let config, session != nil, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await idToken(config: config)
            guard let uid = session?.uid else { return }

            // The look, shared by every student on the account.
            let lookPath = "users/\(uid)/meta/look"
            let remoteLook: Look? = try await Database.get(config: config, path: lookPath, token: token)
            let localLook = Look(model.settings)
            let mergedLook = Merge.value(local: localLook, remote: remoteLook, base: Base.load(Look.self, key: "look"))
            if mergedLook != localLook { apply { mergedLook.apply(to: model) } }
            if mergedLook != remoteLook { try await Database.put(config: config, path: lookPath, token: token, value: mergedLook) }
            Base.save(mergedLook, key: "look")

            // The active student's planner, done marks and goals.
            if let profile = model.active, !profile.isDemo || Self.syncDemoForTesting {
                let key = Self.studentKey(profile)
                let path = "users/\(uid)/students/\(key)"
                let remote: StudentData? = try await Database.get(config: config, path: path, token: token)
                let local = StudentData(model.prefs)
                let merged = StudentData.merge(local: local, remote: remote, base: Base.load(StudentData.self, key: key))
                if merged != local { apply { model.updatePrefs { merged.apply(to: &$0) } } }
                if merged != remote { try await Database.put(config: config, path: path, token: token, value: merged) }
                Base.save(merged, key: key)
            }
            lastSync = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Changes from the server shouldn't immediately schedule another sync.
    private func apply(_ change: () -> Void) {
        applying = true
        change()
        applying = false
    }

    /// Test builds sync the sample student too, so sync can be checked without a real account.
    static var syncDemoForTesting: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// The same student on two devices: their district address and Skyward name.
    static func studentKey(_ profile: Profile) -> String {
        Str.hash(profile.address.lowercased(), (profile.skywardName.isEmpty ? profile.username : profile.skywardName).lowercased())
    }

    // MARK: Google

    private func googleSignIn(config: Config) async throws -> String {
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomString(24)
        let redirect = config.reversedClientID + ":/oauth2redirect"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "select_account"),
        ]
        let callback = try await presenter.authenticate(url: components.url!, scheme: config.reversedClientID)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw AccountError("Google didn't finish signing in.")
        }
        let response: GoogleToken = try await HTTP.form("https://oauth2.googleapis.com/token", [
            "code": code, "client_id": config.clientID, "redirect_uri": redirect,
            "grant_type": "authorization_code", "code_verifier": verifier,
        ])
        guard let idToken = response.id_token else { throw AccountError("Google didn't return an account.") }
        return idToken
    }

    // MARK: Firebase Auth

    private func firebaseSignIn(config: Config, googleIDToken: String) async throws -> Session {
        struct Body: Encodable {
            let postBody: String
            let requestUri = "http://localhost"
            let returnSecureToken = true
            let returnIdpCredential = true
        }
        struct Reply: Decodable { let idToken: String; let refreshToken: String; let localId: String; let email: String?; let expiresIn: String }
        let reply: Reply = try await HTTP.json(
            "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(config.apiKey)",
            body: Body(postBody: "id_token=\(googleIDToken)&providerId=google.com")
        )
        return Session(uid: reply.localId, email: reply.email, refreshToken: reply.refreshToken,
                       idToken: reply.idToken, expires: Date().addingTimeInterval(Double(reply.expiresIn) ?? 3600))
    }

    /// A current Firebase ID token, refreshed when it is about to expire.
    private func idToken(config: Config) async throws -> String {
        guard var current = session else { throw AccountError("Not signed in.") }
        if let token = current.idToken, let expires = current.expires, expires > Date().addingTimeInterval(120) {
            return token
        }
        struct Reply: Decodable { let id_token: String; let refresh_token: String; let expires_in: String; let user_id: String }
        do {
            let reply: Reply = try await HTTP.form("https://securetoken.googleapis.com/v1/token?key=\(config.apiKey)", [
                "grant_type": "refresh_token", "refresh_token": current.refreshToken,
            ])
            current.idToken = reply.id_token
            current.refreshToken = reply.refresh_token
            current.expires = Date().addingTimeInterval(Double(reply.expires_in) ?? 3600)
            session = current
            current.save()
            return reply.id_token
        } catch HTTP.Failure.status(let code, _) where code == 400 {
            // The account was removed or the session revoked: sign out cleanly.
            signOut()
            throw AccountError("Your account session ended. Sign in again to keep syncing.")
        }
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

// MARK: - What syncs

/// The look and app-wide preferences. Window and device settings stay per device.
struct Look: Codable, Equatable {
    var theme: BackgroundTheme
    var gradeStyle: GradeStyle
    var colorBubbles: Bool
    var notifyNewGrades: Bool
    var notifyDueTomorrow: Bool
    var notifyBelowGoal: Bool

    @MainActor init(_ settings: AppSettings) {
        theme = settings.backgroundTheme
        gradeStyle = settings.gradeStyle
        colorBubbles = settings.colorBubbles
        notifyNewGrades = settings.notifyNewGrades
        notifyDueTomorrow = settings.notifyDueTomorrow
        notifyBelowGoal = settings.notifyBelowGoal
    }

    @MainActor func apply(to model: AppModel) {
        model.updateSettings {
            $0.backgroundTheme = theme
            $0.gradeStyle = gradeStyle
            $0.colorBubbles = colorBubbles
            $0.notifyNewGrades = notifyNewGrades
            $0.notifyDueTomorrow = notifyDueTomorrow
            $0.notifyBelowGoal = notifyBelowGoal
        }
    }
}

extension AccountSync {
    /// One student's planner, ticks, goals, class order and GPA choices.
    struct StudentData: Codable, Equatable {
        var tasks: [UUID: PlannerTask]
        var done: Set<String>
        var goals: [String: Double]
        var courseOrder: [String]
        var hiddenCourses: Set<String>

        init(_ prefs: ProfilePrefs) {
            tasks = Dictionary(prefs.tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            done = prefs.doneAssignments
            goals = prefs.goals
            courseOrder = prefs.courseOrder
            hiddenCourses = prefs.hiddenCourses
        }

        func apply(to prefs: inout ProfilePrefs) {
            prefs.tasks = tasks.values.sorted { $0.createdAt < $1.createdAt }
            prefs.doneAssignments = done
            prefs.goals = goals
            prefs.courseOrder = courseOrder
            prefs.hiddenCourses = hiddenCourses
        }

        /// A three-way merge against what this device last synced: a change made
        /// on either side since then is kept; when both changed the same thing,
        /// this device wins. With no history yet, the two are combined.
        static func merge(local: StudentData, remote: StudentData?, base: StudentData?) -> StudentData {
            guard let remote else { return local }
            return StudentData(
                tasks: Merge.map(local: local.tasks, remote: remote.tasks, base: base?.tasks),
                done: Merge.set(local: local.done, remote: remote.done, base: base?.done),
                goals: Merge.map(local: local.goals, remote: remote.goals, base: base?.goals),
                courseOrder: Merge.value(local: local.courseOrder, remote: remote.courseOrder, base: base?.courseOrder),
                hiddenCourses: Merge.set(local: local.hiddenCourses, remote: remote.hiddenCourses, base: base?.hiddenCourses)
            )
        }

        private init(tasks: [UUID: PlannerTask], done: Set<String>, goals: [String: Double], courseOrder: [String], hiddenCourses: Set<String>) {
            self.tasks = tasks
            self.done = done
            self.goals = goals
            self.courseOrder = courseOrder
            self.hiddenCourses = hiddenCourses
        }
    }
}

// MARK: - Plumbing

struct AccountError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension AccountSync {
    /// The values from GoogleService-Info.plist in the app bundle.
    struct Config {
        let apiKey: String
        let clientID: String
        let reversedClientID: String
        let projectID: String
        /// The Realtime Database, e.g. https://name-default-rtdb.firebaseio.com
        let databaseURL: String

        static func load() -> Config? {
            guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
                  let dict = NSDictionary(contentsOf: url) as? [String: Any],
                  let apiKey = dict["API_KEY"] as? String,
                  let clientID = dict["CLIENT_ID"] as? String,
                  let reversed = dict["REVERSED_CLIENT_ID"] as? String,
                  let project = dict["PROJECT_ID"] as? String else { return nil }
            // Older settings files leave the database out; this is its default address.
            let database = (dict["DATABASE_URL"] as? String) ?? "https://\(project)-default-rtdb.firebaseio.com"
            return Config(apiKey: apiKey, clientID: clientID, reversedClientID: reversed, projectID: project,
                          databaseURL: database.hasSuffix("/") ? String(database.dropLast()) : database)
        }
    }

    /// The Firebase session, kept in the Keychain.
    struct Session: Codable {
        var uid: String
        var email: String?
        var refreshToken: String
        var idToken: String?
        var expires: Date?

        private static let key = "account|firebase"

        static func load() -> Session? {
            guard let secret = Keychain.load(key), let data = secret.password.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(Session.self, from: data)
        }

        func save() {
            guard let data = try? JSONEncoder().encode(self), let text = String(data: data, encoding: .utf8) else { return }
            _ = Keychain.save(AccountSecret(password: text, deviceCookie: nil), for: Session.key)
        }

        static func clear() { Keychain.remove(key) }
    }

    /// What this device last synced, per document, for three-way merges.
    enum Base {
        private static var folder: URL {
            let base = ProcessInfo.processInfo.environment["SKYWARDPLUS_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SkywardPlus", isDirectory: true)
            return base.appendingPathComponent("sync", isDirectory: true)
        }

        static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(key + ".json")) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }

        static func save<T: Encodable>(_ value: T, key: String) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? JSONEncoder().encode(value).write(to: folder.appendingPathComponent(key + ".json"), options: .atomic)
        }

        static func clearAll() { try? FileManager.default.removeItem(at: folder) }
    }

    struct GoogleToken: Decodable { let id_token: String? }

    /// Realtime Database over REST. Each synced value is stored as one JSON string
    /// (so keys never trip the database's rules about '.', '#', '$', '/' in names).
    enum Database {
        private static func url(_ config: Config, _ path: String, token: String) -> String {
            "\(config.databaseURL)/\(path).json?auth=\(token)"
        }

        static func get<T: Decodable>(config: Config, path: String, token: String) async throws -> T? {
            let stored: StoredValue? = try await HTTP.json(url(config, path, token: token), method: "GET", body: Optional<String>.none)
            guard let text = stored?.payload, let data = text.data(using: .utf8) else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        }

        static func put<T: Encodable>(config: Config, path: String, token: String, value: T) async throws {
            let text = String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? "{}"
            let _: IgnoredReply = try await HTTP.json(url(config, path, token: token), method: "PUT",
                                                      body: StoredBody(payload: text, modified: Date().timeIntervalSince1970))
        }
    }

    struct StoredValue: Decodable { let payload: String? }
    struct StoredBody: Encodable { let payload: String; let modified: Double }
    struct IgnoredReply: Decodable {}

    /// Firebase answers errors as {"error": "text"} or {"error": {"message": "text"}}.
    enum ErrorReply {
        static func message(from data: Data) -> String {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
            if let text = object["error"] as? String { return text }
            if let inner = object["error"] as? [String: Any], let text = inner["message"] as? String { return text }
            return ""
        }
    }

    enum HTTP {
        enum Failure: LocalizedError {
            case status(Int, String)
            var errorDescription: String? {
                switch self {
                case .status(let code, let message): return message.isEmpty ? "The sync server answered \(code)." : message
                }
            }
        }

        static func json<B: Encodable, R: Decodable>(_ url: String, method: String = "POST", token: String? = nil, body: B?) async throws -> R {
            var request = URLRequest(url: URL(string: url)!)
            request.httpMethod = method
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(body)
            }
            return try await send(request)
        }

        static func form<R: Decodable>(_ url: String, _ fields: [String: String]) async throws -> R {
            var request = URLRequest(url: URL(string: url)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&=+")
            request.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
                .joined(separator: "&").data(using: .utf8)
            return try await send(request)
        }

        private static func send<R: Decodable>(_ request: URLRequest) async throws -> R {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                let message = ErrorReply.message(from: data)
                throw Failure.status(code, message)
            }
            let body = data.isEmpty ? Data("null".utf8) : data
            return try JSONDecoder().decode(R.self, from: body)
        }
    }

    /// Shows Google's page in the system sign-in sheet.
    final class Presenter: NSObject, ASWebAuthenticationPresentationContextProviding {
        @MainActor
        func authenticate(url: URL, scheme: String) async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                    if let callback { continuation.resume(returning: callback) }
                    else { continuation.resume(throwing: error ?? AccountError("Sign-in didn't finish.")) }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                if !session.start() { continuation.resume(throwing: AccountError("Couldn't open the sign-in sheet.")) }
            }
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated {
                #if os(macOS)
                return NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? ASPresentationAnchor()
                #else
                let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first ?? ASPresentationAnchor()
                #endif
            }
        }
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Settings UI

/// The Account page in Settings.
struct AccountSettingsSection: View {
    @Environment(AppModel.self) private var model
    private var account: AccountSync { AccountSync.shared }

    var body: some View {
        if !account.isConfigured {
            SettingsGroup {
                SettingRow(title: "Account sync isn't set up in this build") { EmptyView() }
            }
        } else if let email = account.email {
            SettingsGroup(footer: "Your planner, done marks, goals and theme stay the same on every device. Grades stay on this device.") {
                SettingRow(title: "Signed in as") { Text(email).foregroundStyle(.secondary).lineLimit(1) }
                SettingRow(title: "Last synced") {
                    if account.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(account.lastSync.map { Fmt.ago($0, now: model.now()) } ?? "Not yet").foregroundStyle(.secondary)
                    }
                }
                if let error = account.lastError {
                    Text(error).foregroundStyle(Palette.bad).padding(.horizontal, 4)
                }
                ActionRow(title: "Sync Now") { Task { await account.sync(model: model) } }
                    .disabled(account.isSyncing)
            }
            SettingsGroup {
                ActionRow(title: "Sign Out", role: .destructive) { account.signOut() }
            }
        } else {
            SettingsGroup(footer: "Keeps your planner, done marks, goals and theme the same on every device. Grades stay on this device.") {
                GoogleButton()
                if let error = account.lastError {
                    Text(error).foregroundStyle(Palette.bad).padding(.horizontal, 4)
                }
            }
        }
    }
}

/// The one way to sign in: a big, plain "Continue with Google" button.
struct GoogleButton: View {
    @Environment(AppModel.self) private var model
    var onSignedIn: () -> Void = {}

    var body: some View {
        let account = AccountSync.shared
        Button {
            Task {
                await account.signIn(model: model)
                if account.isSignedIn { onSignedIn() }
            }
        } label: {
            HStack(spacing: 10) {
                if account.isSigningIn {
                    ProgressView().controlSize(.small)
                } else {
                    Text("G")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color(hex: 0x4285F4), in: Circle())
                }
                Text("Continue with Google")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.primary)
            .surface(cornerRadius: 16, hoverable: true)
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(BubbleButtonStyle())
        .disabled(account.isSigningIn || !account.isConfigured)
    }
}
