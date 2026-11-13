import SwiftUI

struct OnboardingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Namespace private var stepNamespace

    @State private var step: Int = 0
    @State private var emailDomainDraft: String = ""

    private let steps: [(title: String, subtitle: String, symbol: String)] = [
        ("Personalize Your Profile", "Choose a profile picture, display name, and accent theme.", "person.crop.circle.badge.checkmark"),
        ("GPA Scale & Course Levels", "Verify how your district weights Honors, Advanced, and AP classes.", "graduationcap.fill"),
        ("Teachers & Bell Schedule", "Configure staff email auto-fill, A/B block days, and grade alerts.", "bell.badge.fill"),
    ]

    var body: some View {
        GeometryReader { geo in
            let metrics = WindowMetrics(width: max(480, geo.size.width), height: max(480, geo.size.height))
            VStack(spacing: 0) {
                headerBar
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: metrics.scaled(18)) {
                        if let profile = model.active {
                            switch step {
                            case 0:
                                profileAndThemeStep(profile: profile)
                                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                            case 1:
                                gpaAndCoursesStep
                                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                            default:
                                schoolAndScheduleStep(profile: profile)
                                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                            }
                        }
                    }
                    .padding(metrics.scaled(22))
                }
                Divider()
                footerBar
            }
            .environment(\.windowMetrics, metrics)
        }
        .background { PageBackground() }
        .onAppear {
            if let profile = model.active {
                let existing = model.prefs.emailDomain.trimmingCharacters(in: .whitespaces)
                if !existing.isEmpty {
                    emailDomainDraft = existing
                } else {
                    let letters = profile.districtName.lowercased().filter { $0.isLetter || $0.isNumber }
                    if !letters.isEmpty {
                        let domain = "\(letters).net"
                        emailDomainDraft = domain
                        model.updatePrefs { $0.emailDomain = domain }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: steps[step].symbol)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(model.theme.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .animation(Motion.snappy, value: step)

                VStack(alignment: .leading, spacing: 2) {
                    Text(steps[step].title)
                        .font(.title3.weight(.bold))
                    Text(steps[step].subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Skip Setup") {
                    completeSetup()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { idx in
                    let isCurrent = idx == step
                    let isDone = idx < step
                    Button {
                        withAnimation(Motion.smooth) { step = idx }
                    } label: {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(isCurrent || isDone ? model.theme.color : Palette.inset)
                                    .frame(width: 22, height: 22)
                                if isDone {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                } else {
                                    Text("\(idx + 1)")
                                        .font(.caption2.weight(.bold).monospacedDigit())
                                        .foregroundStyle(isCurrent ? Color.white : Color.secondary)
                                }
                            }
                            Text(idx == 0 ? "Profile & Theme" : idx == 1 ? "GPA & Classes" : "School & Schedule")
                                .font(.caption.weight(isCurrent ? .semibold : .medium))
                                .foregroundStyle(isCurrent ? .primary : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isCurrent {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(model.theme.color.opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(model.theme.color.opacity(0.28), lineWidth: 1)
                                    )
                                    .matchedGeometryEffect(id: "onboardingStepPill", in: stepNamespace)
                            } else {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Palette.inset)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(Palette.card)
    }

    // MARK: - Step 1: Profile & Theme

    private func profileAndThemeStep(profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(tint: model.theme.color) {
                AvatarPickerRow(profile: profile)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preferred Display Name").font(.subheadline.weight(.semibold))
                        Text("Shown on your Home dashboard and student switcher.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField(
                        profile.skywardName.isEmpty ? profile.username : Str.titleCase(profile.skywardName),
                        text: Binding(
                            get: { profile.displayName },
                            set: { text in model.updateActive { $0.displayName = text } }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                }
            }

            Card {
                Text("Accent Theme").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 12) {
                    ForEach(ThemeColor.allCases) { theme in
                        let isSelected = model.theme == theme
                        Button {
                            withAnimation(Motion.snappy) {
                                model.updateActive { $0.theme = theme }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(theme.gradient)
                                        .frame(width: 38, height: 38)
                                        .shadow(color: theme.color.opacity(isSelected ? 0.4 : 0.15), radius: isSelected ? 6 : 2, y: 2)
                                    if isSelected {
                                        Circle()
                                            .strokeBorder(Color.white, lineWidth: 2.5)
                                            .frame(width: 38, height: 38)
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .scaleEffect(isSelected ? 1.08 : 1.0)
                                Text(theme.title)
                                    .font(.caption.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? theme.color : .primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? theme.color.opacity(0.10) : Color.clear)
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }

                Divider()

                Text("Background Theme").font(.headline)
                BackgroundThemePicker()

                Divider()

                HStack {
                    Text("Appearance").font(.subheadline.weight(.medium))
                    Spacer()
                    Picker("Appearance", selection: Binding(
                        get: { model.settings.appearance },
                        set: { value in model.updateSettings { $0.appearance = value } }
                    )) {
                        ForEach(Appearance.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
            }
        }
    }

    // MARK: - Step 2: GPA & Course Weights

    private var gpaAndCoursesStep: some View {
        let lit = model.selectedLit ?? model.data.currentLit ?? ""
        let entries = GPA.currentEntries(data: model.data, lit: lit, settings: model.prefs.gpa)
        let computed = GPA.compute(entries)
        let currentScale = model.prefs.gpa.scale

        return VStack(alignment: .leading, spacing: 16) {
            Card(tint: model.theme.color) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live GPA Preview (\(lit.isEmpty ? "Current Term" : lit))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Fmt.gpa(computed.weighted))
                                    .font(.display(26, weight: .bold).monospacedDigit())
                                    .foregroundStyle(model.theme.color)
                                    .contentTransition(.numericText())
                                Text("Weighted (\(currentScale.name))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Divider().frame(height: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Fmt.gpa(computed.unweighted))
                                    .font(.display(21, weight: .bold).monospacedDigit())
                                    .contentTransition(.numericText())
                                Text("Unweighted (4.00)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                }
            }

            Card {
                Text("GPA Scale Preset").font(.headline)
                HStack(spacing: 10) {
                    ForEach(GPAScale.presets) { preset in
                        let selected = preset.name == currentScale.name
                        Button {
                            withAnimation(Motion.snappy) {
                                model.updatePrefs { $0.gpa.scale = preset }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(preset.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(selected ? model.theme.color : .primary)
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(model.theme.color)
                                    }
                                }
                                Text("Honors +\(Fmt.points(preset.honorsBonus)) · AP +\(Fmt.points(preset.apBonus))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selected ? model.theme.color.opacity(0.10) : Palette.inset)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(selected ? model.theme.color : Palette.hairline, lineWidth: selected ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
            }

            if !model.courses.isEmpty {
                Card(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Course Levels")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("Auto-detected from course titles")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .rowDivider(true)

                        ForEach(Array(model.courses.enumerated()), id: \.element.id) { idx, course in
                            let level = model.prefs.gpa.level(for: course.name)
                            HStack(spacing: 10) {
                                PeriodBadge(period: course.period)
                                Text(Str.titleCase(course.name))
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Picker("Level", selection: Binding(
                                    get: { level },
                                    set: { newLevel in
                                        withAnimation(Motion.snappy) {
                                            model.updatePrefs { $0.gpa.levels[GPASettings.levelKey(course.name)] = newLevel }
                                        }
                                    }
                                )) {
                                    ForEach(CourseLevel.allCases) { lvl in
                                        Text(lvl.shortTitle).tag(lvl)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 195)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .rowDivider(idx < model.courses.count - 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Step 3: School & Bell Schedule

    private func schoolAndScheduleStep(profile: Profile) -> some View {
        let sampleTeacher = model.teachers.first?.name ?? "Dana Whitfield"
        let sampleEmail = model.prefs.emailPattern.address(for: sampleTeacher, domain: emailDomainDraft)

        return VStack(alignment: .leading, spacing: 16) {
            Card {
                HStack {
                    Image(systemName: "envelope.badge.fill")
                        .font(.title3)
                        .foregroundStyle(model.theme.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Teacher Email Auto-Fill").font(.headline)
                        Text("Skyward doesn't show teacher email addresses. Set your district domain once to email any teacher in one click.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    TextField("District domain (e.g. districtisd.net)", text: $emailDomainDraft)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: emailDomainDraft) { _, newValue in
                            model.updatePrefs { $0.emailDomain = newValue }
                        }

                    Picker("Pattern", selection: Binding(
                        get: { model.prefs.emailPattern },
                        set: { pat in model.updatePrefs { $0.emailPattern = pat } }
                    )) {
                        ForEach(EmailPattern.allCases) { pat in
                            let host = emailDomainDraft.trimmingCharacters(in: .whitespaces).isEmpty ? "district.net" : emailDomainDraft
                            Text("\(pat.example)@\(host)").tag(pat)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if let sampleEmail {
                    HStack(spacing: 6) {
                        Text("Preview for \(Str.titleCase(sampleTeacher)):")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(sampleEmail)
                            .font(.caption.weight(.semibold).monospaced())
                            .foregroundStyle(model.theme.color)
                    }
                }
            }

            Card {
                HStack {
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .font(.title3)
                        .foregroundStyle(model.theme.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bell Schedule & Block Rotation").font(.headline)
                        Text("Track time left in the current period on your Home screen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.prefs.bell.schedules.isEmpty {
                        Button("Load 7-Period Preset") {
                            withAnimation(Motion.snappy) {
                                let schedule = BellMath.defaultSchedule(from: model.data.courses) ?? BellMath.highSchoolPreset()
                                model.updateBell { bell in
                                    bell.schedules = [schedule]
                                    for w in 2...6 { bell.weekdays[w] = schedule.id }
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Pill(text: "\(model.prefs.bell.schedules.first?.periods.count ?? 0) periods active", tint: Palette.good, symbol: "checkmark.circle.fill")
                    }
                }

                Divider()

                Toggle("Alternating A / B Block Days", isOn: Binding(
                    get: { model.prefs.bell.abEnabled },
                    set: { on in
                        model.updateBell {
                            $0.abEnabled = on
                            if $0.abAnchor == nil { $0.abAnchor = model.now() }
                        }
                    }
                ))

                Divider()

                Toggle("Notify When New Grades Post", isOn: Binding(
                    get: { model.settings.notifyNewGrades },
                    set: { on in
                        if on { Task { await Notifier.requestPermission() } }
                        model.updateSettings { $0.notifyNewGrades = on }
                    }
                ))
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            if step > 0 {
                Button {
                    withAnimation(Motion.smooth) { step -= 1 }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            if step < steps.count - 1 {
                Button {
                    withAnimation(Motion.smooth) { step += 1 }
                } label: {
                    HStack(spacing: 6) {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button {
                    completeSetup()
                } label: {
                    Label("Finish Setup", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Palette.card)
    }

    private func completeSetup() {
        model.updatePrefs { $0.onboardingDone = true }
        model.showOnboarding = false
        dismiss()
    }
}
