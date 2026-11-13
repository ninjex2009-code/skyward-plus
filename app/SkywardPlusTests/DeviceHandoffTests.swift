import Foundation
import Testing

@Suite("Phone leaves Skyward to a checking Mac")
struct DeviceHandoffTests {
    private let now: Double = 1_800_000_000

    private func meta(device: String?, minutesAgo: Double?, every: Double? = 5) -> GradeShare.Meta {
        GradeShare.Meta(syncedAt: now - 3_600, hash: "h", device: device,
                        checkedAt: minutesAgo.map { now - $0 * 60 }, everyMinutes: every)
    }

    @Test("A phone skips Skyward when the Mac checked a few minutes ago")
    func phoneDefersToRecentMac() {
        #expect(GradeShare.macIsChecking(meta(device: "mac", minutesAgo: 4), thisDevice: "phone", now: now))
    }

    @Test("A phone checks for itself once the Mac has gone quiet")
    func phoneChecksWhenMacIsOff() {
        #expect(!GradeShare.macIsChecking(meta(device: "mac", minutesAgo: 20), thisDevice: "phone", now: now))
    }

    @Test("The window grows with a slower Mac schedule")
    func windowFollowsMacInterval() {
        #expect(GradeShare.macIsChecking(meta(device: "mac", minutesAgo: 60, every: 30), thisDevice: "phone", now: now))
        #expect(!GradeShare.macIsChecking(meta(device: "mac", minutesAgo: 100, every: 30), thisDevice: "phone", now: now))
    }

    @Test("A Mac never defers, and a phone doesn't defer to another phone")
    func onlyPhonesDeferAndOnlyToMacs() {
        #expect(!GradeShare.macIsChecking(meta(device: "mac", minutesAgo: 1), thisDevice: "mac", now: now))
        #expect(!GradeShare.macIsChecking(meta(device: "phone", minutesAgo: 1), thisDevice: "phone", now: now))
    }

    @Test("Records from before 1.6 (no device or check time) never block a check")
    func oldRecordsDoNotBlock() {
        #expect(!GradeShare.macIsChecking(meta(device: nil, minutesAgo: nil), thisDevice: "phone", now: now))
        #expect(!GradeShare.macIsChecking(nil, thisDevice: "phone", now: now))
    }

    @Test("Older records still decode")
    func oldMetaDecodes() throws {
        let old = try JSONDecoder().decode(GradeShare.Meta.self, from: Data(#"{"syncedAt":5,"hash":"x"}"#.utf8))
        #expect(old.device == nil && old.checkedAt == nil)
    }
}
