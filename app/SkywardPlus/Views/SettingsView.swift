import SwiftUI

/// Settings as a short list of pages, each with a handful of choices.
enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case student, account, appearance, notifications, syncing, mac, about

    var id: String { rawValue }

    static var shown: [SettingsPage] {
        #if os(macOS)
        return [.account, .appearance, .notifications, .syncing, .mac, .about]
        #else
        return [.account, .appearance, .notifications, .syncing, .about]
        #endif
    }

    var title: String {
        switch self {
        case .student: return "Student"
        case .account: return "Account"
        case .appearance: return "Appearance"
        case .notifications: return "Notifications"
        case .syncing: return "Syncing"
        case .mac: return "Mac"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .student: return "person.crop.circle"
        case .account: return "person.icloud"
        case .appearance: return "paintpalette"
        case .notifications: return "bell.badge"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .mac: return "macbook"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: "Settings", spacing: 20, maxWidth: 680) {
            if let profile = model.active {
                NavigationLink(value: SettingsPage.student) {
                    HStack(spacing: 14) {
                        AvatarView(profile: profile, size: 56, scalesWithWindow: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                            Text(profile.districtName.isEmpty ? profile.username : profile.districtName)
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .bubble(cornerRadius: 20)
                }
                .buttonStyle(BubbleButtonStyle())
            }

            RowGroup(items: SettingsPage.shown) { page in
                NavigationLink(value: page) {
                    HStack(spacing: 14) {
                        Image(systemName: page.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(model.theme.color, in: .rect(cornerRadius: 8, style: .continuous))
                        Text(page.title).foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(summary(page)).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BubbleButtonStyle())
            }
        }
        .navigationDestination(for: SettingsPage.self) { SettingsPageView(page: $0).clearWindowBar() }
    }

    private func summary(_ page: SettingsPage) -> String {
        switch page {
        case .account: return AccountSync.shared.email ?? "Not signed in"
        case .appearance: return model.settings.backgroundTheme.title
        case .notifications:
            let on = [model.settings.notifyNewGrades, model.settings.notifyDueTomorrow, model.settings.notifyBelowGoal].filter { $0 }.count
            return on == 0 ? "Off" : "\(on) on"
        case .syncing: return model.settings.backgroundSync ? "Every \(model.settings.syncMinutes) min" : "Manual"
        case .about: return "Version " + AppModel.currentVersion
        default: return ""
        }
    }
}

/// One settings page, built from the same bubbles as the rest of the app so it
/// scales with the window and every control is a comfortable target.
struct SettingsPageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let page: SettingsPage
    @State private var removing: Profile?
    @State private var rememberSheet = false

    var body: some View {
        Screen(title: page.title, spacing: 26, maxWidth: page == .appearance ? 780 : 680) {
            switch page {
            case .student: studentPage
            case .account: AccountSettingsSection()
            case .appearance: appearancePage
            case .notifications: notificationsPage
            case .syncing: syncingPage
            case .mac: macPage
            case .about: aboutPage
            }
        }
        .sheet(isPresented: $rememberSheet) { RememberSignInSheet() }
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
            Text("Their grades, planner and saved sign-in are deleted from this device.")
        }
    }

    // MARK: Student

    @ViewBuilder private var studentPage: some View {
        if let profile = model.active {
            SettingsGroup {
                AvatarPickerRow(profile: profile)
                    .padding(16)
                    .bubble()
                SettingRow(title: "Name") {
                    TextField("Name", text: Binding(
                        get: { profile.displayName },
                        set: { text in model.updateActive { $0.displayName = text } }
                    ), prompt: Text(profile.skywardName.isEmpty ? profile.username : Str.titleCase(profile.skywardName)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                }
                SettingRow(title: "District") {
                    Text(profile.districtName.isEmpty ? (URLComponents(string: profile.address)?.host ?? "") : profile.districtName)
                        .foregroundStyle(.secondary)
                }
                if !model.data.profile.school.isEmpty {
                    SettingRow(title: "School") {
                        Text(Str.titleCase(model.data.profile.school)).foregroundStyle(.secondary)
                    }
                }
            }
            #if os(iOS)
            if Biometrics.isAvailable {
                SettingsGroup(title: "Privacy", footer: "Asks for \(Biometrics.name) every time you open Skyward Plus, so someone holding your phone can't see your grades.") {
                    ToggleRow(title: "Require \(Biometrics.name) to open", isOn: setting(\.biometricLock))
                }
            }
            #endif
            SettingsGroup {
                NavigationLink(value: AppSection.students) {
                    SettingRow(title: "All Students") { Chevron() }
                }
                .buttonStyle(BubbleButtonStyle())
                if !profile.isDemo {
                    ActionRow(title: "Sign In Again") { model.requestReauth(profile) }
                }
                ActionRow(title: "Remove Student", role: .destructive) { removing = profile }
            }
        }
    }

    // MARK: Appearance

    @ViewBuilder private var appearancePage: some View {
        SettingsGroup(title: "Theme") {
            BackgroundThemePicker(columns: 3)
                .padding(16)
                .bubble(cornerRadius: 20)
        }
        SettingsGroup(title: "Grades") {
            SettingRow(title: "Show grades as") {
                Picker("Show grades as", selection: setting(\.gradeStyle)) {
                    ForEach(GradeStyle.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            ToggleRow(title: "Colour by letter grade", isOn: setting(\.colorBubbles))
            #if os(iOS)
            ToggleRow(title: "Nimbus at the bottom of Home", isOn: setting(\.showMascot))
            #endif
        }
        #if os(macOS)
        SettingsGroup(title: "Window") {
            ToggleRow(title: "Translucent window", isOn: setting(\.translucentWindow))
            ToggleRow(title: "Glow around the window", isOn: setting(\.windowGlow))
            ToggleRow(title: "Nimbus walks around empty space", isOn: setting(\.showMascot))
            SettingRow(title: "App icon") { AppIconPicker() }
        }
        #endif
    }

    // MARK: Notifications

    @ViewBuilder private var notificationsPage: some View {
        NotificationStatusGroup()
        SettingsGroup(title: "Tell me about") {
            ToggleRow(title: "New and changed grades", isOn: notifySetting(\.notifyNewGrades))
            ToggleRow(title: "Work marked missing", isOn: notifySetting(\.notifyMissing))
            ToggleRow(title: "Absences and tardies", isOn: notifySetting(\.notifyAttendance))
            ToggleRow(title: "Work due tomorrow", isOn: eveningSetting(\.notifyDueTomorrow))
            ToggleRow(title: "A class under its goal", isOn: notifySetting(\.notifyBelowGoal))
        }
        SettingsGroup(title: "Evening summary", footer: "Today's grades, what's missing, what's due tomorrow and any class under its goal, in one note.") {
            ToggleRow(title: "Send an evening summary", isOn: eveningSetting(\.notifySummary))
            SettingRow(title: model.settings.notifySummary ? "Summary and reminders at" : "Due reminders at") {
                Picker("Time", selection: setting(\.summaryHour)) {
                    ForEach(15..<23) { hour in Text(hourLabel(hour)).tag(hour) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        SettingsGroup(title: "Sounds", footer: "Chimes play for new grades while the app is open, and on grade alerts. A tick plays when you finish a task or assignment.") {
            ToggleRow(title: "Sounds", isOn: setting(\.soundsOn))
            if model.settings.soundsOn {
                ToggleRow(title: "Chime for new grades", isOn: setting(\.soundGradeChimes))
                ToggleRow(title: "Tick when you finish something", isOn: setting(\.soundTaskTicks))
                ActionRow(title: "Play the Grade Chime") { SoundEffects.play(.gradeGreat, settings: model.settings) }
            }
        }
        #if os(macOS)
        PhoneRelayGroup()
        #endif
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func eveningSetting(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { on in
                if on { Task { await Notifier.requestPermission() } }
                model.updateSettings { $0[keyPath: keyPath] = on }
                model.rescheduleDueReminders()
            }
        )
    }

    // MARK: Syncing

    @ViewBuilder private var syncingPage: some View {
        if AccountSync.shared.isConfigured {
            GoogleCalendarGroup()
        }
        SettingsGroup(footer: model.settings.backgroundSync ? syncFooter : nil) {
            ToggleRow(title: "Check Skyward automatically", isOn: setting(\.backgroundSync))
            if model.settings.backgroundSync {
                SettingRow(title: "Every") {
                    Picker("Every", selection: setting(\.syncMinutes)) {
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        if let profile = model.active, model.isQmlativ(profile) {
            SettingsGroup(title: "District sign-in") {
                SettingRow(title: "Saved sign-in") {
                    if model.rememberedSignInFailed(profile) {
                        Text("Didn't work").foregroundStyle(Palette.bad)
                    } else {
                        Text(model.hasRememberedSignIn(profile) ? "Saved" : "Not saved").foregroundStyle(.secondary)
                    }
                }
                ActionRow(title: model.hasRememberedSignIn(profile) ? "Change Saved Sign-In" : "Save Sign-In") { rememberSheet = true }
            }
        }
        SettingsGroup(title: "Due dates") {
            SettingRow(title: "Copy due dates to") {
                Picker("Copy due dates to", selection: Binding(
                    get: { model.settings.exportTarget },
                    set: { value in
                        model.updateSettings { $0.exportTarget = value }
                        model.exportDueDates()
                    }
                )) {
                    ForEach(ExportTarget.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var syncFooter: String {
        #if os(macOS)
        "Runs while Skyward Plus is in the menu bar, and signs back in by itself with your saved sign-in. Skyward allows one sign-in at a time: if you open Skyward in a browser, checks pause for 30 minutes instead of signing you out."
        #else
        "iOS decides how often the app may check in the background, usually every 15 minutes to a few hours. If your Mac is signed in to the same account with Skyward Plus open, your phone gets grades from it instead of signing in, so the two never sign each other out. Otherwise, Skyward allows one sign-in at a time, so a check can sign you out of the Skyward website."
        #endif
    }

    // MARK: Mac

    @ViewBuilder private var macPage: some View {
        #if os(macOS)
        SettingsGroup(footer: model.settings.launchAtLogin && LoginItem.needsApproval ? "Allow Skyward Plus in System Settings › General › Login Items." : nil) {
            ToggleRow(title: "Show in the menu bar", isOn: setting(\.showMenuBarIcon))
            ToggleRow(title: "Keep running when closed", isOn: setting(\.keepInMenuBar))
                .disabled(!model.settings.showMenuBarIcon)
                .opacity(model.settings.showMenuBarIcon ? 1 : 0.5)
            SettingRow(title: "Search from any app", subtitle: model.settings.searchShortcut == "commandK" ? "Other apps lose their own ⌘K while this is on." : nil) {
                Picker("Search from any app", selection: setting(\.searchShortcut)) {
                    ForEach(QuickSearch.Shortcut.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
                .fixedSize()
            }
            ToggleRow(title: "Open at login", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            if Biometrics.isAvailable {
                ToggleRow(title: "Require \(Biometrics.name) to open", isOn: setting(\.biometricLock))
            }
        }
        #endif
    }

    // MARK: About

    @ViewBuilder private var aboutPage: some View {
        SettingsGroup {
            SettingRow(title: "Version") { Text(AppModel.currentVersion).foregroundStyle(.secondary) }
            #if os(macOS)
            UpdateRow()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minHeight: 54)
                .bubble()
            ActionRow(title: "Play the Welcome Again") { AppDelegate.shared?.replayHello() }
            #else
            PhoneUpdateRows()
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

// MARK: - Setting building blocks

/// A titled group of setting rows.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.headline).padding(.leading, 4)
            }
            VStack(spacing: 8) { content }
            if let footer {
                Text(footer).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A label on the left and whatever control or value on the right, in one bubble.
struct SettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .bubble()
        .contentShape(Rectangle())
    }
}

/// A switch row; the whole row is the switch's label, so it is easy to hit.
struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .bubble()
    }
}

/// A row that does something when pressed.
struct ActionRow: View {
    let title: String
    var role: ButtonRole? = nil
    let action: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(role: role, action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(role == .destructive ? Palette.bad : model.theme.color)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .bubble()
            .contentShape(Rectangle())
        }
        .buttonStyle(BubbleButtonStyle())
    }
}

private struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
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

/// Settings → Syncing: copy due dates into a calendar of their own in Google Calendar.
private struct GoogleCalendarGroup: View {
    @Environment(AppModel.self) private var model
    @State private var connected = AccountSync.shared.isCalendarConnected
    @State private var working = false
    @State private var message: String?

    var body: some View {
        SettingsGroup(title: "Google Calendar", footer: message ?? "Due dates go into a \"Skyward Plus\" calendar of their own. The app can only see and change that calendar.") {
            SettingRow(title: connected ? "Connected" : "Copy due dates to Google Calendar") {
                if working {
                    ProgressView().controlSize(.small)
                } else if connected {
                    Button("Disconnect", role: .destructive) {
                        Task {
                            working = true
                            await AccountSync.shared.disconnectCalendar()
                            connected = false
                            working = false
                            message = nil
                        }
                    }
                } else {
                    Button("Connect…") {
                        Task {
                            working = true
                            do {
                                try await AccountSync.shared.connectCalendar()
                                connected = true
                                message = nil
                                model.exportDueDates()
                            } catch {
                                message = error.localizedDescription
                            }
                            working = false
                        }
                    }
                }
            }
        }
    }
}
