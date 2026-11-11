#if DEBUG && os(macOS)
import Foundation

/// Runs the saved-sign-in routine against a stand-in district portal on this Mac
/// and writes what happened to a file. Usage:
///   Skyward Plus --remember-test <base URL> <output.json>
/// with SP_TEST_USER / SP_TEST_PASS in the environment (leave both out to test
/// the no-saved-sign-in path). Only ever point this at a local test server.
enum RememberTest {
    @MainActor
    static func run() async {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--keychain"), args.count > index + 1 {
            keychain(report: args[index + 1])
            exit(0)
        }
        guard let index = args.firstIndex(of: "--remember-test"), args.count > index + 2,
              let base = URL(string: args[index + 1]),
              ["localhost", "127.0.0.1"].contains(base.host ?? "") else { exit(2) }
        let env = ProcessInfo.processInfo.environment
        let user = env["SP_TEST_USER"] ?? ""
        let credentials = user.isEmpty ? nil : DistrictCredentials(username: user, password: env["SP_TEST_PASS"] ?? "")

        let engine = QmlativEngine(base: base)
        await engine.load("Grading/StudentSection/StudentAccess")
        let before = await engine.state()
        let started = Date()
        let result = await engine.silentSignIn(credentials: credentials)
        let after = await engine.state()
        let report: [String: Any] = [
            "signedInBefore": before?.signedIn ?? false,
            "result": result,
            "rejected": engine.lastSilentRejected,
            "seconds": (Date().timeIntervalSince(started) * 10).rounded() / 10,
            "finalPath": after?.path ?? "",
            "name": after?.name ?? "",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: args[index + 2]))
        }
        exit(0)
    }

    /// Saved sign-in round trip with made-up values under a made-up address.
    private static func keychain(report path: String) {
        let address = "https://localhost/keychain-test/"
        var lines: [String] = []
        func check(_ name: String, _ ok: Bool) { lines.append((ok ? "pass" : "FAIL") + "  " + name) }

        Keychain.remove(Keychain.districtKey(address))
        check("nothing saved to begin with", Keychain.loadDistrict(address: address) == nil)
        Keychain.saveDistrict(DistrictCredentials(username: "teststudent", password: "test-pass-123"), address: address)
        check("saved sign-in loads back", Keychain.usableDistrict(address: address) == DistrictCredentials(username: "teststudent", password: "test-pass-123"))
        Keychain.markDistrictRejected(address: address)
        check("refused sign-in is no longer offered", Keychain.usableDistrict(address: address) == nil)
        check("refused sign-in is still on record as refused", Keychain.loadDistrict(address: address)?.rejected == true)
        Keychain.saveDistrict(DistrictCredentials(username: "teststudent", password: "new-test-pass"), address: address)
        check("saving a new sign-in clears the refusal", Keychain.usableDistrict(address: address)?.password == "new-test-pass")
        Keychain.remove(Keychain.districtKey(address))
        check("forgetting removes it", Keychain.loadDistrict(address: address) == nil)
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Changes the model from closures that also read it, the way buttons do.
    /// Doing that in place is a memory-exclusivity violation, which aborts the app;
    /// reaching the end of this function at all is the pass.
    @MainActor
    static func modelUpdates(model: AppModel, report path: String) {
        var lines: [String] = ["profiles: \(model.profiles.count), marking periods: \(model.data.buckets.count)"]
        for bucket in model.data.buckets {
            model.updatePrefs { $0.selectedLit = bucket.lit == model.data.currentLit ? nil : bucket.lit }
            lines.append("switched to \(bucket.lit): showing \(model.selectedLit ?? "-")")
        }
        model.updatePrefs { $0.selectedLit = nil }
        model.updateSettings { $0.compactRows = model.settings.compactRows }
        model.updateActive { $0.theme = model.theme }
        model.updateBell { _ = $0; _ = model.prefs.bell }
        lines.append("pass  model changed from closures that read it")
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
#endif
