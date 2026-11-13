#if os(macOS)
import AppKit
#endif
import CoreText
import SwiftUI

#if os(macOS)

/// First launch: the screen dims, "hello" is written out, and setup happens
/// right there in floating glass panels. When it's done the overlay dissolves
/// and the app window grows into place.
@MainActor
final class HelloOverlayController {
    private var window: HelloWindow?
    private let model: AppModel
    private let onFinish: () -> Void
    private var finished = false

    init(model: AppModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    func show() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            onFinish()
            return
        }
        let window = HelloWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.level = .modalPanel
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        #if DEBUG
        // Lets the flow be inspected in an ordinary window instead of covering the screen.
        if ProcessInfo.processInfo.environment["SKYWARDPLUS_SETUP_WINDOWED"] != nil {
            window.styleMask = [.titled, .resizable]
            window.title = "Setup"
            // SKYWARDPLUS_SETUP_FLOATING keeps the real level, to test what floats above it.
            window.level = ProcessInfo.processInfo.environment["SKYWARDPLUS_SETUP_FLOATING"] != nil ? .modalPanel : .normal
            window.collectionBehavior = []
            window.setFrame(NSRect(x: 80, y: 80, width: 1360, height: 860), display: false)
        }
        #endif

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: window.frame.size))
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]

        model.firstRunActive = true
        let root = FirstRunView { [weak self] in self?.finish() }
            .environment(model)
            .tint(model.theme.color)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)

        window.contentView = blur
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.9
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        self.window = window
    }

    /// The overlay fades while the app window scales up from slightly smaller, so
    /// setup appears to settle into the window.
    private func finish() {
        guard !finished, let overlay = window else { return }
        finished = true
        model.firstRunActive = false
        if let id = model.active?.id, let index = model.profiles.firstIndex(where: { $0.id == id }) {
            model.profiles[index].prefs.onboardingDone = true
            model.save()
        }

        Task { @MainActor in
            // The app window may not exist yet (SwiftUI makes it lazily); it comes up
            // invisible while setup is unfinished, so it can be animated in.
            var main = AppDelegate.shared?.mainWindow
            if main == nil {
                AppDelegate.shared?.showMain(section: nil)
                for _ in 0..<60 {
                    if let window = AppDelegate.shared?.mainWindow { main = window; break }
                    try? await Task.sleep(nanoseconds: 25_000_000)
                }
            }
            var target: NSRect?
            if let main {
                let frame = main.frame
                target = frame
                main.setFrame(frame.insetBy(dx: frame.width * 0.04, dy: frame.height * 0.04), display: false)
                main.alphaValue = 0
                main.makeKeyAndOrderFront(nil)
            }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.65
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                overlay.animator().alphaValue = 0
                if let main, let target {
                    main.animator().setFrame(target, display: true)
                    main.animator().alphaValue = 1
                }
            }, completionHandler: {
                Task { @MainActor in
                    overlay.orderOut(nil)
                    self.window = nil
                    self.onFinish()
                }
            })
        }
    }
}

/// A borderless window has to opt in to key status for typing to reach it.
final class HelloWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

#endif

// MARK: - Flow

private enum SetupStep: Int, CaseIterable {
    case hello, district, signIn, personalize, account, done
}

/// The setup flow itself. The Mac shows it in a full-screen overlay window; the
/// iPhone shows it as a full-screen cover.
struct FirstRunView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onFinish: () -> Void

    @State private var step: SetupStep = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["SKYWARDPLUS_SETUP_STEP"], let n = Int(raw), let step = SetupStep(rawValue: n) { return step }
        #endif
        return .hello
    }()
    @State private var dim = false
    @State private var district: DistrictResult?
    @State private var manualAddress: String?

    var body: some View {
        ZStack {
            Color.black.opacity(dim ? 0.42 : 0).ignoresSafeArea()

            Group {
                switch step {
                case .hello:
                    HelloStep(
                        onContinue: {
                            if model.active != nil && !model.profiles.isEmpty {
                                go(.personalize)
                            } else {
                                go(.district)
                            }
                        },
                        onDifferentAccount: (!model.profiles.isEmpty) ? { go(.district) } : nil
                    )
                case .district:
                    DistrictStep { result in
                        district = result
                        go(.signIn)
                    } onAddress: { address in
                        manualAddress = address
                        district = nil
                        go(.signIn)
                    } onDemo: {
                        Task {
                            await model.addDemo()
                            go(.personalize)
                        }
                    }
                case .signIn:
                    SignInStep(district: district, manualAddress: manualAddress) {
                        go(.personalize)
                    } onBack: {
                        go(.district)
                    }
                case .personalize:
                    PersonalizeStep(
                        onBack: {
                            if model.active != nil && !model.profiles.isEmpty {
                                go(.hello)
                            } else {
                                go(.signIn)
                            }
                        },
                        onContinue: { go(AccountSync.shared.isConfigured && !AccountSync.shared.isSignedIn ? .account : .done) }
                    )
                case .account:
                    AccountStep { go(.done) }
                case .done:
                    DoneStep(onFinish: onFinish)
                }
            }
            #if os(iOS)
            .padding(.horizontal, 20)
            #endif
            .id(step)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 24)).combined(with: .scale(scale: 0.97)),
                removal: .opacity.combined(with: .offset(y: -16)).combined(with: .scale(scale: 1.02))
            ))

            VStack {
                HStack {
                    Spacer()
                    if step != .hello && step != .done {
                        Button("Set Up Later") { onFinish() }
                            .buttonStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(24)
                    }
                }
                Spacer()
                if step != .hello {
                    StepDots(current: step)
                        .padding(.bottom, 36)
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { withAnimation(.easeOut(duration: 1)) { dim = true } }
    }

    private func go(_ next: SetupStep) {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) { step = next }
    }
}

/// Optional: sign in so the planner and theme follow you to your other devices.
private struct AccountStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            StepTitle(title: "Keep it in sync", subtitle: "Sign in to keep your planner, goals and theme the same on your Mac and iPhone.")
            GlassPanel(width: 420) {
                GoogleButton(onSignedIn: onContinue)
                    .environment(\.colorScheme, .dark)
                if let error = AccountSync.shared.lastError {
                    Text(error).font(.callout).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
                }
                Text("Grades stay on this device.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Button("Skip") { onContinue() }
                .buttonStyle(.plain)
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(minWidth: 120, minHeight: 44)
                .contentShape(Rectangle())
        }
    }
}

private struct StepDots: View {
    let current: SetupStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SetupStep.allCases.filter { $0 != .hello }, id: \.rawValue) { step in
                Capsule()
                    .fill(.white.opacity(step == current ? 0.9 : 0.25))
                    .frame(width: step == current ? 20 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current.rawValue) of \(SetupStep.allCases.count - 1)")
    }
}

/// Large white title and a quieter line under it, shared by every step.
private struct StepTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.display(30))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 560)
    }
}

/// The floating glass panel each step's controls sit in.
private struct GlassPanel<Content: View>: View {
    var width: CGFloat = 520
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(22)
            .frame(maxWidth: width)
            .glassSurface(cornerRadius: 24)
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.25), radius: 30, y: 16)
    }
}

private struct PrimaryButton: View {
    let title: String
    var busy = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small).tint(.black) }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 26)
            .padding(.vertical, 11)
            .background(Capsule().fill(.white.opacity(disabled ? 0.4 : 1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled || busy)
        .keyboardShortcut(.defaultAction)
        .hoverLift()
    }
}

// MARK: Hello

private struct HelloStep: View {
    let onContinue: () -> Void
    var onDifferentAccount: (() -> Void)? = nil
    @State private var write: CGFloat = 0
    @State private var fill = false
    @State private var lift = false
    @State private var showTitle = false
    @State private var showButton = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HelloLettering()
                    .trim(from: 0, to: write)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                HelloLettering()
                    .fill(Color.white)
                    .opacity(fill ? 1 : 0)
            }
            .aspectRatio(520.0 / 230.0, contentMode: .fit)
            .frame(maxWidth: 520)
            .padding(.horizontal, 12)
            .shadow(color: .black.opacity(0.25), radius: 20, y: 6)
            .offset(y: lift ? -14 : 0)

            VStack(spacing: 8) {
                Text("Welcome to Skyward Plus")
                    .font(.system(size: 22, weight: .semibold))
                Text("Your Skyward grades, clear and up to date.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .opacity(showTitle ? 1 : 0)
            .offset(y: showTitle ? 0 : 10)

            PrimaryButton(title: "Get Started", action: onContinue)
                .padding(.top, 34)
                .opacity(showButton ? 1 : 0)
                .scaleEffect(showButton ? 1 : 0.94)

            if let onDifferentAccount {
                Button("Search Districts or Add Another Student") {
                    onDifferentAccount()
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.top, 12)
                .opacity(showButton ? 1 : 0)
            }
        }
        .task { await play() }
    }

    private func play() async {
        try? await Task.sleep(nanoseconds: 450_000_000)
        withAnimation(.timingCurve(0.45, 0.05, 0.25, 1, duration: 2.6)) { write = 1 }
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        withAnimation(.easeInOut(duration: 0.8)) { fill = true }
        try? await Task.sleep(nanoseconds: 500_000_000)
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
            lift = true
            showTitle = true
        }
        try? await Task.sleep(nanoseconds: 600_000_000)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showButton = true }
    }
}

// MARK: District

private struct DistrictStep: View {
    let onPick: (DistrictResult) -> Void
    let onAddress: (String) -> Void
    let onDemo: () -> Void

    @State private var finder = DistrictSearch()
    @State private var states: [DistrictState] = []
    @State private var stateID = UserDefaults.standard.string(forKey: "signin.stateID") ?? ""
    @State private var query = ""
    @State private var results: [DistrictResult] = []
    @State private var searching = false
    @State private var searched = false
    @State private var message: String?
    @State private var typing = false
    @State private var address = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 28) {
            StepTitle(title: "Find your school district", subtitle: "Skyward Plus signs in to the same Skyward your school uses.")

            GlassPanel {
                if typing {
                    Text("Your district's Skyward address").font(.headline)
                    GlassField(text: $address, prompt: "https://skyward.iscorp.com/…", focused: $focused)
                        .onSubmit(useAddress)
                    if let message { Text(message).font(.callout).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5)) }
                    HStack {
                        Button("Search by name instead") { typing = false; message = nil }
                            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        PrimaryButton(title: "Continue", disabled: address.trimmingCharacters(in: .whitespaces).isEmpty, action: useAddress)
                    }
                } else {
                    let statePicker = Picker("State", selection: $stateID) {
                        Text(states.isEmpty ? "Loading…" : "Choose").tag("")
                        ForEach(states) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .disabled(states.isEmpty)
                    #if os(iOS)
                    // A phone has no room for the two side by side.
                    HStack {
                        Text("State").foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        statePicker
                    }
                    HStack(spacing: 10) {
                        GlassField(text: $query, prompt: "District name", focused: $focused)
                        if searching { ProgressView().controlSize(.small) }
                    }
                    #else
                    HStack(spacing: 10) {
                        statePicker.frame(width: 150)
                        GlassField(text: $query, prompt: "District name", focused: $focused)
                        if searching { ProgressView().controlSize(.small) }
                    }
                    #endif
                    if !results.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(results.prefix(6)) { result in
                                Button { pick(result) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(Str.titleCase(result.name)).font(.body.weight(.medium))
                                            Text(result.label).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.right").foregroundStyle(.white.opacity(0.5))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .contentShape(Rectangle())
                                    .hoverSheen(cornerRadius: 10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if searched, !searching {
                        Text("No districts match “\(query)” in that state.")
                            .font(.callout).foregroundStyle(.white.opacity(0.6))
                    }
                    if let message { Text(message).font(.callout).foregroundStyle(.white.opacity(0.7)) }
                    Button("Enter the address myself") { typing = true; message = nil }
                        .buttonStyle(.plain).font(.callout).foregroundStyle(.white.opacity(0.6))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: results.count)

            Button("Try it with a sample student first", action: onDemo)
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
        }
        .task { await loadStates() }
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onChange(of: stateID) { _, value in
            UserDefaults.standard.set(value, forKey: "signin.stateID")
            scheduleSearch()
        }
        .onAppear { focused = true }
    }

    private func loadStates() async {
        guard states.isEmpty else { return }
        do {
            states = try await finder.states()
            if !states.contains(where: { $0.id == stateID }) { stateID = "" }
        } catch {
            message = "The district finder isn't answering. You can enter your district's address instead."
            typing = true
        }
    }

    /// Searches as you type, after a short pause.
    private func scheduleSearch() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !stateID.isEmpty, text.count >= 3 else {
            results = []
            searched = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            do {
                let found = try await finder.search(stateID: stateID, query: text)
                guard !Task.isCancelled else { return }
                results = found
                searched = true
                message = nil
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func pick(_ result: DistrictResult) { onPick(result) }

    private func useAddress() {
        let text = address.trimmingCharacters(in: .whitespaces)
        guard SkywardEndpoint.parse(text) != nil else {
            message = "That doesn't look like a web address."
            return
        }
        onAddress(text)
    }
}

/// A large, quiet text field for the dark setup screens.
private struct GlassField: View {
    @Binding var text: String
    let prompt: String
    var secure = false
    var focused: FocusState<Bool>.Binding

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: Text(prompt).foregroundStyle(.white.opacity(0.4)))
            } else {
                TextField("", text: $text, prompt: Text(prompt).foregroundStyle(.white.opacity(0.4)))
            }
        }
        .textFieldStyle(.plain)
        .font(.title3)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
        .focused(focused)
    }
}

// MARK: Sign in

private struct SignInStep: View {
    @Environment(AppModel.self) private var model
    let district: DistrictResult?
    let manualAddress: String?
    let onSignedIn: () -> Void
    let onBack: () -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @State private var busy = false
    @State private var error: String?
    @State private var webReady = false
    @FocusState private var focused: Bool

    private var address: String { district?.url ?? manualAddress ?? "" }
    private var name: String { district.map { Str.titleCase($0.name) } ?? (URLComponents(string: address)?.host ?? "your district") }
    private var isQmlativ: Bool { district?.isQmlativ ?? SkywardEndpoint.looksLikeQmlativ(address) }

    var body: some View {
        VStack(spacing: 24) {
            StepTitle(
                title: "Sign in to \(name)",
                subtitle: isQmlativ
                    ? "Use your district's own sign-in below. Skyward Plus never sees your password."
                    : "Use the username and password you use for Skyward."
            )
            if isQmlativ { webPanel } else { credentialPanel }
            Button("Choose a different district", action: onBack)
                .buttonStyle(.plain).font(.callout).foregroundStyle(.white.opacity(0.6))
        }
    }

    private var webPanel: some View {
        ZStack {
            if let engine = model.qmlativSignIn?.engine {
                HostedQmlativWebView(engine: engine)
                    .clipShape(.rect(cornerRadius: 18))
                    .opacity(webReady ? 1 : 0)
            }
            if !webReady { ProgressView().controlSize(.large) }
        }
        .frame(maxWidth: 820, maxHeight: 540)
        .padding(6)
        .glassSurface(cornerRadius: 24)
        .shadow(color: .black.opacity(0.3), radius: 30, y: 16)
        .task { await runWebSignIn() }
        .onDisappear { model.qmlativSignIn?.engine.attachToHiddenHost() }
    }

    private func runWebSignIn() async {
        model.beginQmlativSignIn(address: address, districtName: name)
        try? await Task.sleep(nanoseconds: 900_000_000)
        withAnimation(.easeOut(duration: 0.3)) { webReady = true }
        while !Task.isCancelled {
            if let engine = model.qmlativSignIn?.engine, let state = await engine.state(), state.signedIn {
                engine.attachToHiddenHost()
                await model.finishQmlativSignIn()
                onSignedIn()
                return
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
    }

    private var credentialPanel: some View {
        GlassPanel(width: 420) {
            if needsCode {
                Text("Enter the security code Skyward sent you.").font(.headline)
                GlassField(text: $code, prompt: "Security code", focused: $focused)
                    .onSubmit { Task { await signIn() } }
            } else {
                GlassField(text: $username, prompt: "Username", focused: $focused)
                GlassField(text: $password, prompt: "Password", secure: true, focused: $focused)
                    .onSubmit { Task { await signIn() } }
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
            }
            HStack {
                Text("Kept in this Mac's Keychain.").font(.footnote).foregroundStyle(.white.opacity(0.5))
                Spacer()
                PrimaryButton(title: needsCode ? "Verify" : "Sign In", busy: busy,
                              disabled: needsCode ? code.isEmpty : (username.isEmpty || password.isEmpty)) {
                    Task { await signIn() }
                }
            }
        }
        .onAppear { focused = true }
    }

    private func signIn() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.signIn(address: address, districtName: name, username: username, password: password,
                                   securityCode: needsCode ? code : nil, trustDevice: true)
            password = ""
            onSignedIn()
        } catch let failure as SkywardError {
            switch failure {
            case .mfaRequired: needsCode = true
            case .mfaInvalid: error = failure.localizedDescription; code = ""
            default: error = failure.localizedDescription
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: Personalize

private struct PersonalizeStep: View {
    @Environment(AppModel.self) private var model
    var onBack: (() -> Void)? = nil
    let onContinue: () -> Void

    @State private var remember = false
    @State private var rememberUser = ""
    @State private var rememberPassword = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 28) {
            StepTitle(title: "Make it yours", subtitle: "You can change all of this later in Settings.")
            GlassPanel(width: 560) {
                Text("Theme").font(.headline)
                BackgroundThemePicker(columns: 3, compact: true)
                    .environment(\.colorScheme, .dark)
                Divider().overlay(.white.opacity(0.1))
                toggle("Tell me about new grades", \.notifyNewGrades, asksPermission: true)
                toggle("Remind me the night before work is due", \.notifyDueTomorrow, asksPermission: true)
                #if os(macOS)
                toggle("Keep grades in the menu bar", \.showMenuBarIcon)
                Toggle(isOn: Binding(get: { model.settings.launchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                    Text("Open when I log in").frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                #endif

                if let profile = model.active, model.isQmlativ(profile) {
                    Divider().overlay(.white.opacity(0.1))
                    Toggle(isOn: $remember.animation(.snappy)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stay signed in")
                            Text("Saves your district sign-in in the Keychain so syncing never stops.")
                                .font(.footnote).foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                    if remember {
                        GlassField(text: $rememberUser, prompt: "District username", focused: $focused)
                        GlassField(text: $rememberPassword, prompt: "District password", secure: true, focused: $focused)
                    }
                }
            }
            HStack(spacing: 14) {
                if let onBack {
                    Button(action: onBack) {
                        Text("Back")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(.white.opacity(0.12)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .hoverLift()
                }
                PrimaryButton(title: "Continue") {
                    if remember, !rememberUser.isEmpty, !rememberPassword.isEmpty {
                        model.rememberSignIn(username: rememberUser.trimmingCharacters(in: .whitespaces), password: rememberPassword)
                    }
                    if model.settings.notifyNewGrades || model.settings.notifyDueTomorrow {
                        Task { await Notifier.requestPermission() }
                    }
                    onContinue()
                }
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let control = content()
        return ViewThatFits(in: .horizontal) {
            HStack {
                Text(title)
                Spacer()
                control
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                control
            }
        }
    }

    private func toggle(_ title: String, _ keyPath: WritableKeyPath<AppSettings, Bool>, asksPermission: Bool = false) -> some View {
        Toggle(isOn: Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.updateSettings { $0[keyPath: keyPath] = value } }
        )) { Text(title).frame(maxWidth: .infinity, alignment: .leading) }
        .toggleStyle(.switch)
    }
}

// MARK: Done

private struct DoneStep: View {
    @Environment(AppModel.self) private var model
    let onFinish: () -> Void
    @State private var shown = false

    var body: some View {
        let syncing = model.syncState.isSyncing || (model.data.courses.isEmpty && model.data.lastSync == nil && model.active != nil)
        let lit = model.selectedLit
        let numbers = lit.map { lit in model.courses(in: lit).compactMap { model.percent($0, lit) } } ?? []
        let average = numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)

        VStack(spacing: 26) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .regular))
                .symbolEffect(.bounce, value: shown)
                .foregroundStyle(.white)
            StepTitle(
                title: model.active.map { "You're all set, \($0.firstName)." } ?? "You're all set.",
                subtitle: syncing ? "Getting your grades from Skyward…" : "Here's where you stand."
            )
            if syncing {
                ProgressView().controlSize(.regular)
            } else if let average {
                HStack(spacing: 40) {
                    figure(Fmt.percent(shown ? average : 0), lit.map { "\($0) average" } ?? "Average")
                    figure("\(shown ? numbers.count : 0)", "classes")
                    figure("\(shown ? model.missingAssignments.count : 0)", "missing")
                }
                .animation(.spring(response: 1.1, dampingFraction: 0.9), value: shown)
            }
            PrimaryButton(title: "Open Skyward Plus", action: onFinish)
                .padding(.top, 6)
        }
        .task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            shown = true
        }
        .onChange(of: model.syncState.isSyncing) { _, busy in
            if !busy { shown = false; Task { try? await Task.sleep(nanoseconds: 150_000_000); shown = true } }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.display(38).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label).font(.callout).foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Lettering

/// "hello" as a vector outline, so it can be drawn on stroke by stroke.
private struct HelloLettering: Shape {
    func path(in rect: CGRect) -> Path {
        let outline = HelloLettering.outline
        let bounds = outline.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        var transform = CGAffineTransform.identity
            .translatedBy(x: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: -scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        guard let fitted = outline.copy(using: &transform) else { return Path() }
        return Path(fitted)
    }

    static let outline: CGPath = {
        let names = ["SnellRoundhand-Bold", "SnellRoundhand", "Zapfino", "Noteworthy-Bold"]
        // Core Text quietly substitutes a font it cannot find, so check the name it gives back.
        let font: CTFont = names.lazy.compactMap { name -> CTFont? in
            let candidate = CTFontCreateWithName(name as CFString, 200, nil)
            return (CTFontCopyPostScriptName(candidate) as String).caseInsensitiveCompare(name) == .orderedSame ? candidate : nil
        }.first ?? CTFontCreateWithName("HelveticaNeue-Light" as CFString, 200, nil)
        let key = NSAttributedString.Key(kCTFontAttributeName as String)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "hello", attributes: [key: font]))
        let path = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName]
            let ctFont: CTFont = runFont.map { unsafeBitCast($0 as AnyObject, to: CTFont.self) } ?? font
            for i in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(ctFont, glyphs[i], nil) else { continue }
                path.addPath(glyph, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
            }
        }
        return path
    }()
}
