#if os(macOS)
import SwiftUI

/// What Nimbus is up to.
enum MascotAct: Equatable {
    case walk, look, sit, fiddle, nap, float, cheer, sad, wave, stretch, hop
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
        enum Kind { case drop, z, spark, wisp }
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
    /// Top row of his body in lane pixels.
    private(set) var oy = 0
    /// How high he is floating, in pixels above the ground.
    private(set) var altitude: Double = 0
    private(set) var particles: [Particle] = []
    private(set) var ground = 19
    private var target: Double = 30
    private var altitudeTarget: Double = 0
    private var until: Double = 0
    private var reactionUntil: Double = 0
    private var last: Double = 0
    private var frameAt: Double = 0
    private var lookAt: Double = 0
    private var blinkUntil: Double = 0
    private var nextBlink: Double = 0
    private var lastSpawn: Double = 0
    private var lastWisp: Double = 0

    static let width = 20

    #if DEBUG
    init() {
        // SKYWARDPLUS_MASCOT=float|sad|cheer starts him that way, for screenshots.
        switch ProcessInfo.processInfo.environment["SKYWARDPLUS_MASCOT"] {
        case "float": act = .float; altitude = 14; altitudeTarget = 14; x = 60; target = 60
        case "sad": act = .sad; reactionUntil = .greatestFiniteMagnitude; x = 60; target = 60
        case "cheer": act = .cheer; reactionUntil = .greatestFiniteMagnitude; x = 60; target = 60
        case "wave": act = .wave; until = .greatestFiniteMagnitude; x = 60; target = 60
        case "stretch": act = .stretch; until = .greatestFiniteMagnitude; x = 60; target = 60
        default: break
        }
    }
    #endif

    var airborne: Bool { altitude > 0.6 }

    func isBlinking(_ now: Double) -> Bool { now < blinkUntil }

    func react(_ next: MascotAct, now: Double, seconds: Double = 6) {
        act = next
        reactionUntil = now + seconds
        particles.removeAll { $0.kind != .wisp }
    }

    /// The pixel rectangle he occupies, for taps.
    func bounds(pixel: CGFloat) -> CGRect {
        CGRect(x: CGFloat(Int(x.rounded()) - 2) * pixel, y: CGFloat(oy - 3) * pixel,
               width: CGFloat(Self.width + 4) * pixel, height: 15 * pixel)
    }

    func step(now: Double, cols: Int, rows: Int, reduceMotion: Bool) {
        let dt = last == 0 ? 0 : min(0.05, now - last)
        last = now
        ground = rows - 1
        let minX = 3.0, maxX = max(3.0, Double(cols - Self.width - 4))
        // Room to float: the lane minus his height, the cap and a margin for sparkles.
        let maxAltitude = Double(max(0, rows - 22))
        let canFloat = maxAltitude >= 6 && !reduceMotion
        x = min(max(x, minX), maxX)
        target = min(max(target, minX), maxX)
        altitudeTarget = min(altitudeTarget, maxAltitude)

        func startFloating() {
            act = .float
            target = Double.random(in: minX...maxX)
            altitudeTarget = Double.random(in: min(6, maxAltitude)...maxAltitude)
        }

        if now < reactionUntil {
            // A reaction plays out before anything else, wherever he is.
        } else if act == .cheer || act == .sad {
            act = airborne ? .float : .look
            until = now + 2
            particles.removeAll { $0.kind != .wisp }
            if act == .float { target = x }
        } else if reduceMotion || maxX - minX < 4 {
            act = .sit
            altitudeTarget = 0
            altitude = 0
        } else {
            switch act {
            case .walk:
                if abs(target - x) < 0.5 {
                    var choices: [(MascotAct, Double)] = [(.look, 3), (.look, 3), (.fiddle, 6), (.sit, 6), (.nap, 10),
                                                         (.wave, 2.4), (.stretch, 2.6), (.hop, 1.9)]
                    if canFloat { choices += [(.float, 0), (.float, 0)] }
                    let pick = choices.randomElement()!
                    if pick.0 == .float { startFloating() } else { act = pick.0; until = now + pick.1 }
                }
            case .float:
                let there = abs(target - x) < 0.5 && abs(altitudeTarget - altitude) < 0.3
                if there {
                    if altitudeTarget > 0, Bool.random() {
                        // Drift somewhere else, or come down for a rest.
                        target = Double.random(in: minX...maxX)
                        altitudeTarget = Double.random(in: min(6, maxAltitude)...max(min(6, maxAltitude), maxAltitude))
                    } else if altitudeTarget > 0 {
                        altitudeTarget = 0
                    } else {
                        altitude = 0
                        act = .look
                        until = now + 2
                    }
                }
            default:
                if now > until {
                    if canFloat, Double.random(in: 0...1) < 0.45 { startFloating() } else {
                        act = .walk
                        target = Double.random(in: minX...maxX)
                    }
                }
            }
        }

        if act == .walk {
            face = target > x ? 1 : -1
            x += Double(face) * min(4.2 * dt, abs(target - x))
        } else if act == .float {
            if abs(target - x) > 0.3 { face = target > x ? 1 : -1 }
            x += Double(face) * min(2.6 * dt, abs(target - x))
        }
        // Rise and settle smoothly, wherever he is.
        if act != .walk {
            let goal = act == .float || now < reactionUntil ? altitudeTarget : 0
            altitude += (goal - altitude) * min(1, 1.6 * dt)
            if abs(goal - altitude) < 0.05 { altitude = goal }
        } else {
            altitude = 0
        }

        if now - frameAt > 0.17 { frame ^= 1; frameAt = now }
        if act == .look, now - lookAt > 0.7 { look = look >= 0 ? -1 : 1; lookAt = now }
        if now > nextBlink { blinkUntil = now + 0.13; nextBlink = now + Double.random(in: 2.2...4.2) }

        // Where his body sits this frame: standing, sitting, breathing, floating or mid-jump.
        let sitting = act == .sit || act == .fiddle || act == .nap
        var top = sitting ? ground - 9 : ground - 11
        if act == .nap { top += Int(now / 0.9) % 2 }
        if act == .walk { top -= frame }  // a little bounce in his step
        if act == .hop {
            let phase = now.truncatingRemainder(dividingBy: 0.62) / 0.5
            if phase < 1 { top -= Int((4 * sin(.pi * phase)).rounded()) }
        }
        if act == .stretch { top -= Int(now / 0.65) % 2 }
        if airborne {
            top -= Int(altitude.rounded())
            top += Int((sin(now * 2.1) * 1.2).rounded())
        }
        if act == .cheer {
            let phase = now.truncatingRemainder(dividingBy: 0.95) / 0.7
            if phase < 1 { top -= Int((6 * sin(.pi * phase)).rounded()) }
        }
        oy = top

        // Rain, sleepy Zs, sparkles and the wisps a floating cloud leaves behind.
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
        if airborne, now - lastWisp > 0.22 {
            let behind = face > 0 ? x - 1 : x + Double(Self.width)
            particles.append(Particle(kind: .wisp, x: behind, y: Double(oy) + Double.random(in: 3...8), born: now))
            lastWisp = now
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
            case .wisp:
                p.x -= Double(face) * 1.5 * dt
                return age < 1.1 ? p : nil
            }
        }
    }
}

/// The free space at the bottom of a page where Nimbus lives. Shown only when the
/// page leaves room for him; the more room, the higher he can float.
struct MascotLane: View {
    static let pixel: CGFloat = 5
    /// Enough for him to stand, with his cap and a hop.
    static let minimumHeight: CGFloat = 21 * pixel
    var height: CGFloat

    @Environment(AppModel.self) private var model
    @Environment(\.backgroundTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    private let brain = MascotBrain.shared

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: activeState == .inactive && !NSApp.isActive)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let cols = Int(geo.size.width / Self.pixel)
                let rows = Int(geo.size.height / Self.pixel)
                let _ = brain.step(now: now, cols: cols, rows: rows, reduceMotion: reduceMotion)
                Canvas { context, _ in
                    MascotPainter(brain: brain, now: now, pixel: Self.pixel, accent: model.theme.color,
                                  dark: theme.isDark).paint(in: &context)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                if brain.bounds(pixel: Self.pixel).contains(point) {
                    brain.react(.cheer, now: Date().timeIntervalSinceReferenceDate, seconds: 1.4)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Nimbus, a little cloud")
        .accessibilityHint("Reacts to new grades")
        .onChange(of: model.mascotReaction) { _, reaction in
            guard let reaction else { return }
            brain.react(reaction.act, now: Date().timeIntervalSinceReferenceDate)
        }
    }
}

/// Draws one frame of Nimbus, pixel by pixel, with soft shading that sets him in the page.
private struct MascotPainter {
    let brain: MascotBrain
    let now: Double
    let pixel: CGFloat
    let accent: Color
    let dark: Bool

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
        let airborne = brain.airborne
        let f = brain.frame
        var cells: [(Int, Int, Color)] = []
        func px(_ c: Int, _ r: Int, _ color: Color) { cells.append((c, r, color)) }

        // Cap and tassel. A lighter navy on dark pages, where ink would vanish.
        let cap = dark ? Color(hex: 0x3A4578) : ink
        for c in 6...13 { px(c, -2, cap) }
        for c in 8...11 { px(c, -1, cap) }
        px(13, -1, accent)
        px(13, 0, accent)
        if airborne { px(14, 1, accent) }  // the tassel trails in the breeze

        // Body.
        for (r, row) in Self.body.enumerated() {
            for (c, k) in row.enumerated() where k != "." {
                px(c, r, k == "s" ? shade : white)
            }
        }

        // Arms: floating, he spreads them a little and paddles slowly.
        switch act {
        case .walk: px(-1, f == 1 ? 6 : 5, shade); px(20, f == 1 ? 5 : 6, shade)
        case .cheer: px(-1, 4, shade); px(-2, 3, shade); px(20, 4, shade); px(21, 3, shade)
        case .fiddle: px(-1, 6, shade); px(20, 4, shade); px(21, 3, shade)
        case .sad, .nap: px(-1, 6, shade); px(20, 6, shade)
        case .wave:
            let up = Int(now / 0.22) % 2 == 0
            px(-1, 5, shade); px(20, up ? 3 : 4, shade); px(21, up ? 2 : 3, shade)
        case .stretch:
            px(-1, 3, shade); px(-2, 2, shade); px(20, 3, shade); px(21, 2, shade)
        case .hop:
            px(-1, 4, shade); px(20, 4, shade)
        case .float:
            let up = Int(now / 0.5) % 2 == 0
            px(-1, up ? 4 : 5, shade); px(-2, up ? 4 : 5, shade); px(20, up ? 5 : 4, shade); px(21, up ? 5 : 4, shade)
        default: px(-1, 5, shade); px(20, 5, shade)
        }

        // Legs: tucked up while floating, just two little nubs.
        if airborne {
            px(7, 9, shade); px(12, 9, shade)
        } else if act == .walk {
            if f == 1 { px(6, 9, shade); px(5, 10, shade); px(13, 9, shade); px(14, 10, shade) }
            else { px(6, 9, shade); px(7, 10, shade); px(13, 9, shade); px(12, 10, shade) }
        } else if !sitting {
            px(6, 9, shade); px(6, 10, shade); px(13, 9, shade); px(13, 10, shade)
        }

        // Face.
        let lx = act == .walk || act == .float ? 1 : act == .look ? brain.look : 0
        for (i, ec) in [6 + lx, 13 + lx].enumerated() {
            switch act {
            case .cheer, .wave, .hop: px(ec - 1, 5, ink); px(ec, 4, ink); px(ec + 1, 5, ink)
            case .stretch: px(ec - 1, 5, ink); px(ec, 5, ink)
            case .nap: px(ec, 5, ink); px(ec + (i == 1 ? -1 : 1), 5, ink)
            case .sad: px(ec, 5, ink); px(ec, 6, ink)
            default:
                if brain.isBlinking(now) { px(ec, 5, ink) } else { px(ec, 4, ink); px(ec, 5, ink) }
            }
        }
        if act != .sad { px(4 + lx, 6, cheek); px(15 + lx, 6, cheek) }
        if act == .cheer { px(9, 6, ink); px(10, 6, ink) }
        if act == .stretch, Int(now / 0.65) % 2 == 1 { px(9, 6, ink); px(10, 6, ink); px(9, 7, ink); px(10, 7, ink) }  // a big yawn
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

        // Shading that sets him in the page.
        // 1. A soft contact shadow on the ground, smaller and fainter the higher he floats.
        let height = CGFloat(brain.altitude)
        let spread = max(0.45, 1 - height / 40)
        let groundY = CGFloat(brain.ground) * pixel
        let centerX = CGFloat(ox) * pixel + CGFloat(MascotBrain.width) * pixel / 2
        let shadowWidth = 17 * pixel * spread
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3 + height * 0.25))
            layer.fill(Path(ellipseIn: CGRect(x: centerX - shadowWidth / 2, y: groundY - pixel * 0.6,
                                              width: shadowWidth, height: pixel * 1.8)),
                       with: .color(.black.opacity((dark ? 0.42 : 0.2) * Double(spread))))
        }
        // 2. His silhouette cast softly onto the page behind him, as if lit from the top left.
        context.drawLayer { layer in
            layer.opacity = dark ? 0.32 : 0.16
            layer.addFilter(.blur(radius: pixel * 1.4))
            layer.translateBy(x: pixel * 1.5, y: pixel * 2.2)
            for (c, r, _) in cells { layer.fill(Path(rect(c, r)), with: .color(.black)) }
        }

        // 3. A faint glow around him on dark pages, so the white reads as soft cloud.
        if dark {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 10))
                let glow = CGRect(x: CGFloat(ox - 2) * pixel, y: CGFloat(oy - 1) * pixel,
                                  width: CGFloat(MascotBrain.width + 4) * pixel, height: 11 * pixel)
                layer.fill(Path(roundedRect: glow, cornerRadius: 5 * pixel), with: .color(Color(hex: 0xC9D6FF).opacity(0.10)))
            }
        }

        // On light pages a faint rim keeps the white cloud from vanishing.
        if !dark {
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
            case .wisp:
                let alpha = max(0, 0.7 - age / 1.1 * 0.7)
                abs(p.x, p.y, white, alpha)
                if age < 0.5 { abs(p.x - Double(brain.face), p.y, white, alpha * 0.6) }
            }
        }
    }
}
#endif
