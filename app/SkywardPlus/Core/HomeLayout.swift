import Foundation

/// The sections of Home the student can reorder and hide.
enum HomeSection: String, CaseIterable, Codable, Identifiable {
    case gradesStrip, bell, needsYou, recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gradesStrip: return "Grades at a glance"
        case .bell: return "Bell countdown"
        case .needsYou: return "Needs You"
        case .recent: return "Recent Grades"
        }
    }

    var symbol: String {
        switch self {
        case .gradesStrip: return "chart.bar.fill"
        case .bell: return "bell.fill"
        case .needsYou: return "exclamationmark.circle.fill"
        case .recent: return "clock.arrow.circlepath"
        }
    }

    /// Full-width sections sit on their own row; the rest share columns.
    var isWide: Bool { self == .gradesStrip || self == .bell }

    static let defaultOrder: [HomeSection] = [.gradesStrip, .bell, .needsYou, .recent]

    /// The saved order, with any section added in a later version appended.
    static func ordered(_ saved: [String]?) -> [HomeSection] {
        var seen = Set<HomeSection>()
        var out: [HomeSection] = []
        for raw in saved ?? [] {
            if let s = HomeSection(rawValue: raw), seen.insert(s).inserted { out.append(s) }
        }
        for s in defaultOrder where !seen.contains(s) { out.append(s) }
        return out
    }

    /// Splits visible sections into rows: each wide section alone, and runs of
    /// column sections together, keeping the student's order.
    static func rows(_ visible: [HomeSection]) -> [[HomeSection]] {
        var rows: [[HomeSection]] = []
        for s in visible {
            if s.isWide {
                rows.append([s])
            } else if let last = rows.last, let first = last.first, !first.isWide {
                rows[rows.count - 1].append(s)
            } else {
                rows.append([s])
            }
        }
        return rows
    }
}
