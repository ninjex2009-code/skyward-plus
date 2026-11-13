import Foundation
import Testing

@Suite("Home layout")
struct HomeLayoutTests {
    @Test("No saved order gives the default order")
    func defaultOrderWhenNothingSaved() {
        #expect(HomeSection.ordered(nil) == HomeSection.defaultOrder)
    }

    @Test("A saved order is kept, unknown and repeated entries dropped, new sections appended")
    func savedOrderIsCleanedUp() {
        let order = HomeSection.ordered(["recent", "bogus", "needsYou", "recent", "classes"])
        #expect(Array(order.prefix(2)) == [.recent, .needsYou])
        #expect(Set(order) == Set(HomeSection.defaultOrder))
        #expect(order.count == HomeSection.defaultOrder.count)
    }

    @Test("Wide sections get their own row; column sections pair up")
    func rowsGroupColumnSections() {
        let rows = HomeSection.rows([.gradesStrip, .needsYou, .recent, .bell])
        #expect(rows == [[.gradesStrip], [.needsYou, .recent], [.bell]])
    }
}

@Suite("Class colors and icons")
struct ClassLookTests {
    @Test("Automatic colors follow position and wrap around")
    func automaticByIndex() {
        #expect(ClassColor.automatic(index: 0, id: "x") == ClassColor.automatic[0])
        #expect(ClassColor.automatic(index: ClassColor.automatic.count + 2, id: "x") == ClassColor.automatic[2])
    }

    @Test("Without a position the color is stable for an id")
    func automaticByID() {
        #expect(ClassColor.automatic(index: nil, id: "course-42") == ClassColor.automatic(index: nil, id: "course-42"))
    }

    @Test("Subjects map to icons", arguments: [
        ("AP Calculus BC", "function"),
        ("AP Physics C: Mechanics", "atom"),
        ("AP Computer Science A", "chevron.left.forwardslash.chevron.right"),
        ("Organic Chemistry Honors", "flask"),
        ("AP English Literature", "book.closed"),
        ("Spanish III Honors", "globe.americas"),
        ("Symphonic Band", "music.note"),
        ("Advisory", "graduationcap"),
    ])
    func subjectIcons(name: String, symbol: String) {
        #expect(ClassSubject.symbol(for: name) == symbol)
    }
}

@Suite("Nimbus's weather")
struct MascotWeatherTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func change(_ score: Double, daysAgo: Double = 0, kind: ChangeKind = .newGrade) -> GradeChange {
        GradeChange(id: UUID().uuidString, date: now.addingTimeInterval(-daysAgo * 86_400), kind: kind,
                    courseID: "c", courseName: "Class", lit: "Q2", title: "Quiz", detail: "",
                    assignmentID: nil, oldValue: nil, newValue: score)
    }

    @Test("No recent grades means clear skies")
    func clearWithoutGrades() {
        #expect(MascotWeather.from(changes: [change(55, daysAgo: 5)], now: now) == .clear)
    }

    @Test("Any low grade brings rain")
    func rainForLowGrade() {
        #expect(MascotWeather.from(changes: [change(98), change(65)], now: now) == .rain)
    }

    @Test("Two or more excellent grades make a rainbow")
    func rainbowForExcellentRun() {
        #expect(MascotWeather.from(changes: [change(97), change(99)], now: now) == .rainbow)
    }

    @Test("Good grades bring the sun")
    func sunForGoodGrades() {
        #expect(MascotWeather.from(changes: [change(91)], now: now) == .sun)
    }

    @Test("Average changes and new assignments don't count")
    func onlyGradedChangesCount() {
        #expect(MascotWeather.from(changes: [change(40, kind: .averageDown), change(40, kind: .newAssignment)], now: now) == .clear)
    }
}
