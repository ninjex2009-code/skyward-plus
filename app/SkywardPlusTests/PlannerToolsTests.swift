import Foundation
import Testing

@Suite("Planner tools")
struct PlannerToolsTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test("School-day repeats skip the weekend")
    func schoolDaysSkipWeekend() {
        let friday = day(2026, 11, 13)
        #expect(calendar.isDate(TaskRepeat.schoolDays.advance(friday, calendar: calendar), inSameDayAs: day(2026, 11, 16)))
    }

    @Test("A repeat left overdue comes back after today, not in the past")
    func overdueRepeatSkipsAhead() throws {
        var task = PlannerTask(title: "Read 20 min", due: day(2026, 11, 2))
        task.repeats = .daily
        let next = try #require(task.nextOccurrence(today: day(2026, 11, 13), calendar: calendar))
        #expect(calendar.isDate(next.due, inSameDayAs: day(2026, 11, 13)))
        #expect(next.repeats == .daily && !next.done)
    }

    @Test("A weekly repeat keeps its checklist, unticked")
    func weeklyRepeatKeepsSteps() throws {
        var task = PlannerTask(title: "Vocab", due: day(2026, 11, 13))
        task.repeats = .weekly
        task.subtasks = [Subtask(title: "Flashcards", done: true), Subtask(title: "Quiz yourself")]
        let next = try #require(task.nextOccurrence(today: day(2026, 11, 13), calendar: calendar))
        #expect(calendar.isDate(next.due, inSameDayAs: day(2026, 11, 20)))
        #expect(next.subtasks.map(\.title) == ["Flashcards", "Quiz yourself"])
        #expect(next.subtasks.allSatisfy { !$0.done })
    }

    @Test("A one-off task doesn't come back")
    func neverRepeats() {
        #expect(PlannerTask(title: "Essay", due: day(2026, 11, 13)).nextOccurrence(today: day(2026, 11, 13), calendar: calendar) == nil)
    }

    @Test("Streaks count back from today, or from yesterday before today's session")
    func streakCounting() {
        let keys: Set<String> = [FocusStreak.key(day(2026, 11, 11), calendar: calendar), FocusStreak.key(day(2026, 11, 12), calendar: calendar)]
        #expect(FocusStreak.count(days: keys, today: day(2026, 11, 13), calendar: calendar) == 2)
        #expect(FocusStreak.count(days: keys.union([FocusStreak.key(day(2026, 11, 13), calendar: calendar)]), today: day(2026, 11, 13), calendar: calendar) == 3)
        #expect(FocusStreak.count(days: keys, today: day(2026, 11, 15), calendar: calendar) == 0)
    }

    @Test("Tasks saved before repeats and checklists still load")
    func oldTasksDecode() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Old","notes":"","due":0,"kind":"homework","done":false,"createdAt":0}"#
        let task = try JSONDecoder().decode(PlannerTask.self, from: Data(json.utf8))
        #expect(task.repeats == .never && task.subtasks.isEmpty)
    }
}
