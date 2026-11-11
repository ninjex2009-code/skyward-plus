import Charts
import SwiftUI

struct ClassDetailView: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case assignments = "Assignments"
        case whatIf = "What-If"
        case analysis = "Analysis"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.windowMetrics) private var metrics
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPhone: the navigation bar shows the class name, and the header stacks.
    private var compact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }
    let courseID: String

    @State private var pane: Pane = .assignments
    @State private var categoryFilter: String = "All"
    @State private var showAllAssignments = false
    @State private var selectedAssignment: Assignment?
    @State private var addingMock = false

    @State private var neededTarget: Double = 90
    @State private var neededPossible: Double = 100
    @State private var neededCategory: String = ""
    @State private var examWeight: Double = 20
    @State private var examTarget: Double = 90

    var body: some View {
        let course = model.course(courseID)
        let lit = model.selectedLit ?? model.data.currentLit ?? course?.grades.last(where: { !$0.isEmpty })?.lit ?? ""
        let detail = model.detail(courseID, lit)
        let whatIf = model.whatIf(courseID, lit)
        let result = model.result(courseID, lit, includeWhatIf: true)
        let baseResult = model.result(courseID, lit, includeWhatIf: false)

        Screen(title: course.map { Str.titleCase($0.name) } ?? "Class", maxWidth: 1000) {
            if let course {
                headerCard(course: course, lit: lit, detail: detail, result: result, baseResult: baseResult, whatIf: whatIf)
                    .staggered(1)

                Picker("View", selection: $pane.animation(.snappy)) {
                    ForEach(Pane.allCases) { p in Text(p.rawValue).tag(p) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                .frame(maxWidth: .infinity)
                .staggered(2)

                if model.isLoadingDetail(courseID, lit), detail == nil {
                    Card {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading assignments for \(lit)…").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                    }
                } else if let err = model.detailError(courseID, lit), detail == nil {
                    Card {
                        VStack(spacing: 14) {
                            EmptyState(symbol: "exclamationmark.triangle", title: "Could not load assignments", message: err)
                            HStack(spacing: 12) {
                                Button {
                                    Task { await model.ensureDetail(courseID, lit, force: true) }
                                } label: {
                                    Label("Try Again", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.borderedProminent)

                                if let profile = model.active, model.isQmlativ(profile) {
                                    Button {
                                        model.requestReauth(profile)
                                    } label: {
                                        Label("Sign In…", systemImage: "person.badge.key")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.bottom, 6)
                        }
                    }
                } else if let detail {
                    switch pane {
                    case .assignments:
                        categoriesCard(detail: detail, result: result)
                            .staggered(3)
                        assignmentsSection(detail: detail, lit: lit, whatIf: whatIf, allowInlineEdit: false)
                            .staggered(4)
                    case .whatIf:
                        whatIfBanner(lit: lit, whatIf: whatIf, result: result, baseResult: baseResult)
                            .staggered(3)
                        categoriesCard(detail: detail, result: result)
                            .staggered(4)
                        assignmentsSection(detail: detail, lit: lit, whatIf: whatIf, allowInlineEdit: true)
                            .staggered(5)
                    case .analysis:
                        analysisSection(course: course, detail: detail, lit: lit, result: result, whatIf: whatIf)
                            .staggered(3)
                    }
                } else {
                    Card {
                        EmptyState(
                            symbol: "doc.text.magnifyingglass",
                            title: "No assignment list for \(lit.isEmpty ? "this class" : lit)",
                            message: "Skyward does not have an assignment breakdown for this column."
                        )
                    }
                }
            }
        }
        .task(id: "\(courseID)|\(lit)") {
            guard !lit.isEmpty else { return }
            await model.ensureDetail(courseID, lit)
            if neededCategory.isEmpty, let first = model.detail(courseID, lit)?.categories.first?.name {
                neededCategory = first
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Everything secondary for this class in one menu.
                Menu {
                    Button {
                        Task { await model.ensureDetail(courseID, lit, force: true) }
                    } label: {
                        Label("Refresh Assignments", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isLoadingDetail(courseID, lit))
                    Menu {
                        ForEach([80.0, 85, 89.5, 90, 93, 95, 97], id: \.self) { value in
                            Button(Fmt.percent(value)) { withAnimation(.snappy) { model.setGoal(value, for: courseID) } }
                        }
                        if model.goal(for: courseID) != nil {
                            Divider()
                            Button("Remove Goal", role: .destructive) { withAnimation(.snappy) { model.setGoal(nil, for: courseID) } }
                        }
                    } label: {
                        Label(model.goal(for: courseID) == nil ? "Set a Goal" : "Change Goal", systemImage: "target")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
            }
        }
        .sheet(item: $selectedAssignment) { assignment in
            if let detail {
                NavigationStack {
                    AssignmentInspectorSheet(courseID: courseID, lit: lit, detail: detail, assignment: assignment)
                }
                #if os(macOS)
                .frame(minWidth: 460, minHeight: 500)
                #endif
            }
        }
        .sheet(isPresented: $addingMock) {
            if let detail {
                NavigationStack {
                    AddMockAssignmentSheet(courseID: courseID, lit: lit, detail: detail)
                }
                #if os(macOS)
                .frame(minWidth: 420, minHeight: 380)
                #endif
            }
        }
    }

    // MARK: Header

    private func headerCard(
        course: Course,
        lit: String,
        detail: GradeDetail?,
        result: CourseResult?,
        baseResult: CourseResult?,
        whatIf: WhatIf
    ) -> some View {
        let displayPercent = (!whatIf.isEmpty ? result?.percent : nil) ?? model.percent(course, lit) ?? result?.percent
        let displayText = displayPercent.map { Fmt.percent($0, digits: 2) } ?? (course.grade(lit)?.text ?? "—")
        let whatIfDelta: Double? = {
            guard !whatIf.isEmpty, let w = result?.percent, let b = baseResult?.percent ?? detail?.percent else { return nil }
            return w - b
        }()
        let level = model.prefs.gpa.level(for: course.name)
        let meta = [
            course.period.isEmpty ? nil : "Period \(course.period)",
            course.teacher.isEmpty ? nil : Str.titleCase(course.teacher),
            course.timeRange.isEmpty ? nil : course.timeRange,
            level == .regular ? nil : level.shortTitle,
        ].compactMap { $0 }.joined(separator: " · ")
        let postedCells = course.grades.filter { !$0.isEmpty }
        let tint = displayPercent.map { GradeColor.color(percent: $0) } ?? .secondary

        let grade = VStack(alignment: compact ? .leading : .trailing, spacing: 2) {
            Text(displayText)
                .font(.system(size: 46, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .animation(.snappy, value: displayText)
            HStack(spacing: 6) {
                if let whatIfDelta {
                    Text("What-if").font(.subheadline.weight(.medium)).foregroundStyle(Palette.warn)
                    DeltaLabel(delta: whatIfDelta)
                } else {
                    if let delta = model.changeSinceSeen(course, lit) { DeltaLabel(delta: delta) }
                    Text(displayPercent.map { GradeColor.letter(for: $0) } ?? "").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
            }
        }
        let facts = VStack(alignment: .leading, spacing: 6) {
            if !meta.isEmpty {
                Text(meta).font(.callout).foregroundStyle(.secondary)
            }
            if let result {
                Text(factsLine(result: result, detail: detail))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }

        return VStack(alignment: .leading, spacing: 16) {
            if compact {
                // On a phone the grade leads and the details get the full width under it,
                // instead of being squeezed into a narrow column beside it.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(displayText)
                            .font(.system(size: 46, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(tint)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: displayText)
                        if let whatIfDelta {
                            Text("What-if").font(.subheadline.weight(.medium)).foregroundStyle(Palette.warn)
                            DeltaLabel(delta: whatIfDelta)
                        } else {
                            Text(displayPercent.map { GradeColor.letter(for: $0) } ?? "")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if let delta = model.changeSinceSeen(course, lit) { DeltaLabel(delta: delta) }
                        }
                    }
                    facts
                }
            } else {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Str.titleCase(course.name))
                            .font(.system(.largeTitle, design: .rounded).bold())
                            .lineLimit(2)
                        facts
                    }
                    Spacer(minLength: 12)
                    grade
                }
            }

            if postedCells.count > 1 {
                HStack(spacing: 2) {
                    ForEach(postedCells, id: \.lit) { cell in
                        let isCurrent = cell.lit == lit
                        Button {
                            withAnimation(.snappy) {
                                model.updatePrefs { $0.selectedLit = cell.lit == model.data.currentLit ? nil : cell.lit }
                            }
                        } label: {
                            VStack(spacing: 1) {
                                Text(cell.lit).font(.caption.weight(.medium)).foregroundStyle(isCurrent ? .primary : .secondary)
                                Text(cell.number.map { Fmt.percent($0) } ?? cell.text)
                                    .font(.callout.weight(isCurrent ? .semibold : .regular).monospacedDigit())
                                    .foregroundStyle(isCurrent ? GradeColor.color(percent: cell.number) : .secondary)
                            }
                            .frame(minWidth: 44)
                            .padding(.vertical, 6)
                            .background(isCurrent ? Palette.inset : .clear, in: .rect(cornerRadius: 8))
                            .contentShape(.rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .help(model.data.bucket(cell.lit)?.displayName ?? cell.lit)
                    }
                }
            }

            goalCard(course: course, lit: lit, detail: detail, current: displayPercent, whatIf: whatIf)
        }
    }

    private func factsLine(result: CourseResult, detail: GradeDetail?) -> String {
        var parts = ["\(Fmt.points(result.earned)) of \(Fmt.points(result.possible)) points"]
        parts.append("\(result.gradedCount) graded")
        parts.append(result.missingCount == 0 ? "nothing missing" : "\(result.missingCount) missing")
        if let adj = detail?.adjustment, adj != 0 { parts.append("adjusted \(Fmt.signed(adj, digits: 2))") }
        return parts.joined(separator: " · ")
    }

    // MARK: Goal

    @ViewBuilder
    private func goalCard(course: Course, lit: String, detail: GradeDetail?, current: Double?, whatIf: WhatIf) -> some View {
        // No goal yet: nothing here. Setting one is in the "…" menu.
        if let goal = model.goal(for: courseID) {
            goalCardBody(goal: goal, detail: detail, current: current, whatIf: whatIf)
        }
    }

    private func goalCardBody(goal: Double, detail: GradeDetail?, current: Double?, whatIf: WhatIf) -> some View {
        Card(padding: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Goal \(Fmt.percent(goal))").font(.headline)
                    Text(goalMessage(goal: goal, current: current, detail: detail, whatIf: whatIf))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            if let current {
                GoalBar(current: current, goal: goal)
            }
        }
    }

    private func goalMessage(goal: Double, current: Double?, detail: GradeDetail?, whatIf: WhatIf) -> String {
        guard let current else { return "No grade yet in this marking period." }
        if current >= goal {
            return "You're \(Fmt.percent(current - goal)) points above it."
        }
        guard let detail, let category = detail.categories.max(by: { ($0.weight ?? 0) < ($1.weight ?? 0) })?.name else {
            return "\(Fmt.percent(goal - current)) points to go."
        }
        switch GradeMath.needed(target: goal, possible: 100, category: category, in: detail, mode: model.gradingMode(courseID), whatIf: whatIf) {
        case .score(let earned, _):
            return "\(Fmt.percent(goal - current)) points to go. A \(Fmt.points(earned)) on the next 100-point \(category.lowercased()) assignment gets you there."
        case .impossible(let best):
            return "Even a 100 on the next \(category.lowercased()) assignment reaches \(Fmt.percent(best)). It will take a few."
        case .secured, .unknown:
            return "\(Fmt.percent(goal - current)) points to go."
        }
    }

    // MARK: Categories

    @ViewBuilder
    private func categoriesCard(detail: GradeDetail, result: CourseResult?) -> some View {
        let categories = result?.categories ?? []
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Categories", subtitle: result?.mode == .weighted ? "Weighted" : "Total points")
                Card {
                    VStack(spacing: 14) {
                        ForEach(categories) { cat in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(cat.name).font(.body.weight(.medium))
                                    if let weight = cat.weight {
                                        Text("\(Fmt.percent(weight, digits: 0))% of grade").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(Fmt.points(cat.earned))/\(Fmt.points(cat.possible))")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(cat.percent.map { Fmt.percent($0) } ?? "—")
                                        .font(.body.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(GradeColor.color(percent: cat.percent))
                                        .frame(minWidth: 44, alignment: .trailing)
                                        .contentTransition(.numericText())
                                }
                                ProgressBar(value: (cat.percent ?? 0) / 100.0, tint: GradeColor.color(percent: cat.percent), height: 4)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: What-if banner

    private func whatIfBanner(lit: String, whatIf: WhatIf, result: CourseResult?, baseResult: CourseResult?) -> some View {
        Card(tint: whatIf.isEmpty ? nil : Palette.warn) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(whatIf.isEmpty ? "Try different scores" : "What-if is on").font(.headline)
                    Text("Click an assignment to change its score, untick it to leave it out, or add one that hasn't happened yet. Nothing changes in Skyward.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if !whatIf.isEmpty {
                    Button("Reset") {
                        withAnimation(.snappy) { model.setWhatIf(WhatIf(), courseID, lit) }
                    }
                }
                Button("Add Assignment") { addingMock = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Assignments list

    private func assignmentsSection(detail: GradeDetail, lit: String, whatIf: WhatIf, allowInlineEdit: Bool) -> some View {
        let applied = GradeMath.applied(detail, whatIf: whatIf)
        let catNames = ["All"] + detail.categories.map { $0.name }
        let filtered = categoryFilter == "All" ? applied : applied.filter { $0.category == categoryFilter }

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Assignments", subtitle: filtered.count == 1 ? "1 assignment" : "\(filtered.count) assignments") {
                if allowInlineEdit {
                    Button("Add Assignment", systemImage: "plus") { addingMock = true }
                        .buttonStyle(.borderless)
                }
            }

            if catNames.count > 2 {
                Picker("Category", selection: $categoryFilter.animation(.snappy)) {
                    ForEach(catNames, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if filtered.isEmpty {
                Card {
                    EmptyState(symbol: "tray", title: "No assignments", message: "No assignments in this category.")
                }
            } else {
                // Long classes show the latest ten; the rest are one tap away.
                let shown = showAllAssignments ? filtered : Array(filtered.prefix(10))
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, assignment in
                            HoverRow {
                                assignmentRow(
                                    assignment: assignment,
                                    detail: detail,
                                    lit: lit,
                                    whatIf: whatIf,
                                    allowInlineEdit: allowInlineEdit
                                )
                            }
                            .rowDivider(index < shown.count - 1)
                        }
                    }
                }
                if filtered.count > 10 {
                    ShowAllButton(showAll: $showAllAssignments, total: filtered.count)
                }
            }
        }
    }

    private func assignmentRow(
        assignment: Assignment,
        detail: GradeDetail,
        lit: String,
        whatIf: WhatIf,
        allowInlineEdit: Bool
    ) -> some View {
        let edit = whatIf.edits[assignment.id]
        let isExcluded = edit?.excluded == true
        let isMock = whatIf.added.contains { $0.id == assignment.id }
        let isEdited = edit != nil || isMock
        let impact = GradeMath.impact(of: assignment.id, in: detail, mode: model.gradingMode(courseID), whatIf: whatIf)
        let pct = assignment.scorePercent
        let bubbleText: String = {
            if let earned = assignment.earned, let possible = assignment.possible {
                return "\(Fmt.points(earned))/\(Fmt.points(possible))"
            }
            return assignment.gradeText
        }()

        return Button {
            selectedAssignment = assignment
        } label: {
            HStack(spacing: 12) {
                if allowInlineEdit {
                    Button {
                        withAnimation(Motion.snappy) {
                            var updated = whatIf
                            var e = updated.edits[assignment.id] ?? ScoreEdit(earned: assignment.earned, possible: assignment.possible)
                            e.excluded.toggle()
                            updated.edits[assignment.id] = e
                            model.setWhatIf(updated, courseID, lit)
                        }
                    } label: {
                        Image(systemName: isExcluded ? "circle" : "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(isExcluded ? Color.secondary : model.theme.color)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .help(isExcluded ? "Include in grade" : "Exclude from grade")
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(assignment.name)
                            .font(.body.weight(.medium))
                            .strikethrough(isExcluded || assignment.dropped || assignment.noCount)
                            .foregroundStyle(isExcluded ? .secondary : .primary)
                            .lineLimit(2)
                        if isMock { Text("Added").font(.subheadline.weight(.medium)).foregroundStyle(Palette.warn) }
                        else if isEdited { Text("Changed").font(.subheadline.weight(.medium)).foregroundStyle(Palette.warn) }
                    }
                    HStack(spacing: 6) {
                        Text([assignment.category, assignment.due.map { Fmt.shortDay($0) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if assignment.missing { Text("Missing").font(.subheadline.weight(.medium)).foregroundStyle(Palette.bad) }
                        if assignment.noCount { Text("Doesn't count").font(.subheadline).foregroundStyle(.secondary) }
                        if assignment.dropped { Text("Dropped").font(.subheadline).foregroundStyle(.secondary) }
                        if assignment.absent { Text("Absent").font(.subheadline).foregroundStyle(Palette.warn) }
                    }
                }
                Spacer(minLength: 8)
                if let impact, abs(impact) >= 0.05 {
                    Text(Fmt.signed(impact, digits: 2))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("How much this assignment moves your average")
                }
                VStack(alignment: .trailing, spacing: 1) {
                    Text(pct.map { Fmt.percent($0) } ?? (assignment.gradeText.isEmpty ? "—" : assignment.gradeText))
                        .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(pct == nil ? Color.secondary : GradeColor.color(percent: pct))
                        .contentTransition(.numericText())
                    if assignment.earned != nil, assignment.possible != nil {
                        Text(bubbleText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    } else if assignment.due.map({ $0 >= Calendar.current.startOfDay(for: model.now()) }) == true {
                        Text("Not graded").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 56, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, model.settings.compactRows ? 8 : 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Analysis

    private func analysisSection(
        course: Course,
        detail: GradeDetail,
        lit: String,
        result: CourseResult?,
        whatIf: WhatIf
    ) -> some View {
        let mode = model.gradingMode(courseID)
        let needed = GradeMath.needed(
            target: neededTarget,
            possible: neededPossible,
            category: neededCategory.isEmpty ? (detail.categories.first?.name ?? "Major") : neededCategory,
            in: detail,
            mode: mode,
            whatIf: whatIf
        )
        let currentAvg = result?.percent ?? model.percent(course, lit) ?? 90
        let examScore = GradeMath.finalExamNeeded(current: currentAvg, examWeight: examWeight, target: examTarget)
        let style = SubjectStyle(color: model.theme.color, symbol: "", label: "")

        return VStack(alignment: .leading, spacing: 16) {
            trendCard(course: course, detail: detail, lit: lit, tint: model.theme.color)

            Card {
                Text("Score needed on the next assignment").font(.headline)
                Text("Find out what you need to score on an upcoming test or assignment to hit your goal.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target Average (%)").font(.caption).foregroundStyle(.secondary)
                        TextField("90", value: $neededTarget, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Points Possible").font(.caption).foregroundStyle(.secondary)
                        TextField("100", value: $neededPossible, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    if !detail.categories.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Category").font(.caption).foregroundStyle(.secondary)
                            Picker("Category", selection: $neededCategory) {
                                ForEach(detail.categories) { cat in
                                    Text(cat.name).tag(cat.name)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }

                Group {
                    switch needed {
                    case .unknown:
                        Text("Enter a positive point value to calculate.").font(.subheadline).foregroundStyle(.secondary)
                    case .secured:
                        Label("You already have \(Fmt.percent(neededTarget))% secured, even with 0 / \(Fmt.points(neededPossible)).", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.good)
                    case .impossible(let best):
                        Label("Full marks (\(Fmt.points(neededPossible))/\(Fmt.points(neededPossible))) reaches \(Fmt.percent(best))%.", systemImage: "info.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.warn)
                    case .score(let earned, let pct):
                        Label("You need at least \(Fmt.points(earned)) / \(Fmt.points(neededPossible)) (\(Fmt.percent(pct))%).", systemImage: "target")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(style.color)
                    }
                }
                .padding(.top, 4)
            }

            Card {
                Text("Final exam").font(.headline)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Exam Weight (%)").font(.caption).foregroundStyle(.secondary)
                        TextField("20", value: $examWeight, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target Semester Grade (%)").font(.caption).foregroundStyle(.secondary)
                        TextField("90", value: $examTarget, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                Text("With your current \(Fmt.percent(currentAvg))% average, you need **\(Fmt.percent(examScore))%** on the final exam to finish with \(Fmt.percent(examTarget))%.")
                    .font(.subheadline)
            }

            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("How this class is averaged").font(.headline)
                        Text("Matches Skyward automatically, or override how this class is calculated.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Formula", selection: Binding(
                        get: { model.gradingMode(courseID) },
                        set: { newMode in model.updatePrefs { $0.gradingModes[courseID] = newMode } }
                    )) {
                        Text("Auto").tag(GradingMode.auto)
                        Text("Weighted").tag(GradingMode.weighted)
                        Text("Total Points").tag(GradingMode.points)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private func trendCard(course: Course, detail: GradeDetail, lit: String, tint: Color) -> some View {
        let points = buildTrendPoints(detail: detail)
        if points.count >= 2 {
            Card {
                Text("Average over time").font(.headline)
                Chart(points) { pt in
                    LineMark(
                        x: .value("Date", pt.date),
                        y: .value("Average", pt.average)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(tint)

                    AreaMark(
                        x: .value("Date", pt.date),
                        yStart: .value("Min", max(50, (points.map { $0.average }.min() ?? 70) - 5)),
                        yEnd: .value("Average", pt.average)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(tint.opacity(0.08))

                    PointMark(
                        x: .value("Date", pt.date),
                        y: .value("Average", pt.average)
                    )
                    .foregroundStyle(tint)
                }
                .chartYScale(domain: max(50, (points.map { $0.average }.min() ?? 75) - 5)...100)
                .frame(height: 190)
            }
        }
    }

    private struct TrendPoint: Identifiable {
        var id = UUID()
        var date: Date
        var average: Double
    }

    private func buildTrendPoints(detail: GradeDetail) -> [TrendPoint] {
        let dated = detail.assignments
            .filter { $0.isGraded && $0.due != nil && !$0.noCount && !$0.dropped }
            .sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
        guard !dated.isEmpty else { return [] }
        var out: [TrendPoint] = []
        var prefix: [Assignment] = []
        for a in dated {
            prefix.append(a)
            var slice = detail
            slice.assignments = prefix
            if let pct = GradeMath.compute(slice, mode: model.gradingMode(courseID)).percent, let due = a.due {
                out.append(TrendPoint(date: due, average: pct))
            }
        }
        return out
    }
}

// MARK: - Assignment Inspector & What-If Sheet

struct AssignmentInspectorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let courseID: String
    let lit: String
    let detail: GradeDetail
    let assignment: Assignment

    @State private var earnedText: String = ""
    @State private var possibleText: String = ""
    @State private var excluded: Bool = false
    @State private var info: AssignmentInfo?

    var body: some View {
        let whatIf = model.whatIf(courseID, lit)
        let impact = GradeMath.impact(of: assignment.id, in: detail, mode: model.gradingMode(courseID), whatIf: whatIf)
        let upside = GradeMath.upside(of: assignment.id, in: detail, mode: model.gradingMode(courseID), whatIf: whatIf)

        Form {
            Section("Assignment") {
                LabeledContent("Title", value: assignment.name)
                if !assignment.category.isEmpty {
                    LabeledContent("Category", value: assignment.category)
                }
                if let due = assignment.due {
                    LabeledContent("Due Date", value: SkyDate.long(due))
                }
                if let impact {
                    LabeledContent("Class Impact", value: Fmt.signed(impact, digits: 2) + "%")
                }
                if let upside, upside > 0.01 {
                    LabeledContent("If Full Marks (100%)", value: "+" + Fmt.percent(upside, digits: 2) + "%")
                }
                if let code = assignment.specialCode {
                    LabeledContent("Special Code", value: code)
                }
            }

            Section("What-If Score") {
                TextField("Points Earned", text: $earnedText)
                TextField("Points Possible", text: $possibleText)
                Toggle("Exclude from Average", isOn: $excluded)
                HStack {
                    Button("Apply What-If") {
                        applyEdit()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    if whatIf.edits[assignment.id] != nil {
                        Button("Reset to Posted", role: .destructive) {
                            var updated = whatIf
                            updated.edits[assignment.id] = nil
                            model.setWhatIf(updated, courseID, lit)
                            dismiss()
                        }
                    }
                }
            }

            if let info, !info.fields.isEmpty {
                Section("Skyward Details") {
                    ForEach(info.fields) { kv in
                        LabeledContent(kv.key, value: kv.value)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Assignment Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    applyEdit()
                    dismiss()
                }
            }
        }
        .onAppear {
            let edit = whatIf.edits[assignment.id]
            let e = edit?.earned ?? assignment.earned
            let p = edit?.possible ?? assignment.possible
            earnedText = e.map { Fmt.points($0) } ?? ""
            possibleText = p.map { Fmt.points($0) } ?? ""
            excluded = edit?.excluded ?? false
        }
        .task {
            info = await model.assignmentInfo(assignment)
        }
    }

    private func applyEdit() {
        var updated = model.whatIf(courseID, lit)
        let newEarned = Double(earnedText.trimmingCharacters(in: .whitespaces))
        let newPossible = Double(possibleText.trimmingCharacters(in: .whitespaces))
        if newEarned == assignment.earned && (newPossible == nil || newPossible == assignment.possible) && !excluded {
            updated.edits[assignment.id] = nil
        } else {
            updated.edits[assignment.id] = ScoreEdit(earned: newEarned, possible: newPossible, excluded: excluded)
        }
        model.setWhatIf(updated, courseID, lit)
    }
}

struct AddMockAssignmentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let courseID: String
    let lit: String
    let detail: GradeDetail

    @State private var name = "Hypothetical Test"
    @State private var category = ""
    @State private var earned: Double = 95
    @State private var possible: Double = 100

    var body: some View {
        Form {
            Section("Hypothetical Assignment") {
                TextField("Title", text: $name)
                if !detail.categories.isEmpty {
                    Picker("Category", selection: $category) {
                        ForEach(detail.categories) { cat in
                            Text(cat.name).tag(cat.name)
                        }
                    }
                } else {
                    TextField("Category", text: $category)
                }
                TextField("Points Earned", value: $earned, format: .number)
                TextField("Points Possible", value: $possible, format: .number)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Add Mock Assignment")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    var updated = model.whatIf(courseID, lit)
                    let cat = category.isEmpty ? (detail.categories.first?.name ?? "Major") : category
                    let mock = Assignment(
                        id: "mock-" + UUID().uuidString,
                        name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Mock Assignment" : name,
                        category: cat,
                        due: model.now(),
                        gradeText: "\(Fmt.points(earned))",
                        percent: possible > 0 ? (earned / possible * 100) : nil,
                        earned: earned,
                        possible: possible
                    )
                    updated.added.append(mock)
                    model.setWhatIf(updated, courseID, lit)
                    dismiss()
                }
                .disabled(possible <= 0)
            }
        }
        .onAppear {
            if category.isEmpty { category = detail.categories.first?.name ?? "Major" }
        }
    }
}
