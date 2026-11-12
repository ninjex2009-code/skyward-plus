import Foundation
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class QmlativEngine: NSObject, WKNavigationDelegate, WKUIDelegate {
    let base: URL
    let webView: WKWebView

    #if os(macOS)
    private let hiddenWindow: NSWindow
    #endif

    private var navContinuation: CheckedContinuation<Void, Never>?
    /// How wide the web view was when the current page finished loading. Skyward
    /// sets up a narrow layout for a narrow first load and keeps it, so a page
    /// loaded while shown in a phone-sized sign-in view must be reloaded before use.
    private var loadedWidth: CGFloat = 0

    /// True when the page was last loaded at phone width (the iPhone sign-in view).
    var loadedNarrow: Bool { loadedWidth > 0 && loadedWidth < 900 }
    private var navTimeoutTask: Task<Void, Never>?
    private var queueTail: Task<Void, Never>?

    init(base: URL) {
        let normalizedBase: URL = {
            var str = base.absoluteString
            if !str.hasSuffix("/") { str += "/" }
            return URL(string: str) ?? base
        }()
        self.base = normalizedBase

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let controller = WKUserContentController()
        #if os(iOS)
        // The engine's web view is hidden and driven by script, and we send a Mac
        // Safari user agent. Skyward switches to touch handling when the browser
        // reports touch input, which an iPhone always does; hide it on Skyward's own
        // pages so they behave exactly as on the Mac. (Sign-in pages are untouched.)
        let host = (normalizedBase.host ?? "") + (normalizedBase.port.map { ":\($0)" } ?? "")
        controller.addUserScript(WKUserScript(
            source: """
            (function () {
              if (location.host !== \(Self.jsString(host))) return;
              // An iPhone lays a page with no viewport tag out 980 wide, however large
              // the web view is. Skyward only opens the assignments side panel on a page
              // at least 1200 wide; on a narrower one a click opens a separate window,
              // which this hidden view can't use. Ask for the view's full desktop width.
              // Pages with their own viewport tag (the sign-in page) keep theirs: it
              // comes later in the page and replaces this one.
              try {
                const viewport = document.createElement('meta');
                viewport.name = 'viewport';
                viewport.content = 'width=1280';
                (document.head || document.documentElement).appendChild(viewport);
              } catch (e) {}
              for (const p of [window, Window.prototype, Document.prototype, HTMLElement.prototype, Element.prototype]) {
                for (const k of ['ontouchstart', 'ontouchmove', 'ontouchend', 'ontouchcancel']) {
                  try { delete p[k]; } catch (e) {}
                }
              }
              try { Object.defineProperty(Navigator.prototype, 'maxTouchPoints', { get: () => 0, configurable: true }); } catch (e) {}
              // Skyward's sign-in page sends the window size with the sign-in and sets
              // the whole session up for a phone when it is narrow; in that session
              // classes never open. Always report the hidden view's desktop size.
              const wide = () => {
                const w = document.getElementById('ScreenWidth'), h = document.getElementById('ScreenHeight');
                if (w && Number(w.value) < 1280) w.value = '1280';
                if (h && Number(h.value) < 900) h.value = '900';
              };
              const submit = HTMLFormElement.prototype.submit;
              HTMLFormElement.prototype.submit = function () { wide(); return submit.apply(this, arguments); };
              document.addEventListener('submit', wide, true);
              document.addEventListener('click', wide, true);
              const timer = setInterval(wide, 200);
              setTimeout(() => clearInterval(timer), 120000);
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        #endif
        controller.addUserScript(WKUserScript(
            source: QmlativScript.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        config.userContentController = controller

        let frame = CGRect(x: 0, y: 0, width: 1280, height: 900)
        let wv = WKWebView(frame: frame, configuration: config)
        wv.customUserAgent = URLSessionTransport.userAgent
        self.webView = wv

        #if os(macOS)
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.alphaValue = 0.0
        win.ignoresMouseEvents = true
        self.hiddenWindow = win
        #endif

        super.init()
        wv.navigationDelegate = self
        wv.uiDelegate = self
        attachToHiddenHost()
    }

    #if os(iOS)
    private var hiddenWindow: UIWindow?
    private static let hiddenFrame = CGRect(x: 0, y: 0, width: 1280, height: 900)

    /// Keeps the web view in a window at desktop size whenever it is not being shown
    /// to the user. Out of a window its timers are throttled; and coming back from the
    /// sign-in sheet it still carries the sheet's Auto Layout setting, which leaves it
    /// 0 points wide, so the page falls into a layout where class panels never open.
    private func ensureAttachedToWindow() {
        // In a window with constraints: it is on screen in a sign-in view. Leave it.
        if webView.window != nil, webView.superview != nil, !webView.translatesAutoresizingMaskIntoConstraints { return }
        if webView.window != nil, webView.superview != nil {
            if webView.frame.size != Self.hiddenFrame.size { webView.frame = Self.hiddenFrame }
            return
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first else { return }

        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = []
        webView.frame = Self.hiddenFrame
        webView.alpha = 0.01
        webView.isUserInteractionEnabled = false
        if let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
            window.insertSubview(webView, at: 0)
        } else {
            let window = hiddenWindow ?? UIWindow(windowScene: scene)
            window.frame = CGRect(x: -2000, y: -2000, width: 1280, height: 900)
            window.alpha = 0.01
            window.isUserInteractionEnabled = false
            window.isHidden = false
            window.addSubview(webView)
            hiddenWindow = window
        }
    }
    #endif

    /// Re-attaches `webView` to the engine's offscreen host window so layout (`offsetParent`) and timers are never throttled.
    func attachToHiddenHost() {
        let frame = CGRect(x: 0, y: 0, width: 1280, height: 900)
        #if os(macOS)
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.frame = frame
        webView.autoresizingMask = [.width, .height]
        hiddenWindow.contentView = webView
        #else
        // Called when a sign-in view closes, possibly while the web view is still in
        // it: take it out first so it is re-hidden at full size, not left behind.
        webView.removeFromSuperview()
        ensureAttachedToWindow()
        #endif
    }

    /// A Swift string as a JavaScript string literal.
    static func jsString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data("[\"\"]".utf8)
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }

    // MARK: Serial Queue

    private func serialized<T>(_ operation: @escaping @MainActor () async -> T) async -> T {
        let previous = queueTail
        var output: T!
        let current = Task { @MainActor in
            await previous?.value
            output = await operation()
        }
        queueTail = current
        await current.value
        return output
    }

    private func serializedThrowing<T>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = queueTail
        var result: Result<T, Error>!
        let current = Task { @MainActor in
            await previous?.value
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
        }
        queueTail = current
        await current.value
        return try result.get()
    }

    // MARK: Public API

    func load(_ path: String) async {
        await serialized {
            await self._load(path)
        }
    }

    func state() async -> QmlState? {
        await _state()
    }

    func isSignedIn() async -> Bool {
        (await _state())?.signedIn == true
    }

    /// How a silent sign-in ended.
    enum SilentOutcome: Equatable {
        case signedIn
        /// The district refused the saved sign-in. Never type it again.
        case rejected
        /// The district is waiting for a person: no saved sign-in, or a security code.
        case needsPerson
        /// Nothing came back in time (network, a slow district page). Safe to try later.
        case noResponse
    }

    /// True when the last silent sign-in typed the saved sign-in and the district
    /// did not accept it. The caller must stop using those details: sending a wrong
    /// password again is how accounts get locked.
    private(set) var lastSilentRejected = false

    func silentSignIn(credentials: DistrictCredentials? = nil) async -> Bool {
        await signInQuietly(credentials: credentials) == .signedIn
    }

    /// Signs back in without showing anything: presses the district sign-in
    /// button, and when the district asks for credentials, fills in the ones the
    /// student chose to remember. One attempt only.
    func signInQuietly(credentials: DistrictCredentials? = nil) async -> SilentOutcome {
        await serialized {
            self.lastSilentRejected = false
            if (await self._state())?.signedIn == true { return .signedIn }
            _ = try? await self.callJS("return window.__sp.clickSSO()")
            let deadline = Date().addingTimeInterval(credentials == nil ? 15 : 30)
            var filledUser = false, filledPassword = false, askedAgain = 0
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if (await self._state())?.signedIn == true { return .signedIn }
                if filledPassword {
                    // The password went in once. If the page is back to an empty
                    // password box, it was refused: stop here rather than wait it out.
                    let again = (try? await self.callJS("return window.__sp.passwordAskedAgain()")) == "1"
                    askedAgain = again ? askedAgain + 1 : 0
                    if askedAgain >= 2 {
                        self.lastSilentRejected = true
                        return .rejected
                    }
                    continue
                }
                guard let credentials else { continue }
                let step = (try? await self.callJS(
                    "return window.__sp.fillLogin(u, p, sent)",
                    arguments: ["u": credentials.username, "p": credentials.password, "sent": filledUser]
                )) ?? "none"
                switch step {
                case "username":
                    if filledUser {  // asked for the username twice: it was refused
                        self.lastSilentRejected = true
                        return .rejected
                    }
                    filledUser = true
                case "password":
                    filledPassword = true
                default:
                    break
                }
            }
            if (await self._state())?.signedIn == true { return .signedIn }
            if filledPassword {
                // Typed and not refused, but not in either: a security code or similar.
                let form = (try? await self.callJS("return window.__sp.passwordAskedAgain()")) == "1"
                if form { self.lastSilentRejected = true; return .rejected }
                return .needsPerson
            }
            let form = (try? await self.callJS("return window.__sp.loginFormShown()")) == "1"
            return form ? .needsPerson : .noResponse
        }
    }

    /// Accounts whose phone-width session was already traded in this run, so it happens once.
    private var replacedMobileSession = false

    /// When Skyward set this session up for a phone, signs out of Skyward only (the
    /// district sign-in stays) and back in at desktop width, once. True when the
    /// app ends up signed in to a desktop session.
    func replaceMobileSession(credentials: DistrictCredentials?) async -> Bool {
        guard let state = await _state(), state.signedIn, state.mobile == true else { return true }
        guard !replacedMobileSession else { return true }
        replacedMobileSession = true
        await serialized {
            _ = try? await self.callJS("const b = document.querySelector('#signOutButton'); if (b) b.click(); return b ? 'clicked' : 'none';")
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if (await self._state())?.signedIn != true { break }
            }
            await self._load("Grading/StudentSection/StudentAccess")
        }
        guard await signInQuietly(credentials: credentials) == .signedIn else { return false }
        await load("Grading/StudentSection/StudentAccess")
        return (await _state())?.signedIn == true
    }

    func grid() async throws -> QmlGrid {
        try await serializedThrowing {
            // Wait briefly if the browse table is still rendering after navigation.
            for _ in 0..<25 {
                let raw = try await self.callJS("return window.__sp.grid()")
                let decoded = try JSONDecoder().decode(QmlGrid.self, from: Data(raw.utf8))
                if !decoded.rows.isEmpty { return decoded }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            let raw = try await self.callJS("return window.__sp.grid()")
            return try JSONDecoder().decode(QmlGrid.self, from: Data(raw.utf8))
        }
    }

    func open(bucketID: String, weights: Bool) async throws -> QmlPanel {
        try await serializedThrowing {
            let raw = try await self.callJS(
                "return await window.__sp.open(id, w)",
                arguments: ["id": bucketID, "w": weights]
            )
            let panel = try JSONDecoder().decode(QmlPanel.self, from: Data(raw.utf8))
            if let error = panel.error, !error.isEmpty {
                throw SkywardError.server("Could not open assignment panel (\(error)).")
            }
            return panel
        }
    }

    func attendance() async throws -> QmlAttendance {
        try await serializedThrowing {
            for _ in 0..<15 {
                let hasTable = (try? await self.callJS("return document.querySelector('table.unlockedBrowseTable') ? '1' : '0'")) == "1"
                if hasTable { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            let raw = try await self.callJS("return await window.__sp.attendance()")
            return try JSONDecoder().decode(QmlAttendance.self, from: Data(raw.utf8))
        }
    }

    func signOut() async {
        await serialized {
            let store = self.webView.configuration.websiteDataStore
            let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
            let matching = records.filter { rec in
                let d = rec.displayName.lowercased()
                return d.contains("iscorp.com") || d.contains("skyward") || d.contains("mckinney")
            }
            if !matching.isEmpty {
                await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: matching)
            }
        }
    }

    #if DEBUG
    func saveDebugPage(in baseDirectory: URL) async -> URL? {
        guard let html = try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String else {
            return nil
        }
        let titleRaw = (try? await webView.evaluateJavaScript("document.title") as? String) ?? "page"
        let safeTitle = titleRaw
            .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let sanitized = html.replacingOccurrences(
            of: "[0-9a-fA-F]{32,}",
            with: "HEX",
            options: .regularExpression
        )
        let debugDir = baseDirectory.appendingPathComponent("debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let fileURL = debugDir.appendingPathComponent("\(safeTitle.isEmpty ? "page" : safeTitle)-\(stamp).html")
        try? Data(sanitized.utf8).write(to: fileURL, options: .atomic)
        return fileURL
    }
    #endif

    // MARK: Internal Implementation

    private func _load(_ path: String) async {
        #if os(iOS)
        ensureAttachedToWindow()
        #endif
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let targetURL = trimmed.isEmpty ? base : (URL(string: trimmed, relativeTo: base)?.absoluteURL ?? base.appendingPathComponent(trimmed))

        resolveNavigation()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.navContinuation = cont
            self.navTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                self?.resolveNavigation()
            }
            self.webView.load(URLRequest(url: targetURL))
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    private func _state() async -> QmlState? {
        guard let raw = try? await callJS("return window.__sp.state()") else { return nil }
        return try? JSONDecoder().decode(QmlState.self, from: Data(raw.utf8))
    }

    private func ensureScriptInstalled() async {
        let installed = (try? await webView.evaluateJavaScript("typeof window.__sp === 'object'")) as? Bool ?? false
        if !installed {
            _ = try? await webView.evaluateJavaScript(QmlativScript.source)
        }
    }

    /// Runs script in the page with a time limit. If the page is replaced while a call
    /// is waiting, WebKit may never answer it; without the limit that would stall
    /// every later sync for this account.
    private func callPage(_ source: String, arguments: [String: Any], seconds: Double = 75) async throws -> Any? {
        final class Once { var done = false }
        let once = Once()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            let timer = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !once.done else { return }
                once.done = true
                continuation.resume(throwing: SkywardError.server("Skyward's page stopped responding."))
            }
            webView.callAsyncJavaScript(source, arguments: arguments, in: nil, in: .page) { result in
                MainActor.assumeIsolated {
                    guard !once.done else { return }
                    once.done = true
                    timer.cancel()
                    switch result {
                    case .success(let value): continuation.resume(returning: value)
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func callJS(_ body: String, arguments: [String: Any] = [:]) async throws -> String {
        #if os(iOS)
        ensureAttachedToWindow()
        #endif
        await ensureScriptInstalled()
        // Installing the helper inside the same call means a page that reloaded a
        // moment ago still has it; a script error comes back as text, not an exception.
        let guarded = """
        if (typeof window.__sp !== 'object') { \(QmlativScript.source); }
        try { \(body) } catch (e) { return '__sp_error:' + (e && e.message ? e.message : String(e)); }
        """
        var lastError = ""
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 600_000_000) }
            do {
                let result = try await callPage(guarded, arguments: arguments)
                guard let str = result as? String else { throw SkywardError.server("Unexpected script response from page.") }
                if str.hasPrefix("__sp_error:") {
                    lastError = String(str.dropFirst("__sp_error:".count))
                    continue
                }
                return str
            } catch let error as NSError where error.domain == WKError.errorDomain {
                // The page went away mid-call (it navigated); try once more.
                lastError = (error.userInfo["WKJavaScriptExceptionMessage"] as? String) ?? error.localizedDescription
            }
        }
        throw SkywardError.server("Skyward's page didn't respond as expected (\(lastError)).")
    }

    private func resolveNavigation() {
        navTimeoutTask?.cancel()
        navTimeoutTask = nil
        if let cont = navContinuation {
            navContinuation = nil
            cont.resume()
        }
    }

    // MARK: WKNavigationDelegate & WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Inside the student site, a new window is Skyward showing details it found no
        // room for on the page. Following it would take this hidden page off the
        // gradebook (and strand whatever was reading it), so it is ignored. Sign-in
        // pages live outside the student site and may still open their windows here.
        if let current = webView.url, current.absoluteString.hasPrefix(base.absoluteString) {
            return nil
        }
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadedWidth = webView.bounds.width
        resolveNavigation()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resolveNavigation()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Ignore NSURLErrorCancelled (-999) when a redirect supersedes an in-flight provisional navigation.
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
            return
        }
        resolveNavigation()
    }
}
