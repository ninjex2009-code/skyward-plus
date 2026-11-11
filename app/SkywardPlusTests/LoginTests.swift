import XCTest

/// A stand-in for a district's Skyward server, covering sign-in and session expiry.
/// The login page mirrors the form a real Skyward login page serves.
final class MiniSkyward: SkywardTransport {
    static let loginPage = """
    <html><head><title>Skyward: Loading page... (05.26.10.00.04-12.8)</title></head><body>
    <form name='detailform' id='detailform' action='' method='post'>
    <input type='text' class='EditInput' name='login' id='login'  autocomplete='off' tabIndex='5' maxlength='50' aria-label='Username' size='28'  aria-labelledby="lblUsername"  />
    <input type='password' class='EditInput' name='password' id='password'  autocomplete='off' tabIndex='10' maxlength='100' size='28' />
    <input type='text' class='EditInput' name='securityCode' id='securityCode'  autocomplete="one-time-code" tabIndex='11' />
    <input type="checkbox" class="" name="cTrustDevice" id="cTrustDevice" tabIndex="11" /><label for="cTrustDevice">Trust This Device</label>
    <a class='button' id='bLoginMFA' href='javascript:if (cbs("bLoginMFA")) {checkSecurityCode();}' role='button'>Sign In</a>
    <a class='button' id='bLogin' tabIndex='15' href='javascript:if (cbs("bLogin")) {tryLogin();}' role='button'>Sign In</a>
    <input type="hidden" name="dwd" id="dwd" value="" />
    <input type="hidden" name="wfaacl" id="wfaacl" value="" />
    <input type="hidden" name="encses" id="encses" value="" />
    <input type="hidden" name="nameid" id="nameid" value="-1" />
    <input type="hidden" name="CurrentProgram" id="CurrentProgram" value="skyportlogin.w" />
    <input type="hidden" name="Browser" id="Browser" value="IE" />
    <input type="hidden" name="duserid" id="duserid" value="-1" />
    <input type="hidden" name="HomePage" id="HomePage" value="sepadm01.w" />
    <input type="hidden" name="hAnon" id="hAnon" value="bjlbYpAByijcxUsV" />
    <input type="hidden" name="web-data-recid" id="web-data-recid" value="" />
    <input type="hidden" name="wfaacl-recid" id="wfaacl-recid" value="" />
    <input type="hidden" name="User-Type" id="User-Type" value="" />
    <input type="hidden" name="showTracker" id="showTracker" value="" />
    <input type="hidden" name="displaySecond" id="displaySecond" value="" />
    <input type="hidden" name="insecure" id="insecure" value="" />
    <input type="hidden" name="redirectTo" id="redirectTo" value="" />
    <input type="hidden" name="enc" id="enc" value="" />
    <input type="hidden" name="hforgotLoginPage" id="hforgotLoginPage" value="seplog01" />
    <input type="hidden" name="userAgent" id="userAgent" value="" />
    <input type="hidden" name="osName" id="osName" value="" />
    <input type="hidden" name="screenWidth" id="screenWidth" value="" />
    </form>
    <form style='display:none;' name='navform' method='post' action='sepadm01.w'>
    <input type="hidden" name="nameid" id="nameid" value="-1" /><input type="hidden" name="dwd" id="dwd" value="" />
    <input type="hidden" name="whereto" id="whereto" value="" />
    </form></body></html>
    """

    private let lock = NSLock()
    private var _log: [SkywardRequest] = []
    private var _cookies: [String: String] = [:]
    private var generation = 0
    private var validEncses: String?

    var user = "jrivera"
    var pass = "p&ss word+1%"
    var requiresMFA = false
    var securityCode = "482913"
    var parent = false

    var log: [SkywardRequest] { lock.lock(); defer { lock.unlock() }; return _log }
    var cookies: [String: String] { lock.lock(); defer { lock.unlock() }; return _cookies }
    func requests(to page: String) -> [SkywardRequest] { log.filter { $0.url.lastPathComponent == page } }

    /// Makes the current session stale, as if it timed out on the server.
    func expireSession() { lock.lock(); validEncses = nil; lock.unlock() }

    func setCookie(name: String, value: String, for url: URL) {
        lock.lock(); _cookies[name] = value; lock.unlock()
    }

    func send(_ request: SkywardRequest) async throws -> SkywardResponse {
        lock.lock()
        _log.append(request)
        lock.unlock()
        let page = request.url.lastPathComponent
        func reply(_ body: String) -> SkywardResponse { SkywardResponse(status: 200, url: request.url, body: body) }

        if request.method == "GET" { return reply(MiniSkyward.loginPage) }

        switch page {
        case "skyporthttp.w":
            guard request.value("requestAction") == "eel", request.value("method") == "extrainfo",
                  request.value("codeType") == "tryLogin", request.value("hAnon") == "bjlbYpAByijcxUsV" else {
                return reply("<li>Malformed request.</li>")
            }
            guard request.value("login") == user, request.value("codeValue") == user, request.value("password") == pass else {
                return reply("<li>Invalid login or password.</li>")
            }
            lock.lock()
            let trusted = _cookies["SkyTrust"] != nil
            lock.unlock()
            if requiresMFA, !trusted, request.value("securityCode") != securityCode {
                return reply("<li>Mfa</li>")
            }
            lock.lock()
            generation += 1
            let encses = "ENC\(generation)x"
            validEncses = encses
            lock.unlock()
            var tokens = "319238^279419^23009402^27834052^58192^s219261^\(parent ? "1" : "2")^sfhome01.w^false^no ^no^no^^zdkNjlfkjbwanfcX^\(encses)"
            if requiresMFA, request.value("cTrustDevice") == "on" { tokens += "^SkyTrust^tr us/t=1" }
            return reply("<li>\(tokens)</li>")

        case "sfhome01.w":
            lock.lock()
            let valid = validEncses
            lock.unlock()
            guard request.value("encses") == valid, request.value("dwd") == "319238", request.value("wfaacl") == "27834052" else {
                return reply("<html><body>Your session has expired and you have been logged out.</body></html>")
            }
            let students = parent
                ? "<div id='sf_StudentList'><a data-nameid='0' href='#'>All Students</a><a data-nameid='58192' href='#'>Jordan Rivera</a><a data-nameid='58193' href='#'>Casey Rivera</a></div>"
                : ""
            return reply("""
            <html><body><div id="sf_UtilityArea"><ul><li class="sf_utilUser notranslate" valign="middle" align="center">Jordan Rivera</li></ul></div>\(students)
            <script data-rel='sff'>sff.sv('sessionid', '279419\u{15}23009402');sff.sv('encses', '\(valid ?? "")');</script></body></html>
            """)

        default:
            lock.lock()
            let valid = validEncses
            lock.unlock()
            guard let valid, request.value("encses") == valid else {
                return reply("<html><body>Your session has expired and you have been logged out.</body></html>")
            }
            return reply("PAGE \(page) for \(request.value("studentId") ?? "self")")
        }
    }
}

final class LoginTests: XCTestCase {
    private func makeSession(_ server: MiniSkyward, url: String = "https://skyward.iscorp.com/p12comexampletx/web/seplog01.w") -> SkywardSession {
        SkywardSession(endpoint: SkywardEndpoint.parse(url)!, transport: server)
    }

    func testEndpointParsing() {
        let a = SkywardEndpoint.parse("https://skyward.iscorp.com/p12comexampletx/web/seplog01.w")
        XCTAssertEqual(a?.base.absoluteString, "https://skyward.iscorp.com/p12comexampletx/web/")
        XCTAssertEqual(a?.loginPage, "seplog01.w")
        XCTAssertEqual(a?.url("skyporthttp.w").absoluteString, "https://skyward.iscorp.com/p12comexampletx/web/skyporthttp.w")
        XCTAssertEqual(a?.url("httploader.p?file=sfgradebook001.w").absoluteString, "https://skyward.iscorp.com/p12comexampletx/web/httploader.p?file=sfgradebook001.w")

        let b = SkywardEndpoint.parse("skyward.example.org/scripts/wsisa.dll/WService=wsEAplus/fwemnu01.w?x=1")
        XCTAssertEqual(b?.base.absoluteString, "https://skyward.example.org/scripts/wsisa.dll/WService=wsEAplus/")
        XCTAssertEqual(b?.loginPage, "fwemnu01.w")

        let c = SkywardEndpoint.parse("https://skyward.example.org/scripts/wsisa.dll/WService=wsEAplus")
        XCTAssertEqual(c?.base.absoluteString, "https://skyward.example.org/scripts/wsisa.dll/WService=wsEAplus/")
        XCTAssertEqual(c?.loginPage, "seplog01.w")

        let d = SkywardEndpoint.parse("http://skyward.iscorp.com/p12eduexampletx/web/skyportlogin")
        XCTAssertEqual(d?.base.absoluteString, "https://skyward.iscorp.com/p12eduexampletx/web/")
        XCTAssertEqual(d?.loginPage, "skyportlogin")

        XCTAssertEqual(SkywardEndpoint.parse("http://localhost:8787/sky/seplog01.w")?.base.absoluteString, "http://localhost:8787/sky/")
        XCTAssertNil(SkywardEndpoint.parse("   "))
        XCTAssertNil(SkywardEndpoint.parse("not a url"))

        XCTAssertTrue(SkywardEndpoint.looksLikeQmlativ("https://skyward.iscorp.com/LakeTravisTXStu"))
        XCTAssertTrue(SkywardEndpoint.looksLikeQmlativ("https://skyward.iscorp.com/ExampleWIStuStudent/Session/Signin"))
        XCTAssertFalse(SkywardEndpoint.looksLikeQmlativ("https://skyward.iscorp.com/p12comexampletx/web/seplog01.w"))
        XCTAssertFalse(SkywardEndpoint.looksLikeQmlativ("https://x.org/scripts/wsisa.dll/WService=wsEAplus/seplog01.w"))
    }

    func testFormEncoding() {
        XCTAssertEqual(FormEncoding.encode([("a b", "x&y=z+%"), ("sessionid", "279419\u{15}23009402")]),
                       "a%20b=x%26y%3Dz%2B%25&sessionid=279419%1523009402")
    }

    func testLoginOutcomeParsing() {
        XCTAssertEqual(SkywardParser.loginOutcome("<li>Invalid login or password.</li>"), .failure("Invalid login or password."))
        XCTAssertEqual(SkywardParser.loginOutcome("<li>Mfa</li>"), .mfaRequired(hideTrustDevice: false))
        XCTAssertEqual(SkywardParser.loginOutcome("<li>Mfa,HideTrustDevice</li>"), .mfaRequired(hideTrustDevice: true))
        let ok = SkywardParser.loginOutcome("<li>319238^279419^23009402^27834052^58192^s219261^2^sfhome01.w^false^no ^no^no^^zdkNjlfkjbwanfcX^jDWadubjdaCOdEjY</li>")
        guard case .success(let tokens) = ok else { return XCTFail("expected success") }
        XCTAssertEqual(tokens.count, 15)
        XCTAssertEqual(tokens[0], "319238")
        XCTAssertEqual(tokens[3], "27834052")
        XCTAssertEqual(tokens[7], "sfhome01.w")
        XCTAssertEqual(tokens[14], "jDWadubjdaCOdEjY")
        if case .failure = SkywardParser.loginOutcome("<li>a^b^c</li>") {} else { XCTFail("short token lists must fail") }
    }

    func testLoginPageForm() {
        let info = SkywardParser.loginPage(MiniSkyward.loginPage)
        XCTAssertTrue(info.hasPasswordLogin)
        XCTAssertTrue(info.looksLikeSkyward)
        XCTAssertEqual(info.fields.first { $0.name == "hAnon" }?.value, "bjlbYpAByijcxUsV")
        XCTAssertEqual(info.fields.first { $0.name == "cTrustDevice" }?.type, "checkbox")
        // navform's fields stay out, and names are not repeated.
        XCTAssertNil(info.fields.first { $0.name == "whereto" })
        XCTAssertEqual(info.fields.filter { $0.name == "dwd" }.count, 1)
    }

    func testSignInSendsWhatTheLoginPageSends() async throws {
        let server = MiniSkyward()
        let session = makeSession(server)
        let result = try await session.login(username: server.user, password: server.pass)

        XCTAssertEqual(result.home.userName, "Jordan Rivera")
        XCTAssertEqual(result.userType, "2")
        XCTAssertNil(result.deviceCookie)
        let codes = await session.codes
        XCTAssertEqual(codes?.dwd, "319238")
        XCTAssertEqual(codes?.wfaacl, "27834052")
        XCTAssertEqual(codes?.encses, "ENC1x")
        XCTAssertEqual(codes?.sessionid, "279419\u{15}23009402")

        let log = server.log
        XCTAssertEqual(log.map { $0.method + " " + $0.url.lastPathComponent }, ["GET seplog01.w", "POST skyporthttp.w", "POST sfhome01.w"])
        let tryLogin = log[1]
        XCTAssertEqual(tryLogin.form.prefix(4).map { $0.0 }, ["requestAction", "method", "codeType", "codeValue"])
        XCTAssertEqual(tryLogin.value("CurrentProgram"), "skyportlogin.w")
        XCTAssertEqual(tryLogin.value("hforgotLoginPage"), "seplog01")
        XCTAssertNil(tryLogin.value("cTrustDevice"), "an unchecked checkbox is not submitted")
        let home = log[2]
        XCTAssertEqual(home.value("login"), "")
        XCTAssertEqual(home.value("password"), "")
        XCTAssertEqual(home.value("web-data-recid"), "279419")
        XCTAssertEqual(home.value("wfaacl-recid"), "23009402")
        XCTAssertEqual(home.value("nameid"), "58192")
        XCTAssertEqual(home.value("duserid"), "s219261")
        XCTAssertEqual(home.value("User-Type"), "2")
        XCTAssertEqual(home.value("enc"), "zdkNjlfkjbwanfcX")
        XCTAssertEqual(home.value("hAnon"), "bjlbYpAByijcxUsV")
    }

    func testWrongPasswordIsReportedWithSkywardsMessage() async {
        let server = MiniSkyward()
        let session = makeSession(server)
        do {
            try await session.login(username: server.user, password: "nope")
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? SkywardError, .invalidLogin("Invalid login or password."))
        }
        let signedIn = await session.isSignedIn
        XCTAssertFalse(signedIn)
        XCTAssertEqual(server.requests(to: "skyporthttp.w").count, 1, "a failed sign-in is never retried")
    }

    func testSecurityCodeAndTrustedDevice() async throws {
        let server = MiniSkyward()
        server.requiresMFA = true
        let session = makeSession(server)

        do {
            try await session.login(username: server.user, password: server.pass)
            XCTFail("expected a security-code prompt")
        } catch {
            XCTAssertEqual(error as? SkywardError, .mfaRequired(hideTrustDevice: false))
        }
        do {
            try await session.login(username: server.user, password: server.pass, securityCode: "000000")
            XCTFail("expected the code to be rejected")
        } catch {
            XCTAssertEqual(error as? SkywardError, .mfaInvalid)
        }

        let result = try await session.login(username: server.user, password: server.pass, securityCode: "482 913", trustDevice: true)
        XCTAssertEqual(result.deviceCookie?.name, "SkyTrust")
        XCTAssertEqual(result.deviceCookie?.value, "tr%20us/t%3D1")
        XCTAssertEqual(server.cookies["SkyTrust"], "tr%20us/t%3D1")
        XCTAssertEqual(server.requests(to: "skyporthttp.w").last?.value("cTrustDevice"), "on")

        // A trusted device signs in again without a code.
        let again = SkywardSession(endpoint: SkywardEndpoint.parse("https://skyward.iscorp.com/p12comexampletx/web/seplog01.w")!, transport: server)
        await again.restoreDeviceCookie(result.deviceCookie!)
        let second = try await again.login(username: server.user, password: server.pass)
        XCTAssertEqual(second.home.userName, "Jordan Rivera")
    }

    func testExpiredSessionSignsInAgainOnceForConcurrentRequests() async throws {
        let server = MiniSkyward()
        let session = makeSession(server)
        try await session.login(username: server.user, password: server.pass)
        let first = try await session.post("sfgradebook001.w")
        XCTAssertEqual(first, "PAGE sfgradebook001.w for self")

        server.expireSession()
        async let a = session.post("sfgradebook001.w")
        async let b = session.post("sfattendance001.w")
        async let c = session.post("sfacademichistory001.w")
        let pages = try await [a, b, c]
        XCTAssertEqual(pages, ["PAGE sfgradebook001.w for self", "PAGE sfattendance001.w for self", "PAGE sfacademichistory001.w for self"])
        XCTAssertEqual(server.requests(to: "skyporthttp.w").count, 2, "one sign-in at the start, one shared re-sign-in")
        let count = await session.loginCount
        XCTAssertEqual(count, 2)
    }

    func testExpiredSessionWithoutCredentialsFails() async throws {
        let server = MiniSkyward()
        let session = makeSession(server)
        await session.adopt(SkywardSession.Codes(dwd: "1", wfaacl: "2", encses: "stale", sessionid: "3", userType: "2"))
        do {
            _ = try await session.post("sfgradebook001.w")
            XCTFail("expected expiry")
        } catch {
            XCTAssertEqual(error as? SkywardError, .sessionExpired)
        }
    }

    func testParentAccountListsChildrenAndSelectsOne() async throws {
        let server = MiniSkyward()
        server.parent = true
        let session = makeSession(server)
        let result = try await session.login(username: server.user, password: server.pass)
        XCTAssertEqual(result.userType, "1")
        XCTAssertEqual(result.home.children, [ChildAccount(id: "58192", name: "Jordan Rivera"), ChildAccount(id: "58193", name: "Casey Rivera")])
        await session.selectStudent("58193")
        let page = try await session.post("sfgradebook001.w")
        XCTAssertEqual(page, "PAGE sfgradebook001.w for 58193")
    }

    func testPagesThatAreNotSkywardAreRejected() async {
        final class Static: SkywardTransport {
            let body: String
            init(_ body: String) { self.body = body }
            func send(_ request: SkywardRequest) async throws -> SkywardResponse { SkywardResponse(status: 200, url: request.url, body: body) }
            func setCookie(name: String, value: String, for url: URL) {}
        }
        let plain = SkywardSession(endpoint: SkywardEndpoint.parse("https://example.org/login")!, transport: Static("<html><body>Hello</body></html>"))
        do { try await plain.login(username: "a", password: "b"); XCTFail() } catch { XCTAssertEqual(error as? SkywardError, .notSkyward) }

        let qml = SkywardSession(endpoint: SkywardEndpoint.parse("https://skyward.iscorp.com/ExampleTXStu")!, transport: Static("<html><title>Skyward Qmlativ</title></html>"))
        do { try await qml.login(username: "a", password: "b"); XCTFail() } catch { XCTAssertEqual(error as? SkywardError, .qmlativ) }

        let ssoPage = "<html><form name='detailform' id='detailform'><input type='hidden' name='hAnon' value='x'/><a class='button' id='bSSOLogin' href='#'>Login with Google</a></form>skyporthttp</html>"
        let sso = SkywardSession(endpoint: SkywardEndpoint.parse("https://skyward.iscorp.com/p12/web/seplog01.w")!, transport: Static(ssoPage))
        do { try await sso.login(username: "a", password: "b"); XCTFail() } catch { XCTAssertEqual(error as? SkywardError, .ssoOnly("Login with Google")) }
    }
}
