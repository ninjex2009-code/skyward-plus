import SwiftUI

/// A burst of confetti for great new grades, in the classes' own colors.
struct Celebration: Equatable {
    var id = UUID()
    /// 1 for a great grade, 2 for 95+, 3 for 100.
    var strength: Int
    var colors: [ClassColor]
}

/// Plays the model's celebration once over everything, then disappears.
/// Clicks pass straight through, and it stays still with Reduce Motion on.
struct CelebrationOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var pieces: [Piece] = []

    private struct Piece {
        var x: Double, vx: Double, vy: Double, spin: Double, size: Double, color: Color, shape: Int, delay: Double
    }

    private let duration = 3.2

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let life = t - p.delay
                    guard life > 0 else { continue }
                    let x = p.x * size.width + p.vx * life * 60
                    let y = -20 + p.vy * life * 60 + 0.5 * 220 * life * life
                    guard y < size.height + 30 else { continue }
                    let fade = min(1, max(0, (duration - t) / 0.6))
                    var piece = context
                    piece.opacity = fade
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(p.spin * life))
                    // Paper flutter: squash one way as it turns.
                    piece.scaleBy(x: 1, y: abs(cos(p.spin * life * 1.7)) * 0.8 + 0.2)
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)
                    let path = p.shape == 0 ? Path(roundedRect: rect, cornerRadius: 1.5) : Path(ellipseIn: rect.insetBy(dx: p.size * 0.2, dy: 0))
                    piece.fill(path, with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onChange(of: model.celebration) { _, celebration in
            guard let celebration, !reduceMotion else { return }
            launch(celebration)
        }
    }

    private func launch(_ c: Celebration) {
        let palette = (c.colors.isEmpty ? [ClassColor.blue] : c.colors).map { Color(hex: $0.hex) }
            + [model.theme.color, Color(hex: 0xFFD166), Color.white]
        let count = 70 + c.strength * 60
        pieces = (0..<count).map { i in
            Piece(x: Double.random(in: 0.05...0.95), vx: Double.random(in: -1.2...1.2), vy: Double.random(in: 0.5...2.5),
                  spin: Double.random(in: -8...8), size: Double.random(in: 7...13), color: palette[i % palette.count],
                  shape: Int.random(in: 0...1), delay: Double.random(in: 0...0.5))
        }
        start = Date()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if self.start != nil { self.start = nil; self.pieces = [] }
        }
    }
}
