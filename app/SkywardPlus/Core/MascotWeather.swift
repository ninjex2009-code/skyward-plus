import Foundation

/// Nimbus's own little weather, from how recent grades went.
enum MascotWeather: Equatable {
    case clear, sun, rain, rainbow

    /// From the last few days' new grades.
    static func from(changes: [GradeChange], now: Date) -> MascotWeather {
        let since = now.addingTimeInterval(-3 * 86_400)
        let scores = changes.filter { $0.date > since && ($0.kind == .newGrade || $0.kind == .updatedGrade) }.compactMap(\.newValue)
        guard !scores.isEmpty else { return .clear }
        if scores.contains(where: { $0 < 70 }) { return .rain }
        let average = scores.reduce(0, +) / Double(scores.count)
        if scores.count >= 2, average >= 95 { return .rainbow }
        return average >= 88 ? .sun : .clear
    }
}
