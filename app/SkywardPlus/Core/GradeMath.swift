import Foundation

// MARK: - Types

enum GradingMode: String, Codable, CaseIterable { case auto, weighted, points }

/// A what-if score for one assignment. It replaces the real score outright: `earned == nil`
/// means "not graded yet", while `possible == nil` keeps the assignment's own points possible.
struct ScoreEdit: Codable, Hashable {
    var earned: Double?
    var possible: Double?
    var excluded = false
}

/// Hypothetical changes to one class. `edits` is keyed by `Assignment.id`.
struct WhatIf: Codable, Hashable {
    var edits: [String: ScoreEdit] = [:]
    var added: [Assignment] = []

    var isEmpty: Bool { edits.isEmpty && added.isEmpty }
}

struct CategoryResult: Hashable, Identifiable {
    var name: String
    var weight: Double?            // as declared in the gradebook
    var effectiveWeight: Double    // share of the average it really carries, 0...100
    var earned: Double
    var possible: Double
    var percent: Double?
    var count: Int

    var id: String { name }
}

struct CourseResult: Hashable {
    var percent: Double?
    var mode: GradingMode          // the method that was used, never .auto
    var categories: [CategoryResult]
    var earned: Double
    var possible: Double
    var gradedCount: Int
    var missingCount: Int
    var matchesPosted: Bool?
}

enum NeededScore: Equatable {
    case unknown
    case secured
    case impossible(best: Double)
    case score(earned: Double, percent: Double)
}

// MARK: - Math

enum GradeMath {
    static func compute(_ detail: GradeDetail, mode: GradingMode = .auto, whatIf: WhatIf = WhatIf()) -> CourseResult {
        evaluate(detail, resolve(mode, in: detail), whatIf)
    }

    /// Whether a score goes into the average. `assignment` may be the original or one from `applied`.
    static func counts(_ assignment: Assignment, edit: ScoreEdit?) -> Bool {
        if edit?.excluded == true { return false }
        let scored = apply(edit, to: assignment)
        guard let earned = scored.earned, let possible = scored.possible else { return false }
        // Non-finite or negative points can only be bad input, and one would poison every total.
        return !scored.noCount && !scored.dropped && earned.isFinite && possible.isFinite && possible >= 0
    }

    /// The assignments as the what-if sees them: edited scores in place, added ones at the end.
    /// Excluded ones stay in the list so they can be shown and restored.
    static func applied(_ detail: GradeDetail, whatIf: WhatIf) -> [Assignment] {
        (detail.assignments + whatIf.added).map { apply(whatIf.edits[$0.id], to: $0) }
    }

    /// Average now minus the average without this assignment.
    static func impact(of assignmentID: String, in detail: GradeDetail, mode: GradingMode = .auto, whatIf: WhatIf = WhatIf()) -> Double? {
        guard let assignment = applied(detail, whatIf: whatIf).first(where: { $0.id == assignmentID }),
              counts(assignment, edit: whatIf.edits[assignmentID]) else { return nil }
        let mode = resolve(mode, in: detail)
        var without = whatIf
        without.edits[assignmentID, default: ScoreEdit()].excluded = true
        guard let now = evaluate(detail, mode, whatIf).percent,
              let rest = evaluate(detail, mode, without).percent else { return nil }
        return now - rest
    }

    /// What the average would gain if this assignment had full marks.
    static func upside(of assignmentID: String, in detail: GradeDetail, mode: GradingMode = .auto, whatIf: WhatIf = WhatIf()) -> Double? {
        guard let assignment = applied(detail, whatIf: whatIf).first(where: { $0.id == assignmentID }),
              let possible = assignment.possible, possible > 0 else { return nil }
        var edit = whatIf.edits[assignmentID] ?? ScoreEdit()
        edit.earned = possible
        edit.possible = possible
        // No-count, dropped and excluded scores stay out of the average whatever they are.
        guard counts(assignment, edit: edit) else { return nil }
        let mode = resolve(mode, in: detail)
        var aced = whatIf
        aced.edits[assignmentID] = edit
        guard let now = evaluate(detail, mode, whatIf).percent,
              let best = evaluate(detail, mode, aced).percent else { return nil }
        // A score already above full marks has nothing left to gain.
        return max(0, best - now)
    }

    /// The score a new assignment worth `possible` points in `category` needs for the average to reach `target`.
    static func needed(target: Double, possible: Double, category: String, in detail: GradeDetail, mode: GradingMode = .auto, whatIf: WhatIf = WhatIf()) -> NeededScore {
        guard target.isFinite, possible.isFinite, possible > 0 else { return .unknown }
        let mode = resolve(mode, in: detail)
        func average(_ earned: Double) -> Double? {
            var probe = whatIf
            probe.added.append(Assignment(id: probeID, name: "", category: category, earned: earned, possible: possible))
            return evaluate(detail, mode, probe).percent
        }
        guard let floor = average(0), let best = average(possible) else { return .unknown }
        // An average that should equal the target can land a few ulps under it.
        let goal = target - 1e-9
        if floor >= goal { return .secured }
        if best < goal { return .impossible(best: best) }
        var low = 0.0, high = possible
        for _ in 0..<60 {
            let middle = (low + high) / 2
            if let value = average(middle), value >= goal { high = middle } else { low = middle }
        }
        let earned = min(possible, (high * 100).rounded(.up) / 100)
        return .score(earned: earned, percent: earned / possible * 100)
    }

    /// The exam score that brings `current` to `target` when the exam is `examWeight` percent of the grade.
    static func finalExamNeeded(current: Double, examWeight: Double, target: Double) -> Double {
        let w = examWeight / 100
        // An exam with no weight cannot move the grade; dividing by it would give NaN.
        guard w > 0 else { return target > current ? .infinity : 0 }
        return (target - current * (1 - w)) / w
    }

    // MARK: Internals

    private static let probeID = "GradeMath.needed.probe"

    private static func apply(_ edit: ScoreEdit?, to assignment: Assignment) -> Assignment {
        guard let edit else { return assignment }
        var copy = assignment
        copy.earned = edit.earned
        copy.possible = edit.possible ?? assignment.possible
        return copy
    }

    /// Settles `.auto` from the real scores alone: the posted percent says nothing about a
    /// what-if, and the method must not flip while the user is editing one.
    private static func resolve(_ mode: GradingMode, in detail: GradeDetail) -> GradingMode {
        guard mode == .auto else { return mode }
        guard detail.categories.contains(where: { ($0.weight ?? 0) > 0 }) else { return .points }
        guard let posted = detail.percent,
              let points = evaluate(detail, .points, WhatIf()).percent else { return .weighted }
        let weighted = evaluate(detail, .weighted, WhatIf()).percent
        let weightedGap = weighted.map { abs($0 - posted) } ?? .infinity
        return weightedGap - abs(points - posted) > 1 ? .points : .weighted
    }

    /// `mode` is already settled here (`.weighted` or `.points`).
    private static func evaluate(_ detail: GradeDetail, _ mode: GradingMode, _ whatIf: WhatIf) -> CourseResult {
        var slots: [CategoryResult] = []
        var position: [String: Int] = [:]
        func place(_ name: String) -> Int {
            let key = name.trimmingCharacters(in: .whitespaces).lowercased()
            if let known = position[key] { return known }
            position[key] = slots.count
            slots.append(CategoryResult(name: name, weight: nil, effectiveWeight: 0, earned: 0, possible: 0, percent: nil, count: 0))
            return slots.count - 1
        }

        for category in detail.categories {
            let i = place(category.name)
            if slots[i].weight == nil { slots[i].weight = category.weight }
        }

        var graded = 0, missing = 0
        for assignment in applied(detail, whatIf: whatIf) {
            let edit = whatIf.edits[assignment.id]
            let i = place(assignment.category)
            if assignment.missing, edit?.excluded != true { missing += 1 }
            guard counts(assignment, edit: edit), let earned = assignment.earned, let possible = assignment.possible else { continue }
            slots[i].earned += earned
            slots[i].possible += possible
            slots[i].count += 1
            graded += 1
        }
        // A category holding only extra credit has points but nothing to take a percent of.
        for i in slots.indices where slots[i].possible > 0 {
            slots[i].percent = slots[i].earned / slots[i].possible * 100
        }
        let earned = slots.reduce(0) { $0 + $1.earned }
        let possible = slots.reduce(0) { $0 + $1.possible }

        var percent: Double?
        if mode == .points {
            if possible > 0 {
                percent = earned / possible * 100
                for i in slots.indices { slots[i].effectiveWeight = slots[i].possible / possible * 100 }
            }
        } else {
            let declared = slots.reduce(0) { $0 + max(0, $1.weight ?? 0) }
            let unweighted = slots.filter { $0.weight == nil && $0.percent != nil }.count
            let share = unweighted > 0 ? max(0, 100 - declared) / Double(unweighted) : 0
            // Only categories with a percent carry weight; dividing by their total is Skyward's "adjusted to".
            let weights = slots.map { $0.percent == nil ? 0 : max(0, $0.weight ?? share) }
            let total = weights.reduce(0, +)
            if total > 0 {
                percent = zip(slots, weights).reduce(0) { $0 + ($1.0.percent ?? 0) * $1.1 } / total
                for i in slots.indices { slots[i].effectiveWeight = weights[i] / total * 100 }
            }
        }

        var matches: Bool?
        // Skyward posts rounded percents, so anything within rounding distance is the same grade.
        if let percent, let posted = detail.percent { matches = abs(percent - posted) < 0.6 }
        return CourseResult(
            percent: percent, mode: mode, categories: slots, earned: earned, possible: possible,
            gradedCount: graded, missingCount: missing, matchesPosted: matches
        )
    }
}
