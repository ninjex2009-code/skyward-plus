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

    /// Re-attaches `webView` to the engine's offscreen host window so layout (`offsetParent`) and timers are never throttled.
    func attachToHiddenHost() {
        let frame = CGRect(x: 0, y: 0, width: 1280, height: 900)
        #if os(macOS)
        webView.removeFromSuperview()
        webView.frame = frame
        webView.autoresizingMask = [.width, .height]
        hiddenWindow.contentView = webView
        #else
        webView.removeFromSuperview()
        webView.frame = frame
        webView.alpha = 0.01
        webView.isUserInteractionEnabled = false
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
            keyWindow.insertSubview(webView, at: 0)
        }
        #endif
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

    /// Signs back in without showing anything: presses the district sign-in
    /// button, and when the district asks for credentials, fills in the ones the
    /// student chose to remember. One attempt only; a failure means the sheet.
    /// True when the last silent sign-in typed the saved sign-in and the district
    /// did not accept it. The caller must stop using those details: sending a wrong
    /// password again is how accounts get locked.
    private(set) var lastSilentRejected = false

    func silentSignIn(credentials: DistrictCredentials? = nil) async -> Bool {
        await serialized {
            self.lastSilentRejected = false
            if (await self._state())?.signedIn == true { return true }
            _ = try? await self.callJS("return window.__sp.clickSSO()")
            let deadline = Date().addingTimeInterval(credentials == nil ? 12 : 30)
            var filledUser = false, filledPassword = false, askedAgain = 0
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if (await self._state())?.signedIn == true { return true }
                if filledPassword {
                    // The password went in once. If the page is back to an empty
                    // password box, it was refused: stop here rather than wait it out.
                    let again = (try? await self.callJS("return window.__sp.passwordAskedAgain()")) == "1"
                    askedAgain = again ? askedAgain + 1 : 0
                    if askedAgain >= 2 {
                        self.lastSilentRejected = true
                        return false
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
                        return false
                    }
                    filledUser = true
                case "password":
                    filledPassword = true
                default:
                    break
                }
            }
            let signedIn = (await self._state())?.signedIn == true
            if !signedIn, filledPassword { self.lastSilentRejected = true }
            return signedIn
        }
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

    private func callJS(_ body: String, arguments: [String: Any] = [:]) async throws -> String {
        await ensureScriptInstalled()
        let result = try await webView.callAsyncJavaScript(
            body,
            arguments: arguments,
            in: nil,
            contentWorld: .page
        )
        if let str = result as? String {
            return str
        }
        throw SkywardError.server("Unexpected script response from page.")
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
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
