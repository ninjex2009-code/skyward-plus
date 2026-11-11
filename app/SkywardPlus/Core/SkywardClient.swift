import Foundation

// MARK: - Errors

enum SkywardError: Error, Equatable, LocalizedError {
    case invalidLogin(String)
    case mfaRequired(hideTrustDevice: Bool)
    case mfaInvalid
    case ssoOnly(String)
    case qmlativ
    case notSkyward
    case sessionExpired
    case notSignedIn
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidLogin(let message):
            return message
        case .mfaRequired:
            return "Skyward sent a security code. Enter it to finish signing in."
        case .mfaInvalid:
            return "That security code was not accepted."
        case .ssoOnly(let label):
            return "This district signs in through \(label.isEmpty ? "single sign-on" : label). Use Web sign-in instead."
        case .qmlativ:
            return "This district uses Skyward's newer Qmlativ system, which Skyward Plus cannot sign in to directly yet."
        case .notSkyward:
            return "That page does not look like a Skyward Family or Student Access login page. Check the address."
        case .sessionExpired:
            return "Your Skyward session ended. Sign in again."
        case .notSignedIn:
            return "Not signed in."
        case .network(let message):
            return "Could not reach Skyward. \(message)"
        case .server(let message):
            return message
        }
    }
}

// MARK: - Transport

struct SkywardRequest {
    var method = "POST"
    var url: URL
    var form: [(String, String)] = []
    var headers: [String: String] = [:]

    func value(_ name: String) -> String? { form.first { $0.0 == name }?.1 }
}

struct SkywardResponse {
    var status: Int
    var url: URL
    var body: String
}

/// Where requests go. The real one talks to the district's server; the demo and
/// the tests swap in a fake that answers with Skyward-shaped pages.
protocol SkywardTransport: AnyObject {
    func send(_ request: SkywardRequest) async throws -> SkywardResponse
    func setCookie(name: String, value: String, for url: URL)
}

enum FormEncoding {
    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// What JavaScript's `escape()` produces. Skyward's login page stores its
    /// trusted-device cookie through it, so the cookie value has to match.
    static func jsEscape(_ value: String) -> String {
        var out = ""
        for scalar in value.unicodeScalars {
            let v = scalar.value
            let plain = (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || "@*_+-./".unicodeScalars.contains(scalar)
            if plain { out.unicodeScalars.append(scalar) }
            else if v < 256 { out += String(format: "%%%02X", v) }
            else { out += String(format: "%%u%04X", v) }
        }
        return out
    }

    /// `application/x-www-form-urlencoded`. Skyward's session id carries a 0x15
    /// control character, which must go out as %15.
    static func encode(_ pairs: [(String, String)]) -> String {
        pairs.map { escape($0.0) + "=" + escape($0.1) }.joined(separator: "&")
    }
}

final class URLSessionTransport: SkywardTransport {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    private let session: URLSession
    private let cookies: HTTPCookieStorage?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpAdditionalHeaders = ["User-Agent": URLSessionTransport.userAgent, "Accept-Language": "en-US,en;q=0.9"]
        cookies = config.httpCookieStorage
        session = URLSession(configuration: config)
    }

    func send(_ request: SkywardRequest) async throws -> SkywardResponse {
        var r = URLRequest(url: request.url)
        r.httpMethod = request.method
        for (name, value) in request.headers { r.setValue(value, forHTTPHeaderField: name) }
        if request.method != "GET" {
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            r.httpBody = Data(FormEncoding.encode(request.form).utf8)
        }
        do {
            let (data, response) = try await session.data(for: r)
            let http = response as? HTTPURLResponse
            return SkywardResponse(status: http?.statusCode ?? 200, url: response.url ?? request.url, body: URLSessionTransport.decode(data))
        } catch let error as URLError {
            throw SkywardError.network(error.localizedDescription)
        }
    }

    /// Skyward serves ISO-8859-1. Bytes that are not valid UTF-8 are read as Latin-1.
    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
    }

    func setCookie(name: String, value: String, for url: URL) {
        guard let host = url.host else { return }
        var path = url.path
        if !path.hasSuffix("/") { path = (path as NSString).deletingLastPathComponent }
        if path.isEmpty { path = "/" }
        let properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: host, .path: path,
            .expires: Date().addingTimeInterval(400 * 86_400),
        ]
        if let cookie = HTTPCookie(properties: properties) { cookies?.setCookie(cookie) }
    }
}

// MARK: - Address handling

/// A district's Skyward address split into the folder its pages live in and the login page name.
struct SkywardEndpoint: Codable, Equatable {
    var base: URL            // always ends in "/"
    var loginPage: String    // "seplog01.w", "fwemnu01.w", "skyportlogin" ...

    var loginURL: URL { url(loginPage) }
    var isQmlativ: Bool {
        SkywardEndpoint.looksLikeQmlativ(base.absoluteString) || SkywardEndpoint.looksLikeQmlativ(loginURL.absoluteString)
    }

    func url(_ page: String) -> URL {
        URL(string: page, relativeTo: base)?.absoluteURL ?? base.appendingPathComponent(page)
    }

    /// Accepts what people paste: with or without https://, with or without the page name.
    static func parse(_ input: String) -> SkywardEndpoint? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var comps = URLComponents(string: text), let host = comps.host, host.contains(".") || host == "localhost" else { return nil }
        comps.query = nil
        comps.fragment = nil
        let local = host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".localhost") || host.hasSuffix(".test")
        if comps.scheme?.lowercased() == "http", !local { comps.scheme = "https" }

        if looksLikeQmlativ(text) {
            let parts = comps.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            if var first = parts.first {
                if first.lowercased().hasSuffix("stusts") {
                    first = String(first.dropLast(3))
                }
                comps.percentEncodedPath = "/" + first + "/"
                if let base = comps.url {
                    return SkywardEndpoint(base: base, loginPage: "Home/Home/Index")
                }
            }
        }

        var path = comps.percentEncodedPath
        if path.isEmpty { path = "/" }
        var page = ""
        if !path.hasSuffix("/") {
            let last = String(path.split(separator: "/", omittingEmptySubsequences: true).last ?? "")
            let lower = last.lowercased()
            let isFolder = lower.contains("wservice=") || lower == "web" || lower.hasSuffix(".dll") || lower.hasSuffix(".exe")
            if isFolder {
                path += "/"
            } else {
                page = last
                path = String(path.dropLast(last.count))
            }
        }
        comps.percentEncodedPath = path
        guard let base = comps.url else { return nil }
        return SkywardEndpoint(base: base, loginPage: page.isEmpty ? "seplog01.w" : page)
    }

    /// Qmlativ addresses look like https://skyward.iscorp.com/DistrictNameSTU/... and
    /// have none of the classic markers.
    static func looksLikeQmlativ(_ input: String) -> Bool {
        let lower = input.lowercased()
        if lower.contains("wsisa") || lower.contains("/web/") || lower.contains(".w") && !lower.contains(".w/") && lower.hasSuffix(".w") { return false }
        if lower.contains("qmlativ") || lower.contains("/session/signin") { return true }
        guard let comps = URLComponents(string: lower.contains("://") ? lower : "https://" + lower) else { return false }
        let parts = comps.path.split(separator: "/").map(String.init)
        guard let first = parts.first else { return false }
        return first.hasSuffix("stu") || first.hasSuffix("stusts") || first.hasSuffix("student") || first.contains("stustudent")
    }
}

// MARK: - Session

/// One signed-in Skyward session. Signing in follows what the district's own
/// login page does: read the page's form, post it to `skyporthttp.w`, then post
/// the form with the returned codes to the home page.
actor SkywardSession {
    struct Codes: Codable, Equatable {
        var dwd = ""
        var wfaacl = ""
        var encses = ""
        var sessionid = ""
        var userType = ""
        var nameid = ""
        var duserid = ""
    }

    struct DeviceCookie: Codable, Equatable {
        var name: String
        var value: String
    }

    struct LoginResult {
        var home: SkywardParser.HomeInfo
        var deviceCookie: DeviceCookie?
        var userType: String
    }

    private(set) var endpoint: SkywardEndpoint
    private let transport: SkywardTransport
    private(set) var codes: Codes?
    private var username = ""
    private var password = ""
    private var hasCredentials = false
    private var studentID: String?
    private var relogin: Task<Void, Error>?
    private(set) var loginCount = 0

    init(endpoint: SkywardEndpoint, transport: SkywardTransport) {
        self.endpoint = endpoint
        self.transport = transport
    }

    var isSignedIn: Bool { codes != nil }

    /// Selects a child on a parent account. Nil means the account's own student.
    func selectStudent(_ id: String?) { studentID = id }

    /// A device Skyward already trusts skips the security-code step.
    func restoreDeviceCookie(_ cookie: DeviceCookie) {
        transport.setCookie(name: cookie.name, value: cookie.value, for: endpoint.loginURL)
    }

    /// Lets later requests sign in again on their own when the session times out.
    func remember(username: String, password: String) {
        self.username = username
        self.password = password
        hasCredentials = true
    }

    /// Uses codes obtained elsewhere (web sign-in).
    func adopt(_ codes: Codes) { self.codes = codes }

    func signOut() {
        codes = nil
        hasCredentials = false
        username = ""
        password = ""
    }

    // MARK: Sign-in

    @discardableResult
    func login(username: String, password: String, securityCode: String? = nil, trustDevice: Bool = false) async throws -> LoginResult {
        let page = try await transport.send(SkywardRequest(method: "GET", url: endpoint.loginURL))
        if page.status >= 400 {
            throw SkywardError.server("Skyward answered with an error (HTTP \(page.status)). Check the address.")
        }
        // Follow a redirect to the folder the pages really live in (except when redirected to Qmlativ's STS login service).
        let finalFolder = page.url.deletingLastPathComponent()
        if !SkywardEndpoint.looksLikeQmlativ(page.url.absoluteString),
           finalFolder.host != nil, finalFolder.absoluteString.hasSuffix("/"),
           finalFolder != endpoint.base, page.url.lastPathComponent.isEmpty == false {
            endpoint.base = finalFolder
        }

        let info = SkywardParser.loginPage(page.body)
        if info.fields.isEmpty {
            if page.body.range(of: "qmlativ", options: .caseInsensitive) != nil
                || SkywardEndpoint.looksLikeQmlativ(page.url.absoluteString)
                || endpoint.isQmlativ {
                throw SkywardError.qmlativ
            }
            throw SkywardError.notSkyward
        }
        guard info.hasPasswordLogin else {
            if info.hasSSO { throw SkywardError.ssoOnly(info.ssoLabel) }
            throw SkywardError.notSkyward
        }

        var fields: [(String, String)] = info.fields.filter { $0.type != "checkbox" }.map { ($0.name, $0.value) }
        func set(_ name: String, _ value: String) {
            if let index = fields.firstIndex(where: { $0.0 == name }) {
                fields[index].1 = value
            } else {
                fields.append((name, value))
            }
        }
        set("login", username)
        set("password", password)
        if fields.contains(where: { $0.0 == "securityCode" }) || securityCode != nil {
            set("securityCode", (securityCode ?? "").replacingOccurrences(of: " ", with: ""))
        }
        if securityCode != nil, trustDevice { fields.append(("cTrustDevice", "on")) }
        set("userAgent", URLSessionTransport.userAgent)
        set("osName", "Mac OS X")
        set("brwsInfo", "Safari 17")
        set("subversion", "17")
        set("supported", "true")
        set("screenWidth", "1440")
        set("screenHeight", "900")

        let tryLogin: [(String, String)] = [
            ("requestAction", "eel"), ("method", "extrainfo"), ("codeType", "tryLogin"), ("codeValue", username),
        ] + fields
        loginCount += 1
        let reply = try await transport.send(SkywardRequest(method: "POST", url: endpoint.url("skyporthttp.w"), form: tryLogin))

        let tokens: [String]
        switch SkywardParser.loginOutcome(reply.body) {
        case .failure(let message):
            throw SkywardError.invalidLogin(message)
        case .mfaRequired(let hide):
            if securityCode == nil { throw SkywardError.mfaRequired(hideTrustDevice: hide) }
            throw SkywardError.mfaInvalid
        case .success(let list):
            tokens = list
        }

        var deviceCookie: DeviceCookie?
        if tokens.count > 16, !tokens[15].isEmpty, !tokens[16].isEmpty {
            let cookie = DeviceCookie(name: tokens[15], value: FormEncoding.jsEscape(tokens[16]))
            transport.setCookie(name: cookie.name, value: cookie.value, for: endpoint.loginURL)
            deviceCookie = cookie
        }

        // The login page fills these into its form and submits it to the home page.
        set("login", "")
        set("password", "")
        set("securityCode", "")
        fields.removeAll { $0.0 == "cTrustDevice" }
        set("dwd", tokens[0])
        set("web-data-recid", tokens[1])
        set("wfaacl-recid", tokens[2])
        set("wfaacl", tokens[3])
        set("nameid", tokens[4])
        set("duserid", tokens[5])
        set("User-Type", tokens[6])
        set("showTracker", tokens[8])
        set("displaySecond", tokens[10])
        set("insecure", tokens[11])
        set("redirectTo", tokens[12])
        set("enc", tokens[13])
        set("encses", tokens[14])
        let homePage = tokens[7].trimmingCharacters(in: .whitespaces).isEmpty ? "sfhome01.w" : tokens[7].trimmingCharacters(in: .whitespaces)

        let home = try await transport.send(SkywardRequest(method: "POST", url: endpoint.url(homePage), form: fields))
        if home.status >= 400 {
            throw SkywardError.server("Skyward accepted the sign-in but would not open the home page (HTTP \(home.status)).")
        }
        let homeInfo = SkywardParser.home(home.body)

        codes = Codes(
            dwd: tokens[0],
            wfaacl: tokens[3],
            encses: homeInfo.encses ?? tokens[14],
            sessionid: homeInfo.sessionID ?? (tokens[1] + "\u{15}" + tokens[2]),
            userType: tokens[6],
            nameid: tokens[4],
            duserid: tokens[5]
        )
        self.username = username
        self.password = password
        hasCredentials = true
        return LoginResult(home: homeInfo, deviceCookie: deviceCookie, userType: tokens[6])
    }

    // MARK: Pages

    /// Posts to a Skyward page with the session codes. When the session has timed
    /// out it signs in again once and retries; concurrent callers share that sign-in.
    func post(_ page: String, extra: [(String, String)] = []) async throws -> String {
        for attempt in 0..<2 {
            guard let codes else { throw SkywardError.notSignedIn }
            var form: [(String, String)] = [
                ("dwd", codes.dwd), ("wfaacl", codes.wfaacl), ("encses", codes.encses),
                ("sessionid", codes.sessionid), ("User-Type", codes.userType),
            ]
            if let studentID { form.append(("studentId", studentID)) }
            form.append(contentsOf: extra)
            let response = try await transport.send(SkywardRequest(method: "POST", url: endpoint.url(page), form: form))
            if response.status >= 500 {
                throw SkywardError.server("Skyward answered with an error (HTTP \(response.status)).")
            }
            if !SkywardParser.isSessionExpired(response.body) { return response.body }
            guard attempt == 0, hasCredentials else { throw SkywardError.sessionExpired }
            try await refresh(staleEncses: codes.encses)
        }
        throw SkywardError.sessionExpired
    }

    private func refresh(staleEncses: String) async throws {
        if let current = codes, current.encses != staleEncses { return }
        if let running = relogin {
            try await running.value
            return
        }
        let user = username, pass = password
        let task = Task { _ = try await self.login(username: user, password: pass) }
        relogin = task
        defer { relogin = nil }
        try await task.value
    }

    func home() async throws -> SkywardParser.HomeInfo {
        return SkywardParser.home(try await post("sfhome01.w"))
    }

    func gradebookPage() async throws -> String {
        return try await post("sfgradebook001.w")
    }

    /// The assignment list behind one grade cell.
    func gradeDetailPage(course: Course, bucket: String) async throws -> String {
        let extra: [(String, String)] = [
            ("action", "viewGradeInfoDialog"), ("gridCount", "1"), ("fromHttp", "yes"),
            ("stuId", course.studentID), ("entityId", course.entityID), ("corNumId", course.cni),
            ("track", course.track), ("section", course.section), ("gbId", course.gid),
            ("bucket", bucket), ("subjectId", ""), ("dialogLevel", "1"), ("isEoc", course.isEoc),
            ("ishttp", "true"), ("requestId", String(Int(Date().timeIntervalSince1970 * 1000))),
        ]
        let body = try await post("httploader.p?file=sfgradebook001.w", extra: extra)
        if body.contains("grid_stuAssignmentSummaryGrid") || body.contains("gb_heading") { return body }
        // Older servers answer the same action on the gradebook page itself.
        return try await post("sfgradebook001.w", extra: [
            ("action", "viewGradeInfoDialog"), ("fromHttp", "yes"), ("ishttp", "true"),
            ("corNumId", course.cni), ("bucket", bucket), ("gbId", course.gid), ("section", course.section),
        ])
    }

    func assignmentInfoPage(assignmentID: String, gradebookID: String, studentID: String) async throws -> String {
        return try await post("sfdialogs.w", extra: [
            ("action", "dialog"), ("ishttp", "true"), ("assignId", assignmentID),
            ("gbId", gradebookID), ("type", "assignment"), ("student", studentID),
        ])
    }

    func historyPage() async throws -> String {
        return try await post("sfacademichistory001.w")
    }

    func attendancePage() async throws -> String {
        return try await post("sfattendance001.w")
    }

    func studentInfoPage() async throws -> String {
        return try await post("sfstudentinfo001.w")
    }
}
