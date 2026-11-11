import SwiftUI

struct ScheduleView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedSemester: Int = 0   // 0 = all
    @State private var dayFilter: DayPattern = .every

    var body: some View {
        let lit = model.selectedLit ?? model.data.currentLit ?? ""
        let sorted = model.courses.sorted { ($0.periodNumber, $0.name) < ($1.periodNumber, $1.name) }
        let filtered = sorted.filter { course in
            if selectedSemester != 0 {
                let sems = model.data.semesters(for: course)
                if !sems.isEmpty, !sems.contains(selectedSemester) { return false }
            }
            if dayFilter != .every {
                let pattern = model.prefs.dayPatterns[course.id] ?? .every
                if pattern != .every && pattern != dayFilter { return false }
            }
            return true
        }

        Screen(title: "Schedule") {
            HStack(spacing: 12) {
                Picker("Semester", selection: $selectedSemester.animation(.snappy)) {
                    Text("Full Year").tag(0)
                    Text("Semester 1").tag(1)
                    Text("Semester 2").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Picker("Day", selection: $dayFilter.animation(.snappy)) {
                    Text("All Days").tag(DayPattern.every)
                    Text("A Day").tag(DayPattern.a)
                    Text("B Day").tag(DayPattern.b)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .staggered(0)

            if filtered.isEmpty {
                Card {
                    EmptyState(
                        symbol: "calendar.day.timeline.left",
                        title: "No classes match this filter",
                        message: "Switch semester or A/B day above, or refresh your gradebook."
                    )
                }
                .staggered(1)
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, course in
                            let pattern = model.prefs.dayPatterns[course.id] ?? .every
                            HStack(spacing: 14) {
                                Text(course.period.isEmpty ? "–" : course.period)
                                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 54, alignment: .leading)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)

                                NavigationLink(value: CourseRoute(courseID: course.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Str.titleCase(course.name))
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text([course.timeRange, Str.titleCase(course.teacher)].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Picker("Meets", selection: Binding(
                                    get: { pattern },
                                    set: { p in withAnimation(.snappy) { model.updatePrefs { $0.dayPatterns[course.id] = p } } }
                                )) {
                                    ForEach(DayPattern.allCases) { Text($0.title).tag($0) }
                                }
                                .labelsHidden()
                                .fixedSize()
                                .help("Which days this class meets on an A/B schedule")

                                if !lit.isEmpty {
                                    GradeBubble(text: model.gradeText(course, lit), percent: model.percent(course, lit), size: .small)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .rowDivider(index < filtered.count - 1)
                        }
                    }
                }
                .staggered(1)
            }

        }
    }
}

struct BellScheduleView: View {
    @Environment(AppModel.self) private var model
    @State private var addingPeriod = false
    @State private var newPeriodName = "Period"
    @State private var newStartHour = 8
    @State private var newStartMinute = 15
    @State private var newEndHour = 9
    @State private var newEndMinute = 5

    private let weekdayNames: [(Int, String)] = [
        (2, "Monday"), (3, "Tuesday"), (4, "Wednesday"), (5, "Thursday"), (6, "Friday"), (7, "Saturday"), (1, "Sunday"),
    ]

    var body: some View {
        let bell = model.prefs.bell
        let activeSchedule = bell.schedules.first

        Screen(title: "Bell Schedule") {
            BellBannerCard()
                .staggered(0)

            TimelineView(.periodic(from: .now, by: 15)) { context in
                let now = context.date
                let nowMin = BellMath.minutes(of: now)
                if let schedule = BellMath.schedule(for: now, config: bell) ?? activeSchedule, !schedule.periods.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(schedule.name) {
                            HStack(spacing: 8) {
                                Button("Add Period", systemImage: "plus") { addingPeriod = true }
                                    .buttonStyle(.borderless)
                            }
                        }
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                let sorted = schedule.sorted
                                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, period in
                                    let isCurrent = nowMin >= period.start && nowMin < period.end
                                    HoverRow {
                                        HStack(spacing: 12) {
                                            Text("\(BellMath.format(period.start))")
                                                .font(.callout.monospacedDigit())
                                                .foregroundStyle(isCurrent ? model.theme.color : .secondary)
                                                .frame(width: 72, alignment: .leading)
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(period.name).font(.body.weight(.medium))
                                                    if isCurrent {
                                                        Text("Now").font(.subheadline.weight(.semibold)).foregroundStyle(model.theme.color)
                                                    }
                                                }
                                                Text("Until \(BellMath.format(period.end)) · \(max(0, period.end - period.start)) min")
                                                    .font(.subheadline.monospacedDigit())
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Button(role: .destructive) {
                                                withAnimation(Motion.snappy) {
                                                    removePeriod(period.id, in: schedule.id)
                                                }
                                            } label: {
                                                Image(systemName: "trash").foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.borderless)
                                            .help("Remove \(period.name)")
                                            .accessibilityLabel("Remove \(period.name)")
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 11)
                                    }
                                    .rowDivider(index < sorted.count - 1)
                                }
                            }
                        }
                    }
                    .staggered(1)
                } else {
                    Card {
                        EmptyState(
                            symbol: "bell",
                            title: "No bell schedule configured",
                            message: "Load the standard 7-period high school bell schedule (7:15 AM – 2:30 PM), build from class times, or add periods manually."
                        )
                        HStack(spacing: 10) {
                            Spacer()
                            Button {
                                withAnimation(Motion.snappy) {
                                    loadHighSchoolPreset()
                                }
                            } label: {
                                Text("Use a 7-Period Day")
                            }
                            .buttonStyle(.borderedProminent)

                            if BellMath.defaultSchedule(from: model.data.courses) != nil {
                                Button("Build from Class Times") {
                                    resetToSkywardTimes()
                                }
                                .buttonStyle(.bordered)
                            }

                            Button("Add Period…") {
                                addingPeriod = true
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                        }
                    }
                    .staggered(1)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Alerts and A/B Days")
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notify Before Next Period").font(.subheadline.weight(.medium))
                            Text("Sends a local notification before each bell rings.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Notify", selection: Binding(
                            get: { bell.notifyBefore },
                            set: { minutes in
                                if minutes > 0 {
                                    Task { await Notifier.requestPermission() }
                                }
                                model.updateBell { $0.notifyBefore = minutes }
                            }
                        )) {
                            Text("Off").tag(0)
                            Text("2 min before").tag(2)
                            Text("5 min before").tag(5)
                            Text("10 min before").tag(10)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alternating A / B Days").font(.subheadline.weight(.medium))
                            Text("Tracks whether today is an A day or B day across school days.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("A/B Days", isOn: Binding(
                            get: { bell.abEnabled },
                            set: { on in
                                withAnimation(Motion.snappy) {
                                    model.updateBell {
                                        $0.abEnabled = on
                                        if $0.abAnchor == nil { $0.abAnchor = model.now() }
                                    }
                                }
                            }
                        ))
                        .labelsHidden()
                    }

                    if bell.abEnabled {
                        HStack {
                            Text("Today is")
                            Spacer()
                            Picker("Today", selection: Binding(
                                get: { BellMath.isADay(model.now(), config: bell) ?? true },
                                set: { isA in
                                    model.updateBell {
                                        $0.abAnchor = model.now()
                                        $0.abAnchorIsA = isA
                                    }
                                }
                            )) {
                                Text("A Day").tag(true)
                                Text("B Day").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 200)
                        }
                    }
                }
            }
            .staggered(2)

            if !bell.schedules.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("School Days")
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(weekdayNames.enumerated()), id: \.element.0) { index, item in
                                let (weekday, label) = item
                                HStack {
                                    Text(label)
                                    Spacer()
                                    Picker(label, selection: Binding(
                                        get: { bell.weekdays[weekday] },
                                        set: { id in model.updateBell { $0.weekdays[weekday] = id } }
                                    )) {
                                        Text("No School").tag(UUID?.none)
                                        ForEach(bell.schedules) { sched in
                                            Text(sched.name).tag(UUID?.some(sched.id))
                                        }
                                    }
                                    .labelsHidden()
                                    .fixedSize()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .rowDivider(index < weekdayNames.count - 1)
                            }
                        }
                    }
                }
                .staggered(3)

                HStack(spacing: 10) {
                    Button("Load 7-Period Preset") {
                        withAnimation(Motion.snappy) {
                            loadHighSchoolPreset()
                        }
                    }
                    .buttonStyle(.bordered)

                    if BellMath.defaultSchedule(from: model.data.courses) != nil {
                        Button("Reset to Skyward Class Times") {
                            resetToSkywardTimes()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .staggered(4)
            }
        }
        .sheet(isPresented: $addingPeriod) {
            NavigationStack {
                Form {
                    Section("New Period") {
                        TextField("Period Name", text: $newPeriodName)
                        HStack {
                            Text("Start (24h)")
                            Spacer()
                            Stepper("\(String(format: "%02d", newStartHour)):\(String(format: "%02d", newStartMinute))", value: $newStartHour, in: 6...20)
                            Stepper("min", value: $newStartMinute, in: 0...55, step: 5).labelsHidden()
                        }
                        HStack {
                            Text("End (24h)")
                            Spacer()
                            Stepper("\(String(format: "%02d", newEndHour)):\(String(format: "%02d", newEndMinute))", value: $newEndHour, in: 6...21)
                            Stepper("min", value: $newEndMinute, in: 0...55, step: 5).labelsHidden()
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Add Period")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { addingPeriod = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            let start = newStartHour * 60 + newStartMinute
                            let end = max(start + 15, newEndHour * 60 + newEndMinute)
                            addPeriod(BellPeriod(name: newPeriodName, start: start, end: end))
                            addingPeriod = false
                        }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 300)
            #endif
        }
    }

    private func addPeriod(_ period: BellPeriod) {
        model.updateBell { bell in
            if bell.schedules.isEmpty {
                let schedule = BellSchedule(name: "Regular Day", periods: [period])
                bell.schedules = [schedule]
                for w in 2...6 { bell.weekdays[w] = schedule.id }
            } else {
                bell.schedules[0].periods.append(period)
            }
        }
    }

    private func removePeriod(_ periodID: UUID, in scheduleID: UUID) {
        model.updateBell { bell in
            guard let i = bell.schedules.firstIndex(where: { $0.id == scheduleID }) else { return }
            bell.schedules[i].periods.removeAll { $0.id == periodID }
        }
    }

    private func loadHighSchoolPreset() {
        let preset = BellMath.highSchoolPreset()
        model.updateBell { bell in
            bell.schedules = [preset]
            bell.weekdays = [:]
            for w in 2...6 { bell.weekdays[w] = preset.id }
        }
    }

    private func resetToSkywardTimes() {
        guard let schedule = BellMath.defaultSchedule(from: model.data.courses) else { return }
        model.updateBell { bell in
            bell.schedules = [schedule]
            bell.weekdays = [:]
            for w in 2...6 { bell.weekdays[w] = schedule.id }
        }
    }
}
