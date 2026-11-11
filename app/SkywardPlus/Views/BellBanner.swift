import SwiftUI

/// The current period and the time left in it. Shown only while school is in session.
struct BellBannerCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = BellMath.status(at: context.date, config: model.prefs.bell)
            if let line = BellBannerCard.line(for: status) {
                Button {
                    model.section = .bell
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.title).font(.headline)
                                Text(line.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            if let seconds = status.secondsLeft {
                                Text(BellMath.countdown(seconds))
                                    .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                                    .contentTransition(.numericText(countsDown: true))
                                    .accessibilityLabel("\(seconds / 60) minutes left")
                            }
                        }
                        if let progress = status.progress {
                            ProgressBar(value: progress, tint: model.theme.color, height: 4)
                        }
                    }
                    .padding(14)
                    .glassSurface(cornerRadius: 14)
                    .hoverSheen(cornerRadius: 14)
                    .contentShape(.rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .hoverLift()
            }
        }
    }

    static func line(for status: BellStatus) -> (title: String, detail: String)? {
        switch status.phase {
        case .during:
            guard let current = status.current else { return nil }
            let next = status.next.map { "Next: \($0.name) at \(BellMath.format($0.start))" } ?? "Last period today"
            return (current.name, "Ends \(BellMath.format(current.end)) · \(next)")
        case .passing:
            guard let next = status.next else { return nil }
            return ("Passing period", "\(next.name) starts at \(BellMath.format(next.start))")
        case .before:
            // Only in the hour before school, not all night.
            guard let next = status.next, let left = status.secondsLeft, left <= 3600 else { return nil }
            return ("School starts soon", "\(next.name) at \(BellMath.format(next.start))")
        case .after, .noSchool:
            return nil
        }
    }
}
