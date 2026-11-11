import SwiftUI

/// The overview on every platform: what needs you, your classes at a glance, and
/// what just came in. Average and GPA appear once, as ways into Grades. The full
/// week of due work lives in Planner.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: "Home", spacing: 22) {
            HomeHeader()
                .staggered(0)
            SyncStatusView { model.requestReauth() }
            BellBannerCard()
            if model.data.courses.isEmpty {
                Card {
                    EmptyState(
                        symbol: model.syncState.isSyncing ? "arrow.triangle.2.circlepath" : "tray",
                        title: model.syncState.isSyncing ? "Getting your grades" : "No classes yet",
                        message: model.syncState.isSyncing ? "This takes a few seconds the first time." : "Refresh to load your classes."
                    )
                }
            } else {
                HomeColumns().staggered(1)
            }
        }
        .refreshable { await model.refresh() }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.titleAndIcon)
                .disabled(model.syncState.isSyncing)
            }
        }
        #endif
    }
}

private struct HomeColumns: View {
    @Environment(\.windowMetrics) private var metrics

    var body: some View {
        switch metrics.columns {
        case 3:
            HStack(alignment: .top, spacing: 22) {
                NeedsYouSection().frame(maxWidth: .infinity, alignment: .top)
                ClassGrid().frame(maxWidth: .infinity, alignment: .top)
                RecentSection().frame(maxWidth: .infinity, alignment: .top)
            }
        case 2:
            HStack(alignment: .top, spacing: 22) {
                NeedsYouSection().frame(maxWidth: .infinity, alignment: .top)
                VStack(alignment: .leading, spacing: 22) {
                    ClassGrid()
                    RecentSection()
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        default:
            VStack(alignment: .leading, spacing: 22) {
                NeedsYouSection()
                ClassGrid()
                RecentSection()
            }
        }
    }
}

// MARK: - Header

private struct HomeHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.windowMetrics) private var metrics

    var body: some View {
        let lit = model.selectedLit
        let numbers = lit.map { lit in model.courses(in: lit).compactMap { model.percent($0, lit) } } ?? []
        let average = numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)
        let gpa = lit.map { GPA.compute(GPA.currentEntries(data: model.data, lit: $0, settings: model.prefs.gpa)) }

        let figures = HStack(spacing: 12) {
            if let average {
                FigureButton(number: average, format: { Fmt.percent($0) }, label: (lit ?? "") + " average", tint: GradeColor.color(percent: average)) {
                    model.gradesTab = .classes
                    model.section = .grades
                }
            }
            if let weighted = gpa?.weighted {
                FigureButton(number: weighted, format: { Fmt.gpa($0) }, label: "GPA", tint: .primary) {
                    model.section = .gpa
                }
            }
        }

        if metrics.width < 620 {
            VStack(alignment: .leading, spacing: 14) {
                Text(dateLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                figures
            }
        } else {
            HStack(alignment: .bottom, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.now().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(model.active?.firstName ?? "Home")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("Updated " + Fmt.ago(model.data.lastSync, now: model.now()))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                figures.frame(maxWidth: 420)
            }
            .padding(.top, 4)
        }
    }

    private var dateLine: String {
        model.now().formatted(.dateTime.weekday(.wide).month(.wide).day()) + " · updated " + Fmt.ago(model.data.lastSync, now: model.now())
    }
}

/// A big number that is also the way to the screen it summarises.
private struct FigureButton: View {
    let number: Double
    let format: (Double) -> String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(cornerRadius: 18, hoverable: true)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(BubbleButtonStyle())
        .accessibilityLabel("\(label) \(format(number))")
    }
}

// MARK: - Needs you

/// Missing work, what is due today or tomorrow, and classes under their goal.
/// When there is none of that it says so in one line.
private struct NeedsYouSection: View {
    @Environment(AppModel.self) private var model
    @State private var completed = 0

    var body: some View {
        let allMissing = model.missingAssignments
        let missing = Array(allMissing.prefix(5))
        let missingTitles = Set(allMissing.map { $0.assignment.name })
        let cutoff = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: model.now())) ?? model.now()
        let due = Array(model.dueItems.filter { !$0.done && $0.due < cutoff && !missingTitles.contains($0.title) }.prefix(5))
        let below = belowGoal
        let total = allMissing.count + due.count + below.count

        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Needs You")
            if total == 0 {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(Palette.good)
                        .symbolEffect(.bounce, value: completed)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All caught up").font(.headline)
                        Text("Nothing missing or due by \(Fmt.relativeDay(cutoff, now: model.now()).lowercased()).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(cornerRadius: 18)
            } else {
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
                                subtitle: "Under your goal of \(Fmt.percent(entry.goal))",
                                trailing: Fmt.percent(entry.percent), trailingTint: Palette.warn
                            )
                            .bubble()
                        }
                        .buttonStyle(BubbleButtonStyle())
                    }
                }
                if allMissing.count > missing.count {
                    Button("\(allMissing.count - missing.count) more missing") { model.section = .planner }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
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
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

/// Something due soon: tap the circle (or swipe right on iPhone) to finish it.
private struct DueNeedRow: View {
    @Environment(AppModel.self) private var model
    let item: AppModel.DueItem
    let complete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: complete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(Color.secondary.opacity(0.8))
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
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .swipeToComplete(done: false, action: complete)
        .bubble()
    }
}

// MARK: - Classes

/// Every class as a chip: name and grade, nothing else. Tap for the class.
private struct ClassGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let lit = model.selectedLit {
            let courses = model.courses(in: lit).filter { !model.gradeText($0, lit).isEmpty || $0.grade(lit)?.hasDetail == true }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Classes") {
                    Button("All Grades") {
                        model.gradesTab = .classes
                        model.section = .grades
                    }
                        .buttonStyle(.borderless)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                    ForEach(courses) { course in
                        NavigationLink(value: CourseRoute(courseID: course.id)) {
                            ClassChip(course: course, lit: lit)
                        }
                        .buttonStyle(BubbleButtonStyle())
                    }
                }
            }
        }
    }
}

private struct ClassChip: View {
    @Environment(AppModel.self) private var model
    let course: Course
    let lit: String

    var body: some View {
        let missing = model.detail(course.id, lit)?.assignments.filter { $0.missing }.count ?? 0
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Str.titleCase(course.name))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if missing > 0 {
                    Text("\(missing) missing").font(.caption).foregroundStyle(Palette.bad)
                }
            }
            Spacer(minLength: 4)
            GradeBubble(text: model.gradeText(course, lit), percent: model.percent(course, lit), size: .small)
        }
        .padding(12)
        .frame(minHeight: 66)
        .bubble()
    }
}

// MARK: - Recent

/// Grades that came in recently.
private struct RecentSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let changes = Array(model.recentChanges.filter { $0.kind == .newGrade || $0.kind == .updatedGrade }.prefix(6))
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
