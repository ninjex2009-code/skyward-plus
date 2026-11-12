import Foundation
import Testing

@Suite("Alert wording")
struct AlertTextTests {
    private func change(_ kind: ChangeKind, course: String = "c1", name: String = "Statistics AP", title: String = "Unit 4 Test",
                        detail: String = "92/100", old: Double? = nil, new: Double? = nil) -> GradeChange {
        GradeChange(id: UUID().uuidString, date: Date(), kind: kind, courseID: course, courseName: name, lit: "Q2",
                    title: title, detail: detail, assignmentID: "a", oldValue: old, newValue: new)
    }

    @Test("One new grade names the score, the assignment and the new average")
    func singleGrade() throws {
        let alerts = AlertText.grades([
            change(.newGrade),
            change(.averageUp, title: "Statistics AP", detail: "90.4 → 91.2", old: 90.4, new: 91.2),
        ], averages: [:])
        let alert = try #require(alerts.first)
        #expect(alerts.count == 1)
        #expect(alert.title == "Statistics AP: 92/100")
        #expect(alert.body == "Unit 4 Test\nAverage 91.2% (was 90.4%).")
        #expect(alert.courseID == "c1")
        #expect(alert.plainTitle == "New grade in Statistics AP")
        #expect(!alert.plainBody.contains("92"))
    }

    @Test("A changed grade says what it changed from")
    func changedGrade() throws {
        let alert = try #require(AlertText.grades([change(.updatedGrade, detail: "80/100 → 85/100")], averages: ["c1": 88]).first)
        #expect(alert.title == "Statistics AP: grade changed")
        #expect(alert.body == "Unit 4 Test: 80/100 → 85/100\nAverage 88%.")
    }

    @Test("Posted but ungraded work is not announced")
    func newAssignmentIgnored() {
        #expect(AlertText.grades([change(.newAssignment, detail: "Due Nov 12")], averages: [:]).isEmpty)
    }

    @Test("Many classes at once become one alert")
    func manyClassesCollapse() throws {
        let changes = (1...6).map { change(.newGrade, course: "c\($0)", name: "Class \($0)") }
        let alerts = AlertText.grades(changes, averages: [:], limit: 4)
        let alert = try #require(alerts.first)
        #expect(alerts.count == 1)
        #expect(alert.title == "6 new grades in 6 classes")
        #expect(alert.courseID == nil)
    }

    @Test("The evening note leaves out today's grades when Skyward wasn't checked today")
    func eveningUnchecked() throws {
        let facts = AlertText.EveningFacts(newGradesToday: 0, changedClasses: [], missing: ["Lab 3"],
                                           dueTomorrow: [("Essay", "English")], underGoal: [], checkedToday: false)
        let alert = try #require(AlertText.evening(facts))
        #expect(!alert.body.contains("No new grades"))
        #expect(alert.body.contains("Due tomorrow: English: Essay"))
        #expect(alert.body.contains("1 missing: Lab 3"))
    }

    @Test("Nothing to say means no evening note")
    func eveningEmpty() {
        let facts = AlertText.EveningFacts(newGradesToday: 0, changedClasses: [], missing: [], dueTomorrow: [], underGoal: [], checkedToday: false)
        #expect(AlertText.evening(facts) == nil)
    }
}

@Suite("Phone relay")
struct PhoneRelayTests {
    @Test("New topics are long, random and valid")
    func topics() {
        let a = PhoneRelay.newTopic(), b = PhoneRelay.newTopic()
        #expect(a != b)
        #expect(PhoneRelay.isValid(a))
        #expect(a.count >= 30)
        #expect(!PhoneRelay.isValid("has space"))
        #expect(!PhoneRelay.isValid("abc"))
    }

    @Test("The request keeps the topic out of the URL and hides scores when asked")
    func request() throws {
        let alert = Alert(id: "x", title: "Statistics AP: 92/100", body: "Unit 4 Test", plainTitle: "New grade in Statistics AP",
                          plainBody: "Open Skyward Plus to see it.", courseID: "c 1", thread: "t")
        let request = try #require(PhoneRelay.request(for: alert, config: .init(topic: "skywardplus-test123", includeScores: false)))
        #expect(request.url == PhoneRelay.server)
        #expect(request.httpMethod == "POST")
        let json = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(json["topic"] as? String == "skywardplus-test123")
        #expect(json["title"] as? String == "New grade in Statistics AP")
        #expect(json["click"] as? String == "skywardplus://class/c%201")
        #expect(PhoneRelay.request(for: alert, config: .init(topic: "bad topic", includeScores: true)) == nil)
    }
}
