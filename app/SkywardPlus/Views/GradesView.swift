import SwiftUI

/// Every class with its average for the chosen marking period.
struct GradesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false

    var body: some View {
        let lit = model.selectedLit
        Screen(title: "Grades") {
            SyncStatusView { model.requestReauth() }
            if model.data.courses.isEmpty {
                Card {
                    EmptyState(
                        symbol: "tray",
                        title: model.syncState.isSyncing ? "Getting your grades" : "No classes yet",
                        message: model.syncState.isSyncing ? "This takes a few seconds the first time." : "Refresh to load your classes."
                    )
                }
            } else {
                MarkingPeriodBar()
                    .staggered(0)
                if let lit {
                    GradesSummary(lit: lit)
                        .staggered(1)
                    classList(lit)
                        .staggered(2)
                }
                if !model.data.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.data.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Refresh Grades", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.syncState.isSyncing)
                    Button {
                        editing = true
                    } label: {
                        Label("Reorder or Hide Classes", systemImage: "list.bullet")
                    }
                    #if os(macOS)
                    Button {
                        model.exportReport()
                    } label: {
                        Label("Export Grade Report", systemImage: "doc.richtext")
                    }
                    #endif
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .disabled(model.data.courses.isEmpty)
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { ClassOrderEditor() }
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 520)
            #endif
        }
    }

    @ViewBuilder
    private func classList(_ lit: String) -> some View {
        let courses = model.courses(in: lit)
        if courses.isEmpty {
            Card {
                EmptyState(
                    symbol: "calendar.badge.exclamationmark",
                    title: "Nothing in \(lit)",
                    message: "No grades posted yet."
                )
            }
        } else {
            RowGroup(items: courses, wide: true) { course in
                NavigationLink(value: CourseRoute(courseID: course.id)) {
                    HoverRow {
                        ClassRow(course: course, lit: lit)
                    }
                }
                .buttonStyle(BubbleButtonStyle())
            }
            let hidden = model.prefs.hiddenCourses.count
            if hidden > 0 {
                Text("\(hidden) hidden \(hidden == 1 ? "class" : "classes"). Use Edit to show \(hidden == 1 ? "it" : "them").")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Chips for each gradebook column. The current one is marked with a dot and animated capsule.
/// Every Skyward grading column in one track, like a segmented control.
/// A dot marks the current marking period; columns without grades are dimmed.
/// The quarters, as chips. Report cards, progress reports and exams live under
/// Grades > Report Card instead, so this row stays short.
struct MarkingPeriodBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let quarters = model.data.buckets.filter { $0.kind == .term }
        let shown = quarters.isEmpty ? model.data.buckets : quarters
        PeriodChips(
            buckets: shown,
            selected: model.selectedLit,
            current: model.data.currentLit,
            dim: { lit in !model.courses.contains { !($0.grade(lit)?.isEmpty ?? true) } }
        ) { lit in
            let choice: String? = lit == model.data.currentLit ? nil : lit
            withAnimation(.snappy(duration: 0.25)) {
                model.updatePrefs { $0.selectedLit = choice }
            }
        }
        .onAppear {
            // A report-card or progress column picked before 1.2 isn't on this row.
            if let picked = model.prefs.selectedLit, !shown.contains(where: { $0.lit == picked }) {
                model.updatePrefs { $0.selectedLit = nil }
            }
        }
    }
}

/// A row of period chips, each a comfortable target. The current period has a dot.
struct PeriodChips: View {
    @Environment(AppModel.self) private var model
    let buckets: [TermBucket]
    let selected: String?
    var current: String?
    var dim: (String) -> Bool = { _ in false }
    let choose: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(buckets) { bucket in
                        let isOn = bucket.lit == selected
                        Button {
                            choose(bucket.lit)
                        } label: {
                            HStack(spacing: 5) {
                                if bucket.lit == current {
                                    Circle().fill(isOn ? Color.white : model.theme.color).frame(width: 5, height: 5)
                                }
                                Text(buckets.count <= 6 ? bucket.displayName : bucket.lit)
                                    .font(.subheadline.weight(isOn ? .semibold : .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isOn ? Color.white : (dim(bucket.lit) ? Color.secondary : Color.primary))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 38)
                            .background {
                                if isOn {
                                    Capsule().fill(model.theme.color)
                                        .shadow(color: model.theme.color.opacity(0.35), radius: 6, y: 3)
                                } else {
                                    Capsule().fill(.clear).surface(cornerRadius: 19, hoverable: true)
                                }
                            }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(BubbleButtonStyle())
                        .id(bucket.lit)
                        .help(bucket.displayName)
                        .accessibilityLabel(bucket.displayName + (bucket.lit == current ? ", current" : ""))
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .sensoryFeedback(.selection, trigger: selected)
            .onAppear { if let selected { proxy.scrollTo(selected, anchor: .center) } }
        }
    }
}

struct GradesSummary: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let lit: String

    var body: some View {
        let courses = model.courses(in: lit)
        let numbers = courses.compactMap { model.percent($0, lit) }
        let average = numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)
        let gpa = GPA.compute(GPA.currentEntries(data: model.data, lit: lit, settings: model.prefs.gpa))
        let missing = lit == model.data.currentLit ? model.missingAssignments.count : 0

        // One quiet band of three figures, not three big-number tiles.
        let roomy = sizeClass != .compact
        Card {
            HStack(alignment: .top, spacing: 0) {
                figure(average.map { Fmt.percent($0) } ?? "—", "Average", average.map { GradeColor.color(percent: $0) } ?? .primary,
                       caption: roomy ? (model.data.bucket(lit)?.displayName ?? lit) : nil)
                separator
                figure(Fmt.gpa(gpa.weighted), "GPA", .primary,
                       caption: roomy ? "Unweighted " + Fmt.gpa(gpa.unweighted) : nil)
                separator
                figure("\(missing)", "Missing", missing == 0 ? .secondary : Palette.bad,
                       caption: roomy ? (missing == 0 ? "All turned in" : "Needs attention") : nil)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1)
            .padding(.horizontal, 16)
    }

    private func figure(_ value: String, _ label: String, _ tint: Color, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Text(value)
                .font(.display(sizeClass == .compact ? 19 : 22, relativeTo: .title2).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            if let caption { Text(caption).font(.footnote).foregroundStyle(.tertiary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ClassRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.windowMetrics) private var metrics
    let course: Course
    let lit: String
    @State private var hovering = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        #if os(iOS)
        if sizeClass == .compact {
            PhoneClassRow(course: course, lit: lit)
        } else {
            wideRow
        }
        #else
        wideRow
        #endif
    }

    @ViewBuilder private var wideRow: some View {
        let percent = model.percent(course, lit)
        let missing = model.detail(course.id, lit)?.assignments.filter { $0.missing }.count ?? 0
        let level = model.prefs.gpa.level(for: course.name)
        let maxPriorChips = metrics.width < 700 ? 0 : (metrics.width >= 1000 ? 4 : 2)
        let historyChips = priorGrades(for: course, excluding: lit, limit: maxPriorChips)
        let meta = [
            course.period.isEmpty ? nil : "Period \(course.period)",
            course.teacher.isEmpty ? nil : Str.titleCase(course.teacher),
            level == .regular ? nil : level.shortTitle,
        ].compactMap { $0 }.joined(separator: " · ")

        HStack(spacing: 14) {
            ClassBadge(courseID: course.id, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(Str.titleCase(course.name))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !meta.isEmpty {
                        Text(meta).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if missing > 0 {
                        Text("\(missing) missing").font(.subheadline.weight(.medium)).foregroundStyle(Palette.bad)
                    }
                }
            }
            Spacer(minLength: 8)

            ForEach(historyChips) { chip in
                VStack(alignment: .trailing, spacing: 0) {
                    Text(chip.lit).font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
                    Text(chip.text).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(minWidth: 34, alignment: .trailing)
                .help("\(chip.lit): \(chip.text)")
            }

            if let delta = model.changeSinceSeen(course, lit) {
                DeltaLabel(delta: delta)
            }
            GradeBubble(text: model.gradeText(course, lit), percent: percent)
                .scaleEffect(hovering ? 1.05 : 1)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(hovering ? .secondary : .tertiary)
                .offset(x: hovering ? 3 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, model.settings.compactRows ? 7 : 11)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
    }

    private struct PriorChip: Identifiable {
        var id: String { lit }
        var lit: String
        var text: String
        var percent: Double?
    }

    private func priorGrades(for course: Course, excluding activeLit: String, limit: Int) -> [PriorChip] {
        guard limit > 0 else { return [] }
        // Earlier columns only, in Skyward's order.
        let order = model.data.buckets.map(\.lit)
        guard let activeIndex = order.firstIndex(of: activeLit) else { return [] }
        let earlier = Set(order.prefix(activeIndex))
        let nonEmpty = course.grades.filter { !$0.isEmpty && earlier.contains($0.lit) }
        let slice: [PostedGrade] = Array(nonEmpty.suffix(limit))
        return slice.map { cell in
            PriorChip(lit: cell.lit, text: cell.number.map { Fmt.percent($0) } ?? cell.text, percent: cell.number)
        }
    }
}

/// Drag to reorder; switch a class off to hide it everywhere.
struct ClassOrderEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(model.allCoursesOrdered) { course in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Str.titleCase(course.name))
                            Text(course.period.isEmpty ? Str.titleCase(course.teacher) : "Period \(course.period) · \(Str.titleCase(course.teacher))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Show", isOn: Binding(
                            get: { !model.prefs.hiddenCourses.contains(course.id) },
                            set: { show in
                                model.updatePrefs { prefs in
                                    if show { prefs.hiddenCourses.remove(course.id) } else { prefs.hiddenCourses.insert(course.id) }
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                }
                .onMove { from, to in
                    var ids = model.allCoursesOrdered.map { $0.id }
                    ids.move(fromOffsets: from, toOffset: to)
                    model.updatePrefs { $0.courseOrder = ids }
                }
            } footer: {
                Text("Drag to reorder. Hidden classes are left out of Grades, Home and GPA until you show them again.")
            }
            Section {
                Button("Reset to Skyward's Order") {
                    model.updatePrefs { prefs in
                        prefs.courseOrder = []
                        prefs.hiddenCourses = []
                    }
                }
            }
        }
        .navigationTitle("Classes")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}
