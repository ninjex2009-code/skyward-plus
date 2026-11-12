import Foundation
import Testing

@Suite("Sharing grades between devices")
struct GradeShareTests {
    private func data(synced: Double?, courses: [String] = ["c1", "c2"], details: [String] = [], warning: Bool = false) -> StudentData {
        var d = StudentData()
        d.skywardCurrentLit = "Q2"
        d.courses = courses.map { id in
            var c = Course(id: id, name: "Class " + id)
            c.grades = [PostedGrade(lit: "Q2", bucket: "b" + id, text: "95", hasDetail: true)]
            return c
        }
        for id in details {
            d.details[StudentData.detailKey(id, "Q2")] = GradeDetail(courseID: id, lit: "Q2", bucket: "b" + id)
        }
        d.lastSync = synced.map { Date(timeIntervalSince1970: $0) }
        if warning { d.warnings = ["Assignments could not be loaded for: Class c2. Reason: no-panel"] }
        return d
    }

    @Test("A device with nothing takes the account's grades")
    func emptyTakesRemote() throws {
        let remote = data(synced: 100, details: ["c1", "c2"])
        let result = try #require(GradeShare.combine(local: nil, remote: remote))
        #expect(result.details.count == 2)
    }

    @Test("Newer grades from the account replace older ones here")
    func newerRemoteWins() throws {
        let local = data(synced: 100, details: ["c1"], warning: true)
        let remote = data(synced: 200, details: ["c1", "c2"])
        let result = try #require(GradeShare.combine(local: local, remote: remote))
        #expect(result.lastSync == Date(timeIntervalSince1970: 200))
        #expect(result.details.count == 2)
        #expect(result.warnings.isEmpty)
    }

    @Test("A newer read here keeps its grades but fills assignment lists it couldn't load")
    func olderRemoteOnlyFills() throws {
        let local = data(synced: 300, details: ["c1"], warning: true)
        let remote = data(synced: 200, details: ["c1", "c2"])
        let result = try #require(GradeShare.combine(local: local, remote: remote))
        #expect(result.lastSync == Date(timeIntervalSince1970: 300))
        #expect(result.details[StudentData.detailKey("c2", "Q2")] != nil)
        #expect(result.warnings.isEmpty, "the could-not-load warning goes once every list is filled")
    }

    @Test("Nothing to fill means nothing changes")
    func nothingToDo() {
        let local = data(synced: 300, details: ["c1", "c2"])
        let remote = data(synced: 200, details: ["c1"])
        #expect(GradeShare.combine(local: local, remote: remote) == nil)
    }

    @Test("Lists for classes this device doesn't have aren't copied in")
    func ignoresUnknownClasses() {
        let local = data(synced: 300, courses: ["c1"], details: ["c1"])
        let remote = data(synced: 200, courses: ["c1", "c9"], details: ["c1", "c9"])
        #expect(GradeShare.combine(local: local, remote: remote) == nil)
    }

    @Test("The fingerprint ignores when lists were fetched but notices grade changes")
    func fingerprint() {
        var a = data(synced: 100, details: ["c1"])
        var b = a
        b.details[StudentData.detailKey("c1", "Q2")]?.fetchedAt = Date(timeIntervalSince1970: 999)
        b.lastSync = Date(timeIntervalSince1970: 500)
        #expect(GradeShare.fingerprint(a) == GradeShare.fingerprint(b))
        a.courses[0].grades[0].text = "88"
        #expect(GradeShare.fingerprint(a) != GradeShare.fingerprint(b))
    }
}
