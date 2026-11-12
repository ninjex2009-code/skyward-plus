import Testing
import Foundation

@Suite("Account sync merges")
struct SyncMergeTests {
    @Test("Adds on both devices are both kept")
    func addsOnBothSides() {
        let base: [String: Int] = ["a": 1]
        let merged = Merge.map(local: ["a": 1, "mac": 2], remote: ["a": 1, "phone": 3], base: base)
        #expect(merged == ["a": 1, "mac": 2, "phone": 3])
    }

    @Test("A delete on the other device sticks when this device didn't touch it")
    func remoteDelete() {
        let merged = Merge.map(local: ["a": 1, "b": 2], remote: ["a": 1], base: ["a": 1, "b": 2])
        #expect(merged == ["a": 1])
    }

    @Test("An edit here beats a delete there")
    func editBeatsDelete() {
        let merged = Merge.map(local: ["b": 5], remote: [:], base: ["b": 2])
        #expect(merged == ["b": 5])
    }

    @Test("Both changed the same item: this device wins")
    func conflictLocalWins() {
        #expect(Merge.map(local: ["a": 10], remote: ["a": 20], base: ["a": 1]) == ["a": 10])
    }

    @Test("First sync on a device combines both, preferring this device")
    func firstSync() {
        #expect(Merge.map(local: ["a": 1, "x": 9], remote: ["a": 2, "y": 8], base: nil) == ["a": 1, "x": 9, "y": 8])
        #expect(Merge.set(local: ["a"], remote: ["b"], base: nil) == ["a", "b"])
    }

    @Test("Ticks: added and removed on either side")
    func sets() {
        // Phone ticked "p" and unticked "old"; Mac ticked "m".
        let merged = Merge.set(local: ["keep", "old", "m"], remote: ["keep", "p"], base: ["keep", "old"])
        #expect(merged == ["keep", "m", "p"])
    }

    @Test("Untick here and tick there of different items")
    func setsIndependent() {
        let merged = Merge.set(local: ["a"], remote: ["a", "b", "c"], base: ["a", "b"])
        // This device unticked b; the other device ticked c.
        #expect(merged == ["a", "c"])
    }

    @Test("A new device takes the account's single values, like its theme")
    func newDeviceTakesAccountValues() {
        #expect(Merge.value(local: "midnight", remote: "obsidian", base: nil) == "obsidian")
        #expect(Merge.value(local: ["a", "b"], remote: ["b", "a"], base: nil) == ["b", "a"])
        #expect(Merge.value(local: "midnight", remote: nil, base: nil) == "midnight", "a brand-new account keeps this device's choice")
    }

    @Test("Single values: the side that changed wins")
    func values() {
        #expect(Merge.value(local: 1, remote: 2, base: 1) == 2)
        #expect(Merge.value(local: 3, remote: 2, base: 1) == 3)
        #expect(Merge.value(local: 3, remote: nil, base: 1) == 3)
    }
}
