import SwiftUI

/// What Nimbus is up to.
enum MascotAct: Equatable {
    case walk, look, sit, fiddle, nap, float, cheer, sad, wave, stretch, hop, study, perch
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
    /// Where he's headed and what he'll do when he gets there.
    private var pending: MascotAct?
    private var perchPending = false
    /// Where his desk and hammock stand, in lane pixels, when there's room for them.
    private(set) var deskX: Int?
    private(set) var hammockX: Int?
    private(set) var inHammock = false
    private var perchTop: Int?
    private(set) var mood: MascotWeather = .clear
    private var moodAt: Double = -100

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
        case "study", "hammock", "perch": debugPlace = ProcessInfo.processInfo.environment["SKYWARDPLUS_MASCOT"]
        case "rain": debugMood = .rain; act = .look; until = .greatestFiniteMagnitude; x = 60; target = 60
        case "sun": debugMood = .sun; act = .sit; until = .greatestFiniteMagnitude; x = 60; target = 60
        case "rainbow": debugMood = .rainbow; act = .look; until = .greatestFiniteMagnitude; x = 60; target = 60
        default: break
        }
        if let debugMood { mood = debugMood }
    }
    private var debugPlace: String?
    private var debugMood: MascotWeather?

    /// Puts him straight into a scene for screenshots.
    private func placeForDebug(perches: [CGRect], pixel: CGFloat) {
        guard let place = debugPlace else { return }
        switch place {
        case "study":
            guard let deskX else { return }
            act = .study; x = Double(deskX + 3); target = x; face = 1
        case "hammock":
            guard let hammockX else { return }
            act = .nap; inHammock = true; x = Double(hammockX + 4); target = x
        default:
            guard let rect = perches.filter({ $0.width > 200 && $0.minY > 100 }).max(by: { $0.minY < $1.minY }) else { return }
            let top = Int(rect.minY / pixel)
            act = .perch; perchTop = top; x = Double(Int(rect.minX / pixel) + 6); target = x
            altitude = Double(ground - top); altitudeTarget = altitude
        }
        until = .greatestFiniteMagnitude
        debugPlace = nil
    }
    #endif

    var airborne: Bool { altitude > 0.6 }

    func isBlinking(_ now: Double) -> Bool { now < blinkUntil }

    func react(_ next: MascotAct, now: Double, seconds: Double = 6) {
        act = next
        reactionUntil = now + seconds
        pending = nil
        perchPending = false
        inHammock = false
        particles.removeAll { $0.kind != .wisp }
    }

    /// The pixel rectangle he occupies, for taps.
    func bounds(pixel: CGFloat) -> CGRect {
        CGRect(x: CGFloat(Int(x.rounded()) - 2) * pixel, y: CGFloat(oy - 3) * pixel,
               width: CGFloat(Self.width + 4) * pixel, height: 15 * pixel)
    }

    /// Rechecks his weather now and then; it only changes with new grades.
    func updateMood(_ changes: [GradeChange], date: Date) {
        let now = date.timeIntervalSinceReferenceDate
        #if DEBUG
        if debugMood != nil { return }
        #endif
        guard now - moodAt > 5 else { return }
        moodAt = now
        mood = MascotWeather.from(changes: changes, now: date)
    }

    /// Shows his weather for a few seconds at a time, while he's idle.
    func showsWeather(_ now: Double) -> Bool {
        #if DEBUG
        if debugMood != nil { return true }
        #endif
        return mood != .clear && [.look, .sit, .fiddle, .stretch, .study, .perch, .wave].contains(act) && Int(now / 7) % 3 == 0
    }

    /// - Parameters:
    ///   - rows: the whole page's height in pixels; the ground is the bottom row.
    ///   - freeRows: how much of that, from the bottom, is empty for him to roam.
    ///   - perches: card frames (in points) he can climb onto and sit on.
    func step(now: Double, cols: Int, rows: Int, freeRows: Int, perches: [CGRect], pixel: CGFloat, reduceMotion: Bool) {
        let dt = last == 0 ? 0 : min(0.05, now - last)
        last = now
        ground = rows - 1
        let minX = 3.0, maxX = max(3.0, Double(cols - Self.width - 4))
        deskX = cols >= 70 ? max(4, Int(Double(cols) * 0.12)) : nil
        hammockX = cols >= 110 ? Int(Double(cols) * 0.62) : nil
        // Room to float: the free space minus his height, the cap and a margin for sparkles.
        let maxAltitude = Double(max(0, freeRows - 22))
        let canFloat = maxAltitude >= 6 && !reduceMotion
        x = min(max(x, minX), maxX)
        target = min(max(target, minX), maxX)
        if !perchPending && act != .perch { altitudeTarget = min(altitudeTarget, maxAltitude) }
        #if DEBUG
        placeForDebug(perches: perches, pixel: pixel)
        #endif

        // A card edge to sit on: wide enough, with room above it, nearest the free space.
        func perchSpot() -> (col: Double, altitude: Double)? {
            let usable = perches.filter { $0.width >= CGFloat(Self.width + 8) * pixel && $0.minY > 16 * pixel && $0.minY < CGFloat(ground - 20) * pixel }
            // One of the lowest few cards, so he doesn't always pick the same one.
            guard let rect = usable.sorted(by: { $0.minY > $1.minY }).prefix(3).randomElement() else { return nil }
            let lo = Double(Int(rect.minX / pixel) + 2), hi = Double(Int(rect.maxX / pixel) - Self.width - 2)
            guard hi > lo else { return nil }
            let top = Int(rect.minY / pixel)
            return (Double.random(in: lo...hi), Double(ground - top))
        }

        func choose() {
            var choices: [(MascotAct, Double)] = [(.look, 3), (.look, 3), (.fiddle, 6), (.sit, 6), (.nap, 10),
                                                 (.wave, 2.4), (.stretch, 2.6), (.hop, 1.9)]
            if canFloat { choices += [(.float, 0), (.float, 0)] }
            if deskX != nil { choices += [(.study, 12), (.study, 12)] }
            if canFloat, !perches.isEmpty { choices += [(.perch, 0), (.perch, 0)] }
            let pick = choices.randomElement()!
            switch pick.0 {
            case .float:
                startFloating()
            case .study:
                if let deskX { target = Double(deskX + 3); pending = .study; act = .walk }
            case .nap where hammockX != nil:
                target = Double(hammockX! + 4); pending = .nap; act = .walk
            case .perch:
                if let spot = perchSpot() {
                    act = .float; target = min(max(spot.col, minX), maxX); altitudeTarget = spot.altitude; perchPending = true
                } else {
                    act = .look; until = now + 3
                }
            default:
                act = pick.0; until = now + pick.1
            }
        }

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
            pending = nil
            perchPending = false
            altitudeTarget = 0
            altitude = 0
        } else {
            switch act {
            case .walk:
                if abs(target - x) < 0.5 {
                    if let next = pending {
                        pending = nil
                        act = next
                        until = now + (next == .study ? Double.random(in: 10...16) : Double.random(in: 9...14))
                        inHammock = next == .nap && hammockX != nil
                        if next == .study { face = 1 }
                    } else {
                        choose()
                    }
                }
            case .float:
                let there = abs(target - x) < 0.5 && abs(altitudeTarget - altitude) < 0.3
                if there {
                    if perchPending {
                        perchPending = false
                        act = .perch
                        perchTop = ground - Int(altitudeTarget.rounded())
                        until = now + Double.random(in: 8...14)
                    } else if altitudeTarget > 0, Bool.random() {
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
                if act == .perch, let lastTop = perchTop {
                    // Ride along with the card as the page scrolls, and hop off if it goes.
                    let center = CGFloat(x + Double(Self.width) / 2) * pixel
                    let tops = perches.filter { $0.minX < center && $0.maxX > center }.map { Int($0.minY / pixel) }
                    if let top = tops.min(by: { abs($0 - lastTop) < abs($1 - lastTop) }), abs(top - lastTop) < 40,
                       top > 16, top < ground - 12 {
                        perchTop = top
                        altitudeTarget = Double(ground - top)
                        altitude = altitudeTarget
                    } else {
                        until = 0
                    }
                }
                if now > until {
                    inHammock = false
                    perchTop = nil
                    if act == .perch {
                        // Float back down from the card.
                        act = .float; altitudeTarget = 0; target = x
                    } else if canFloat, Double.random(in: 0...1) < 0.45 { startFloating() } else {
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
            let goal = act == .float || act == .perch || now < reactionUntil ? altitudeTarget : 0
            altitude += (goal - altitude) * min(1, 1.6 * dt)
            if abs(goal - altitude) < 0.05 { altitude = goal }
        } else {
            altitude = 0
        }

        if now - frameAt > 0.17 { frame ^= 1; frameAt = now }
        if act == .look, now - lookAt > 0.7 { look = look >= 0 ? -1 : 1; lookAt = now }
        if now > nextBlink { blinkUntil = now + 0.13; nextBlink = now + Double.random(in: 2.2...4.2) }

        // Where his body sits this frame: standing, sitting, breathing, floating or mid-jump.
        let sitting = act == .sit || act == .fiddle || act == .nap || act == .perch
        var top = sitting ? ground - 9 : ground - 11
        if act == .study { top = ground - 16 }  // head and arms above the desk
        if act == .nap && inHammock { top = ground - 14 }  // face above the fabric
        if act == .nap { top += Int(now / 0.9) % 2 }
        if act == .walk { top -= frame }  // a little bounce in his step
        if act == .hop {
            let phase = now.truncatingRemainder(dividingBy: 0.62) / 0.5
            if phase < 1 { top -= Int((4 * sin(.pi * phase)).rounded()) }
        }
        if act == .stretch { top -= Int(now / 0.65) % 2 }
        if airborne {
            top -= Int(altitude.rounded())
            if act != .perch { top += Int((sin(now * 2.1) * 1.2).rounded()) }
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
        if airborne, act != .perch, now - lastWisp > 0.22 {
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

/// Card frames Nimbus can perch on, collected from the page without re-rendering it.
final class NimbusPerches {
    var rects: [CGRect] = []
}

struct NimbusPerchKey: PreferenceKey {
    static let space = "nimbus.page"
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value.append(contentsOf: nextValue()) }
}

/// Nimbus's layer over a page. He roams the free space at the bottom (the more
/// room, the higher he floats) and climbs onto the cards above it. Only Nimbus
/// himself catches clicks; everything else passes through to the page.
struct MascotLane: View {
    static let pixel: CGFloat = 5
    /// Enough for him to stand, with his cap and a hop.
    static let minimumHeight: CGFloat = 21 * pixel
    var freeHeight: CGFloat
    var perches: NimbusPerches

    @Environment(AppModel.self) private var model
    @Environment(\.backgroundTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    private let brain = MascotBrain.shared

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: phase != .active)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let cols = Int(geo.size.width / Self.pixel)
                let rows = Int(geo.size.height / Self.pixel)
                let _ = brain.updateMood(model.data.changes, date: timeline.date)
                let _ = brain.step(now: now, cols: cols, rows: rows, freeRows: Int(freeHeight / Self.pixel),
                                   perches: perches.rects, pixel: Self.pixel, reduceMotion: reduceMotion)
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        MascotPainter(brain: brain, now: now, pixel: Self.pixel, accent: model.theme.color,
                                      dark: theme.isDark).paint(in: &context)
                    }
                    .allowsHitTesting(false)
                    let hit = brain.bounds(pixel: Self.pixel)
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: hit.width, height: hit.height)
                        .offset(x: hit.minX, y: hit.minY)
                        .onTapGesture {
                            brain.react(.cheer, now: Date().timeIntervalSinceReferenceDate, seconds: 1.4)
                        }
                        .accessibilityElement()
                        .accessibilityLabel("Nimbus, a little cloud")
                        .accessibilityHint("Reacts to new grades")
                }
            }
        }
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

    // MARK: His world

    private let woodTop = Color(hex: 0xC48C58)
    private let woodEdge = Color(hex: 0x8C5B33)
    private let woodDark = Color(hex: 0x5E3B20)
    private let paper = Color(hex: 0xF3EFE4)
    private let canvas = Color(hex: 0xF1E9DA)

    /// Fills one lane pixel (not mirrored with his facing).
    private func cell(_ context: inout GraphicsContext, _ c: Int, _ r: Int, _ color: Color, _ alpha: Double = 1) {
        context.fill(Path(CGRect(x: CGFloat(c) * pixel, y: CGFloat(r) * pixel, width: pixel, height: pixel)),
                     with: .color(color.opacity(alpha)))
    }

    /// The study desk: a lamp, a stack of books and a sheet of paper. With him at
    /// it, it's drawn over him so he sits behind it.
    private func paintDesk(_ context: inout GraphicsContext, at d: Int, lit: Bool) {
        let g = brain.ground
        if lit {
            // Warm lamp light pooling on the desk and the wall behind.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 14))
                let glow = CGRect(x: CGFloat(d + 12) * pixel, y: CGFloat(g - 17) * pixel, width: 20 * pixel, height: 13 * pixel)
                layer.fill(Path(ellipseIn: glow), with: .color(Color(hex: 0xFFD27A).opacity(dark ? 0.32 : 0.4)))
            }
        }
        for c in d...(d + 31) { cell(&context, c, g - 7, woodTop); cell(&context, c, g - 6, woodEdge) }
        for r in (g - 5)...(g - 1) {
            cell(&context, d + 1, r, woodDark); cell(&context, d + 30, r, woodDark)
            if r > g - 5 { cell(&context, d + 2, r, woodEdge.opacity(0.6)) }
        }
        // Books, spines out.
        for c in (d + 1)...(d + 5) { cell(&context, c, g - 8, Color(hex: 0x4F7CAC)); cell(&context, c, g - 9, accent) }
        for c in (d + 2)...(d + 4) { cell(&context, c, g - 10, Color(hex: 0x6BAF7B)) }
        // The page he's working on.
        for c in (d + 9)...(d + 15) { cell(&context, c, g - 8, paper) }
        // The lamp: base, arm, shade and a bulb that glows while he works.
        for c in (d + 25)...(d + 28) { cell(&context, c, g - 8, woodDark) }
        for r in (g - 12)...(g - 9) { cell(&context, d + 26, r, Color(hex: 0x3C415C)) }
        for c in (d + 24)...(d + 29) { cell(&context, c, g - 13, accent) }
        for c in (d + 25)...(d + 28) { cell(&context, c, g - 14, accent) }
        if lit { for c in (d + 25)...(d + 28) { cell(&context, c, g - 12, Color(hex: 0xFFE4A3)) } }
    }

    /// The hammock between two posts. Its fabric sags; with him in it, the fabric
    /// is drawn over him so he lies in it.
    private func paintHammockPosts(_ context: inout GraphicsContext, at h: Int) {
        let g = brain.ground
        for r in (g - 15)...(g - 1) { cell(&context, h, r, woodDark); cell(&context, h + 28, r, woodDark) }
        cell(&context, h - 1, g - 15, woodEdge); cell(&context, h + 29, g - 15, woodEdge)
        // Ropes down to the fabric's ends.
        cell(&context, h + 1, g - 13, Color(hex: 0xC9B79A)); cell(&context, h + 2, g - 12, Color(hex: 0xC9B79A))
        cell(&context, h + 27, g - 13, Color(hex: 0xC9B79A)); cell(&context, h + 26, g - 12, Color(hex: 0xC9B79A))
    }

    private func paintHammockFabric(_ context: inout GraphicsContext, at h: Int, occupied: Bool) {
        let g = brain.ground
        let sway = occupied ? sin(now * 1.3) * 0.6 : 0
        for c in 3...25 {
            let t = Double(c - 3) / 22
            let r = g - 11 + Int((Double(occupied ? 5 : 3) * sin(.pi * t) + sway).rounded())
            let stripe = (c / 3) % 2 == 0 ? accent : canvas
            cell(&context, h + c, r, stripe)
            cell(&context, h + c, r + 1, stripe.opacity(0.85))
            if occupied {
                // Deeper cloth wrapped around him, so he sinks into it.
                cell(&context, h + c, r + 2, stripe.opacity(0.7))
                cell(&context, h + c, r + 3, stripe.opacity(0.55))
            }
            cell(&context, h + c, r + (occupied ? 4 : 2), Color.black, dark ? 0.18 : 0.08)
        }
    }

    /// His own little weather, above his cap: a raincloud, a sun or a rainbow.
    private func paintWeather(_ context: inout GraphicsContext) {
        let ox = Int(brain.x.rounded()), top = brain.oy - 4
        switch brain.mood {
        case .rain:
            let cloud = Color(hex: 0x8892AE)
            for c in 6...14 { cell(&context, ox + c, top - 3, cloud) }
            for c in 5...15 { cell(&context, ox + c, top - 2, cloud) }
            for c in 7...10 { cell(&context, ox + c, top - 4, cloud) }
            for c in 11...13 { cell(&context, ox + c, top - 4, cloud.opacity(0.85)) }
            let fall = Int(now / 0.14) % 3
            for (i, c) in [6, 9, 12, 15].enumerated() {
                let r = top - 1 + (fall + i) % 3
                cell(&context, ox + c, r, rain)
            }
        case .sun:
            let sun = Color(hex: 0xFFC94A), cx = ox + 17, cy = top - 4
            for dr in -2...2 { for dc in -2...2 where abs(dr) + abs(dc) < 4 { cell(&context, cx + dc, cy + dr, sun) } }
            if Int(now / 0.5) % 2 == 0 {
                for (dc, dr) in [(0, -4), (0, 4), (-4, 0), (4, 0), (3, -3), (-3, -3), (3, 3), (-3, 3)] {
                    cell(&context, cx + dc, cy + dr, sun, 0.8)
                }
            }
        case .rainbow:
            let bands = [Color(hex: 0xF0707A), Color(hex: 0xF5C04A), Color(hex: 0x7CC67E), Color(hex: 0x6FA8E8)]
            for (i, band) in bands.enumerated() {
                let radius = 12.0 - Double(i)
                for c in -12...12 {
                    let dx = Double(c)
                    guard abs(dx) <= radius else { continue }
                    let dy = (radius * radius - dx * dx).squareRoot() * 0.5
                    cell(&context, ox + 10 + c, top - Int(dy.rounded()), band, 0.9)
                }
            }
        case .clear:
            break
        }
    }

    func paint(in context: inout GraphicsContext) {
        let act = brain.act
        // Props he's using go in front of him; otherwise he walks in front of them.
        let atDesk = act == .study && !brain.airborne
        let inHammock = act == .nap && brain.inHammock
        if let d = brain.deskX, !atDesk { paintDesk(&context, at: d, lit: false) }
        if let h = brain.hammockX {
            paintHammockPosts(&context, at: h)
            if !inHammock { paintHammockFabric(&context, at: h, occupied: false) }
        }
        paintNimbus(in: &context)
        if let d = brain.deskX, atDesk { paintDesk(&context, at: d, lit: true) }
        if let h = brain.hammockX, inHammock { paintHammockFabric(&context, at: h, occupied: true) }
        if brain.showsWeather(now) { paintWeather(&context) }
    }

    private func paintNimbus(in context: inout GraphicsContext) {
        let act = brain.act
        let sitting = act == .sit || act == .fiddle || act == .nap || act == .study
        let perched = act == .perch
        let airborne = brain.airborne && !perched
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
        case .study:
            // Writing: one arm on the page, the pencil scratching away.
            let scribble = Int(now / 0.16) % 3
            px(-1, 6, shade); px(20, 6, shade); px(21, 6, shade)
            px(22 - scribble % 2, 5, pencil); px(22 - scribble % 2, 4, pencil)
        case .perch:
            px(-1, 7, shade); px(20, 7, shade)  // hands on the edge
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
        if perched {
            // Sitting on the edge of a card, legs swinging over it.
            let swing = Int(now / 0.4) % 2
            px(6, 9, shade); px(6 + swing, 10, shade); px(13, 9, shade); px(13 - swing, 10, shade)
        } else if airborne {
            px(7, 9, shade); px(12, 9, shade)
        } else if act == .walk {
            if f == 1 { px(6, 9, shade); px(5, 10, shade); px(13, 9, shade); px(14, 10, shade) }
            else { px(6, 9, shade); px(7, 10, shade); px(13, 9, shade); px(12, 10, shade) }
        } else if !sitting {
            px(6, 9, shade); px(6, 10, shade); px(13, 9, shade); px(13, 10, shade)
        }

        // Face.
        let lx = act == .walk || act == .float || act == .study ? 1 : act == .look ? brain.look : 0
        for (i, ec) in [6 + lx, 13 + lx].enumerated() {
            switch act {
            case .cheer, .wave, .hop: px(ec - 1, 5, ink); px(ec, 4, ink); px(ec + 1, 5, ink)
            case .stretch: px(ec - 1, 5, ink); px(ec, 5, ink)
            case .nap: px(ec, 5, ink); px(ec + (i == 1 ? -1 : 1), 5, ink)
            case .sad: px(ec, 5, ink); px(ec, 6, ink)
            case .study:
                // Eyes down on the page, with a blink now and then.
                if brain.isBlinking(now) { px(ec, 6, ink) } else { px(ec, 5, ink); px(ec, 6, ink) }
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
        let height = perched ? 0 : CGFloat(brain.altitude)
        let spread = max(0.45, 1 - height / 40)
        let groundY = CGFloat(perched ? oy + 9 : brain.ground) * pixel
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
