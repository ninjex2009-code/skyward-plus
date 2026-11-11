import Foundation

// MARK: - Gradebook

/// What a gradebook column stands for. Skyward lets each district name its own
/// grading buckets, so this is inferred from the short code.
enum BucketKind: String, Codable, CaseIterable {
    case progress, term, exam, semester, final, other

    static func classify(_ raw: String) -> BucketKind {
        let lit = raw.uppercased().filter { !$0.isWhitespace }
        guard !lit.isEmpty else { return .other }
        if lit.allSatisfy({ $0.isNumber }) { return .term }
        if let first = lit.first, first.isNumber {
            // "9W1", "6W3", "1ST"
            return lit.contains("W") || lit.hasSuffix("ST") || lit.hasSuffix("ND") || lit.hasSuffix("RD") || lit.hasSuffix("TH") ? .term : .other
        }
        let letters = String(lit.prefix { $0.isLetter })
        switch letters {
        case "P", "PR", "PRG", "PG", "IP", "IPR", "INT", "I", "MT", "MID", "M":
            return .progress
        case "Q", "QT", "QTR", "T", "TM", "TRM", "TERM", "N", "NW", "C", "CY", "CYC", "MP", "SW", "W", "G", "GP":
            return .term
        case "SE", "EX", "EXM", "E", "X", "XM", "FE", "ME", "EOC", "SX":
            return .exam
        case "S", "SM", "SEM", "SA":
            return .semester
        case "FIN", "FNL", "FINAL", "F", "FG", "FA", "YR", "YA", "Y", "YAVG", "AV", "AVG", "EOY":
            return .final
        default:
            return .other
        }
    }

    var label: String {
        switch self {
        case .progress: return "Progress report"
        case .term: return "Term"
        case .exam: return "Exam"
        case .semester: return "Semester"
        case .final: return "Final"
        case .other: return "Other"
        }
    }
}

struct TermBucket: Codable, Hashable, Identifiable {
    var lit: String          // short code shown in the column header: "Q1", "PR2", "S1"
    var bucket: String       // Skyward's internal bucket name: "TERM 1"
    var name: String         // long name from the header tooltip, when there is one

    var id: String { lit }
    var kind: BucketKind { BucketKind.classify(lit) }
    var displayName: String { name.isEmpty ? lit : name }
}

struct PostedGrade: Codable, Hashable {
    var lit: String
    var bucket: String
    var text: String         // "95", "A-", or "" when the cell is empty
    var hasDetail: Bool      // the cell opens an assignment list

    var number: Double? { Double(text.trimmingCharacters(in: .whitespaces)) }
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// An assignment listed under a class on the main gradebook page.
struct InlineAssignment: Codable, Hashable {
    var aid: String?
    var gid: String?
    var name: String
    var due: Date?
    var lit: String
    var gradeText: String
}

struct Course: Codable, Hashable, Identifiable {
    var id: String
    var studentID: String = ""
    var entityID: String = ""
    var cni: String = ""         // corNumId
    var track: String = ""
    var section: String = ""
    var gid: String = ""         // gbId
    var isEoc: String = "no"
    var name: String
    var teacher: String = ""
    var period: String = ""
    var timeRange: String = ""
    var grades: [PostedGrade] = []
    var inline: [InlineAssignment] = []

    func grade(_ lit: String) -> PostedGrade? { grades.first { $0.lit == lit } }

    var periodNumber: Int { period.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) } ?? 99 }
}

struct GradeCategory: Codable, Hashable, Identifiable {
    var name: String
    var weight: Double?           // "weighted at 70.00%"
    var adjustedWeight: Double?   // "adjusted to 77.78%" when another category is empty
    var gradeText: String = ""
    var percent: Double?
    var earned: Double?
    var possible: Double?

    var id: String { name }
}

struct Assignment: Codable, Hashable, Identifiable {
    var id: String
    var aid: String?
    var gid: String?
    var sid: String?
    var name: String
    var category: String = ""
    var due: Date?
    var gradeText: String = ""
    var percent: Double?
    var earned: Double?
    var possible: Double?
    var missing = false
    var noCount = false
    var absent = false
    var absentNote = ""
    var specialCode: String?

    /// Skyward excludes dropped scores from the average.
    var dropped: Bool { (specialCode ?? "").localizedCaseInsensitiveContains("drop") }

    /// True when this assignment has a score that goes into the average.
    var isGraded: Bool { earned != nil && possible != nil }

    var scorePercent: Double? {
        if let earned, let possible, possible > 0 { return earned / possible * 100 }
        return percent
    }
}

struct BreakdownItem: Codable, Hashable, Identifiable {
    var lit: String
    var gradeText: String
    var percent: Double?
    var weight: Double?

    var id: String { lit }
}

/// The assignment list behind one grade cell: one class, one grading bucket.
struct GradeDetail: Codable, Hashable {
    var courseID: String
    var lit: String
    var bucket: String
    var courseName: String = ""
    var teacher: String = ""
    var period: String = ""
    var gradeText: String = ""
    var percent: Double?
    var begin: Date?
    var end: Date?
    var adjustment: Double?
    var breakdown: [BreakdownItem] = []
    var categories: [GradeCategory] = []
    var assignments: [Assignment] = []
    var fetchedAt: Date = Date()
}

// MARK: - Other pages

struct HistoryLit: Codable, Hashable {
    var lit: String
    var name: String
}

struct HistoryCourse: Codable, Hashable, Identifiable {
    var name: String
    var terms: String
    var grades: [String]          // aligned with the year's lits

    var id: String { name + "|" + terms }
}

struct HistoryYear: Codable, Hashable, Identifiable {
    var title: String             // "2018 - 2019, Grade 12"
    var lits: [HistoryLit] = []
    var courses: [HistoryCourse] = []

    var id: String { title }

    var startYear: Int? {
        let digits = title.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return digits.first { $0 > 1900 }
    }

    var gradeLevel: String? {
        guard let range = title.range(of: "Grade", options: .caseInsensitive) else { return nil }
        let rest = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
}

enum AttendanceKind: String, Codable {
    case tardy, excused, unexcused, other
}

struct AttendanceEvent: Codable, Hashable, Identifiable {
    var date: Date
    var reason: String
    var periods: String
    var classes: [String] = []

    var id: String { "\(Int(date.timeIntervalSince1970))|\(reason)|\(periods)" }

    var kind: AttendanceKind {
        let r = reason.lowercased()
        if r.contains("tard") || r.contains("late") { return .tardy }
        if r.contains("unex") || r.contains("truan") || r.contains("skip") { return .unexcused }
        if r.contains("exc") || r.contains("ill") || r.contains("medical") || r.contains("doctor") || r.contains("sick") || r.contains("note") { return .excused }
        if r.contains("activity") || r.contains("testing") { return .other }
        return .other
    }
}

struct KeyValue: Codable, Hashable, Identifiable {
    var key: String
    var value: String

    var id: String { key }
}

struct StudentProfile: Codable, Hashable {
    var name = ""
    var school = ""
    var gradeLevel = ""
    var attributes: [KeyValue] = []
    var photoPath: String?
}

struct ChildAccount: Codable, Hashable, Identifiable {
    var id: String
    var name: String
}

struct AssignmentInfo: Codable, Hashable {
    var title = ""
    var fields: [KeyValue] = []
}

// MARK: - Tracking over time

struct GradeSnapshot: Codable, Hashable {
    var date: Date
    var grades: [String: Double]      // "courseID|lit" -> percent
}

enum ChangeKind: String, Codable {
    case newGrade, updatedGrade, newAssignment, averageUp, averageDown
}

struct GradeChange: Codable, Hashable, Identifiable {
    var id: String
    var date: Date
    var kind: ChangeKind
    var courseID: String
    var courseName: String
    var lit: String
    var title: String
    var detail: String
    var assignmentID: String?
    var oldValue: Double?
    var newValue: Double?
}

/// Everything fetched from Skyward for one student.
struct StudentData: Codable {
    var profile = StudentProfile()
    var buckets: [TermBucket] = []
    var skywardCurrentLit: String?
    var courses: [Course] = []
    var details: [String: GradeDetail] = [:]
    var attendance: [AttendanceEvent] = []
    var history: [HistoryYear] = []
    var snapshots: [GradeSnapshot] = []
    var changes: [GradeChange] = []
    var lastSync: Date?
    var historySyncedAt: Date?
    var profileSyncedAt: Date?
    var warnings: [String] = []

    static func detailKey(_ courseID: String, _ lit: String) -> String { courseID + "|" + lit }

    func detail(_ courseID: String, _ lit: String) -> GradeDetail? { details[StudentData.detailKey(courseID, lit)] }

    func bucket(_ lit: String) -> TermBucket? { buckets.first { $0.lit == lit } }

    /// The marking period to show by default: the latest term column that has a grade.
    var currentLit: String? {
        func hasGrades(_ b: TermBucket) -> Bool {
            courses.contains { !($0.grade(b.lit)?.isEmpty ?? true) }
        }
        if let hit = buckets.last(where: { $0.kind == .term && hasGrades($0) }) { return hit.lit }
        if let hit = buckets.last(where: { hasGrades($0) }) { return hit.lit }
        return buckets.first(where: { $0.kind == .term })?.lit ?? buckets.first?.lit
    }

    /// Which semester a column belongs to, counting from 1. Nil for year-long
    /// columns (final grade) and when the district has no semester columns.
    func semester(of lit: String) -> Int? {
        guard let index = buckets.firstIndex(where: { $0.lit == lit }) else { return nil }
        let kind = buckets[index].kind
        guard kind != .final, kind != .other else { return nil }
        var count = 0
        for (i, b) in buckets.enumerated() where b.kind == .semester {
            if i >= index { return count + 1 }
            count += 1
        }
        return nil
    }

    /// The semesters in which a class has a grade column.
    func semesters(for course: Course) -> Set<Int> {
        var out = Set<Int>()
        for g in course.grades where g.hasDetail || !g.isEmpty {
            if let s = semester(of: g.lit) { out.insert(s) }
        }
        return out
    }
}

// MARK: - Dates

enum SkyDate {
    private static let textual: [DateFormatter] = {
        ["EEE MMM d, yyyy", "EEE, MMM d, yyyy", "MMM d, yyyy", "MMMM d, yyyy", "EEEE, MMMM d, yyyy", "EEE MMM dd yyyy", "yyyy-MM-dd"].map { format in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            f.isLenient = true
            return f
        }
    }()

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// Reads "09/06/18", "9/6/2018", "Tue Sep 6, 2018" and similar. Dates land on noon local time.
    static func parse(_ raw: String) -> Date? {
        let s = raw.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let token = s.split(separator: " ").first.map(String.init) ?? s
        let parts = token.split(separator: "/")
        if parts.count == 3, let m = Int(parts[0]), let d = Int(parts[1]), var y = Int(parts[2]), (1...12).contains(m), (1...31).contains(d) {
            if y < 100 { y += y < 70 ? 2000 : 1900 }
            return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))
        }
        for f in textual {
            if let date = f.date(from: s) {
                return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
            }
        }
        return nil
    }

    static func make(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    static func short(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d/%02d/%02d", c.month ?? 1, c.day ?? 1, (c.year ?? 2000) % 100)
    }

    static func long(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d/%02d/%04d", c.month ?? 1, c.day ?? 1, c.year ?? 2000)
    }
}

// MARK: - Small helpers

enum Str {
    /// First capture groups of the first match, or nil.
    static func match(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for g in 0..<m.numberOfRanges {
            if let r = Range(m.range(at: g), in: text) { groups.append(String(text[r])) } else { groups.append("") }
        }
        return groups
    }

    static func number(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let s = raw.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        return Double(s)
    }

    /// Stable short hash for building ids from text.
    static func hash(_ parts: String...) -> String {
        var h: UInt64 = 1469598103934665603
        for p in parts {
            for byte in p.utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
            h = (h ^ 0x1F) &* 1099511628211
        }
        return String(h, radix: 36)
    }

    /// "ALGEBRA 2 HONORS" -> "Algebra 2 Honors", keeping short all-caps tokens such as AP and US.
    static func titleCase(_ raw: String) -> String {
        let keep: Set<String> = ["AP", "IB", "US", "PE", "II", "III", "IV", "AB", "BC", "GT", "DC", "CS", "ELA", "PAP", "JROTC", "STEM", "ESL", "UIL", "CTE"]
        func formatToken(_ w: String) -> String {
            if keep.contains(w.uppercased()) { return w.uppercased() }
            if w.count <= 1 || w.contains(where: { $0.isNumber }) { return w.uppercased() }
            guard w == w.uppercased() || w == w.lowercased() else { return w }
            return w.prefix(1).uppercased() + w.dropFirst().lowercased()
        }
        return raw.split(separator: " ").map { word -> String in
            let w = String(word)
            if w.contains("-") {
                return w.split(separator: "-", omittingEmptySubsequences: false)
                    .map { formatToken(String($0)) }
                    .joined(separator: "-")
            }
            return formatToken(w)
        }.joined(separator: " ")
    }
}
