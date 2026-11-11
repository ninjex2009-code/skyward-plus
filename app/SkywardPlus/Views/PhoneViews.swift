#if os(iOS)
import SwiftUI

// The iPhone app: four tabs, each answering one question.
//   Home     what needs me right now
//   Grades   how am I doing (classes, and GPA beside them)
//   Planner  what is coming
//   You      school information and settings

enum PhoneTab: String, Hashable {
    case home, grades, planner, you
}

enum GradesMode: String, CaseIterable, Identifiable {
    case classes = "Classes"
    case gpa = "GPA"
    var id: String { rawValue }
}

struct PhoneTabs: View {
    @Environment(AppModel.self) private var model
    @State private var tab = PhoneTab.home
    @State private var gradesMode = GradesMode.classes
    @State private var youPath = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            PhoneStack { PhoneHome(showGrades: showGrades) }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(PhoneTab.home)
            PhoneGrades(mode: $gradesMode)
                .tabItem { Label("Grades", systemImage: "graduationcap") }
                .tag(PhoneTab.grades)
            PhoneStack { PlannerView() }
                .tabItem { Label("Planner", systemImage: "checklist") }
                .tag(PhoneTab.planner)
            NavigationStack(path: $youPath) {
                PhoneYou()
                    .navigationDestination(for: AppSection.self) { SectionScreen(section: $0) }
                    .navigationDestination(for: CourseRoute.self) { ClassDetailView(courseID: $0.courseID) }
            }
            .tabItem { Label("You", systemImage: "person.crop.circle") }
            .tag(PhoneTab.you)
        }
        .sensoryFeedback(.selection, trigger: tab)
        .onChange(of: model.section) { _, section in route(to: section) }
        .onChange(of: tab) { _, tab in
            // Keep the model's idea of the current section in step with the tab bar.
            switch tab {
            case .home: if model.section != .home { model.section = .home }
            case .grades: if model.section != .grades, model.section != .gpa { model.section = gradesMode == .gpa ? .gpa : .grades }
            case .planner: if model.section != .planner { model.section = .planner }
            case .you: break
            }
        }
        #if DEBUG
        .task {
            // Opens straight to a screen, for checking each one in the simulator.
            let env = ProcessInfo.processInfo.environment
            if let raw = env["SKYWARDPLUS_SECTION"] {
                if raw == "you" { tab = .you } else if let section = AppSection(rawValue: raw) { model.section = section }
            }
            if env["SKYWARDPLUS_OPEN_COURSE"] != nil, let first = model.courses.first {
                model.section = .grades
                model.openCourse = first.id
            }
        }
        #endif
    }

    private func showGrades(_ mode: GradesMode) {
        gradesMode = mode
        tab = .grades
    }

    /// Other parts of the app ask for a section by name; this finds it on the phone.
    private func route(to section: AppSection) {
        switch section {
        case .home: tab = .home
        case .grades: gradesMode = .classes; tab = .grades
        case .gpa: gradesMode = .gpa; tab = .grades
        case .planner: tab = .planner
        default:
            youPath = NavigationPath([section])
            tab = .you
        }
    }
}

/// A navigation stack that can open a class or any section from its root.
struct PhoneStack<Root: View>: View {
    @ViewBuilder var root: Root

    var body: some View {
        NavigationStack {
            root
                .navigationDestination(for: CourseRoute.self) { ClassDetailView(courseID: $0.courseID) }
                .navigationDestination(for: AppSection.self) { SectionScreen(section: $0) }
        }
    }
}

// MARK: - Home

struct PhoneHome: View {
    @Environment(AppModel.self) private var model
    let showGrades: (GradesMode) -> Void

    var body: some View {
        Screen(title: "Home", spacing: 24) {
            Text(dateLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, -6)
            SyncStatusView { model.requestReauth() }
            if model.data.courses.isEmpty {
                Card {
                    EmptyState(
                        symbol: model.syncState.isSyncing ? "arrow.triangle.2.circlepath" : "tray",
                        title: model.syncState.isSyncing ? "Getting your grades" : "No classes yet",
                        message: model.syncState.isSyncing ? "This takes a few seconds the first time." : "Pull down to load your classes from Skyward."
                    )
                }
            } else {
                NeedsYouSection().staggered(0)
                SummaryTiles(showGrades: showGrades).staggered(1)
                BellBannerCard()
                PhoneClassesSection(showGrades: showGrades).staggered(2)
                PhoneRecentSection().staggered(3)
            }
        }
        .refreshable { await model.refresh() }
    }

    private var dateLine: String {
        let date = model.now().formatted(.dateTime.weekday(.wide).month(.wide).day())
        return date + " · updated " + Fmt.ago(model.data.lastSync, now: model.now())
    }
}

/// The top of Home: missing work, what is due today or tomorrow, and classes
/// under their goal. When there is none of that, it says so in one line.
private struct NeedsYouSection: View {
    @Environment(AppModel.self) private var model
    @State private var completed = 0

    var body: some View {
        let missing = Array(model.missingAssignments.prefix(4))
        let missingTitles = Set(model.missingAssignments.map { $0.assignment.name })
        let cutoff = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: model.now())) ?? model.now()
        let due = Array(model.dueItems.filter { !$0.done && $0.due < cutoff && !missingTitles.contains($0.title) }.prefix(5))
        let below = belowGoal
        let total = model.missingAssignments.count + due.count + below.count

        VStack(alignment: .leading, spacing: 10) {
            if total == 0 {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(Palette.good)
                            .symbolEffect(.bounce, value: completed)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You're all caught up").font(.headline)
                            Text("Nothing missing and nothing due before \(Fmt.relativeDay(cutoff, now: model.now()).lowercased()).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                SectionHeader("Needs You")
                VStack(spacing: 10) {
                    ForEach(missing) { item in
                        NavigationLink(value: CourseRoute(courseID: item.course.id)) {
                            NeedRow(
                                symbol: "exclamationmark.circle.fill", tint: Palette.bad,
                                title: item.assignment.name,
                                subtitle: Str.titleCase(item.course.name),
                                trailing: "Missing", trailingTint: Palette.bad
                            )
                            .bubble()
                        }
                        .buttonStyle(BubbleButtonStyle())
                    }
                    ForEach(due) { item in
                        DueNeedRow(item: item) {
                            withAnimation(.snappy) { model.toggleDue(item.id) }
                            completed += 1
                        }
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.96))))
                    }
                    ForEach(below, id: \.course.id) { entry in
                        NavigationLink(value: CourseRoute(courseID: entry.course.id)) {
                            NeedRow(
                                symbol: "arrow.down.right.circle.fill", tint: Palette.warn,
                                title: Str.titleCase(entry.course.name),
                                subtitle: "Below your goal of \(Fmt.percent(entry.goal))",
                                trailing: Fmt.percent(entry.percent), trailingTint: Palette.warn
                            )
                            .bubble()
                        }
                        .buttonStyle(BubbleButtonStyle())
                    }
                }
                if model.missingAssignments.count > missing.count {
                    Text("\(model.missingAssignments.count - missing.count) more missing in Planner")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
        .sensoryFeedback(.success, trigger: completed)
    }

    private var belowGoal: [(course: Course, percent: Double, goal: Double)] {
        guard let lit = model.data.currentLit else { return [] }
        return model.courses(in: lit).compactMap { course in
            guard let goal = model.goal(for: course.id), let percent = model.percent(course, lit), percent < goal else { return nil }
            return (course, percent, goal)
        }
    }
}

private struct NeedRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    let trailing: String
    var trailingTint: Color = .secondary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(trailing)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(trailingTint)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// Something due soon: tap the circle, or swipe right, to mark it done.
private struct DueNeedRow: View {
    @Environment(AppModel.self) private var model
    let item: AppModel.DueItem
    let complete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: complete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark done")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                if !item.course.isEmpty {
                    Text(item.course).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(Fmt.relativeDay(item.due, now: model.now()))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Calendar.current.isDate(item.due, inSameDayAs: model.now()) ? Palette.warn : .secondary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .swipeToComplete(done: false, action: complete)
        .bubble()
    }
}

/// Average and GPA, each a way into Grades.
private struct SummaryTiles: View {
    @Environment(AppModel.self) private var model
    let showGrades: (GradesMode) -> Void

    var body: some View {
        if let lit = model.selectedLit {
            let numbers = model.courses(in: lit).compactMap { model.percent($0, lit) }
            let average = numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)
            let gpa = GPA.compute(GPA.currentEntries(data: model.data, lit: lit, settings: model.prefs.gpa))
            HStack(spacing: 12) {
                if let average {
                    tile(number: average, format: { Fmt.percent($0) }, label: "\(lit) average", tint: GradeColor.color(percent: average)) { showGrades(.classes) }
                }
                if let weighted = gpa.weighted {
                    tile(number: weighted, format: { Fmt.gpa($0) }, label: "GPA", tint: .primary) { showGrades(.gpa) }
                }
            }
        }
    }

    private func tile(number: Double, format: @escaping (Double) -> String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Card {
                VStack(alignment: .leading, spacing: 2) {
                    RollingNumber(value: number, format: format)
                        .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                    HStack(spacing: 4) {
                        Text(label).font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct PhoneClassesSection: View {
    @Environment(AppModel.self) private var model
    let showGrades: (GradesMode) -> Void

    var body: some View {
        if let lit = model.selectedLit {
            let courses = model.courses(in: lit).filter { !model.gradeText($0, lit).isEmpty || $0.grade(lit)?.hasDetail == true }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Classes") {
                    Button("See All") { showGrades(.classes) }
                }
                RowGroup(items: courses) { course in
                    NavigationLink(value: CourseRoute(courseID: course.id)) {
                        PhoneClassRow(course: course, lit: lit)
                    }
                    .buttonStyle(BubbleButtonStyle())
                }
            }
        }
    }
}

/// A class on the phone: its name, who teaches it, and the grade. Nothing else.
struct PhoneClassRow: View {
    @Environment(AppModel.self) private var model
    let course: Course
    let lit: String

    var body: some View {
        let missing = model.detail(course.id, lit)?.assignments.filter { $0.missing }.count ?? 0
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Str.titleCase(course.name))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !course.teacher.isEmpty {
                        Text(Str.titleCase(course.teacher)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if missing > 0 {
                        Text("\(missing) missing").foregroundStyle(Palette.bad).layoutPriority(1)
                    }
                }
                .font(.footnote)
            }
            Spacer(minLength: 8)
            GradeBubble(text: model.gradeText(course, lit), percent: model.percent(course, lit))
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}

private struct PhoneRecentSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let changes = Array(model.recentChanges.filter { $0.kind == .newGrade || $0.kind == .updatedGrade }.prefix(5))
        if !changes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Recent Grades")
                RowGroup(items: changes) { change in
                    NavigationLink(value: CourseRoute(courseID: change.courseID)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(change.title).lineLimit(1)
                                Text(change.courseName + " · " + Fmt.dueDay(change.date, now: model.now()))
                                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(change.detail)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(GradeColor.color(percent: change.newValue))
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BubbleButtonStyle())
                }
            }
        }
    }
}

// MARK: - Grades

/// Classes and GPA share a tab: the switch sits in the navigation bar.
struct PhoneGrades: View {
    @Environment(AppModel.self) private var model
    @Binding var mode: GradesMode
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch mode {
                case .classes: GradesView()
                case .gpa: GPAView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if path.isEmpty {
                    ToolbarItem(placement: .principal) {
                        Picker("Show", selection: $mode.animation(.snappy)) {
                            ForEach(GradesMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                }
            }
            .navigationDestination(for: CourseRoute.self) { ClassDetailView(courseID: $0.courseID) }
            .navigationDestination(for: AppSection.self) { SectionScreen(section: $0) }
        }
        .sensoryFeedback(.selection, trigger: mode)
        .onAppear(perform: openRequestedCourse)
        .onChange(of: model.openCourse) { _, _ in openRequestedCourse() }
    }

    /// Something elsewhere asked for a class; show it here.
    private func openRequestedCourse() {
        guard let id = model.openCourse else { return }
        model.openCourse = nil
        mode = .classes
        path = NavigationPath([CourseRoute(courseID: id)])
    }
}

// MARK: - You

struct PhoneYou: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: "You", spacing: 24) {
            if let profile = model.active {
                NavigationLink(value: AppSection.students) {
                    HStack(spacing: 14) {
                        AvatarView(profile: profile, size: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(subtitle(profile))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .bubble(cornerRadius: 20)
                }
                .buttonStyle(BubbleButtonStyle())
                .accessibilityHint("Switch or add a student")
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(AppSection.school + AppSection.app) { section in
                    NavigationLink(value: section) {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: section.symbol)
                                .font(.title2)
                                .foregroundStyle(model.theme.color)
                                .frame(height: 28)
                            Text(section.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                        .bubble(cornerRadius: 20)
                    }
                    .buttonStyle(BubbleButtonStyle())
                }
            }

            Text("Updated " + Fmt.ago(model.data.lastSync, now: model.now()) + ". Pull down to refresh.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .refreshable { await model.refresh() }
    }

    private func subtitle(_ profile: Profile) -> String {
        let school = Str.titleCase(model.data.profile.school)
        if !school.isEmpty { return school }
        return profile.districtName.isEmpty ? profile.username : profile.districtName
    }
}

// MARK: - Welcome

/// The first-launch setup on iPhone: the same hello and guided steps as the Mac,
/// over the app blurred behind it.
struct PhoneWelcome: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        FirstRunView(onFinish: finish)
            .environment(\.colorScheme, .dark)
            .tint(model.theme.color)
            .background {
                LinearGradient(colors: [Color(hex: 0x10162A), .black], startPoint: .top, endPoint: .bottom)
                    .opacity(0.86)
                    .ignoresSafeArea()
            }
            .presentationBackground(.ultraThinMaterial)
            .interactiveDismissDisabled()
            .onAppear { model.firstRunActive = true }
    }

    private func finish() {
        model.firstRunActive = false
        if model.active != nil { model.updatePrefs { $0.onboardingDone = true } }
        withAnimation(.easeInOut(duration: 0.45)) {
            model.updateSettings { $0.helloShown = true }
        }
    }
}

// MARK: - Swipe

/// Drag a row to the right to finish it. Past the threshold the row arms (with a
/// tap of feedback) and letting go completes it; short of that it springs back.
private struct SwipeToComplete: ViewModifier {
    let done: Bool
    let action: () -> Void
    @State private var offset: CGFloat = 0
    @State private var armed = false
    private let threshold: CGFloat = 84

    func body(content: Content) -> some View {
        content
            .background(.background.opacity(0.001))
            .offset(x: offset)
            .background(alignment: .leading) {
                if offset > 0 {
                    ZStack(alignment: .leading) {
                        (armed ? Palette.good : Color.secondary.opacity(0.35))
                        Image(systemName: done ? "arrow.uturn.backward" : "checkmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .scaleEffect(armed ? 1.15 : 0.9)
                            .padding(.leading, 20)
                    }
                    .animation(.snappy(duration: 0.15), value: armed)
                }
            }
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
            .modifier(RightwardPan(
                changed: { x in
                    offset = x < threshold ? x : threshold + (x - threshold) * 0.35
                    armed = x >= threshold
                },
                ended: {
                    let fire = armed
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
                    armed = false
                    if fire { action() }
                }
            ))
            .sensoryFeedback(.impact(weight: .medium), trigger: armed) { _, now in now }
            .accessibilityAction(named: done ? "Mark not done" : "Mark done", action)
    }
}

/// Attaches a pan that only starts for a mostly sideways, rightward drag, so
/// vertical scrolling is untouched, and that cancels the row's own tap once it
/// starts, so swiping a row never also opens it.
private struct RightwardPan: ViewModifier {
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(PanRecognizer(changed: changed, ended: ended))
        } else {
            // Before iOS 18 there is no way to do this without fighting the scroll
            // view; the circle on the row still marks it done.
            content
        }
    }
}

@available(iOS 18.0, *)
private struct PanRecognizer: UIGestureRecognizerRepresentable {
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .changed:
            changed(max(0, recognizer.translation(in: recognizer.view).x))
        case .ended, .cancelled, .failed:
            ended()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.x > 0 && abs(velocity.x) > abs(velocity.y) * 1.5
        }
    }
}

extension View {
    func swipeToComplete(done: Bool, action: @escaping () -> Void) -> some View {
        modifier(SwipeToComplete(done: done, action: action))
    }
}
#else
import SwiftUI

extension View {
    /// Swiping rows is an iPhone gesture; on the Mac this does nothing.
    func swipeToComplete(done: Bool, action: @escaping () -> Void) -> some View { self }
}
#endif
