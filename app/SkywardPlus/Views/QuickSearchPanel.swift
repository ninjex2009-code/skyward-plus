#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Search from anywhere: a shortcut that works in every app opens the ⌘K
/// palette in a small floating panel, Spotlight-style, even with the window closed.
@MainActor
final class QuickSearch {
    static let shared = QuickSearch()

    enum Shortcut: String, CaseIterable, Identifiable {
        case off, optionCommandK, controlOptionK, commandK
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: return "Off"
            case .optionCommandK: return "⌥⌘K"
            case .controlOptionK: return "⌃⌥K"
            case .commandK: return "⌘K everywhere"
            }
        }
        fileprivate var carbonModifiers: UInt32? {
            switch self {
            case .off: return nil
            case .optionCommandK: return UInt32(cmdKey | optionKey)
            case .controlOptionK: return UInt32(controlKey | optionKey)
            case .commandK: return UInt32(cmdKey)
            }
        }
    }

    private weak var model: AppModel?
    private var panel: SearchPanel?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var resignObserver: NSObjectProtocol?

    func install(model: AppModel) {
        self.model = model
        apply(Shortcut(rawValue: model.settings.searchShortcut) ?? .optionCommandK)
    }

    func apply(_ shortcut: Shortcut) {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        guard let modifiers = shortcut.carbonModifiers else { return }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { QuickSearch.shared.toggle() } }
                return noErr
            }, 1, &type, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x534B5950), id: 1)  // "SKYP"
        RegisterEventHotKey(UInt32(kVK_ANSI_K), modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
    }

    /// In the main window, the palette opens over it; anywhere else, in the panel.
    func toggle() {
        if panel?.isVisible == true { hide(); return }
        if NSApp.isActive, let main = AppDelegate.shared?.mainWindow, main.isKeyWindow, let model {
            model.showPalette.toggle()
            return
        }
        show()
    }

    func show() {
        guard let model, !model.profiles.isEmpty, !model.isLocked else {
            AppDelegate.shared?.showMain(section: nil)
            return
        }
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - frame.height * 0.12))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(model: AppModel) -> SearchPanel {
        let panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let content = SearchPanelContent(
            onClose: { [weak self] in self?.hide() },
            onActivate: { [weak self] in
                self?.hide()
                AppDelegate.shared?.showMain(section: nil)
            }
        )
        .environment(model)
        panel.contentView = NSHostingView(rootView: content)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        return panel
    }
}

/// A borderless panel that still takes typing.
private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

private struct SearchPanelContent: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void
    let onActivate: () -> Void
    @State private var generation = 0

    var body: some View {
        VStack {
            CommandPalette(onClose: onClose, onActivate: onActivate)
                .id(generation)
            Spacer(minLength: 0)
        }
        .padding(30)
        .frame(width: 640, height: 520, alignment: .top)
        .tint(model.theme.color)
        .environment(\.backgroundTheme, model.settings.backgroundTheme)
        .environment(\.accentTheme, model.theme)
        .environment(\.colorScheme, model.settings.backgroundTheme.isDark ? .dark : .light)
        // A fresh palette (empty query, focused field) each time the panel opens.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if (note.object as? NSWindow) is SearchPanel { generation += 1 }
        }
    }
}
#endif
