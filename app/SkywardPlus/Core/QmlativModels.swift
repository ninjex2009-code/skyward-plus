import Foundation

struct QmlState: Decodable, Equatable {
    var host: String
    var path: String
    var title: String
    var signedIn: Bool
    var signInPage: Bool
    var duplicateSession: Bool
    var name: String
    var school: String
    /// Skyward set this session up for a phone (it was signed in at phone width).
    var mobile: Bool? = nil
}

struct QmlGrid: Decodable, Equatable {
    struct Head: Decodable, Equatable {
        var text: String
        var current: Bool
    }
    struct Cell: Decodable, Equatable {
        var text: String
        var id: String
        var link: Bool
    }
    struct Row: Decodable, Equatable {
        var section: String
        var student: String
        var name: String
        var code: String
        var period: String
        var cells: [Cell]
    }
    var heads: [Head]
    var rows: [Row]
    var missing: String
}

struct QmlPanel: Decodable, Equatable {
    struct Row: Decodable, Equatable {
        var category: Bool
        var name: String
        var due: String
        var grade: String
        var score: String
        var points: String
        var attempts: String
        var flagged: Bool
    }
    struct Weight: Decodable, Equatable {
        var name: String
        var weight: String
        var adjusted: String
        var percent: String
    }
    var error: String?
    var teacher: String?
    var period: String?
    var lit: String?
    var range: String?
    var grade: String?
    var percent: String?
    var rows: [Row]?
    var weights: [Weight]?
}

struct QmlAttendance: Decodable, Equatable {
    var heads: [String]
    var rows: [[String]]
    var legend: [String: String]
    var totals: String
}

enum QmlativMapper {
    static func gradebook(_ grid: QmlGrid) -> (buckets: [TermBucket], courses: [Course], currentLit: String?) {
        var buckets: [TermBucket] = []
        var bucketColumns: [(index: Int, lit: String)] = []
        var currentLit: String?

        for (j, head) in grid.heads.enumerated() where j >= 2 {
            let text = head.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            buckets.append(TermBucket(lit: text, bucket: text, name: ""))
            bucketColumns.append((j, text))
            if head.current {
                currentLit = text
            }
        }

        var allCourses: [Course] = []
        for row in grid.rows {
            var grades: [PostedGrade] = []
            for col in bucketColumns where col.index < row.cells.count {
                let cell = row.cells[col.index]
                let text = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty || cell.link {
                    grades.append(PostedGrade(
                        lit: col.lit,
                        bucket: cell.id,
                        text: text,
                        hasDetail: cell.link && !cell.id.isEmpty
                    ))
                }
            }
            let course = Course(
                id: row.section,
                studentID: row.student,
                cni: row.section,
                name: row.name,
                teacher: "",
                period: period(row.period),
                timeRange: "",
                grades: grades
            )
            allCourses.append(course)
        }

        let graded = allCourses.filter { course in
            course.grades.contains { !$0.isEmpty }
        }
        let courses = graded.isEmpty ? allCourses : graded
        return (buckets, courses, currentLit)
    }

    static func detail(_ panel: QmlPanel, courseID: String, lit: String, bucket: String, now: Date = Date()) -> GradeDetail? {
        if let err = panel.error, !err.isEmpty { return nil }

        let weightsList = panel.weights ?? []
        func findWeight(_ name: String) -> QmlPanel.Weight? {
            weightsList.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }

        var beginDate: Date?
        var endDate: Date?
        if let range = panel.range, !range.isEmpty {
            let parts = range.split(separator: "-", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if let first = parts.first { beginDate = SkyDate.parse(first) }
            if parts.count > 1 { endDate = SkyDate.parse(parts[1]) }
        }

        var categories: [GradeCategory] = []
        var assignments: [Assignment] = []
        var currentCategory = ""

        for row in panel.rows ?? [] {
            let pts = points(row.points)
            if row.category {
                currentCategory = row.name
                let w = findWeight(row.name)
                categories.append(GradeCategory(
                    name: row.name,
                    weight: w.flatMap { number($0.weight) },
                    adjustedWeight: w.flatMap { number($0.adjusted) },
                    gradeText: row.grade,
                    percent: number(row.score),
                    earned: pts.earned,
                    possible: pts.possible
                ))
            } else {
                let id = "q" + Str.hash(row.name, row.due, currentCategory)
                let isMissing = row.flagged && (pts.earned ?? 0) == 0
                assignments.append(Assignment(
                    id: id,
                    name: row.name,
                    category: currentCategory,
                    due: SkyDate.parse(row.due),
                    gradeText: row.grade,
                    percent: number(row.score),
                    earned: pts.earned,
                    possible: pts.possible,
                    missing: isMissing
                ))
            }
        }

        for w in weightsList {
            if !categories.contains(where: { $0.name.caseInsensitiveCompare(w.name) == .orderedSame }) {
                categories.append(GradeCategory(
                    name: w.name,
                    weight: number(w.weight),
                    adjustedWeight: number(w.adjusted),
                    gradeText: "",
                    percent: number(w.percent),
                    earned: nil,
                    possible: nil
                ))
            }
        }

        return GradeDetail(
            courseID: courseID,
            lit: lit,
            bucket: bucket,
            teacher: panel.teacher ?? "",
            period: panel.period.map(period) ?? "",
            gradeText: panel.grade ?? "",
            percent: panel.percent.flatMap(number),
            begin: beginDate,
            end: endDate,
            categories: categories,
            assignments: assignments,
            fetchedAt: now
        )
    }

    static func attendance(_ page: QmlAttendance) -> [AttendanceEvent] {
        let dateIndex = page.heads.firstIndex {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Date") == .orderedSame
        } ?? 1

        var events: [AttendanceEvent] = []
        for row in page.rows {
            guard dateIndex < row.count else { continue }
            let rawDate = row[dateIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let dateToken = rawDate.split(separator: " ").first.map(String.init),
                  let date = SkyDate.parse(dateToken) else { continue }

            var codeOrder: [String] = []
            var periodsByCode: [String: [String]] = [:]

            for (colIndex, cell) in row.enumerated() where colIndex != dateIndex && colIndex < page.heads.count {
                let header = page.heads[colIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                let code = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !header.isEmpty, !code.isEmpty else { continue }
                if periodsByCode[code] == nil {
                    codeOrder.append(code)
                }
                periodsByCode[code, default: []].append(header)
            }

            for code in codeOrder {
                let periods = (periodsByCode[code] ?? []).joined(separator: ", ")
                let reason = page.legend[code] ?? code
                events.append(AttendanceEvent(
                    date: date,
                    reason: reason,
                    periods: periods,
                    classes: []
                ))
            }
        }
        return events
    }

    static func number(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    static func points(_ text: String) -> (earned: Double?, possible: Double?) {
        let parts = text.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return (nil, nil) }
        return (number(parts[0]), number(parts[1]))
    }

    static func period(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("period ") {
            s = String(s.dropFirst("period ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let dashRange = s.range(of: " - ") {
            s = String(s[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }
}
