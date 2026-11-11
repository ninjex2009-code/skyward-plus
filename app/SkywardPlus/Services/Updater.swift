#if os(macOS)
import AppKit
import Foundation

/// Installs a newer release from GitHub: downloads its DMG, copies the app out,
/// and swaps it in after this copy quits, then relaunches.
///
/// A file the app downloads itself carries no quarantine flag, so the new
/// version opens without the "can't check for malware" prompt.
@MainActor
@Observable
final class Updater {
    enum Phase: Equatable {
        case idle
        case downloading(Double)
        case installing
        case failed(String)
    }

    static let shared = Updater()
    private(set) var phase: Phase = .idle

    var isBusy: Bool {
        switch phase {
        case .downloading, .installing: return true
        default: return false
        }
    }

    func install(_ update: UpdateInfo) async {
        guard !isBusy else { return }
        guard let url = update.downloadURL else {
            NSWorkspace.shared.open(update.pageURL)
            return
        }
        phase = .downloading(0)
        do {
            let dmg = try await download(url)
            phase = .installing
            let staged = try await stage(dmg)
            try relaunch(replacingWith: staged)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Steps

    private func download(_ url: URL) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("The download isn't available.") }
        let total = max(response.expectedContentLength, 1)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("SkywardPlusUpdate-\(UUID().uuidString).dmg")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var received: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                phase = .downloading(min(1, Double(received) / Double(total)))
            }
        }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
        phase = .downloading(1)
        return file
    }

    /// Mounts the DMG, copies the app to a temporary folder and unmounts.
    private func stage(_ dmg: URL) async throws -> URL {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("SkywardPlusMount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try await run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-noverify", "-noautoopen", "-mountpoint", mount.path])
        defer {
            Task.detached { _ = try? await Updater.runDetached("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        }
        guard let appName = try FileManager.default.contentsOfDirectory(atPath: mount.path).first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError("The download didn't contain the app.")
        }
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("SkywardPlusStaged-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        let target = staged.appendingPathComponent(appName)
        try await run("/usr/bin/ditto", [mount.appendingPathComponent(appName).path, target.path])
        try await run("/usr/bin/codesign", ["--verify", "--deep", target.path])
        _ = try? await run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])
        try? FileManager.default.removeItem(at: dmg)
        return target
    }

    /// Hands off to a small script that waits for this process to exit, replaces
    /// the app bundle in place, and opens the new one.
    private func relaunch(replacingWith staged: URL) throws {
        let current = Bundle.main.bundleURL
        let parent = current.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError("Skyward Plus can't replace itself in \(parent.path). Move it to Applications and try again.")
        }
        let script = """
        #!/bin/bash
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(current.path).old"
        mv "\(current.path)" "\(current.path).old" && /usr/bin/ditto "\(staged.path)" "\(current.path)" && rm -rf "\(current.path).old" || mv "\(current.path).old" "\(current.path)"
        /usr/bin/xattr -dr com.apple.quarantine "\(current.path)" 2>/dev/null
        /usr/bin/open "\(current.path)"
        rm -rf "\(staged.deletingLastPathComponent().path)"
        """
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("skywardplus-update.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        try process.run()
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) async throws -> String {
        try await Updater.runDetached(tool, arguments)
    }

    nonisolated static func runDetached(_ tool: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { finished in
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if finished.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: UpdateError("Update step failed: \((tool as NSString).lastPathComponent)."))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
#endif
