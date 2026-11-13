import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home, grades, planner, gpa, schedule, bell, attendance, reports, transcript, teachers, students, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .grades: return "Grades"
        case .planner: return "Planner"
        case .gpa: return "GPA"
        case .schedule: return "Schedule"
        case .bell: return "Bell Schedule"
        case .attendance: return "Attendance"
        case .reports: return "Report Cards"
        case .transcript: return "Transcript"
        case .teachers: return "Teachers"
        case .students: return "Students"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .grades: return "chart.bar.doc.horizontal.fill"
        case .planner: return "checklist"
        case .gpa: return "graduationcap.fill"
        case .schedule: return "calendar.day.timeline.left"
        case .bell: return "bell.badge.fill"
        case .attendance: return "calendar.badge.checkmark"
        case .reports: return "doc.text.fill"
        case .transcript: return "scroll.fill"
        case .teachers: return "envelope.fill"
        case .students: return "person.2.fill"
        case .settings: return "gearshape.fill"
        }
    }

    /// The everyday sections (also the first iPhone tabs).
    static let tabs: [AppSection] = [.home, .grades, .planner]
    /// Bell and Teachers live inside Schedule.
    static let school: [AppSection] = [.schedule, .attendance]
    static let app: [AppSection] = [.settings]
    /// Everything in the sidebar, in order (also ⌘1…⌘8).
    static let sidebar: [AppSection] = tabs + school + app

    /// The sidebar row that shows this section.
    var host: AppSection {
        switch self {
        case .bell, .teachers: return .schedule
        case .gpa, .reports, .transcript: return .grades
        case .students: return .settings
        default: return self
        }
    }
}

/// Pushes a class page onto whichever navigation stack is showing.
struct CourseRoute: Hashable {
    var courseID: String
}

/// Asks the main view to present the sign-in sheet, either to add a student or
/// to sign an existing one in again.
struct SignInRequest: Identifiable {
    let id = UUID()
    var reauth: Profile?
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    /// Each theme sets its own light or dark look.
    private var scheme: ColorScheme? {
        model.settings.backgroundTheme.isDark ? .dark : .light
    }

    var body: some View {
        Group {
            if model.profiles.isEmpty {
                NavigationStack { SignInView(isFirstRun: true) }
            } else if model.isLocked {
                LockView()
            } else {
                MainView()
            }
        }
        .windowEffects()
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(get: { !model.settings.helloShown }, set: { _ in })) {
            PhoneWelcome()
                .environment(model)
        }
        #endif
        .tint(model.theme.color)
        .environment(\.backgroundTheme, model.settings.backgroundTheme)
        .environment(\.accentTheme, model.theme)
        .preferredColorScheme(scheme)
        .sheet(
            isPresented: Binding(
                get: { !model.firstRunActive && (model.qmlativSignIn != nil || model.signInRequest != nil || model.showOnboarding) },
                set: { presented in
                    if !presented {
                        model.qmlativSignIn = nil
                        model.signInRequest = nil
                        model.showOnboarding = false
                    }
                }
            )
        ) {
            Group {
                if let session = model.qmlativSignIn {
                    QmlativSignInSheet(session: session)
                        #if os(macOS)
                        .frame(minWidth: 860, minHeight: 640)
                        #endif
                } else if let request = model.signInRequest {
                    NavigationStack {
                        SignInView(reauth: request.reauth)
                    }
                    #if os(macOS)
                    .frame(minWidth: 520, minHeight: 620)
                    #endif
                } else if model.showOnboarding {
                    OnboardingSheet()
                        #if os(macOS)
                        .frame(minWidth: 720, minHeight: 640)
                        #endif
                }
            }
            .environment(\.backgroundTheme, model.settings.backgroundTheme)
            .environment(\.accentTheme, model.theme)
            .environment(\.windowTranslucent, false)
            .preferredColorScheme(scheme)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                model.markSeen()
                model.lockIfNeeded()
            case .active:
                Task { await refreshIfStale() }
            default:
                break
            }
        }
        .onChange(of: model.active?.id) { _, _ in
            checkOnboarding()
        }
        .task {
            checkOnboarding()
            await refreshIfStale()
        }
    }

    private func checkOnboarding() {
        guard Notifier.isEnabled,
              !model.firstRunActive,
              !model.isLocked,
              model.qmlativSignIn == nil,
              model.signInRequest == nil,
              let active = model.active,
              !active.isDemo,
              !active.prefs.onboardingDone else { return }
        model.showOnboarding = true
    }

    /// Syncs on launch and on return to the app, at most every ten minutes.
    private func refreshIfStale() async {
        guard !model.isLocked, model.active != nil, !model.syncState.isSyncing else { return }
        if case .needsSignIn = model.syncState { return }
        let last = model.data.lastSync ?? .distantPast
        if model.now().timeIntervalSince(last) > 600 { await model.refresh() }
    }
}

struct LockView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(model.theme.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: model.theme.color.opacity(0.3), radius: 16, y: 8)
            Text("Skyward Plus is locked").font(.title2.weight(.semibold))
            Text("Unlock to see grades.").foregroundStyle(.secondary)
            Button {
                Task { await model.unlock() }
            } label: {
                Label("Unlock with \(Biometrics.name)", systemImage: Biometrics.symbol)
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PageBackground() }
        .task { await model.unlock() }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            #if os(macOS)
            SidebarLayout()
                .overlay(alignment: .top) {
                    if model.showPalette {
                        ZStack(alignment: .top) {
                            Color.black.opacity(0.12)
                                .ignoresSafeArea()
                                .onTapGesture { model.showPalette = false }
                            CommandPalette()
                                .padding(.top, 90)
                                .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                        }
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.showPalette)
            #else
            if sizeClass == .compact { PhoneTabs() } else { SidebarLayout() }
            #endif
        }
        .overlay { CelebrationOverlay() }

    }
}

/// One navigation stack per section, with the routes every screen may push.
struct SectionHost: View {
    @Environment(AppModel.self) private var model
    let section: AppSection
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            SectionScreen(section: section)
                .clearWindowBar()
                .navigationDestination(for: CourseRoute.self) { ClassDetailView(courseID: $0.courseID).clearWindowBar() }
                .navigationDestination(for: AppSection.self) { SectionScreen(section: $0).clearWindowBar() }
        }
        .onAppear(perform: openRequestedCourse)
        .onChange(of: model.openCourse) { _, _ in openRequestedCourse() }
    }

    /// Search and the menu bar ask for a class; the Grades stack shows it.
    private func openRequestedCourse() {
        guard section == .grades, let id = model.openCourse else { return }
        model.openCourse = nil
        path = NavigationPath([CourseRoute(courseID: id)])
    }
}

extension View {
    /// Keeps the Mac window's title bar see-through on every page, including pages
    /// pushed onto a stack (each page sets its own toolbar, so each has to ask).
    @ViewBuilder func clearWindowBar() -> some View {
        #if os(macOS)
        if #available(macOS 26, *) {
            self.toolbarBackground(.hidden, for: .windowToolbar)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .scrollEdgeEffectHidden(true, for: .top)
        } else if #available(macOS 15, *) {
            self.toolbarBackground(.hidden, for: .windowToolbar)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self.toolbarBackground(.hidden, for: .windowToolbar)
        }
        #else
        self
        #endif
    }
}

struct SectionScreen: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .home: HomeView()
        case .grades, .gpa, .reports, .transcript: GradesHub()
        case .planner: PlannerView()
        case .schedule, .bell, .teachers: ScheduleHub()
        case .attendance: AttendanceView()
        case .students: StudentsView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - iPad and Mac

struct SidebarLayout: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @AppStorage("sidebar.compact") private var compactSidebar = false
    @State private var windowWidth: CGFloat = 1100

    var body: some View {
        // The sidebar zooms with the window by the same amount as the page beside it,
        // so the two always look like one app at one size.
        let base: CGFloat = compactSidebar ? 76 : 256
        let scale = Screen<EmptyView>.scale(forWidth: max(320, windowWidth - base - 10))
        HStack(spacing: 0) {
            ScaledLayout(scale: scale) {
                AppSidebar(compact: $compactSidebar)
                    .environment(\.displayScale, displayScale * scale)
                    .scaleEffect(scale, anchor: .topLeading)
            }
            .frame(width: base * scale)
            .padding(.leading, 10)
            .padding(.vertical, 10)
            .zIndex(1)
            SectionHost(section: model.section)
                .id(model.section)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 10)).animation(Motion.smooth),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
                .overlay(alignment: .top) { SyncLine() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { PageBackground().overlay { PointerLight() } }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { windowWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in windowWidth = width }
            }
        }
        .environment(\.pageBackgroundProvided, true)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: compactSidebar)
    }
}

/// Shows who is active and switches between students.
struct ProfileSwitcher: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let profile = model.active {
            Menu {
                ForEach(model.profiles) { other in
                    Button {
                        withAnimation(Motion.snappy) {
                            model.setActive(other.id)
                        }
                    } label: {
                        if other.id == profile.id {
                            Label(other.name, systemImage: "checkmark")
                        } else {
                            Text(other.name)
                        }
                    }
                }
                Divider()
                Button {
                    model.showOnboarding = true
                } label: {
                    Label("Customize Profile…", systemImage: "slider.horizontal.3")
                }
                Button {
                    model.signInRequest = SignInRequest()
                } label: {
                    Label("Add Student…", systemImage: "person.badge.plus")
                }
            } label: {
                HStack(spacing: 10) {
                    AvatarView(profile: profile, size: 36, scalesWithWindow: false)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.name).font(.headline).lineLimit(1)
                        Text(profile.districtName.isEmpty ? profile.username : profile.districtName)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .padding(.vertical, 4)
        }
    }
}

struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if model.syncState.isSyncing {
                ProgressView().controlSize(.small)
                Text("Syncing…").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(model.data.lastSync != nil ? Palette.good : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text("Updated " + Fmt.ago(model.data.lastSync, now: model.now()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                SpinningRefreshIcon(spinning: model.syncState.isSyncing)
                    .font(.callout.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(model.syncState.isSyncing)
            .help("Refresh grades")
            .accessibilityLabel("Refresh grades")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - Students

/// Everyone signed in on this device: switch, rename, or remove.
struct StudentsView: View {
    @Environment(AppModel.self) private var model
    @State private var removing: Profile?

    var body: some View {
        Screen(title: "Students", maxWidth: 720) {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                        HoverRow {
                            HStack(spacing: 12) {
                                AvatarView(profile: profile, size: 46)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(profile.name).font(.headline)
                                        if profile.isDemo { Pill(text: "Demo", tint: .secondary) }
                                    }
                                    Text(profile.districtName.isEmpty ? profile.username : profile.districtName)
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                    Text("Updated " + Fmt.ago(model.data(for: profile.id).lastSync, now: model.now()))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if profile.id == model.active?.id {
                                    Pill(text: "Active", tint: profile.theme.color, filled: true)
                                } else {
                                    Button("Switch") {
                                        withAnimation(Motion.snappy) {
                                            model.setActive(profile.id)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                                Menu {
                                    if profile.id == model.active?.id {
                                        Button {
                                            model.showOnboarding = true
                                        } label: {
                                            Label("Customize Profile…", systemImage: "wand.and.stars")
                                        }
                                    }
                                    if case .needsSignIn = model.syncStates[profile.id] ?? .idle {
                                        Button("Sign In Again…") { model.requestReauth(profile) }
                                    }
                                    Button("Refresh") { Task { await model.refresh(profile.id) } }
                                    Button("Remove…", role: .destructive) { removing = profile }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                                .accessibilityLabel("More for \(profile.name)")
                            }
                            .padding(14)
                        }
                        .rowDivider(index < model.profiles.count - 1)
                    }
                }
            }
            .staggered(0)

            HStack(spacing: 12) {
                Button {
                    model.signInRequest = SignInRequest()
                } label: {
                    Label("Add Student", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.showOnboarding = true
                } label: {
                    Label("Run Setup Wizard", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
            }
            .staggered(1)

            Text("Parents can add each child, or sign in once with a family account to add them all. Each student keeps their own theme, planner and settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .staggered(2)
        }
        .confirmationDialog(
            "Remove \(removing?.name ?? "this student")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let profile = removing { model.removeProfile(profile.id) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("Their grades, planner and saved password are deleted from this device. Nothing changes in Skyward.")
        }
    }
}


/// The refresh arrow, turning while a sync runs. It is driven by the clock rather
/// than a repeating animation, which would also animate the arrow's position
/// whenever the footer's layout changed and send it drifting.
struct SpinningRefreshIcon: View {
    let spinning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !spinning || reduceMotion)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(spinning && !reduceMotion ? turn * 360 : 0))
        }
    }
}
