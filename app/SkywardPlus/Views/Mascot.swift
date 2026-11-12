#if os(macOS)
import SwiftUI

/// What Nimbus is up to.
enum MascotAct: Equatable {
    case walk, look, sit, fiddle, nap, cheer, sad
}

/// A grade reaction the model asks for after a sync.
struct MascotReaction: Equatable {
    var act: MascotAct
    var id = UUID()
}

/// Nimbus's mind: where he is, what he's doing, and the little bits that float
/// around him. One shared instance, so he stays put when you change screens.
final class MascotBrain {
    static let shared = MascotBrain()

    struct Particle {
        enum Kind { case drop, z, spark }
        var kind: Kind
        var x: Double
        var y: Double
        var born: Double
    }

    private(set) var x: Double = 6
    private(set) var face = 1
    private(set) var act: MascotAct = .walk
    private(set) var frame = 0
    private(set) var look = 0
    private(set) var oy = 0
    private(set) var particles: [Particle] = []
    private var target: Double = 30
    private var until: Double = 0
    private var reactionUntil: Double = 0
    private var last: Double = 0
    private var frameAt: Double = 0
    private var lookAt: Double = 0
    private var blinkUntil: Double = 0
    private var nextBlink: Double = 0
    private var lastSpawn: Double = 0
    private var cols = 60

    static let width = 20

    func isBlinking(_ now: Double) -> Bool { now < blinkUntil }

    func react(_ next: MascotAct, now: Double, seconds: Double = 6) {
        act = next
        reactionUntil = now + seconds
        particles.removeAll()
    }

    /// The pixel rectangle he occupies, for taps.
    func bounds(pixel: CGFloat) -> CGRect {
        CGRect(x: CGFloat(Int(x.rounded()) - 2) * pixel, y: CGFloat(oy - 3) * pixel,
               width: CGFloat(Self.width + 4) * pixel, height: 15 * pixel)
    }

    func step(now: Double, cols: Int, rows: Int, reduceMotion: Bool) {
        let dt = last == 0 ? 0 : min(0.05, now - last)
        last = now
        self.cols = cols
        let minX = 3.0, maxX = max(3.0, Double(cols - Self.width - 4))
        x = min(max(x, minX), maxX)
        target = min(max(target, minX), maxX)

        if now < reactionUntil {
            // A reaction plays out before anything else.
        } else if act == .cheer || act == .sad {
            act = .look
            until = now + 2
            particles.removeAll()
        } else if reduceMotion || maxX - minX < 4 {
            act = .sit
        } else if act == .walk {
            if abs(target - x) < 0.5 {
                let choices: [(MascotAct, Double)] = [(.look, 3), (.look, 3), (.fiddle, 6), (.sit, 6), (.nap, 10)]
                let pick = choices.randomElement()!
                act = pick.0
                until = now + pick.1
            }
        } else if now > until {
            act = .walk
            target = Double.random(in: minX...maxX)
        }

        if act == .walk {
            face = target > x ? 1 : -1
            x += Double(face) * min(4.2 * dt, abs(target - x))
        }
        if now - frameAt > 0.17 { frame ^= 1; frameAt = now }
        if act == .look, now - lookAt > 0.7 { look = look >= 0 ? -1 : 1; lookAt = now }
        if now > nextBlink { blinkUntil = now + 0.13; nextBlink = now + Double.random(in: 2.2...4.2) }

        // Where his body sits this frame: standing, sitting, breathing or mid-jump.
        let ground = rows - 1
        let sitting = act == .sit || act == .fiddle || act == .nap
        var top = sitting ? ground - 9 : ground - 11
        if act == .nap { top += Int(now / 0.9) % 2 }
        if act == .cheer {
            let phase = now.truncatingRemainder(dividingBy: 0.95) / 0.7
            if phase < 1 { top -= Int((6 * sin(.pi * phase)).rounded()) }
        }
        oy = top

        // Rain, sleepy Zs and sparkles.
        switch act {
        case .sad where now - lastSpawn > 0.11:
            particles.append(Particle(kind: .drop, x: x + Double.random(in: 2...17), y: Double(oy + 9), born: now))
            lastSpawn = now
        case .nap where now - lastSpawn > 1.3:
            particles.append(Particle(kind: .z, x: x + (face > 0 ? 18 : 0), y: Double(oy - 2), born: now))
            lastSpawn = now
        case .cheer where now - lastSpawn > 0.26:
            particles.append(Particle(kind: .spark, x: x + Double.random(in: -5...24), y: Double(oy) + Double.random(in: -6...3), born: now))
            lastSpawn = now
        default:
            break
        }
        particles = particles.compactMap { p in
            var p = p
            let age = now - p.born
            switch p.kind {
            case .drop:
                p.y += 13 * dt
                return p.y < Double(ground) ? p : nil
            case .z:
                return age < 2.6 ? p : nil
            case .spark:
                return age < 0.7 ? p : nil
            }
        }
    }
}

/// The strip along the bottom of a page where Nimbus lives. Shown only when the
/// page leaves that much room empty.
struct MascotLane: View {
    static let pixel: CGFloat = 4
    static let rows = 20
    static var height: CGFloat { CGFloat(rows) * pixel }

    @Environment(AppModel.self) private var model
    @Environment(\.backgroundTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    private let brain = MascotBrain.shared

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: activeState == .inactive && !isKey)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let cols = Int(geo.size.width / Self.pixel)
                let _ = brain.step(now: now, cols: cols, rows: Self.rows, reduceMotion: reduceMotion)
                Canvas { context, _ in
                    MascotPainter(brain: brain, now: now, pixel: Self.pixel, accent: model.theme.color,
                                  outlined: !theme.isDark).paint(in: &context)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                if brain.bounds(pixel: Self.pixel).contains(point) {
                    brain.react(.cheer, now: Date().timeIntervalSinceReferenceDate, seconds: 1.4)
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel("Nimbus, a little cloud")
        .accessibilityHint("Reacts to new grades")
        .onChange(of: model.mascotReaction) { _, reaction in
            guard let reaction else { return }
            brain.react(reaction.act, now: Date().timeIntervalSinceReferenceDate)
        }
    }

    /// Keeps him moving while the window is in front even if SwiftUI reports a
    /// stale inactive state.
    private var isKey: Bool { NSApp.isActive }
}

/// Draws one frame of Nimbus, pixel by pixel.
private struct MascotPainter {
    let brain: MascotBrain
    let now: Double
    let pixel: CGFloat
    let accent: Color
    let outlined: Bool

    private static let body = [
        "........wwww........",
        "..www..wwwwww.www...",
        ".wwwwwwwwwwwwwwwwww.",
        "wwwwwwwwwwwwwwwwwwww",
        "wwwwwwwwwwwwwwwwwwww",
        "wwwwwwwwwwwwwwwwwwww",
        "wwwwwwwwwwwwwwwwwwww",
        "swwwwwwwwwwwwwwwwwws",
        ".ssssssssssssssssss.",
    ].map { Array($0) }

    private var sad: Bool { brain.act == .sad }
    private var white: Color { sad ? Color(hex: 0xD3D9E8) : Color(hex: 0xEEF2FF) }
    private var shade: Color { sad ? Color(hex: 0x9AA7C8) : Color(hex: 0xB7C5EA) }
    private let ink = Color(hex: 0x1E2440)
    private let cheek = Color(hex: 0xF4A7BC)
    private let pencil = Color(hex: 0xF2B33D)
    private let rain = Color(hex: 0x7FB3E8)
    private let zColor = Color(hex: 0x9AA6C8)
    private let rim = Color(hex: 0x8F9BC0)

    func paint(in context: inout GraphicsContext) {
        let act = brain.act
        let sitting = act == .sit || act == .fiddle || act == .nap
        let f = brain.frame
        var cells: [(Int, Int, Color)] = []
        func px(_ c: Int, _ r: Int, _ color: Color) { cells.append((c, r, color)) }

        // Cap and tassel. A lighter navy on dark pages, where ink would vanish.
        let cap = outlined ? ink : Color(hex: 0x3A4578)
        for c in 6...13 { px(c, -2, cap) }
        for c in 8...11 { px(c, -1, cap) }
        px(13, -1, accent)
        px(13, 0, accent)

        // Body.
        for (r, row) in Self.body.enumerated() {
            for (c, k) in row.enumerated() where k != "." {
                px(c, r, k == "s" ? shade : white)
            }
        }

        // Arms.
        switch act {
        case .walk: px(-1, f == 1 ? 6 : 5, shade); px(20, f == 1 ? 5 : 6, shade)
        case .cheer: px(-1, 4, shade); px(-2, 3, shade); px(20, 4, shade); px(21, 3, shade)
        case .fiddle: px(-1, 6, shade); px(20, 4, shade); px(21, 3, shade)
        case .sad, .nap: px(-1, 6, shade); px(20, 6, shade)
        default: px(-1, 5, shade); px(20, 5, shade)
        }

        // Legs.
        if act == .walk {
            if f == 1 { px(6, 9, shade); px(5, 10, shade); px(13, 9, shade); px(14, 10, shade) }
            else { px(6, 9, shade); px(7, 10, shade); px(13, 9, shade); px(12, 10, shade) }
        } else if !sitting {
            px(6, 9, shade); px(6, 10, shade); px(13, 9, shade); px(13, 10, shade)
        }

        // Face.
        let lx = act == .walk ? 1 : act == .look ? brain.look : 0
        for (i, ec) in [6 + lx, 13 + lx].enumerated() {
            switch act {
            case .cheer: px(ec - 1, 5, ink); px(ec, 4, ink); px(ec + 1, 5, ink)
            case .nap: px(ec, 5, ink); px(ec + (i == 1 ? -1 : 1), 5, ink)
            case .sad: px(ec, 5, ink); px(ec, 6, ink)
            default:
                if brain.isBlinking(now) { px(ec, 5, ink) } else { px(ec, 4, ink); px(ec, 5, ink) }
            }
        }
        if act != .sad { px(4, 6, cheek); px(15, 6, cheek) }
        if act == .cheer { px(9, 6, ink); px(10, 6, ink) }
        if act == .sad { px(9, 7, ink); px(10, 7, ink) }

        // The pencil he twirls and tosses.
        if act == .fiddle {
            let m = now.truncatingRemainder(dividingBy: 3.2)
            let toss = m < 0.7 ? Int((5 * sin(.pi * m / 0.7)).rounded()) : 0
            if Int(now / 0.3) % 2 == 1 {
                for c in 22...24 { px(c, 1 - toss, pencil) }
                px(25, 1 - toss, cheek)
            } else {
                for r in 0...2 { px(22, r - toss, pencil) }
                px(22, -1 - toss, cheek)
            }
        }

        let ox = Int(brain.x.rounded())
        let oy = brain.oy
        func rect(_ c: Int, _ r: Int) -> CGRect {
            let cc = brain.face > 0 ? c : MascotBrain.width - 1 - c
            return CGRect(x: CGFloat(ox + cc) * pixel, y: CGFloat(oy + r) * pixel, width: pixel, height: pixel)
        }

        // A soft shadow on the ground.
        do {
            let ground = MascotLane.rows - 1
            let shadow = CGRect(x: CGFloat(ox + 3) * pixel, y: CGFloat(ground) * pixel, width: 14 * pixel, height: pixel)
            context.fill(Path(shadow), with: .color(.black.opacity(0.14)))
        }

        // On light pages a faint rim keeps the white cloud from vanishing.
        if outlined {
            let filled = Set(cells.map { "\($0.0),\($0.1)" })
            var rimCells = Set<String>()
            for (c, r, _) in cells {
                for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !filled.contains("\(c + dc),\(r + dr)") {
                    rimCells.insert("\(c + dc),\(r + dr)")
                }
            }
            for key in rimCells {
                let parts = key.split(separator: ",").compactMap { Int($0) }
                context.fill(Path(rect(parts[0], parts[1])), with: .color(rim.opacity(0.55)))
            }
        }
        for (c, r, color) in cells { context.fill(Path(rect(c, r)), with: .color(color)) }

        // Particles live in lane coordinates, not body coordinates.
        func abs(_ x: Double, _ y: Double, _ color: Color, _ alpha: Double = 1) {
            let r = CGRect(x: CGFloat(x.rounded()) * pixel, y: CGFloat(y.rounded()) * pixel, width: pixel, height: pixel)
            context.fill(Path(r), with: .color(color.opacity(alpha)))
        }
        for p in brain.particles {
            let age = now - p.born
            switch p.kind {
            case .drop:
                abs(p.x, p.y, rain); abs(p.x, p.y + 1, rain)
            case .z:
                let zx = p.x + age * 1.2 * Double(brain.face), zy = p.y - age * 2, alpha = max(0, 1 - age / 2.6)
                for q in [(0, 0), (1, 0), (2, 0), (1, 1), (0, 2), (1, 2), (2, 2)] {
                    abs(zx + Double(q.0), zy + Double(q.1), zColor, alpha)
                }
            case .spark:
                abs(p.x, p.y, pencil)
                if age < 0.4 {
                    for q in [(-1, 0), (1, 0), (0, -1), (0, 1)] { abs(p.x + Double(q.0), p.y + Double(q.1), pencil) }
                }
            }
        }
    }
}
#endif
