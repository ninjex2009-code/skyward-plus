import Foundation

/// One notification, worded twice: in full, and without scores for a phone
/// relay the student chose to keep private.
struct Alert: Equatable {
    var id: String
    var title: String
    var body: String
    var plainTitle: String
    var plainBody: String
    /// Tapping the alert opens this class.
    var courseID: String?
    /// Alerts with the same thread stack together.
    var thread: String
}

/// The wording of every alert. Pure, so it can be tested.
enum AlertText {
    /// New absences and tardies since the last check, recent ones only (Skyward
    /// sometimes back-fills old records, which shouldn't ring the phone).
    static func newAttendance(previous: [AttendanceEvent], current: [AttendanceEvent], now: Date) -> [AttendanceEvent] {
        let known = Set(previous.map(\.id))
        let since = now.addingTimeInterval(-14 * 86_400)
        return current.filter { !known.contains($0.id) && $0.date >= since }.sorted { $0.date < $1.date }
    }

    /// One alert for new attendance records: what was recorded and when, nothing more.
    static func attendance(_ events: [AttendanceEvent]) -> Alert? {
        guard let first = events.first else { return nil }
        let day = DateFormatter()
        day.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        func label(_ e: AttendanceEvent) -> String {
            switch e.kind {
            case .tardy: return "Tardy"
            case .excused: return "Excused absence"
            case .unexcused: return "Unexcused absence"
            case .other: return e.reason.isEmpty ? "Attendance" : e.reason
            }
        }
        func when(_ e: AttendanceEvent) -> String {
            let periods = e.periods.trimmingCharacters(in: .whitespaces)
            return day.string(from: e.date) + (periods.isEmpty ? "" : " · period \(periods)")
        }
        let title = events.count == 1 ? "\(label(first)) recorded" : "\(events.count) attendance records"
        let body = events.count == 1 ? when(first) : events.prefix(3).map { "\(label($0)): \(when($0))" }.joined(separator: "\n")
        return Alert(
            id: "attendance-" + Str.hash(events.map(\.id).joined(separator: ",")),
            title: title, body: body,
            plainTitle: "Attendance updated", plainBody: "Open Skyward Plus to see it.",
            courseID: nil, thread: "attendance"
        )
    }

    /// "+0.6" or "−1.2", one decimal.
    static func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "−") + String(format: "%.1f", abs(value))
    }

    static func pct(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return text + "%"
    }

    /// One alert per class with new or changed grades (or a moved average), at most
    /// `limit`; past that, a single alert listing them all.
    static func grades(_ changes: [GradeChange], averages: [String: Double], limit: Int = 4) -> [Alert] {
        var order: [String] = []
        var byCourse: [String: [GradeChange]] = [:]
        for change in changes where change.kind != .newAssignment {
            if byCourse[change.courseID] == nil { order.append(change.courseID) }
            byCourse[change.courseID, default: []].append(change)
        }
        guard !order.isEmpty else { return [] }

        var alerts: [Alert] = []
        for courseID in order {
            let items = byCourse[courseID] ?? []
            let graded = items.filter { $0.kind == .newGrade || $0.kind == .updatedGrade }
            let moved = items.first { $0.kind == .averageUp || $0.kind == .averageDown }
            let course = items[0].courseName
            let average: String? = {
                if let moved, let old = moved.oldValue, let new = moved.newValue {
                    return "Average \(pct(new)) (was \(pct(old)))."
                }
                if let now = averages[courseID] { return "Average \(pct(now))." }
                return nil
            }()

            var title: String
            var lines: [String] = []
            if graded.count == 1, let one = graded.first {
                if one.kind == .updatedGrade {
                    title = "\(course): grade changed"
                    lines.append("\(one.title): \(one.detail)")
                } else {
                    title = "\(course): \(one.detail)"
                    // One quiet fact: how much this grade moved the class.
                    if let impact = one.impact, abs(impact) >= 0.05 {
                        lines.append("\(one.title) · \(signed(impact)) to your average")
                    } else {
                        lines.append(one.title)
                    }
                }
            } else if graded.count > 1 {
                title = "\(course): \(graded.count) new grades"
                lines.append(contentsOf: graded.prefix(3).map { "\($0.title): \($0.detail)" })
                if graded.count > 3 { lines.append("and \(graded.count - 3) more") }
            } else if let moved {
                title = "\(course) average \(moved.kind == .averageUp ? "went up" : "went down")"
            } else {
                continue
            }
            if let average { lines.append(average) }
            let plainTitle = graded.isEmpty ? "\(course) average changed" : (graded.count == 1 ? "New grade in \(course)" : "\(graded.count) new grades in \(course)")
            alerts.append(Alert(
                id: "grades-" + Str.hash(items.map(\.id).joined(separator: ",")),
                title: title, body: lines.joined(separator: "\n"),
                plainTitle: plainTitle, plainBody: "Open Skyward Plus to see it.",
                courseID: courseID, thread: "grades-" + courseID
            ))
        }

        guard alerts.count > limit else { return alerts }
        let names = order.compactMap { byCourse[$0]?.first?.courseName }
        let count = changes.filter { $0.kind == .newGrade || $0.kind == .updatedGrade }.count
        let title = count > 0 ? "\(count) new grades in \(names.count) classes" : "Averages changed in \(names.count) classes"
        return [Alert(
            id: "grades-" + Str.hash(changes.map(\.id).joined(separator: ",")),
            title: title, body: names.joined(separator: ", "),
            plainTitle: title, plainBody: names.joined(separator: ", "),
            courseID: nil, thread: "grades"
        )]
    }

    static func missing(_ items: [(courseID: String, course: String, title: String)]) -> Alert? {
        guard let first = items.first else { return nil }
        let single = items.count == 1
        let title = single ? "Missing in \(first.course)" : "\(items.count) assignments marked missing"
        let body = single
            ? "\(first.title) is marked missing in Skyward."
            : items.prefix(4).map { "\($0.course): \($0.title)" }.joined(separator: "\n")
        return Alert(
            id: "missing-" + Str.hash(items.map { $0.courseID + $0.title }.joined(separator: ",")),
            title: title, body: body, plainTitle: title, plainBody: body,
            courseID: single ? first.courseID : nil, thread: "missing"
        )
    }

    static func belowGoal(courseID: String, course: String, percent: Double, goal: Double) -> Alert {
        Alert(
            id: "goal-" + Str.hash(courseID, String(percent)),
            title: "\(course) is under your goal",
            body: "Now \(pct(percent)). Your goal is \(pct(goal)).",
            plainTitle: "\(course) is under your goal",
            plainBody: "Open Skyward Plus to see where it stands.",
            courseID: courseID, thread: "goals"
        )
    }

    struct EveningFacts {
        var newGradesToday: Int
        var changedClasses: [String]
        var missing: [String]
        var dueTomorrow: [(title: String, course: String)]
        var underGoal: [(course: String, percent: Double, goal: Double)]
        /// When Skyward was last read; nil or not today means today's grades may be unknown.
        var checkedToday: Bool
    }

    /// The evening note. Nil when there is nothing at all to say.
    static func evening(_ facts: EveningFacts) -> Alert? {
        var lines: [String] = []
        var plain: [String] = []
        if facts.checkedToday {
            if facts.newGradesToday > 0 {
                let classes = facts.changedClasses.prefix(3).joined(separator: ", ")
                lines.append("\(facts.newGradesToday) new grade\(facts.newGradesToday == 1 ? "" : "s") today" + (classes.isEmpty ? "" : ": \(classes)"))
                plain.append("\(facts.newGradesToday) new grade\(facts.newGradesToday == 1 ? "" : "s") today")
            } else {
                lines.append("No new grades today.")
                plain.append("No new grades today.")
            }
        }
        if !facts.dueTomorrow.isEmpty {
            let list = facts.dueTomorrow.prefix(3).map { $0.course.isEmpty ? $0.title : "\($0.course): \($0.title)" }
            lines.append("Due tomorrow: " + list.joined(separator: "; ") + (facts.dueTomorrow.count > 3 ? " and \(facts.dueTomorrow.count - 3) more" : ""))
            plain.append("\(facts.dueTomorrow.count) due tomorrow")
        }
        if !facts.missing.isEmpty {
            lines.append("\(facts.missing.count) missing: " + facts.missing.prefix(3).joined(separator: ", "))
            plain.append("\(facts.missing.count) missing")
        }
        if !facts.underGoal.isEmpty {
            lines.append("Under goal: " + facts.underGoal.prefix(3).map { "\($0.course) \(pct($0.percent))" }.joined(separator: ", "))
            plain.append("\(facts.underGoal.count) under goal")
        }
        guard !lines.isEmpty else { return nil }
        return Alert(
            id: "evening", title: "Tonight in Skyward", body: lines.joined(separator: "\n"),
            plainTitle: "Tonight in Skyward", plainBody: plain.joined(separator: " · "),
            courseID: nil, thread: "evening"
        )
    }

    static func test(relaying: Bool) -> Alert {
        Alert(
            id: "test-" + UUID().uuidString,
            title: "Notifications are working",
            body: relaying ? "This Mac will send new grades here and to your phone." : "New grades will show up like this.",
            plainTitle: "Notifications are working",
            plainBody: "New grades will show up like this.",
            courseID: nil, thread: "test"
        )
    }
}

/// Copies alerts to the free ntfy app on a phone, through ntfy.sh. Anyone who
/// knows the topic can read it, so topics are long and random.
enum PhoneRelay {
    struct Config: Equatable {
        var topic: String
        var includeScores: Bool
    }

    static let server = URL(string: "https://ntfy.sh/")!

    static func newTopic() -> String {
        let letters = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return "skywardplus-" + String((0..<20).map { _ in letters.randomElement()! })
    }

    /// Topics ntfy accepts: letters, digits, dashes and underscores.
    static func isValid(_ topic: String) -> Bool {
        topic.count >= 6 && topic.count <= 64 && topic.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// A JSON publish request. The topic travels in the body, not the URL.
    static func request(for alert: Alert, config: Config) -> URLRequest? {
        guard isValid(config.topic) else { return nil }
        var payload: [String: Any] = [
            "topic": config.topic,
            "title": config.includeScores ? alert.title : alert.plainTitle,
            "message": config.includeScores ? alert.body : alert.plainBody,
            "tags": ["mortar_board"],
        ]
        if let courseID = alert.courseID,
           let encoded = courseID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            payload["click"] = "skywardplus://class/" + encoded
        } else {
            payload["click"] = "skywardplus://grades"
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        var request = URLRequest(url: server, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    static func send(_ alert: Alert, config: Config) {
        guard let request = request(for: alert, config: config) else { return }
        Task.detached(priority: .utility) {
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}
