#if DEBUG
import Foundation
import WebKit
#if os(iOS)
import UIKit
#endif

/// Opens a class through the real sync engine against the local stand-in
/// gradebook (app/tools/mock-portal/server.py, mode=gradebook) and writes what
/// happened to a file. Usage, with the server running:
///   --engine-test <base URL> <output.json> <normal|narrow|detached>
///   normal    the hidden web view as it is after launch
///   narrow    first shown at phone width (as in the sign-in sheet), then hidden again
///   detached  taken out of the window before use
/// Only ever point this at a local server.
enum EngineTest {
    /// What the page believes about its own size, read from inside it.
    @MainActor
    static func pageMetrics(_ engine: QmlativEngine) async -> String {
        let script = """
        return JSON.stringify({
          clientWidth: document.documentElement.clientWidth, innerWidth: window.innerWidth,
          screenWidth: screen.width, scale: window.visualViewport ? window.visualViewport.scale : null,
          viewportTags: [...document.querySelectorAll('meta[name=viewport]')].map(m => m.content),
          screenWidthField: (document.getElementById('ScreenWidth') || {}).value || null,
          platform: navigator.platform, touch: 'ontouchstart' in window, path: location.pathname
        });
        """
        let value = try? await engine.webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        return (value as? String) ?? "unreadable"
    }

    /// `--probe-url <public page URL> <output.json>`: loads one page in the hidden
    /// web view and writes how it was laid out. Reads only; never types or submits.
    @MainActor
    static func probeIfRequested() async {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--probe-url"), args.count > index + 2,
              let url = URL(string: args[index + 1]), let host = url.host, let scheme = url.scheme,
              let root = URL(string: "\(scheme)://\(host)\(url.port.map { ":\($0)" } ?? "")/") else { return }
        try? await Task.sleep(nanoseconds: 800_000_000)
        let engine = QmlativEngine(base: root)
        await engine.load(url.path + (url.query.map { "?" + $0 } ?? ""))
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        var report: [String: Any] = ["page": await pageMetrics(engine)]
        #if os(iOS)
        report["webViewWidth"] = Int(engine.webView.frame.width)
        #endif
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: args[index + 2]))
        }
    }

    @MainActor
    static func runIfRequested() async {
        await probeIfRequested()
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--engine-test"), args.count > index + 3,
              let base = URL(string: args[index + 1]),
              ["localhost", "127.0.0.1"].contains(base.host ?? "") else { return }
        let output = URL(fileURLWithPath: args[index + 2])
        let scenario = args[index + 3]
        // Give the window a moment to come up, as it would before a real sync.
        try? await Task.sleep(nanoseconds: 800_000_000)

        let started = Date()
        let engine = QmlativEngine(base: base)
        var report: [String: Any] = ["scenario": scenario]

        #if os(iOS)
        if scenario == "narrow" {
            // What the sign-in sheet does: host the web view at phone width with constraints.
            let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first
            let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
            window?.addSubview(container)
            let web = engine.webView
            web.removeFromSuperview()
            web.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(web)
            NSLayoutConstraint.activate([
                web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                web.topAnchor.constraint(equalTo: container.topAnchor),
                web.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            await engine.load("Grading/StudentSection/StudentAccess")
            // The sheet asks for the web view back while it is still on screen.
            engine.attachToHiddenHost()
            container.removeFromSuperview()
        } else if scenario == "detached" {
            engine.webView.removeFromSuperview()
        } else if scenario == "popups" {
            // What happens to the main page when it opens a new window, two ways.
            func js(_ source: String) async -> String {
                ((try? await engine.webView.callAsyncJavaScript(source, arguments: [:], in: nil, contentWorld: .page)) as? String) ?? "call failed"
            }
            await engine.load("Grading/StudentSection/StudentAccess")
            report["open"] = await js("const w = window.open('/MockISDStu/Gradebook/popout?id=direct'); return String(w);")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            report["pathAfterOpen"] = await js("return location.pathname")
            await engine.load("Grading/StudentSection/StudentAccess")
            report["form"] = await js("const f = document.createElement('form'); f.method = 'POST'; f.target = '_blank'; f.action = '/MockISDStu/Gradebook/popout?id=form'; document.body.appendChild(f); f.submit(); f.remove(); return 'submitted';")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            report["pathAfterForm"] = await js("return location.pathname")
            await engine.load("Grading/StudentSection/StudentAccess")
            report["click"] = await js("const a = document.querySelector('td.linkPanelCell a'); a.click(); return 'clicked at width ' + document.documentElement.clientWidth;")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            report["pathAfterClick"] = await js("return location.pathname")
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                try? data.write(to: output)
            }
            return
        } else if scenario == "mobile" || scenario == "narrowsignin" {
            // Test values from the mock portal (tools/mock-portal/server.py).
            let credentials = DistrictCredentials(username: "teststudent", password: "test-pass-123")
            if scenario == "narrowsignin" {
                // Sign in inside a phone-width view, as the iPhone sign-in sheet does.
                let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first
                let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
                window?.addSubview(container)
                let web = engine.webView
                web.removeFromSuperview()
                web.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(web)
                NSLayoutConstraint.activate([
                    web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    web.topAnchor.constraint(equalTo: container.topAnchor),
                    web.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
                await engine.load("Grading/StudentSection/StudentAccess")
                report["signInPage"] = await pageMetrics(engine)
                report["narrowSignIn"] = String(describing: await engine.signInQuietly(credentials: credentials))
                engine.attachToHiddenHost()
                container.removeFromSuperview()
            }
            await engine.load("Grading/StudentSection/StudentAccess")
            report["mobileBefore"] = (await engine.state())?.mobile ?? false
            do {
                let data = try await SyncEngine.syncQmlativ(engine: engine, credentials: credentials, previous: nil)
                report["details"] = data.details.count
                report["warnings"] = data.warnings.joined(separator: " | ")
            } catch {
                report["error"] = error.localizedDescription
            }
            report["mobileAfter"] = (await engine.state())?.mobile ?? false
            report["seconds"] = (Date().timeIntervalSince(started) * 10).rounded() / 10
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                try? data.write(to: output)
            }
            return
        }
        #endif

        await engine.load("Grading/StudentSection/StudentAccess")
        report["signedIn"] = (await engine.state())?.signedIn ?? false
        report["page"] = await pageMetrics(engine)
        do {
            let grid = try await engine.grid()
            let mapped = QmlativMapper.gradebook(grid)
            report["classes"] = mapped.courses.count
            report["averagesRead"] = mapped.courses.filter { $0.grade("Q2")?.isEmpty == false }.count
            if let course = mapped.courses.first, let grade = course.grade("Q2") {
                let panel = try await engine.open(bucketID: grade.bucket, weights: true)
                report["panelError"] = panel.error ?? ""
                let detail = QmlativMapper.detail(panel, courseID: course.id, lit: "Q2", bucket: grade.bucket)
                report["assignments"] = detail?.assignments.count ?? 0
                report["categories"] = detail?.categories.count ?? 0
            }
        } catch {
            report["error"] = error.localizedDescription
        }
        report["pathAfter"] = (await engine.state())?.path ?? ""
        #if os(iOS)
        report["webViewWidth"] = Int(engine.webView.frame.width)
        report["touchVisible"] = (try? await engine.webView.callAsyncJavaScript(
            "return ('ontouchstart' in window) || navigator.maxTouchPoints > 0;", arguments: [:], in: nil, contentWorld: .page)) as? Bool ?? true
        report["inWindow"] = engine.webView.window != nil
        #endif
        report["seconds"] = (Date().timeIntervalSince(started) * 10).rounded() / 10
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: output)
        }
    }
}
#endif
