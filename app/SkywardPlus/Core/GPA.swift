import Foundation

enum CourseLevel: String, Codable, CaseIterable, Identifiable {
    case regular, honors, ap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: return "Regular"
        case .honors: return "Honors / Pre-AP"
        case .ap: return "AP / IB / Dual"
        }
    }

    var shortTitle: String {
        switch self {
        case .regular: return "Regular"
        case .honors: return "Honors"
        case .ap: return "AP / IB"
        }
    }
}

struct ScaleRow: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var min: Double
    var letter: String
    var points: Double
}

struct GPAScale: Codable, Hashable, Identifiable {
    var name: String
    var rows: [ScaleRow]
    var honorsBonus: Double
    var apBonus: Double

    var id: String { name }

    private var sortedRows: [ScaleRow] {
        rows.sorted { $0.min > $1.min }
    }

    func points(for percent: Double) -> Double {
        guard percent.isFinite else { return 0 }
        let ordered = sortedRows
        if let hit = ordered.first(where: { percent >= $0.min - 1e-9 }) {
            return hit.points
        }
        return ordered.last?.points ?? 0
    }

    func letter(for percent: Double) -> String {
        guard percent.isFinite else { return "" }
        let ordered = sortedRows
        if let hit = ordered.first(where: { percent >= $0.min - 1e-9 }) {
            return hit.letter
        }
        return ordered.last?.letter ?? "F"
    }

    func points(forLetter raw: String) -> Double? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty else { return nil }
        if let exact = rows.first(where: { $0.letter.uppercased() == cleaned }) {
            return exact.points
        }
        // When a scale only lists whole letters (A, B, C, D, F) and a transcript carries A- or B+,
        // match the base letter so valid letter grades still count.
        let base = String(cleaned.prefix { $0.isLetter })
        if base != cleaned, let fallback = rows.first(where: { $0.letter.uppercased() == base }) {
            return fallback.points
        }
        return nil
    }

    func bonus(for level: CourseLevel) -> Double {
        switch level {
        case .regular: return 0
        case .honors: return honorsBonus
        case .ap: return apBonus
        }
    }

    static let presets: [GPAScale] = [
        GPAScale(
            name: "4.0 Standard",
            rows: [
                ScaleRow(min: 90, letter: "A", points: 4.0),
                ScaleRow(min: 80, letter: "B", points: 3.0),
                ScaleRow(min: 70, letter: "C", points: 2.0),
                ScaleRow(min: 60, letter: "D", points: 1.0),
                ScaleRow(min: 0, letter: "F", points: 0.0),
            ],
            honorsBonus: 0.5,
            apBonus: 1.0
        ),
        GPAScale(
            name: "4.0 Plus / Minus",
            rows: [
                ScaleRow(min: 97, letter: "A+", points: 4.0),
                ScaleRow(min: 93, letter: "A", points: 4.0),
                ScaleRow(min: 90, letter: "A-", points: 3.7),
                ScaleRow(min: 87, letter: "B+", points: 3.3),
                ScaleRow(min: 83, letter: "B", points: 3.0),
                ScaleRow(min: 80, letter: "B-", points: 2.7),
                ScaleRow(min: 77, letter: "C+", points: 2.3),
                ScaleRow(min: 73, letter: "C", points: 2.0),
                ScaleRow(min: 70, letter: "C-", points: 1.7),
                ScaleRow(min: 67, letter: "D+", points: 1.3),
                ScaleRow(min: 63, letter: "D", points: 1.0),
                ScaleRow(min: 60, letter: "D-", points: 0.7),
                ScaleRow(min: 0, letter: "F", points: 0.0),
            ],
            honorsBonus: 0.5,
            apBonus: 1.0
        ),
        GPAScale(
            name: "5.0 / 6.0 Tiered",
            rows: [
                ScaleRow(min: 90, letter: "A", points: 4.0),
                ScaleRow(min: 80, letter: "B", points: 3.0),
                ScaleRow(min: 70, letter: "C", points: 2.0),
                ScaleRow(min: 60, letter: "D", points: 1.0),
                ScaleRow(min: 0, letter: "F", points: 0.0),
            ],
            honorsBonus: 1.0,
            apBonus: 2.0
        ),
    ]
}

struct GPASettings: Codable, Hashable {
    var scale: GPAScale = GPAScale.presets[0]
    var levels: [String: CourseLevel] = [:]
    var credits: [String: Double] = [:]
    var excluded: Set<String> = []
    var includeTranscript: Bool = true

    static func levelKey(_ courseName: String) -> String {
        courseName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    func level(for courseName: String) -> CourseLevel {
        levels[GPASettings.levelKey(courseName)] ?? GPA.guessLevel(courseName)
    }
}

struct GPAEntry: Hashable, Identifiable {
    var id: String
    var name: String
    var year: String?
    var percent: Double?
    var letter: String
    var level: CourseLevel
    var credits: Double
    var excluded: Bool
    var unweighted: Double?
    var weighted: Double?
}

struct GPAResult: Hashable {
    var weighted: Double?
    var unweighted: Double?
    var credits: Double
    var entries: [GPAEntry]
}

enum GPA {
    static func guessLevel(_ courseName: String) -> CourseLevel {
        let upper = courseName.uppercased()
        // Check Pre-AP before AP so "PRE-AP" is classified as honors rather than AP.
        if upper.contains("PRE-AP") || upper.contains("PRE AP") || upper.contains("PREAP") {
            return .honors
        }
        let words = Set(upper.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if words.contains("PAP") { return .honors }
        if words.contains("AP") || words.contains("IB") || words.contains("DUAL") || words.contains("DC") || words.contains("ONRAMPS") {
            return .ap
        }
        if upper.contains("DUAL CREDIT") || upper.contains("ADVANCED PLACEMENT") {
            return .ap
        }
        if words.contains("HONORS") || words.contains("HON") || words.contains("HNR")
            || words.contains("ADVANCED") || words.contains("ADV") || words.contains("GT")
            || words.contains("ACCELERATED") || words.contains("ACCEL") || upper.contains("G/T")
            || upper.contains("GIFTED") {
            return .honors
        }
        return .regular
    }

    static func currentEntries(
        data: StudentData,
        lit: String,
        settings: GPASettings,
        overrides: [String: Double] = [:]
    ) -> [GPAEntry] {
        var out: [GPAEntry] = []
        for course in data.courses {
            let id = "cur|\(course.id)"
            let level = settings.level(for: course.name)
            let credits = settings.credits[id] ?? 1.0
            let isExcluded = settings.excluded.contains(id)
            let number = overrides[course.id] ?? data.detail(course.id, lit)?.percent ?? course.grade(lit)?.number
            let rawText = course.grade(lit)?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let entry = makeEntry(
                id: id,
                name: course.name,
                year: nil,
                percent: number,
                rawText: rawText,
                level: level,
                credits: credits,
                excluded: isExcluded,
                scale: settings.scale
            ) else { continue }
            out.append(entry)
        }
        return out
    }

    static func transcriptEntries(history: [HistoryYear], settings: GPASettings) -> [GPAEntry] {
        var out: [GPAEntry] = []
        for year in history {
            let yearKey = year.startYear.map(String.init) ?? year.title
            for course in year.courses {
                let upperName = GPASettings.levelKey(course.name)
                let level = settings.level(for: course.name)

                struct ColumnGrade {
                    var lit: String
                    var kind: BucketKind
                    var number: Double?
                    var raw: String
                }

                var valid: [ColumnGrade] = []
                for (index, litInfo) in year.lits.enumerated() where index < course.grades.count {
                    let raw = course.grades[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !raw.isEmpty else { continue }
                    let num = Str.number(raw)
                    if num != nil || settings.scale.points(forLetter: raw) != nil {
                        valid.append(ColumnGrade(lit: litInfo.lit, kind: BucketKind.classify(litInfo.lit), number: num, raw: raw))
                    }
                }
                guard !valid.isEmpty else { continue }

                let semesters = valid.filter { $0.kind == .semester }
                if !semesters.isEmpty {
                    for sem in semesters {
                        let id = "\(yearKey)|\(upperName)|\(sem.lit)"
                        let credits = settings.credits[id] ?? 0.5
                        let excluded = settings.excluded.contains(id)
                        if let entry = makeEntry(
                            id: id, name: course.name, year: year.title,
                            percent: sem.number, rawText: sem.raw,
                            level: level, credits: credits, excluded: excluded, scale: settings.scale
                        ) {
                            out.append(entry)
                        }
                    }
                    continue
                }

                if let finalCol = valid.last(where: { $0.kind == .final }) {
                    let id = "\(yearKey)|\(upperName)|\(finalCol.lit)"
                    let credits = settings.credits[id] ?? 1.0
                    let excluded = settings.excluded.contains(id)
                    if let entry = makeEntry(
                        id: id, name: course.name, year: year.title,
                        percent: finalCol.number, rawText: finalCol.raw,
                        level: level, credits: credits, excluded: excluded, scale: settings.scale
                    ) {
                        out.append(entry)
                    }
                    continue
                }

                let terms = valid.filter { $0.kind == .term }
                let pool = terms.isEmpty ? valid : terms
                let litTag = pool.last?.lit ?? "TERM"
                let id = "\(yearKey)|\(upperName)|\(litTag)"
                let credits = settings.credits[id] ?? 1.0
                let excluded = settings.excluded.contains(id)
                let numbers = pool.compactMap { $0.number }
                if !numbers.isEmpty {
                    let mean = numbers.reduce(0, +) / Double(numbers.count)
                    if let entry = makeEntry(
                        id: id, name: course.name, year: year.title,
                        percent: mean, rawText: "",
                        level: level, credits: credits, excluded: excluded, scale: settings.scale
                    ) {
                        out.append(entry)
                    }
                } else if let firstRaw = pool.last?.raw,
                          let entry = makeEntry(
                            id: id, name: course.name, year: year.title,
                            percent: nil, rawText: firstRaw,
                            level: level, credits: credits, excluded: excluded, scale: settings.scale
                          ) {
                    out.append(entry)
                }
            }
        }
        return out
    }

    static func compute(_ entries: [GPAEntry]) -> GPAResult {
        var totalCredits = 0.0
        var weightedSum = 0.0
        var unweightedSum = 0.0
        for entry in entries where !entry.excluded && entry.credits > 0 {
            guard let uw = entry.unweighted, let w = entry.weighted else { continue }
            totalCredits += entry.credits
            unweightedSum += uw * entry.credits
            weightedSum += w * entry.credits
        }
        guard totalCredits > 0 else {
            return GPAResult(weighted: nil, unweighted: nil, credits: 0, entries: entries)
        }
        return GPAResult(
            weighted: weightedSum / totalCredits,
            unweighted: unweightedSum / totalCredits,
            credits: totalCredits,
            entries: entries
        )
    }

    private static func makeEntry(
        id: String,
        name: String,
        year: String?,
        percent: Double?,
        rawText: String,
        level: CourseLevel,
        credits: Double,
        excluded: Bool,
        scale: GPAScale
    ) -> GPAEntry? {
        if let percent, percent.isFinite {
            let letter = scale.letter(for: percent)
            let uw = scale.points(for: percent)
            let w = uw > 0 ? uw + scale.bonus(for: level) : 0
            return GPAEntry(
                id: id, name: name, year: year, percent: percent, letter: letter,
                level: level, credits: credits, excluded: excluded,
                unweighted: uw, weighted: w
            )
        }
        if let uw = scale.points(forLetter: rawText) {
            let letter = rawText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let w = uw > 0 ? uw + scale.bonus(for: level) : 0
            return GPAEntry(
                id: id, name: name, year: year, percent: nil, letter: letter,
                level: level, credits: credits, excluded: excluded,
                unweighted: uw, weighted: w
            )
        }
        return nil
    }
}
