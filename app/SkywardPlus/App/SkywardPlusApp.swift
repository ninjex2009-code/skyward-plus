import SwiftUI

#if os(macOS)
import AppKit

@main
struct SkywardPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        let model = delegate.model
        Window("Skyward Plus", id: AppDelegate.mainWindowID) {
            RootView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 580)
                .background(MainWindowTracker())
                .onOpenURL { model.handle(url: $0) }
        }
        .defaultSize(width: 1180, height: 800)
        .commands { AppCommands(model: model) }

        MenuBarExtra(isInserted: Binding(
            get: { model.settings.showMenuBarIcon },
            set: { value in
                if value != model.settings.showMenuBarIcon { model.updateSettings { $0.showMenuBarIcon = value } }
            }
        )) {
            MenuBarView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // The menus exist from launch, before any window does, so this is the one
        // place AppKit code can always get a way to open the SwiftUI window.
        let _ = { MainWindowTracker.openWindow = openWindow }()
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppDelegate.shared?.showMain(section: .settings) }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Task { await model.checkForUpdates(manual: true) } }
            Button("Replay Welcome Animation (“hello”)") { AppDelegate.shared?.replayHello() }
        }
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .toolbar) {
            Button("Refresh Grades") { Task { await model.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
            Button("Search…") { QuickSearch.shared.toggle() }
            .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Export Grade Report…") { model.exportReport() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model.data.courses.isEmpty)
            #if DEBUG
            Button("Save Page for Debugging") { Task { await model.saveDebugPage() } }
            #endif
        }
        CommandMenu("Go") {
            ForEach(Array(AppSection.sidebar.enumerated()), id: \.element) { index, section in
                Button(section.title) { AppDelegate.shared?.showMain(section: section) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
    }
}

/// Owns the model, the menu bar behaviour and the first-launch hello.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let mainWindowID = "main"
    static private(set) weak var shared: AppDelegate?

    let model = AppModel()
    private var hello: HelloOverlayController?
    let aura = WindowAura()
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains("--render-screens") {
            Task { await ScreenRenderer.run(model: model) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--model-selftest"), CommandLine.arguments.count > index + 1 {
            RememberTest.modelUpdates(model: model, report: CommandLine.arguments[index + 1])
            exit(0)
        }
        if CommandLine.arguments.contains("--remember-test") {
            Task { await RememberTest.run() }
            return
        }
        #endif
        model.startScheduler()
        QuickSearch.shared.install(model: model)
        LoginItem.sync(model.settings.launchAtLogin)
        AppIconApplier.apply(model.settings.appIcon)

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.windowWillClose(window) }
        })
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard AppDelegate.isMainWindow(window) else { return }
                if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
                AppDelegate.shared?.aura.attach(to: window)
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["SKYWARDPLUS_WINDOW_SIZE"] {
                let parts = raw.split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 {
                    DispatchQueue.main.async {
                        window.setFrame(NSRect(x: 40, y: 40, width: parts[0], height: parts[1]), display: true)
                    }
                }
            }
            #endif
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.syncIfDue() }
        })

        if !model.settings.helloShown {
            playHello()
        } else {
            // SwiftUI only creates the window once the app is frontmost; a launch
            // from the menu bar or a script would otherwise leave no window at all.
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if self?.mainWindow == nil { self?.showMain(section: nil) }
            }
        }
        Task { await model.checkForUpdates(manual: false) }
        Task { await AccountSync.shared.sync(model: model) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(model.settings.keepInMenuBar && model.settings.showMenuBarIcon)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMain(section: nil) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.markSeen()
    }

    static func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix(mainWindowID) == true
    }

    var mainWindow: NSWindow? { NSApp.windows.first { AppDelegate.isMainWindow($0) } }

    /// Brings the main window back (it may have been closed into the menu bar).
    func showMain(section: AppSection?) {
        if let section { model.section = section }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else if let open = MainWindowTracker.openWindow {
            open(id: AppDelegate.mainWindowID)
        } else {
            // No window has existed yet: use the Window menu entry SwiftUI adds for the scene.
            let items = NSApp.mainMenu?.items.flatMap { $0.submenu?.items ?? [] } ?? []
            if let item = items.first(where: { $0.title == "Skyward Plus" && $0.action != nil }) {
                NSApp.sendAction(item.action!, to: item.target, from: item)
            }
        }
    }

    private func windowWillClose(_ window: NSWindow) {
        guard AppDelegate.isMainWindow(window) else { return }
        model.markSeen()
        model.lockIfNeeded()
        // With the window gone the app lives only in the menu bar, so drop the Dock icon.
        if model.settings.keepInMenuBar, model.settings.showMenuBarIcon {
            if window.isVisible, window.alphaValue > 0.9 { MenuBarFold.play(from: window) }
            DispatchQueue.main.async {
                if self.mainWindow?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }

    // MARK: First launch

    func replayHello() {
        guard hello == nil else { return }
        playHello()
    }

    func playHello() {
        let controller = HelloOverlayController(model: model) { [weak self] in
            guard let self else { return }
            self.model.updateSettings { $0.helloShown = true }
            self.hello = nil
            if self.mainWindow == nil { self.showMain(section: nil) }
            self.mainWindow?.alphaValue = 1
            self.aura.refresh()
            NSApp.activate(ignoringOtherApps: true)
        }
        hello = controller
        // The SwiftUI window appears a moment after launch; hide it as soon as it exists.
        Task { @MainActor in
            for _ in 0..<40 {
                if let window = self.mainWindow { window.alphaValue = 0; break }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
        }
        controller.show()
    }
}

/// Lets AppKit code reopen the SwiftUI window, and tags it so it can be found again.
struct MainWindowTracker: NSViewRepresentable {
    @Environment(\.openWindow) private var openWindow
    static var openWindow: OpenWindowAction?

    func makeNSView(context: Context) -> NSView {
        let view = TaggingView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        MainWindowTracker.openWindow = openWindow
    }

    private final class TaggingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(AppDelegate.mainWindowID)
            // Clear, so the blurred desktop behind the content can show through.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            if AppDelegate.shared?.model.settings.helloShown == false { window.alphaValue = 0 }
            AppDelegate.shared?.aura.attach(to: window)
        }
    }
}

#else

@main
struct SkywardPlusApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var phase

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        BackgroundRefresh.register(model: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: phase) { _, phase in
                    if phase == .background { BackgroundRefresh.schedule(model: model) }
                    if phase == .active {
                        Task {
                            await AccountSync.shared.sync(model: model)
                            model.syncIfDue()
                        }
                    }
                }
                .task {
                    model.startScheduler()
                    await AccountSync.shared.sync(model: model)
                }
                #if DEBUG
                .task { await EngineTest.runIfRequested() }
                #endif
        }
    }
}

#endif
