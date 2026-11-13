import Foundation
import Testing

@Suite("Study groups")
struct StudyGroupTests {
    @Test("Codes are six unambiguous characters")
    func codeShape() {
        for _ in 0..<50 {
            let code = InviteCode.make()
            #expect(code.count == 6)
            #expect(!code.contains(where: { "01OIL".contains($0) }))
        }
    }

    @Test("Typed or pasted codes are cleaned up", arguments: [
        ("abc234", "ABC234"),
        (" ab-c2 34 ", "ABC234"),
        ("skywardplus://join/ABC234", "ABC234"),
        ("Join my study group in Skyward Plus: skywardplus://join/QRS789 (code QRS789)", "QRS789"),
        ("hello", nil),
    ])
    func normalize(input: String, expected: String?) {
        #expect(InviteCode.normalize(input) == expected)
    }

    @Test("Open to-dos come first, oldest first; done ones sink")
    func taskOrder() {
        var group = StudyGroup(name: "Bio", owner: "a", code: "ABC234", createdAt: 0)
        group.tasks = [
            "x": .init(title: "Done one", done: true, by: "a", createdAt: 1),
            "y": .init(title: "Second", done: false, by: "a", createdAt: 3),
            "z": .init(title: "First", done: false, by: "b", createdAt: 2),
        ]
        #expect(group.openTasks.map(\.task.title) == ["First", "Second", "Done one"])
    }

    @Test("Past sessions drop off; upcoming ones are in order")
    func upcomingSessions() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var group = StudyGroup(name: "Bio", owner: "a", code: "ABC234", createdAt: 0)
        group.sessions = [
            "old": .init(title: "Old", start: now.timeIntervalSince1970 - 86_400, minutes: 60, by: "a"),
            "later": .init(title: "Later", start: now.timeIntervalSince1970 + 7_200, minutes: 60, by: "a"),
            "soon": .init(title: "Soon", start: now.timeIntervalSince1970 + 600, minutes: 30, by: "b"),
        ]
        #expect(group.upcomingSessions(after: now).map(\.session.title) == ["Soon", "Later"])
    }

    @Test("A group of eight is full")
    func fullAtEight() {
        var group = StudyGroup(name: "Bio", owner: "a", code: "ABC234", createdAt: 0)
        group.members = Dictionary(uniqueKeysWithValues: (0..<8).map { ("u\($0)", StudyGroup.Member(name: "S\($0)", joinedAt: Double($0))) })
        #expect(group.isFull)
    }
}
