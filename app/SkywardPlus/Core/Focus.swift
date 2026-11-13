import Foundation

/// A running focus session on one task.
struct FocusSession: Equatable {
    var taskID: UUID
    var title: String
    var start: Date
    var end: Date

    var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
}

/// Days with a finished focus session, and the run of them up to today.
enum FocusStreak {
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Consecutive focus days ending today, or yesterday (today isn't over yet).
    static func count(days: Set<String>, today: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: today)
        if !days.contains(key(day, calendar: calendar)) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var run = 0
        while days.contains(key(day, calendar: calendar)) {
            run += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return run
    }
}
