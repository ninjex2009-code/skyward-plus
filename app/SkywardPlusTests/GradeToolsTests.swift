import Foundation
import Testing

@Suite("Grade tools")
struct GradeToolsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The term GPA needed brings the cumulative GPA to the goal")
    func termGPANeeded() throws {
        let earlier = GPAResult(weighted: 4.4, unweighted: 3.9, credits: 14, entries: [])
        let term = GPAResult(weighted: 4.5, unweighted: 3.9, credits: 7, entries: [])
        let needed = try #require(GPA.termGPANeeded(goal: 4.5, earlier: earlier, term: term))
        // (4.5 × 21 − 4.4 × 14) / 7 = 4.7
        #expect(abs(needed - 4.7) < 0.0001)
    }

    @Test("No credits this term means no answer")
    func noTermCredits() {
        let earlier = GPAResult(weighted: 4.4, unweighted: 3.9, credits: 14, entries: [])
        let term = GPAResult(weighted: nil, unweighted: nil, credits: 0, entries: [])
        #expect(GPA.termGPANeeded(goal: 4.5, earlier: earlier, term: term) == nil)
    }

    @Test("Without a saved weight, a semester exam counts one seventh")
    func examWeightDefault() {
        let prefs = ProfilePrefs()
        #expect(abs(prefs.examWeight - 100.0 / 7) < 0.0001)
    }

    @Test("A new grade's alert says how much it moved the class")
    func impactInAlert() throws {
        let change = GradeChange(id: "c", date: now, kind: .newGrade, courseID: "math", courseName: "Calculus",
                                 lit: "Q2", title: "Quiz 4", detail: "46/50", assignmentID: "a",
                                 oldValue: nil, newValue: 92, impact: 0.64)
        let alert = try #require(AlertText.grades([change], averages: ["math": 95.1]).first)
        #expect(alert.body.contains("Quiz 4 · +0.6 to your average"))
    }

    @Test("Tiny moves aren't mentioned")
    func tinyImpactOmitted() throws {
        let change = GradeChange(id: "c", date: now, kind: .newGrade, courseID: "math", courseName: "Calculus",
                                 lit: "Q2", title: "Quiz 4", detail: "46/50", assignmentID: "a",
                                 oldValue: nil, newValue: 92, impact: 0.01)
        let alert = try #require(AlertText.grades([change], averages: [:]).first)
        #expect(!alert.body.contains("to your average"))
    }

    @Test("Only new, recent attendance records alert")
    func newAttendanceOnly() {
        let old = AttendanceEvent(date: now.addingTimeInterval(-2 * 86_400), reason: "Tardy", periods: "1")
        let fresh = AttendanceEvent(date: now.addingTimeInterval(-3_600), reason: "Unexcused", periods: "3")
        let backfill = AttendanceEvent(date: now.addingTimeInterval(-60 * 86_400), reason: "Excused", periods: "2")
        let found = AlertText.newAttendance(previous: [old], current: [old, fresh, backfill], now: now)
        #expect(found == [fresh])
    }

    @Test("One tardy reads plainly")
    func tardyAlertWording() throws {
        let tardy = AttendanceEvent(date: now, reason: "Tardy", periods: "2")
        let alert = try #require(AlertText.attendance([tardy]))
        #expect(alert.title == "Tardy recorded")
        #expect(alert.body.contains("period 2"))
    }
}
