import SwiftUI

/// The overview on every platform: what needs you, your classes at a glance, and
/// what just came in. Average and GPA appear once, as ways into Grades. The full
/// week of due work lives in Planner.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false

    var body: some View {
        Screen(title: "Home", spacing: 22) {
            HomeHeader()
                .staggered(0)
            SyncStatusView { model.requestReauth() }
            #if os(iOS)
            UpdateBanner()
            #endif
            if model.data.courses.isEmpty {
                Card {
                    EmptyState(
                        symbol: model.syncState.isSyncing ? "arrow.triangle.2.circlepath" : "tray",
                        title: model.syncState.isSyncing ? "Getting your grades" : "No classes yet",
                        message: model.syncState.isSyncing ? "This takes a few seconds the first time." : "Refresh to load your classes."
                    )
                }
            } else {
                ForEach(Array(HomeSection.rows(sectionsWithContent).enumerated()), id: \.offset) { index, row in
                    HomeRow(sections: row).staggered(index + 1)
                }
                #if os(iOS)
                // On iPhone Nimbus has his own little patch of ground at the end of Home.
                if model.settings.showMascot {
                    MascotLane(freeHeight: 150, perches: NimbusPerches())
                        .frame(height: 150)
                        .padding(.horizontal, -16)
                }
                #endif
            }
        }
        .refreshable { await model.refresh() }
        .sheet(isPresented: $editing) {
            NavigationStack { HomeEditor() }
            #if os(macOS)
                .frame(minWidth: 380, minHeight: 420)
            #endif
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit Home", systemImage: "slider.horizontal.3") { editing = true }
            }
        }
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = true
                } label: {
                    Label("Edit Home", systemImage: "slider.horizontal.3")
                }
                .help("Reorder or hide Home's sections")
            }
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

/// One row of Home: a wide section alone, or a run of sections sharing columns.
extension HomeView {
    /// Visible sections that have something to show, so an empty one never leaves
    /// a blank column beside its neighbour.
    var sectionsWithContent: [HomeSection] {
        model.homeSectionsVisible.filter { section in
            switch section {
            case .recent: return model.recentChanges.contains { $0.kind == .newGrade || $0.kind == .updatedGrade }
            default: return true
            }
        }
    }
}

private struct HomeRow: View {
    @Environment(\.windowMetrics) private var metrics
    let sections: [HomeSection]

    var body: some View {
        if sections.count == 1 || metrics.columns <= 1 {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(sections) { HomeSectionView(section: $0) }
            }
        } else {
            let columns = min(metrics.columns, sections.count)
            HStack(alignment: .top, spacing: 22) {
                ForEach(0..<columns, id: \.self) { c in
                    VStack(alignment: .leading, spacing: 22) {
                        // Fill columns left to right; extra sections stack in the last one.
                        ForEach(Array(sections.enumerated()).filter { min($0.offset, columns - 1) == c }, id: \.element) { _, section in
                            HomeSectionView(section: section)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
    }
}

private struct HomeSectionView: View {
    let section: HomeSection

    var body: some View {
        switch section {
        case .gradesStrip: GradesStrip()
        case .bell: BellBannerCard()
        case .needsYou: NeedsYouSection()
        case .recent: RecentSection()
        }
    }
}

/// Every class average in one row, in each class's color. Tap one to open it.
private struct GradesStrip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.windowMetrics) private var metrics
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if let lit = model.selectedLit {
            let courses = model.courses(in: lit).filter { !model.gradeText($0, lit).isEmpty }
            if sizeClass == .compact {
                // On a phone, one row you swipe through, so Home doesn't open on
                // four rows of chips; the fade at the edge says there's more.
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(courses) { course in
                            NavigationLink(value: CourseRoute(courseID: course.id)) {
                                GlanceChip(course: course, lit: lit).frame(width: 140)
                            }
                            .buttonStyle(BubbleButtonStyle())
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 2)
                    .padding(.trailing, 24)
                }
                .scrollIndicators(.never)
                .scrollTargetBehavior(.viewAligned)
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                }
            } else {
            // Every class shows, in balanced rows (8 classes: 4 + 4, never 7 + 1).
            let available = min(metrics.width - metrics.horizontalPadding * 2, metrics.contentMaxWidth)
            let fit = max(1, Int((available + 10) / 160))
            let rows = max(1, Int(ceil(Double(courses.count) / Double(fit))))
            let columns = max(1, Int(ceil(Double(courses.count) / Double(rows))))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                ForEach(courses) { course in
                    NavigationLink(value: CourseRoute(courseID: course.id)) {
                        GlanceChip(course: course, lit: lit)
                    }
                    .buttonStyle(BubbleButtonStyle())
                }
            }
            }
        }
    }
}

private struct GlanceChip: View {
    @Environment(AppModel.self) private var model
    let course: Course
    let lit: String

    var body: some View {
        let percent = model.percent(course, lit)
        let color = model.classColor(course.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(Str.titleCase(course.name))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(model.gradeText(course, lit))
                .font(.display(20, relativeTo: .title3).monospacedDigit())
                .foregroundStyle(percent.map { GradeColor.color(percent: $0) } ?? .primary)
                .contentTransition(.numericText())
            // How far through the A range (or whichever band) this class sits.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(color.gradient)
                        .frame(width: geo.size.width * CGFloat(max(0.04, min(1, ((percent ?? 0) - 60) / 40))))
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bubble()
    }
}

/// Reorder and hide Home's sections.
struct HomeEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var order: [HomeSection] = []

    var body: some View {
        List {
            Section {
                ForEach(order) { section in
                    HStack(spacing: 12) {
                        Image(systemName: section.symbol)
                            .foregroundStyle(model.theme.color)
                            .frame(width: 24)
                        Text(section.title)
                        Spacer()
                        Toggle(section.title, isOn: Binding(
                            get: { !(model.settings.homeHidden ?? []).contains(section.rawValue) },
                            set: { model.setHomeSection(section, visible: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(.vertical, 4)
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    model.setHomeOrder(order)
                }
            } footer: {
                Text("Drag to reorder. Switch a section off to hide it.")
            }
        }
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        .navigationTitle("Edit Home")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .cancellationAction) {
                Button("Reset") {
                    order = HomeSection.defaultOrder
                    model.setHomeOrder(order)
                    model.updateSettings { $0.homeHidden = nil }
                }
            }
        }
        .onAppear { order = model.homeSectionsAll }
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

        let figures = HStack(alignment: .bottom, spacing: 6) {
            if let average {
                FigureButton(number: average, format: { Fmt.percent($0) }, label: (lit ?? "") + " average", tint: GradeColor.color(percent: average)) {
                    model.gradesTab = .classes
                    model.section = .grades
                }
            }
            if average != nil, gpa?.weighted != nil {
                Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 40).padding(.bottom, 8)
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
                    Text(model.now().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(model.active?.firstName ?? "Home")
                        .font(.display(34, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 16)
                figures.fixedSize()
            }
            .padding(.top, 4)
        }
    }

    private var dateLine: String {
        model.now().formatted(.dateTime.weekday(.wide).month(.wide).day()) + " · updated " + Fmt.ago(model.data.lastSync, now: model.now())
    }
}

/// A figure set into the header, not boxed in a tile, that is also the way to
/// the screen it summarises.
private struct FigureButton: View {
    let number: Double
    let format: (Double) -> String
    let label: String
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                RollingNumber(value: number, format: format)
                    .font(.display(27).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(tint)
                HStack(spacing: 4) {
                    Text(label).font(.subheadline).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                        .offset(x: hovering ? 2 : 0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel("\(label) \(format(number))")
    }
}

// MARK: - Needs you

/// Something on the Needs You list.
private enum NeedItem: Identifiable {
    case missing(AppModel.DatedAssignment)
    case due(AppModel.DueItem)
    case below(course: Course, percent: Double, goal: Double)

    var id: String {
        switch self {
        case .missing(let item): return "m|" + item.id
        case .due(let item): return "d|" + item.id
        case .below(let course, _, _): return "b|" + course.id
        }
    }
}

/// Missing work, what is due today or tomorrow, and classes under their goal.
/// The first three show; the rest are one tap away. With nothing to show it says so.
private struct NeedsYouSection: View {
    @Environment(AppModel.self) private var model
    @State private var completed = 0

    var body: some View {
        let items = needs
        let cutoff = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: model.now())) ?? model.now()

        Group {
            if items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Needs You")
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
                }
            } else {
                CollapsibleList("Needs You", items: items, preview: 3, key: "home.needs") { item in
                    row(item)
                }
            }
        }
        .sensoryFeedback(.success, trigger: completed)
    }

    @ViewBuilder
    private func row(_ item: NeedItem) -> some View {
        switch item {
        case .missing(let entry):
            NavigationLink(value: CourseRoute(courseID: entry.course.id)) {
                NeedRow(
                    symbol: "exclamationmark.circle.fill", tint: Palette.bad,
                    title: entry.assignment.name,
                    subtitle: Str.titleCase(entry.course.name),
                    trailing: "Missing", trailingTint: Palette.bad
                )
                .bubble()
            }
            .buttonStyle(BubbleButtonStyle())
        case .due(let due):
            DueNeedRow(item: due) {
                withAnimation(.snappy) { model.toggleDue(due.id) }
                completed += 1
            }
        case .below(let course, let percent, let goal):
            NavigationLink(value: CourseRoute(courseID: course.id)) {
                NeedRow(
                    symbol: "arrow.down.right.circle.fill", tint: Palette.warn,
                    title: Str.titleCase(course.name),
                    subtitle: "Under your goal of \(Fmt.percent(goal))",
                    trailing: Fmt.percent(percent), trailingTint: Palette.warn
                )
                .bubble()
            }
            .buttonStyle(BubbleButtonStyle())
        }
    }

    /// Missing first, then today and tomorrow, then classes under their goal.
    private var needs: [NeedItem] {
        let missing = model.missingAssignments
        let missingTitles = Set(missing.map { $0.assignment.name })
        let cutoff = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: model.now())) ?? model.now()
        let due = model.dueItems.filter { !$0.done && $0.due < cutoff && !missingTitles.contains($0.title) }
        var out: [NeedItem] = missing.map { .missing($0) } + due.map { .due($0) }
        if let lit = model.data.currentLit {
            for course in model.courses(in: lit) {
                if let goal = model.goal(for: course.id), let percent = model.percent(course, lit), percent < goal {
                    out.append(.below(course: course, percent: percent, goal: goal))
                }
            }
        }
        return out
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

// MARK: - Recent

/// Grades that came in recently: three show, the rest are one tap away.
private struct RecentSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let changes = Array(model.recentChanges.filter { $0.kind == .newGrade || $0.kind == .updatedGrade }.prefix(25))
        if !changes.isEmpty {
            CollapsibleList("Recent Grades", items: changes, preview: 3, key: "home.recent") { change in
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
                    .bubble()
                }
                .buttonStyle(BubbleButtonStyle())
            }
        }
    }
}
