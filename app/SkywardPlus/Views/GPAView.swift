import SwiftUI

struct GPAView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var editingScale = false
    @State private var overrides: [String: Double] = [:]
    @State private var editingCourse: Course?

    var body: some View {
        let lit = model.selectedLit ?? model.data.currentLit ?? ""
        let settings = model.prefs.gpa
        let combinedOverrides: [String: Double] = {
            var map = overrides
            for course in model.courses {
                if map[course.id] == nil, !model.whatIf(course.id, lit).isEmpty,
                   let pct = model.result(course.id, lit, includeWhatIf: true)?.percent {
                    map[course.id] = pct
                }
            }
            return map
        }()

        let visibleIDs = Set(model.courses.map { "cur|\($0.id)" })
        let currentEntries = GPA.currentEntries(data: model.data, lit: lit, settings: settings, overrides: combinedOverrides)
            .filter { visibleIDs.contains($0.id) }
        let transcriptEntries = settings.includeTranscript
            ? GPA.transcriptEntries(history: model.data.history, settings: settings)
            : []
        let allEntries = currentEntries + transcriptEntries
        let result = GPA.compute(allEntries)
        let currentOnly = GPA.compute(currentEntries)

        Screen(title: "GPA", maxWidth: 1000) {
            MarkingPeriodBar()
                .staggered(0)

            HStack(alignment: .bottom, spacing: 28) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.gpa(result.weighted))
                        .font(.display(44).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text("Weighted GPA").font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.gpa(result.unweighted))
                        .font(.display(26, weight: .medium).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Text("Unweighted").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(lit.isEmpty ? "This term" : lit): \(Fmt.gpa(currentOnly.weighted))")
                        .font(.callout.monospacedDigit())
                    Text("\(Fmt.points(result.credits)) credits")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
            .staggered(1)

            let scaleLine = Text("\(settings.scale.name) · Honors +\(Fmt.points(settings.scale.honorsBonus)) · AP/IB +\(Fmt.points(settings.scale.apBonus))")
                .font(.callout)
                .foregroundStyle(.secondary)
            let transcriptToggle = Group {
                if !(model.isActiveQmlativ && model.data.history.isEmpty) {
                    Toggle("Include transcript", isOn: Binding(
                        get: { model.prefs.gpa.includeTranscript },
                        set: { value in withAnimation(.snappy) { model.updatePrefs { $0.gpa.includeTranscript = value } } }
                    ))
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif
                }
            }
            Group {
                if sizeClass == .compact {
                    VStack(alignment: .leading, spacing: 10) {
                        scaleLine
                        transcriptToggle
                    }
                } else {
                    HStack(spacing: 12) {
                        scaleLine
                        Spacer()
                        transcriptToggle
                    }
                }
            }
            .staggered(2)

            if !overrides.isEmpty {
                Card(tint: Palette.warn) {
                    HStack {
                        Text("What-if: \(overrides.count) \(overrides.count == 1 ? "grade" : "grades") changed. Your real GPA is unchanged.")
                            .font(.callout)
                        Spacer()
                        Button("Reset") { withAnimation(.snappy) { overrides = [:] } }
                    }
                }
            }

            currentCoursesSection(entries: currentEntries, lit: lit)
                .staggered(3)

            if settings.includeTranscript, !transcriptEntries.isEmpty {
                transcriptSection(entries: transcriptEntries)
                    .staggered(4)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingScale = true
                } label: {
                    Label("GPA Scale", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $editingScale) {
            NavigationStack {
                GPAScaleSheet()
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 540)
            #endif
        }
        .sheet(item: $editingCourse) { course in
            NavigationStack {
                CourseWhatIfSheet(
                    course: course,
                    currentPercent: combinedOverrides[course.id] ?? model.percent(course, lit) ?? 90,
                    hasOverride: overrides[course.id] != nil,
                    onSave: { newPct in overrides[course.id] = newPct },
                    onClear: { overrides[course.id] = nil }
                )
            }
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 280)
            #endif
        }
    }

    private func currentCoursesSection(entries: [GPAEntry], lit: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("\(lit.isEmpty ? "Current" : lit) Classes", subtitle: sizeClass == .compact ? "Tap a grade to try a different one." : "Click a grade to try a different one.")
            if entries.isEmpty {
                Card {
                    EmptyState(symbol: "graduationcap", title: "No graded classes in \(lit)", message: "Choose a marking period with grades to calculate GPA.")
                }
            } else {
                RowGroup(items: entries) { entry in
                    HoverRow {
                        entryRow(entry: entry, isCurrent: true)
                    }
                }
            }
        }
    }

    private func transcriptSection(entries: [GPAEntry]) -> some View {
        let grouped = Dictionary(grouping: entries) { $0.year ?? "Transcript" }
        let years = grouped.keys.sorted(by: >)

        return VStack(alignment: .leading, spacing: 16) {
            ForEach(years, id: \.self) { year in
                if let list = grouped[year] {
                    let yearGPA = GPA.compute(list)
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(year, subtitle: "Weighted \(Fmt.gpa(yearGPA.weighted)) · Unweighted \(Fmt.gpa(yearGPA.unweighted)) · \(Fmt.points(yearGPA.credits)) cr")
                        RowGroup(items: list) { entry in
                            HoverRow {
                                entryRow(entry: entry, isCurrent: false)
                            }
                        }
                    }
                }
            }
        }
    }

    private func entryRow(entry: GPAEntry, isCurrent: Bool) -> some View {
        let courseID = entry.id.hasPrefix("cur|") ? String(entry.id.dropFirst(4)) : nil
        let isOverridden = courseID.map { overrides[$0] != nil } ?? false
        return HStack(spacing: 12) {
            Button {
                withAnimation(Motion.snappy) {
                    model.updatePrefs { prefs in
                        if prefs.gpa.excluded.contains(entry.id) {
                            prefs.gpa.excluded.remove(entry.id)
                        } else {
                            prefs.gpa.excluded.insert(entry.id)
                        }
                    }
                }
            } label: {
                Image(systemName: entry.excluded ? "circle" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(entry.excluded ? Color.secondary.opacity(0.6) : model.theme.color)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(entry.excluded ? "Include in GPA" : "Exclude from GPA")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Str.titleCase(entry.name))
                        .font(.body.weight(.medium))
                        .strikethrough(entry.excluded)
                        .foregroundStyle(entry.excluded ? .secondary : .primary)
                        .lineLimit(1)
                    if isOverridden {
                        Text("What-if").font(.subheadline.weight(.medium)).foregroundStyle(Palette.warn)
                    }
                }
                HStack(spacing: 8) {
                    Menu {
                        ForEach(CourseLevel.allCases) { lvl in
                            Button {
                                withAnimation(Motion.snappy) {
                                    model.updatePrefs { $0.gpa.levels[GPASettings.levelKey(entry.name)] = lvl }
                                }
                            } label: {
                                if lvl == entry.level {
                                    Label(lvl.title, systemImage: "checkmark")
                                } else {
                                    Text(lvl.title)
                                }
                            }
                        }
                    } label: {
                        MenuChip(text: entry.level.shortTitle)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    Menu {
                        ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { cr in
                            Button("\(Fmt.points(cr)) credit\(cr == 1 ? "" : "s")") {
                                model.updatePrefs { $0.gpa.credits[entry.id] = cr }
                            }
                        }
                    } label: {
                        MenuChip(text: "\(Fmt.points(entry.credits)) \(entry.credits == 1 ? "credit" : "credits")")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    if let w = entry.weighted, let uw = entry.unweighted {
                        // The phone has room for the points this class counts for, not both.
                        Text(sizeClass == .compact ? Fmt.gpa(w) : "\(Fmt.gpa(w)) weighted · \(Fmt.gpa(uw))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            if isCurrent, let courseID, let course = model.course(courseID) {
                Button {
                    editingCourse = course
                } label: {
                    GradeBubble(
                        text: entry.percent.map { Fmt.percent($0) } ?? entry.letter,
                        percent: entry.percent,
                        size: .small
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Set hypothetical grade for GPA")
            } else {
                GradeBubble(
                    text: entry.percent.map { Fmt.percent($0) } ?? entry.letter,
                    percent: entry.percent,
                    size: .small
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct CourseWhatIfSheet: View {
    @Environment(\.dismiss) private var dismiss
    let course: Course
    @State var currentPercent: Double
    let hasOverride: Bool
    var onSave: (Double) -> Void
    var onClear: () -> Void

    var body: some View {
        Form {
            Section(Str.titleCase(course.name)) {
                HStack {
                    Text("Hypothetical Grade")
                    Spacer()
                    Text(Fmt.percent(currentPercent) + "%")
                        .font(.headline.monospacedDigit())
                }
                Slider(value: $currentPercent, in: 50...100, step: 0.5)
                TextField("Percent", value: $currentPercent, format: .number)
            }
            if hasOverride {
                Section {
                    Button("Reset to Real Grade", role: .destructive) {
                        onClear()
                        dismiss()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("GPA What-If")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") {
                    onSave(currentPercent)
                    dismiss()
                }
            }
        }
    }
}

struct GPAScaleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let scale = model.prefs.gpa.scale
        Form {
            Section("Presets") {
                ForEach(GPAScale.presets) { preset in
                    Button {
                        model.updatePrefs { $0.gpa.scale = preset }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).foregroundStyle(.primary)
                                Text("Honors +\(Fmt.points(preset.honorsBonus)) · AP/IB +\(Fmt.points(preset.apBonus))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if preset.name == scale.name {
                                Image(systemName: "checkmark").foregroundStyle(model.theme.color)
                            }
                        }
                    }
                }
            }

            Section("Course Level Bonuses") {
                Stepper(
                    value: Binding(
                        get: { model.prefs.gpa.scale.honorsBonus },
                        set: { v in model.updatePrefs { $0.gpa.scale.honorsBonus = v } }
                    ),
                    in: 0...2,
                    step: 0.25
                ) {
                    HStack {
                        Text("Honors / Pre-AP Bonus")
                        Spacer()
                        Text("+" + String(format: "%.2f", scale.honorsBonus)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Stepper(
                    value: Binding(
                        get: { model.prefs.gpa.scale.apBonus },
                        set: { v in model.updatePrefs { $0.gpa.scale.apBonus = v } }
                    ),
                    in: 0...3,
                    step: 0.25
                ) {
                    HStack {
                        Text("AP / IB / Dual Bonus")
                        Spacer()
                        Text("+" + String(format: "%.2f", scale.apBonus)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }

            Section("Grade Cutoffs") {
                ForEach(scale.rows) { row in
                    HStack {
                        Text(row.letter).font(.headline).frame(width: 40, alignment: .leading)
                        Text("≥ \(Fmt.percent(row.min))%").foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f pts", row.points)).monospacedDigit()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("GPA Scale")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}


/// A small pill that opens a menu: big enough to hit, quiet enough to ignore.
private struct MenuChip: View {
    @Environment(AppModel.self) private var model
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
        .background(model.theme.color.opacity(0.28), in: Capsule())
        .contentShape(Capsule())
    }
}
