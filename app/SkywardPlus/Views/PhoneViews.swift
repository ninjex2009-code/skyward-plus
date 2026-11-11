#if os(iOS)
import SwiftUI

// The iPhone app: four tabs, each answering one question.
//   Home     what needs me right now
//   Grades   how am I doing (classes, report cards, GPA)
//   Planner  what is coming
//   You      schedule, attendance and settings

enum PhoneTab: String, Hashable {
    case home, grades, planner, you
}

struct PhoneTabs: View {
    @Environment(AppModel.self) private var model
    @State private var tab = PhoneTab.home
    @State private var youPath = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            SectionHost(section: .home)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(PhoneTab.home)
            SectionHost(section: .grades)
                .tabItem { Label("Grades", systemImage: "graduationcap") }
                .tag(PhoneTab.grades)
            SectionHost(section: .planner)
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
            case .grades: if model.section != .grades { model.section = .grades }
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

    /// Other parts of the app ask for a section by name; this finds it on the phone.
    /// (The model has already mapped GPA and report cards onto Grades.)
    private func route(to section: AppSection) {
        switch section {
        case .home: tab = .home
        case .grades: tab = .grades
        case .planner: tab = .planner
        default:
            youPath = NavigationPath([section])
            tab = .you
        }
    }
}

// MARK: - Class row

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

// MARK: - You

struct PhoneYou: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: "You", spacing: 24, maxWidth: 720) {
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
