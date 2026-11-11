import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var editingClasses = false
    @State private var removing: Profile?
    @State private var rememberSheet = false

    var body: some View {
        Form {
            if let profile = model.active {
                studentSection(profile)
            }
            lookSection
            syncSection
            notificationSection
            #if os(macOS)
            macSection
            #endif
            aboutSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background { PageBackground() }
        .navigationTitle("Settings")
        .sheet(isPresented: $editingClasses) {
            NavigationStack { ClassOrderEditor() }
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 520)
            #endif
        }
        .sheet(isPresented: $rememberSheet) {
            RememberSignInSheet()
        }
        .confirmationDialog(
            "Remove \(removing?.name ?? "this student")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let id = removing?.id { model.removeProfile(id) }
                removing = nil
            }
        } message: {
            Text("Their grades, planner and saved sign-in are deleted from this Mac. Nothing changes in Skyward.")
        }
    }

    // MARK: Student

    private func studentSection(_ profile: Profile) -> some View {
        Section {
            AvatarPickerRow(profile: profile)
            TextField("Display name", text: Binding(
                get: { profile.displayName },
                set: { text in model.updateActive { $0.displayName = text } }
            ), prompt: Text(profile.skywardName.isEmpty ? profile.username : Str.titleCase(profile.skywardName)))
            LabeledContent("District", value: profile.districtName.isEmpty ? (URLComponents(string: profile.address)?.host ?? "") : profile.districtName)
            if !model.data.profile.school.isEmpty {
                LabeledContent("School", value: Str.titleCase(model.data.profile.school))
            }
            LabeledContent("Classes") {
                HStack {
                    if !model.prefs.hiddenCourses.isEmpty {
                        Text("\(model.prefs.hiddenCourses.count) hidden").foregroundStyle(.secondary)
                    }
                    Button("Reorder or Hide…") { editingClasses = true }
                }
            }
            HStack {
                Button("Sign In Again…") { model.requestReauth(profile) }
                    .disabled(profile.isDemo)
                Spacer()
                Button("Remove Student…", role: .destructive) { removing = profile }
            }
        } header: {
            Text("Student")
        }
    }

    // MARK: Look

    private var lookSection: some View {
        Section("Appearance") {
            Picker("Appearance", selection: setting(\.appearance)) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            LabeledContent("Accent colour") {
                AccentPicker()
            }

            Picker("Background", selection: setting(\.backgroundTheme)) {
                ForEach(BackgroundTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }

            Picker("Grades", selection: setting(\.gradeStyle)) {
                ForEach(GradeStyle.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Colour grades by letter", isOn: setting(\.colorBubbles))
            Toggle("Compact rows", isOn: setting(\.compactRows))

            #if os(macOS)
            Toggle("Translucent window", isOn: setting(\.translucentWindow))
            Toggle("Glow around the window", isOn: setting(\.windowGlow))
            LabeledContent("App icon") {
                AppIconPicker()
            }
            #endif
        }
    }

    // MARK: Sync

    private var syncSection: some View {
        Section {
            Toggle("Check Skyward in the background", isOn: setting(\.backgroundSync))
            Picker("Check every", selection: setting(\.syncMinutes)) {
                Text("15 minutes").tag(15)
                Text("30 minutes").tag(30)
                Text("1 hour").tag(60)
                Text("2 hours").tag(120)
            }
            .disabled(!model.settings.backgroundSync)

            if let profile = model.active, model.isQmlativ(profile) {
                LabeledContent("District sign-in") {
                    HStack {
                        if model.rememberedSignInFailed(profile) {
                            Text("Didn't work").foregroundStyle(Palette.bad)
                        } else {
                            Text(model.hasRememberedSignIn(profile) ? "Remembered" : "Not saved")
                                .foregroundStyle(.secondary)
                        }
                        Button(model.hasRememberedSignIn(profile) ? "Change…" : "Remember…") { rememberSheet = true }
                    }
                }
            }

            Picker("Copy due dates to", selection: Binding(
                get: { model.settings.exportTarget },
                set: { value in
                    model.updateSettings { $0.exportTarget = value }
                    model.exportDueDates()
                }
            )) {
                ForEach(ExportTarget.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Syncing")
        } footer: {
            Text(syncFooter)
        }
    }

    private var syncFooter: String {
        var parts: [String] = []
        if model.settings.backgroundSync {
            parts.append("Each check signs in to Skyward, which signs you out of Skyward in your browser.")
        }
        if model.settings.exportTarget != .off {
            parts.append("Due dates go to a list called “Skyward Plus” and stay in sync.")
        }
        return parts.joined(separator: " ")
    }

    private var notificationSection: some View {
        Section("Notifications") {
            Toggle("New grades", isOn: notifySetting(\.notifyNewGrades))
            Toggle("Due tomorrow and missing work", isOn: Binding(
                get: { model.settings.notifyDueTomorrow },
                set: { on in
                    if on { Task { await Notifier.requestPermission() } }
                    model.updateSettings { $0.notifyDueTomorrow = on }
                    model.rescheduleDueReminders()
                }
            ))
            Toggle("A class drops below its goal", isOn: notifySetting(\.notifyBelowGoal))
        }
    }

    // MARK: Mac

    #if os(macOS)
    private var macSection: some View {
        Section {
            Toggle("Show in the menu bar", isOn: setting(\.showMenuBarIcon))
            Toggle("Keep running when the window is closed", isOn: setting(\.keepInMenuBar))
                .disabled(!model.settings.showMenuBarIcon)
            Toggle("Open at login", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            if Biometrics.isAvailable {
                Toggle("Require \(Biometrics.name) to open", isOn: setting(\.biometricLock))
            }
        } header: {
            Text("Mac")
        } footer: {
            if model.settings.launchAtLogin && LoginItem.needsApproval {
                Text("Allow Skyward Plus in System Settings › General › Login Items.")
            }
        }
    }
    #endif

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: AppModel.currentVersion)
            #if os(macOS)
            UpdateRow()
            #endif
        }
    }

    // MARK: Bindings

    private func setting<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in withAnimation(.snappy) { model.updateSettings { $0[keyPath: keyPath] = value } } }
        )
    }

    private func notifySetting(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { on in
                if on { Task { await Notifier.requestPermission() } }
                model.updateSettings { $0[keyPath: keyPath] = on }
            }
        )
    }
}

/// Ten colour dots; the selected one gets a ring.
private struct AccentPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ThemeColor.allCases) { theme in
                let selected = model.theme == theme
                Button {
                    withAnimation(.snappy) { model.updateActive { $0.theme = theme } }
                } label: {
                    Circle()
                        .fill(theme.color)
                        .frame(width: 18, height: 18)
                        .padding(3)
                        .overlay { Circle().strokeBorder(selected ? theme.color : .clear, lineWidth: 2) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(theme.title)
                .accessibilityLabel(theme.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

#if os(macOS)
import AppKit

private struct AppIconPicker: View {
    @Environment(AppModel.self) private var model

    static let choices: [(id: String, title: String, theme: ThemeColor)] = [
        ("AppIcon", "Sky", .sky),
        ("AppIconIndigo", "Indigo", .indigo),
        ("AppIconForest", "Forest", .forest),
        ("AppIconSunset", "Sunset", .sunset),
        ("AppIconGraphite", "Graphite", .graphite),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppIconPicker.choices, id: \.id) { choice in
                let selected = model.settings.appIcon == choice.id
                Button {
                    model.updateSettings { $0.appIcon = choice.id }
                    AppIconApplier.apply(choice.id)
                } label: {
                    Group {
                        if let image = AppIconApplier.image(for: choice.id) {
                            Image(nsImage: image).resizable()
                        } else {
                            RoundedRectangle(cornerRadius: 6).fill(choice.theme.color)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .padding(2)
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? model.theme.color : .clear, lineWidth: 2) }
                }
                .buttonStyle(.plain)
                .help(choice.title)
            }
        }
    }
}

enum AppIconApplier {
    static func image(for id: String) -> NSImage? {
        NSImage(named: id)
    }

    /// Swaps the Dock icon. Called at launch too, since macOS doesn't remember it.
    @MainActor
    static func apply(_ id: String) {
        NSApplication.shared.applicationIconImage = id == "AppIcon" ? nil : NSImage(named: id)
    }
}

private struct UpdateRow: View {
    @Environment(AppModel.self) private var model
    private var updater: Updater { Updater.shared }

    var body: some View {
        if let update = model.availableUpdate {
            LabeledContent {
                switch updater.phase {
                case .downloading(let fraction):
                    ProgressView(value: fraction).frame(width: 140)
                case .installing:
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Installing…") }
                case .failed(let message):
                    HStack {
                        Text(message).foregroundStyle(Palette.bad).lineLimit(2)
                        Button("Try Again") { Task { await updater.install(update) } }
                    }
                case .idle:
                    HStack {
                        Button("Release Notes") { NSWorkspace.shared.open(update.pageURL) }
                        Button("Update and Relaunch") { Task { await updater.install(update) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } label: {
                Text("Version \(update.version) is available")
            }
        } else {
            LabeledContent {
                Button("Check Now") { Task { await model.checkForUpdates(manual: true) } }
            } label: {
                Text("Updates")
                if let message = model.updateMessage {
                    Text(message)
                } else if let last = model.settings.lastUpdateCheck {
                    Text("Checked \(Fmt.ago(last, now: model.now()))")
                }
            }
        }
    }
}
#endif
