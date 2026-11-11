import SwiftUI

// MARK: - Attendance

struct AttendanceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.windowMetrics) private var metrics
    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date?

    var body: some View {
        let events = model.data.attendance
        let tardies = events.filter { $0.kind == .tardy }.count
        let excused = events.filter { $0.kind == .excused }.count
        let unexcused = events.filter { $0.kind == .unexcused }.count

        let filtered: [AttendanceEvent] = {
            guard let selectedDate else { return events }
            return events.filter { SkyDate.calendar.isDate($0.date, inSameDayAs: selectedDate) }
        }()

        Screen(title: "Attendance") {
            StatGrid(count: 4) {
                StatTile(title: "Days with records", value: "\(events.count)")
                StatTile(title: "Excused", value: "\(excused)")
                StatTile(title: "Tardies", value: "\(tardies)", tint: tardies > 0 ? Palette.warn : .primary)
                StatTile(title: "Unexcused", value: "\(unexcused)", tint: unexcused > 0 ? Palette.bad : .primary)
            }
            .staggered(0)

            if metrics.twoColumnSplit {
                HStack(alignment: .top, spacing: metrics.scaled(16)) {
                    calendarCard(events: events)
                        .frame(maxWidth: 420)
                    eventsListSection(filtered: filtered)
                        .frame(maxWidth: .infinity)
                }
                .staggered(1)
            } else {
                calendarCard(events: events)
                    .staggered(1)
                eventsListSection(filtered: filtered)
                    .staggered(2)
            }
        }
        .onAppear {
            displayedMonth = events.first?.date ?? model.now()
        }
    }

    private func eventsListSection(filtered: [AttendanceEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                selectedDate.map { Fmt.day($0) } ?? "This Year",
                subtitle: "\(filtered.count) \(filtered.count == 1 ? "entry" : "entries")"
            ) {
                if selectedDate != nil {
                    Button("Show All") {
                        withAnimation(Motion.snappy) { selectedDate = nil }
                    }
                    .buttonStyle(.borderless)
                }
            }

            if filtered.isEmpty {
                Card {
                    EmptyState(
                        symbol: "calendar.badge.checkmark",
                        title: selectedDate == nil ? "Perfect attendance" : "No events on this date",
                        message: selectedDate == nil ? "Skyward has no absences or tardies on record." : "Select another highlighted day or tap Show All."
                    )
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, event in
                            HoverRow {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(GradeColor.attendance(event.kind))
                                        .frame(width: 8, height: 8)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(event.reason).font(.body.weight(.medium))
                                        }
                                        HStack(spacing: 6) {
                                            Text(kindLabel(event.kind)).foregroundStyle(GradeColor.attendance(event.kind))
                                            Text("· Periods \(event.periods)")
                                            if !event.classes.isEmpty {
                                                Text("· " + event.classes.map { Str.titleCase($0) }.joined(separator: ", "))
                                                    .lineLimit(1)
                                            }
                                        }
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Text(Fmt.day(event.date))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                            }
                            .rowDivider(index < filtered.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func calendarCard(events: [AttendanceEvent]) -> some View {
        let cal = SkyDate.calendar
        let monthTitle: String = {
            let f = DateFormatter()
            f.dateFormat = "MMMM yyyy"
            return f.string(from: displayedMonth)
        }()
        let days = monthCells(for: displayedMonth, calendar: cal)
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        return Card {
            HStack {
                Text(monthTitle).font(.headline)
                Spacer()
                Button {
                    withAnimation(Motion.snappy) {
                        if let prev = cal.date(byAdding: .month, value: -1, to: displayedMonth) { displayedMonth = prev }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    withAnimation(Motion.snappy) {
                        if let next = cal.date(byAdding: .month, value: 1, to: displayedMonth) { displayedMonth = next }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(weekdays, id: \.self) { w in
                    Text(w).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let dayNum = cal.component(.day, from: date)
                        let dayEvents = events.filter { cal.isDate($0.date, inSameDayAs: date) }
                        let isSelected = selectedDate.map { cal.isDate($0, inSameDayAs: date) } ?? false
                        let tint = dayEvents.first.map { GradeColor.attendance($0.kind) }
                        Button {
                            withAnimation(Motion.snappy) {
                                if isSelected { selectedDate = nil } else { selectedDate = date }
                            }
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(dayNum)")
                                    .font(.subheadline.weight(dayEvents.isEmpty ? .regular : .bold).monospacedDigit())
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                Circle()
                                    .fill(isSelected ? Color.white : (tint ?? Color.clear))
                                    .frame(width: 5, height: 5)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? model.theme.color : (tint?.opacity(0.15) ?? Color.clear))
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
    }

    private func monthCells(for month: Date, calendar: Calendar) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        var out: [Date?] = Array(repeating: nil, count: max(0, firstWeekday - 1))
        for day in range {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: interval.start) {
                out.append(d)
            }
        }
        return out
    }

    private func kindLabel(_ kind: AttendanceKind) -> String {
        switch kind {
        case .tardy: return "Tardy"
        case .excused: return "Excused"
        case .unexcused: return "Unexcused"
        case .other: return "Note"
        }
    }
}

// MARK: - Report Cards & Progress Reports

struct ReportCardsView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case reportCards = "Report Cards"
        case progressReports = "Progress Reports"
        case allGrid = "Full Matrix"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .reportCards
    @State private var pickedLit: String = ""

    var body: some View {
        let buckets = filteredBuckets
        let activeLit: String = {
            if buckets.contains(where: { $0.lit == pickedLit }) { return pickedLit }
            return buckets.last(where: { b in model.courses.contains { !($0.grade(b.lit)?.isEmpty ?? true) } })?.lit
                ?? buckets.first?.lit ?? ""
        }()

        Screen(title: "Report Cards") {
            HStack {
                Picker("Kind", selection: $mode.animation(.snappy)) {
                    ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                if mode != .allGrid, !buckets.isEmpty {
                    Picker("Marking period", selection: Binding(get: { activeLit }, set: { pickedLit = $0 })) {
                        ForEach(buckets) { b in Text(b.displayName).tag(b.lit) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .staggered(0)

            if mode == .allGrid {
                matrixCard
                    .staggered(1)
            } else if buckets.isEmpty {
                Card {
                    EmptyState(
                        symbol: "doc.text",
                        title: "No \(mode.rawValue.lowercased()) columns",
                        message: "Switch to Full Matrix to see every grading column from Skyward."
                    )
                }
                .staggered(1)
            } else {
                if !activeLit.isEmpty {
                    GradesSummary(lit: activeLit)
                        .staggered(2)
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            let courses = model.courses
                            ForEach(Array(courses.enumerated()), id: \.element.id) { index, course in
                                NavigationLink(value: CourseRoute(courseID: course.id)) {
                                    HoverRow {
                                        ClassRow(course: course, lit: activeLit)
                                    }
                                }
                                .buttonStyle(.plain)
                                .rowDivider(index < courses.count - 1)
                            }
                        }
                    }
                    .staggered(3)
                }
            }
        }
    }

    private var filteredBuckets: [TermBucket] {
        switch mode {
        case .reportCards:
            return model.data.buckets.filter { $0.kind == .term || $0.kind == .semester || $0.kind == .final || $0.kind == .exam }
        case .progressReports:
            return model.data.buckets.filter { $0.kind == .progress }
        case .allGrid:
            return model.data.buckets
        }
    }

    private var matrixCard: some View {
        let buckets = model.data.buckets
        let courses = model.courses
        return Card(padding: 0) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Class")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 230, alignment: .leading)
                        ForEach(buckets) { b in
                            Text(b.lit)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(b.lit == model.data.currentLit ? model.theme.color : .secondary)
                                .frame(width: 48, alignment: .center)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .rowDivider(true)

                    ForEach(Array(courses.enumerated()), id: \.element.id) { index, course in
                        let style = SubjectStyle.forCourse(course.name)
                        HoverRow {
                            HStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: style.symbol)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(style.color)
                                        .frame(width: 24, height: 24)
                                        .background(style.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Str.titleCase(course.name))
                                            .font(.subheadline.weight(.medium))
                                            .lineLimit(1)
                                        Text(Str.titleCase(course.teacher))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 230, alignment: .leading)

                                ForEach(buckets) { b in
                                    GradeBubble(
                                        text: model.gradeText(course, b.lit),
                                        percent: model.percent(course, b.lit),
                                        size: .small
                                    )
                                    .frame(width: 48)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .rowDivider(index < courses.count - 1)
                    }
                }
            }
        }
    }
}

// MARK: - Academic History / Transcript

struct TranscriptView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let years = model.data.history
        let entries = GPA.transcriptEntries(history: years, settings: model.prefs.gpa)
        let summary = GPA.compute(entries)

        Screen(title: "Transcript") {
            if years.isEmpty {
                Card {
                    EmptyState(
                        symbol: "scroll.fill",
                        title: model.isActiveQmlativ ? "Transcript is not available for this district yet" : "No transcript history yet",
                        message: model.isActiveQmlativ
                            ? "Current classes and marking periods are available in Grades and Report Cards."
                            : "Completed school years from Skyward Academic History appear here."
                    )
                }
            } else {
                HStack(spacing: 10) {
                    StatTile(title: "Years", value: "\(years.count)", caption: "Academic history", symbol: "calendar")
                    StatTile(title: "Transcript GPA (W)", value: Fmt.gpa(summary.weighted), caption: model.prefs.gpa.scale.name, tint: model.theme.color, symbol: "graduationcap.fill")
                    StatTile(title: "Transcript GPA (UW)", value: Fmt.gpa(summary.unweighted), caption: "4.00 scale", symbol: "scalemass.fill")
                    StatTile(title: "Credits", value: Fmt.points(summary.credits), caption: "Completed", symbol: "checkmark.seal.fill")
                }

                ForEach(years) { year in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(year.title, subtitle: "\(year.courses.count) courses")
                        Card(padding: 0) {
                            ScrollView(.horizontal) {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(spacing: 8) {
                                        Text("Course")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 220, alignment: .leading)
                                        Text("Terms")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 52, alignment: .center)
                                        ForEach(year.lits, id: \.lit) { lit in
                                            Text(lit.lit)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 48, alignment: .center)
                                                .help(lit.name)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .rowDivider(true)

                                    ForEach(Array(year.courses.enumerated()), id: \.element.id) { index, course in
                                        HStack(spacing: 8) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(Str.titleCase(course.name))
                                                    .font(.subheadline.weight(.medium))
                                                    .lineLimit(1)
                                                let lvl = model.prefs.gpa.level(for: course.name)
                                                if lvl != .regular {
                                                    Text(lvl.shortTitle).font(.caption2).foregroundStyle(.secondary)
                                                }
                                            }
                                            .frame(width: 220, alignment: .leading)

                                            Text(course.terms)
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                                .frame(width: 52, alignment: .center)

                                            ForEach(Array(year.lits.enumerated()), id: \.element.lit) { colIdx, _ in
                                                let text = colIdx < course.grades.count ? course.grades[colIdx] : ""
                                                GradeBubble(
                                                    text: text,
                                                    percent: Str.number(text),
                                                    size: .small
                                                )
                                                .frame(width: 48)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .rowDivider(index < year.courses.count - 1)
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Teachers

struct TeachersView: View {
    @Environment(AppModel.self) private var model
    @State private var editingTeacher: AppModel.Teacher?
    @State private var customEmail = ""

    private func suggestedDomain(for profile: Profile) -> String? {
        let letters = profile.districtName.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !letters.isEmpty else { return nil }
        return "\(letters).net"
    }

    var body: some View {
        let teachers = model.teachers

        Screen(title: "Teachers") {
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Teacher e-mail addresses").font(.headline)
                        Text("Skyward doesn't list them. Enter your district's e-mail domain and pick the format; every address fills in.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.prefs.emailDomain.isEmpty,
                       let active = model.active,
                       let suggested = suggestedDomain(for: active) {
                        Button("Use \(suggested)") {
                            withAnimation(Motion.snappy) {
                                model.updatePrefs { $0.emailDomain = suggested }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                HStack(spacing: 12) {
                    TextField("District domain (e.g. district.org)", text: Binding(
                        get: { model.prefs.emailDomain },
                        set: { dom in model.updatePrefs { $0.emailDomain = dom } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                    Picker("Format", selection: Binding(
                        get: { model.prefs.emailPattern },
                        set: { pat in model.updatePrefs { $0.emailPattern = pat } }
                    )) {
                        ForEach(EmailPattern.allCases) { pat in
                            let domain = model.prefs.emailDomain.trimmingCharacters(in: .whitespaces)
                            let host = domain.isEmpty ? "district.org" : domain.replacingOccurrences(of: "@", with: "")
                            Text("\(pat.example)@\(host)").tag(pat)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .staggered(0)

            if teachers.isEmpty {
                Card {
                    EmptyState(symbol: "envelope", title: "No teachers listed", message: "Refresh your gradebook to load your classes and teachers.")
                }
                .staggered(1)
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(teachers.enumerated()), id: \.element.id) { index, teacher in
                            let firstCourse = teacher.courses.first?.name ?? ""
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Str.titleCase(teacher.name)).font(.body.weight(.medium))
                                    Text(teacher.courses.map { ($0.period.isEmpty ? "" : "Period \($0.period) · ") + Str.titleCase($0.name) }.joined(separator: ", "))
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                    Text(teacher.email ?? "No e-mail address")
                                        .font(.subheadline)
                                        .foregroundStyle(teacher.email == nil ? .tertiary : .secondary)
                                        .textSelection(.enabled)
                                }
                                Spacer(minLength: 8)
                                Button("Edit…") {
                                    customEmail = model.prefs.teacherEmails[teacher.name] ?? teacher.email ?? ""
                                    editingTeacher = teacher
                                }
                                .buttonStyle(.borderless)
                                if let email = teacher.email, let mailURL = URL(string: "mailto:\(email)") {
                                    Link(destination: mailURL) {
                                        Label("Email", systemImage: "envelope")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .rowDivider(index < teachers.count - 1)
                        }
                    }
                }
                .staggered(1)
            }
        }
        .sheet(item: $editingTeacher) { teacher in
            NavigationStack {
                Form {
                    Section(Str.titleCase(teacher.name)) {
                        TextField("teacher@district.org", text: $customEmail)
                            .autocorrectionDisabled()
                    }
                    if model.prefs.teacherEmails[teacher.name] != nil {
                        Section {
                            Button("Use District Pattern Instead", role: .destructive) {
                                model.updatePrefs { $0.teacherEmails[teacher.name] = nil }
                                editingTeacher = nil
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Teacher Email")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingTeacher = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let trimmed = customEmail.trimmingCharacters(in: .whitespaces)
                            model.updatePrefs { $0.teacherEmails[teacher.name] = trimmed.isEmpty ? nil : trimmed }
                            editingTeacher = nil
                        }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 240)
            #endif
        }
    }
}
