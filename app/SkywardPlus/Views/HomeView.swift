import SwiftUI

/// The overview: how the student is doing, what needs attention, what is due,
/// and what changed. Every block hides itself when it has nothing to say.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: "Home") {
            HomeHeader()
                .staggered(0)
            SyncStatusView { model.requestReauth() }
            BellBannerCard()
                .staggered(1)
            if model.data.courses.isEmpty {
                Card {
                    EmptyState(
                        symbol: model.syncState.isSyncing ? "arrow.triangle.2.circlepath" : "tray",
                        title: model.syncState.isSyncing ? "Getting your grades" : "No classes yet",
                        message: model.syncState.isSyncing ? "This takes a few seconds the first time." : "Refresh to load your classes from Skyward."
                    )
                }
            } else {
                AttentionSection().staggered(2)
                HomeColumns().staggered(3)
            }
        }
        .refreshable { await model.refresh() }
    }
}

// MARK: - Header

private struct HomeHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.windowMetrics) private var metrics

    var body: some View {
        let lit = model.selectedLit
        let courses = lit.map { model.courses(in: $0) } ?? []
        let numbers = courses.compactMap { course in lit.flatMap { model.percent(course, $0) } }
        let average = numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)
        let gpa = lit.map { GPA.compute(GPA.currentEntries(data: model.data, lit: $0, settings: model.prefs.gpa)) }

        let compact = metrics.width < 560
        let title = VStack(alignment: .leading, spacing: 4) {
            Text(model.now().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(model.active?.firstName ?? "Home")
                .font(.system(.largeTitle, design: .rounded).bold())
            Text(summary(lit: lit, classCount: courses.count))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        let figures = Group {
            if let average {
                Figure(label: lit.map { "\($0) average" } ?? "Average", number: average, format: { Fmt.percent($0) }, tint: GradeColor.color(percent: average), alignment: compact ? .leading : .trailing)
            }
            if let weighted = gpa?.weighted {
                Figure(label: "GPA", number: weighted, format: { Fmt.gpa($0) }, tint: .primary, alignment: compact ? .leading : .trailing)
                    .help("Weighted. Unweighted \(Fmt.gpa(gpa?.unweighted))")
            }
        }
        Group {
            if compact {
                // On a phone the numbers get their own row instead of squeezing the name.
                VStack(alignment: .leading, spacing: 14) {
                    title
                    HStack(alignment: .bottom, spacing: 28) { figures }
                }
            } else {
                HStack(alignment: .bottom, spacing: 24) {
                    title
                    Spacer(minLength: 16)
                    figures
                }
            }
        }
        .padding(.top, 8)
    }

    private func summary(lit: String?, classCount: Int) -> String {
        var parts: [String] = []
        if let lit, let bucket = model.data.bucket(lit) { parts.append(bucket.displayName) }
        if classCount > 0 { parts.append(classCount == 1 ? "1 class" : "\(classCount) classes") }
        parts.append("updated " + Fmt.ago(model.data.lastSync, now: model.now()))
        return parts.joined(separator: " · ")
    }
}

private struct Figure: View {
    let label: String
    let number: Double
    let format: (Double) -> String
    let tint: Color
    var alignment: HorizontalAlignment = .trailing

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            RollingNumber(value: number, format: format)
                .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Needs attention

/// Missing work and classes under their goal. Hidden when there is neither.
private struct AttentionSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let missing = model.missingAssignments
        let lit = model.data.currentLit
        let below = lit.map { lit in
            model.courses(in: lit).compactMap { course -> (Course, Double, Double)? in
                guard let goal = model.goal(for: course.id), let p = model.percent(course, lit), p < goal else { return nil }
                return (course, p, goal)
            }
        } ?? []

        if !missing.isEmpty || !below.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Needs Attention")
                Card(padding: 0, tint: Palette.bad) {
                    VStack(spacing: 0) {
                        ForEach(Array(missing.prefix(6).enumerated()), id: \.element.id) { index, item in
                            Button {
                                model.section = .grades
                                model.openCourse = item.course.id
                            } label: {
                                HomeRow(
                                    title: item.assignment.name,
                                    subtitle: Str.titleCase(item.course.name) + (item.assignment.due.map { " · due " + Fmt.dueDay($0, now: model.now()) } ?? ""),
                                    trailing: "Missing",
                                    trailingTint: Palette.bad
                                )
                            }
                            .buttonStyle(.plain)
                            .rowDivider(index < min(missing.count, 6) - 1 || !below.isEmpty)
                        }
                        ForEach(Array(below.enumerated()), id: \.element.0.id) { index, entry in
                            Button {
                                model.section = .grades
                                model.openCourse = entry.0.id
                            } label: {
                                HomeRow(
                                    title: Str.titleCase(entry.0.name),
                                    subtitle: "Below your goal of \(Fmt.percent(entry.2))",
                                    trailing: Fmt.percent(entry.1),
                                    trailingTint: Palette.warn
                                )
                            }
                            .buttonStyle(.plain)
                            .rowDivider(index < below.count - 1)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Columns

private struct HomeColumns: View {
    @Environment(\.windowMetrics) private var metrics

    var body: some View {
        if metrics.width >= 900 {
            HStack(alignment: .top, spacing: 20) {
                ClassesSection().frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 24) {
                    DueSoonSection()
                    RecentSection()
                }
                .frame(width: min(380, metrics.width * 0.38))
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                ClassesSection()
                DueSoonSection()
                RecentSection()
            }
        }
    }
}

private struct ClassesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let lit = model.selectedLit {
            let courses = model.courses(in: lit).filter { !model.gradeText($0, lit).isEmpty || $0.grade(lit)?.hasDetail == true }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Classes") {
                    Button("All Grades") { model.section = .grades }
                        .buttonStyle(.borderless)
                }
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(courses.enumerated()), id: \.element.id) { index, course in
                            NavigationLink(value: CourseRoute(courseID: course.id)) {
                                ClassRow(course: course, lit: lit)
                            }
                            .buttonStyle(.plain)
                            .rowDivider(index < courses.count - 1)
                        }
                    }
                }
            }
        }
    }
}

/// The next seven days of Skyward work and planner tasks, tick to mark done.
private struct DueSoonSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: model.now()) ?? model.now()
        let items = model.dueItems.filter { $0.due <= horizon }
        let days = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.due) }.sorted { $0.key < $1.key }

        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Due Soon") {
                Button("Planner") { model.section = .planner }
                    .buttonStyle(.borderless)
            }
            Card(padding: 0) {
                if items.isEmpty {
                    Text("Nothing due in the next week.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.element.key) { dayIndex, day in
                            Text(Fmt.relativeDay(day.key, now: model.now()))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.top, dayIndex == 0 ? 12 : 14)
                                .padding(.bottom, 2)
                            ForEach(day.value) { item in
                                DueRow(item: item)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

private struct DueRow: View {
    @Environment(AppModel.self) private var model
    let item: AppModel.DueItem

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { toggle() }
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.done ? model.theme.color : Color.secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Mark not done" : "Mark done")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? .secondary : .primary)
                    .lineLimit(1)
                if !item.course.isEmpty {
                    Text(item.course).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .hoverSheen()
    }

    private func toggle() {
        model.toggleDue(item.id)
    }
}

/// Grades that came in recently.
private struct RecentSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let changes = Array(model.recentChanges.filter { $0.kind == .newGrade || $0.kind == .updatedGrade }.prefix(6))
        if !changes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Recent Grades")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                            Button {
                                model.section = .grades
                                model.openCourse = change.courseID
                            } label: {
                                HomeRow(
                                    title: change.title,
                                    subtitle: change.courseName + " · " + Fmt.dueDay(change.date, now: model.now()),
                                    trailing: change.detail,
                                    trailingTint: GradeColor.color(percent: change.newValue)
                                )
                            }
                            .buttonStyle(.plain)
                            .rowDivider(index < changes.count - 1)
                        }
                    }
                }
            }
        }
    }
}

private struct HomeRow: View {
    let title: String
    let subtitle: String
    let trailing: String
    var trailingTint: Color = .secondary

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(trailing)
                .font(.callout.weight(.medium).monospacedDigit())
                .foregroundStyle(trailingTint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .hoverSheen()
    }
}
