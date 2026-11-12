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
    @MainActor
    static func runIfRequested() async {
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
