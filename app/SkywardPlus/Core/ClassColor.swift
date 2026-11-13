import Foundation

/// A class's color, picked by the student or given automatically, used wherever
/// the class appears: rows, tiles, the calendar, the menu bar and the report card.
enum ClassColor: String, Codable, CaseIterable, Identifiable, Hashable {
    case blue, orange, green, pink, violet, teal, amber, red, cyan, lime, indigo, rose

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// 0xRRGGBB, bright enough to read on dark themes and deep enough for light ones.
    var hex: UInt32 {
        switch self {
        case .blue: return 0x3B82F6
        case .orange: return 0xF97316
        case .green: return 0x22C55E
        case .pink: return 0xEC4899
        case .violet: return 0x8B5CF6
        case .teal: return 0x14B8A6
        case .amber: return 0xF59E0B
        case .red: return 0xEF4444
        case .cyan: return 0x06B6D4
        case .lime: return 0x84CC16
        case .indigo: return 0x6366F1
        case .rose: return 0xF43F5E
        }
    }

    /// Automatic colors in the order classes appear, spaced so neighbours differ.
    static let automatic: [ClassColor] = [.blue, .orange, .green, .pink, .violet, .teal, .amber, .red, .cyan, .lime, .indigo, .rose]

    /// The automatic color for a class at a position, or from its id when it has none.
    static func automatic(index: Int?, id: String) -> ClassColor {
        if let index { return automatic[index % automatic.count] }
        let sum = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return automatic[sum % automatic.count]
    }
}

/// Guesses a subject icon from a class name.
enum ClassSubject {
    private static let rules: [(keys: [String], symbol: String)] = [
        (["calc", "algebra", "geometry", "math", "statistic", "precalc", "trig"], "function"),
        (["physics"], "atom"),
        (["computer", "coding", "programming", " cs "], "chevron.left.forwardslash.chevron.right"),
        (["chem"], "flask"),
        (["bio", "anatomy", "environmental", "earth"], "leaf"),
        (["english", "literature", "writing", "reading", "journalism"], "book.closed"),
        (["history", "government", "economics", "geography", "civics", "psychology", "sociology"], "building.columns"),
        (["spanish", "french", "german", "chinese", "latin", "japanese", "language"], "globe.americas"),
        (["band", "orchestra", "choir", "music"], "music.note"),
        (["art", "drawing", "painting", "ceramics", "design"], "paintpalette"),
        (["theatre", "theater", "drama"], "theatermasks"),
        (["athletic", "physical education", " pe", "football", "basketball", "soccer", "volleyball", "track", "dance"], "figure.run"),
        (["health"], "heart"),
        (["science"], "testtube.2"),
    ]

    static func symbol(for name: String) -> String {
        let n = " " + name.lowercased() + " "
        for rule in rules where rule.keys.contains(where: { n.contains($0) }) { return rule.symbol }
        return "graduationcap"
    }
}
