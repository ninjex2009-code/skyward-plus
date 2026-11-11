#if os(macOS)
import AppKit
import SwiftUI

/// A soft glow in the accent colour that sits outside the window, on the desktop.
/// It is how the window shows what it is doing without putting anything in the
/// way: it breathes while grades are syncing, flares once when something new
/// arrives, and dims when the window is not the one in use.
///
/// It is a second, click-through window kept directly behind the main one.
@MainActor
final class WindowAura {
    enum Activity: Equatable { case idle, syncing }

    private let spread: CGFloat = 110
    private let panel: NSWindow
    private let glow = CALayer()
    private static let nominalInner: CGFloat = 200
    private static let radius: CGFloat = 14
    private weak var parent: NSWindow?
    private var observers: [NSObjectProtocol] = []

    /// The pill that slides out from under the window's bottom edge.
    let notice = AuraNotice()
    private var noticeHost: NSHostingView<NoticePill>?
    private var noticeTask: Task<Void, Never>?

    private var color: NSColor = .controlAccentColor
    private var activity: Activity = .idle
    private var enabled = true
    private var dark = true

    init() {
        panel = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]
        panel.setAccessibilityElement(false)

        let view = NSView()
        view.wantsLayer = true
        panel.contentView = view
        // The glow is a picture drawn once per colour and stretched nine-slice style,
        // so resizing the window never has to blur anything live.
        glow.contentsScale = 2
        let edge = (spread + 40) / (spread * 2 + WindowAura.nominalInner)
        glow.contentsCenter = CGRect(x: edge, y: edge, width: 1 - edge * 2, height: 1 - edge * 2)
        glow.contentsGravity = .resize
        glow.opacity = 0
        glow.contents = renderGlow()
        view.layer?.addSublayer(glow)
        let host = NSHostingView(rootView: NoticePill(notice: notice))
        view.addSubview(host)
        noticeHost = host
    }

    /// Follows `window` from now on. Safe to call again for the same window.
    func attach(to window: NSWindow) {
        guard parent !== window else { layout(); return }
        detach()
        parent = window
        window.addChildWindow(panel, ordered: .below)
        let center = NotificationCenter.default
        let relayout: (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.layout() } }
        let restyle: (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.applyLevel(animated: true) } }
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main, using: relayout))
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
                     NSWindow.willEnterFullScreenNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main, using: restyle))
        }
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.detach() }
        })
        layout()
        applyLevel(animated: false)
    }

    private func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        parent = nil
    }

    func update(color: NSColor, activity: Activity, enabled: Bool, dark: Bool) {
        let changed = self.activity != activity
        let recolored = self.color != color
        self.color = color
        self.activity = activity
        self.enabled = enabled
        self.dark = dark
        if recolored {
            let fade = CATransition()
            fade.duration = 0.4
            glow.add(fade, forKey: "recolor")
            glow.contents = renderGlow()
        }
        if changed || glow.animation(forKey: "breathe") == nil { applyLevel(animated: true) }
    }

    /// Says something short just below the window, then tucks it back underneath.
    /// It sits outside the window so it never covers what is being read.
    func announce(_ text: String, symbol: String) {
        guard let parent, parent.isVisible, parent.alphaValue > 0.9, !parent.styleMask.contains(.fullScreen) else { return }
        noticeTask?.cancel()
        notice.text = text
        notice.symbol = symbol
        notice.dark = dark
        notice.tint = Color(nsColor: color)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduce ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.74)) { notice.shown = true }
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.28)) { self?.notice.shown = false }
        }
    }

    /// Re-reads the window's state, for changes no notification reports (its alpha).
    func refresh() {
        layout()
        applyLevel(animated: true)
    }

    /// One bright beat, for when new grades land.
    func pulse() {
        guard enabled, parent?.isVisible == true, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let beat = CAKeyframeAnimation(keyPath: "opacity")
        let rest = restingOpacity
        beat.values = [rest, min(1, rest + 0.5), rest]
        beat.keyTimes = [0, 0.25, 1]
        beat.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        beat.duration = 1.6
        glow.add(beat, forKey: "pulse")
    }

    /// Light spilling from the window's edge: a wide soft wash plus a tighter rim,
    /// with the window's own area cut out so nothing shows through it.
    private func renderGlow() -> CGImage? {
        let side = WindowAura.nominalInner + spread * 2
        let scale: CGFloat = 2
        let pixels = Int(side * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let tint = color.usingColorSpace(.sRGB) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let inner = bounds.insetBy(dx: spread, dy: spread)
        let radius = WindowAura.radius
        ctx.addRect(bounds)
        ctx.addPath(CGPath(roundedRect: inner.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip(using: .evenOdd)
        let body = CGPath(roundedRect: inner.insetBy(dx: 8, dy: 8), cornerWidth: radius, cornerHeight: radius, transform: nil)
        for (blur, alpha, drop) in [(64.0, 0.60, -12.0), (20.0, 0.50, -2.0)] {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: drop * scale), blur: blur * scale, color: tint.withAlphaComponent(alpha).cgColor)
            ctx.setFillColor(tint.cgColor)
            ctx.addPath(body)
            ctx.fillPath()
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    #if DEBUG
    /// Draws the glow over a stand-in desktop so its strength can be judged from a file.
    func dump(to url: URL, desktop: NSColor, dark: Bool) {
        guard let image = renderGlow() else { return }
        let side = CGFloat(image.width) / 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: image.width, pixelsHigh: image.height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        let cg = ctx.cgContext
        cg.scaleBy(x: 2, y: 2)
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        cg.setFillColor(desktop.cgColor)
        cg.fill(bounds)
        cg.setAlpha(dark ? 0.42 : 0.30)
        cg.draw(image, in: bounds)
        cg.setAlpha(1)
        cg.setFillColor(NSColor(white: dark ? 0.13 : 0.97, alpha: 1).cgColor)
        cg.addPath(CGPath(roundedRect: bounds.insetBy(dx: spread, dy: spread), cornerWidth: 14, cornerHeight: 14, transform: nil))
        cg.fillPath()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif

    private var restingOpacity: Float {
        guard enabled, let parent, parent.alphaValue > 0.9, !parent.styleMask.contains(.fullScreen),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { return 0 }
        let base: Float = dark ? 0.55 : 0.40
        return parent.isKeyWindow ? base : base * 0.35
    }

    private func applyLevel(animated: Bool) {
        let rest = restingOpacity
        glow.removeAnimation(forKey: "breathe")
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.6 : 0)
        glow.opacity = rest
        CATransaction.commit()
        guard rest > 0, activity == .syncing, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = rest * 0.7
        breathe.toValue = min(1, rest * 1.9)
        breathe.duration = 1.5
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(breathe, forKey: "breathe")
    }

    private func layout() {
        guard let parent else { return }
        let frame = parent.frame.insetBy(dx: -spread, dy: -spread)
        panel.setFrame(frame, display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = CGRect(origin: .zero, size: frame.size)
        CATransaction.commit()
        // A strip directly under the window's bottom edge.
        noticeHost?.frame = CGRect(x: spread, y: spread - 64, width: parent.frame.width, height: 64)
        if !panel.isVisible, parent.isVisible { parent.addChildWindow(panel, ordered: .below) }
    }
}

@MainActor @Observable
final class AuraNotice {
    var text = ""
    var symbol = "checkmark.circle.fill"
    var shown = false
    var dark = true
    var tint = Color.accentColor
}

struct NoticePill: View {
    let notice: AuraNotice

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: notice.symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(notice.tint)
            Text(notice.text)
                .font(.callout.weight(.medium))
                .foregroundStyle(notice.dark ? Color.white : Color.black.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(notice.dark ? Color(white: 0.17).opacity(0.96) : Color.white.opacity(0.97), in: .capsule)
        .overlay { Capsule().strokeBorder(notice.dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 0.5) }
        .shadow(color: .black.opacity(notice.dark ? 0.45 : 0.18), radius: 12, y: 5)
        // Hidden, it rests up behind the window; shown, it hangs just under the edge.
        .offset(y: notice.shown ? 12 : -44)
        .opacity(notice.shown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}

/// Closing the window folds it up into the menu bar icon, which shows where the
/// app went and that it is still running.
@MainActor
enum MenuBarFold {
    static func play(from window: NSWindow) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let frameView = window.contentView?.superview ?? window.contentView,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds),
              let icon = NSApp.windows.first(where: { $0.className.contains("NSStatusBarWindow") && $0.isVisible })?.frame
        else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        let image = NSImage(size: frameView.bounds.size)
        image.addRepresentation(rep)

        let ghost = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        ghost.isOpaque = false
        ghost.backgroundColor = .clear
        ghost.hasShadow = true
        ghost.level = .floating
        ghost.ignoresMouseEvents = true
        ghost.isReleasedWhenClosed = false
        ghost.animationBehavior = .none
        let picture = NSImageView(frame: NSRect(origin: .zero, size: window.frame.size))
        picture.image = image
        picture.imageScaling = .scaleAxesIndependently
        picture.wantsLayer = true
        picture.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        picture.layer?.cornerRadius = 14
        picture.layer?.masksToBounds = true
        picture.autoresizingMask = [.width, .height]
        ghost.contentView = picture
        ghost.orderFront(nil)

        let target = NSRect(x: icon.midX - 12, y: icon.midY - 8, width: 24, height: 16)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.42
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.9, 0.55)
            ghost.animator().setFrame(target, display: true)
            ghost.animator().alphaValue = 0.15
        }, completionHandler: {
            Task { @MainActor in ghost.orderOut(nil) }
        })
    }
}

/// What sits behind every screen: the desktop, blurred, when the window is translucent.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Keeps the window's translucency and its glow in step with the model.
struct WindowEffects: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var translucent: Bool { model.settings.translucentWindow && !reduceTransparency }

    func body(content: Content) -> some View {
        content
            .environment(\.windowTranslucent, translucent)
            .background {
                if translucent { BehindWindowBlur().ignoresSafeArea() }
            }
            .onAppear(perform: sync)
            .onChange(of: model.theme) { _, _ in sync() }
            .onChange(of: model.syncState.isSyncing) { was, now in
                sync()
                if was, !now { announceSyncResult() }
            }
            .onChange(of: model.unseenChangeCount, initial: true) { _, count in
                NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
            }
            .onChange(of: model.settings.windowGlow) { _, _ in sync() }
            .onChange(of: scheme) { _, _ in sync() }
            .onChange(of: model.unseenChangeCount) { old, new in
                if new > old { AppDelegate.shared?.aura.pulse() }
            }
    }

    private func announceSyncResult() {
        guard model.settings.windowGlow else { return }
        let aura = AppDelegate.shared?.aura
        if case .failed = model.syncState {
            aura?.announce("Couldn't reach Skyward", symbol: "wifi.slash")
        } else if model.unseenChangeCount > 0 {
            let n = model.unseenChangeCount
            aura?.announce(n == 1 ? "1 new grade" : "\(n) new grades", symbol: "arrow.down.circle.fill")
        } else {
            aura?.announce("Up to date", symbol: "checkmark.circle.fill")
        }
    }

    private func sync() {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["SKYWARDPLUS_AURA_DUMP"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                AppDelegate.shared?.aura.dump(to: URL(fileURLWithPath: path + "-dark.png"), desktop: NSColor(red: 0.10, green: 0.16, blue: 0.24, alpha: 1), dark: true)
                AppDelegate.shared?.aura.dump(to: URL(fileURLWithPath: path + "-light.png"), desktop: NSColor(red: 0.78, green: 0.84, blue: 0.90, alpha: 1), dark: false)
            }
        }
        #endif
        AppDelegate.shared?.aura.update(
            color: NSColor(model.theme.color),
            activity: model.syncState.isSyncing ? .syncing : .idle,
            enabled: model.settings.windowGlow,
            dark: scheme == .dark
        )
    }
}
#endif

import SwiftUI

private struct WindowTranslucentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the page surface should let the blurred desktop show through.
    var windowTranslucent: Bool {
        get { self[WindowTranslucentKey.self] }
        set { self[WindowTranslucentKey.self] = newValue }
    }
}

extension View {
    /// Applies the Mac window effects; does nothing elsewhere.
    @ViewBuilder
    func windowEffects() -> some View {
        #if os(macOS)
        modifier(WindowEffects())
        #else
        self
        #endif
    }
}
