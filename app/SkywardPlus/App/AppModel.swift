import Foundation
import Observation
import SwiftUI

enum SyncState: Equatable {
    case idle
    case syncing(String)
    case failed(String)
    /// Skyward wants the password or a security code again. Nothing retries until the user acts.
    case needsSignIn(String)
    /// Paused on purpose and will try again by itself (see the message for when).
    case waiting(String)

    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
}

/// Files under Application Support. Passwords are not here; they are in the Keychain.
struct Store {
    struct State: Codable {
        var profiles: [Profile]
        var settings: AppSettings
    }

    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else if let override = ProcessInfo.processInfo.environment["SKYWARDPLUS_HOME"], !override.isEmpty {
            self.directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base.appendingPathComponent("SkywardPlus", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    func loadState() -> State? { read(State.self, "state.json") }
    func saveState(_ state: State) { write(state, "state.json") }
    func loadData(_ id: UUID) -> StudentData? { read(StudentData.self, "data-\(id.uuidString).json") }
    func saveData(_ data: StudentData, _ id: UUID) { write(data, "data-\(id.uuidString).json") }

    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("data-\(id.uuidString).json"))
        try? FileManager.default.removeItem(at: avatarURL(id))
    }

    func avatarURL(_ id: UUID) -> URL { directory.appendingPathComponent("avatar-\(id.uuidString).png") }
}

/// The app's state: who is signed in, their Skyward data, and what they have set up.
@MainActor
@Observable
final class AppModel {
    var profiles: [Profile] = []
    var settings = AppSettings()
    private(set) var studentData: [UUID: StudentData] = [:]

    var syncStates: [UUID: SyncState] = [:]
    var isLocked = false
    /// The section on screen (sidebar selection, or the tab on iPhone).
    var section: AppSection = .home {
        didSet {
            // Bell, Teachers and Transcript are tabs inside another sidebar row.
            switch section {
            case .bell: scheduleTab = .bell
            case .teachers: scheduleTab = .teachers
            case .gpa: gradesTab = .gpa
            case .reports: gradesTab = .reportCard; if reportsTab == .transcript { reportsTab = .cards }
            case .transcript: gradesTab = .reportCard; reportsTab = .transcript
            default: break
            }
            if section.host != section { section = section.host }
        }
    }
    /// Set to present the sign-in sheet.
    var signInRequest: SignInRequest?
    /// Set to present the Qmlativ district web sign-in sheet.
    var qmlativSignIn: QmlativSignInSession?
    /// Set to present the First-Time Setup Wizard for the active student.
    var showOnboarding = false
    /// ⌘K search palette.
    var showPalette = false
    /// The full-screen first-run setup is on screen; the main window stays out of the way.
    var firstRunActive = false
    /// A class to push in the Grades section (set from search or the menu bar).
    var openCourse: String?
    /// Asks the planner to open its new-task sheet.
    var newTaskRequest = false
    /// Sub-tab inside merged sections (Schedule: classes/bell/teachers, Reports: cards/transcript).
    var scheduleTab: ScheduleTab = .classes
    var reportsTab: ReportsTab = .cards
    var gradesTab: GradesTab = .classes
    /// A newer release on GitHub, when one was found.
    var availableUpdate: UpdateInfo?
    /// One-line result of a manual update check.
    var updateMessage: String?
    /// What-if edits per "courseID|lit" of the active student. Not saved: they are scratch work.
    var whatIfs: [String: WhatIf] = [:]
    private(set) var loadingDetails: Set<String> = []
    private(set) var detailErrors: [String: String] = [:]
    /// Bumped when a profile picture changes so views reload it.
    private(set) var avatarVersion = 0

    @ObservationIgnored let store: Store
    @ObservationIgnored private var sessions: [String: SkywardSession] = [:]
    @ObservationIgnored private var qmlativEngines: [String: QmlativEngine] = [:]
    @ObservationIgnored private var accountTasks: [String: Task<Void, Never>] = [:]
    /// Accounts whose saved sign-in was refused. They are not tried again until the user signs in.
    @ObservationIgnored var blockedAccounts: Set<String> = []
    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored var schedulerTimer: Timer?
    /// Per account: no automatic sync before this time (after a failure or a pause).
    @ObservationIgnored var retryAfter: [String: Date] = [:]
    /// Per account: failures in a row, for backing off.
    @ObservationIgnored var failureStreak: [String: Int] = [:]
    /// Per account: the last sync that found the app signed in.
    @ObservationIgnored var lastGoodSync: [String: Date] = [:]
    /// Per student: the last sync that read every class and attendance.
    @ObservationIgnored var lastFullSync: [UUID: Date] = [:]
    #if os(macOS)
    /// Keeps macOS from napping the app, so the timer fires on time with the window closed.
    @ObservationIgnored var awakeActivity: NSObjectProtocol?
    #endif
    @ObservationIgnored var exportTask: Task<Void, Never>?

    init(store: Store = Store()) {
        self.store = store
        if let state = store.loadState() {
            profiles = state.profiles
            settings = state.settings
            for profile in profiles {
                if let data = store.loadData(profile.id) { studentData[profile.id] = data }
            }
        }
        if settings.activeProfileID == nil || !profiles.contains(where: { $0.id == settings.activeProfileID }) {
            settings.activeProfileID = profiles.first?.id
        }
        isLocked = settings.biometricLock && !profiles.isEmpty
    }

    // MARK: Current student

    var active: Profile? { profiles.first { $0.id == settings.activeProfileID } ?? profiles.first }
    var data: StudentData { active.flatMap { studentData[$0.id] } ?? StudentData() }
    var prefs: ProfilePrefs { active?.prefs ?? ProfilePrefs() }
    /// The accent colour comes from the theme.
    var theme: ThemeColor { settings.backgroundTheme.accent }
    var syncState: SyncState { active.flatMap { syncStates[$0.id] } ?? .idle }

    func data(for id: UUID) -> StudentData { studentData[id] ?? StudentData() }

    /// The marking period on screen: the one picked by hand if it still exists, else the current one.
    var selectedLit: String? {
        let d = data
        if let picked = prefs.selectedLit, d.buckets.contains(where: { $0.lit == picked }) { return picked }
        return d.currentLit
    }

    var selectedBucket: TermBucket? { selectedLit.flatMap { data.bucket($0) } }

    /// Classes in the student's own order, hidden ones left out.
    var courses: [Course] { ordered(data.courses).filter { !prefs.hiddenCourses.contains($0.id) } }
    var allCoursesOrdered: [Course] { ordered(data.courses) }

    private func ordered(_ list: [Course]) -> [Course] {
        let order = prefs.courseOrder
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return list.enumerated().sorted { a, b in
            let ra = rank[a.element.id] ?? (order.count + a.element.periodNumber * 100 + a.offset)
            let rb = rank[b.element.id] ?? (order.count + b.element.periodNumber * 100 + b.offset)
            return ra < rb
        }.map { $0.element }
    }

    func course(_ id: String) -> Course? { data.courses.first { $0.id == id } }

    /// Classes that have a column for this marking period.
    func courses(in lit: String) -> [Course] {
        courses.filter { $0.grade(lit) != nil }
    }

    // MARK: Grades

    func detail(_ courseID: String, _ lit: String) -> GradeDetail? { data.detail(courseID, lit) }

    private func whatIfKey(_ courseID: String, _ lit: String) -> String { StudentData.detailKey(courseID, lit) }

    func whatIf(_ courseID: String, _ lit: String) -> WhatIf { whatIfs[whatIfKey(courseID, lit)] ?? WhatIf() }

    func setWhatIf(_ value: WhatIf, _ courseID: String, _ lit: String) {
        whatIfs[whatIfKey(courseID, lit)] = value.isEmpty ? nil : value
    }

    func gradingMode(_ courseID: String) -> GradingMode { prefs.gradingModes[courseID] ?? .auto }

    /// The computed average of a class, with any what-if applied.
    func result(_ courseID: String, _ lit: String, includeWhatIf: Bool = true) -> CourseResult? {
        guard let detail = detail(courseID, lit) else { return nil }
        return GradeMath.compute(detail, mode: gradingMode(courseID), whatIf: includeWhatIf ? whatIf(courseID, lit) : WhatIf())
    }

    /// The number to show for a class: Skyward's exact score when the assignment list
    /// is loaded, otherwise the rounded grade from the gradebook grid.
    func percent(_ course: Course, _ lit: String) -> Double? {
        if let exact = detail(course.id, lit)?.percent { return exact }
        return course.grade(lit)?.number
    }

    /// Text for a grade bubble: "94.6", "95", or a letter such as "A-".
    func gradeText(_ course: Course, _ lit: String) -> String {
        if let p = percent(course, lit) { return Fmt.percent(p) }
        return course.grade(lit)?.text ?? ""
    }

    /// Change in a class average since the app was last closed.
    func changeSinceSeen(_ course: Course, _ lit: String) -> Double? {
        guard let now = percent(course, lit), let then = prefs.lastSeenGrades[StudentData.detailKey(course.id, lit)] else { return nil }
        let delta = now - then
        return abs(delta) >= 0.05 ? delta : nil
    }

    /// Remember today's averages so the next launch can show what moved.
    func markSeen() {
        guard active != nil else { return }
        var seen: [String: Double] = [:]
        for course in data.courses {
            for grade in course.grades {
                if let p = percent(course, grade.lit) { seen[StudentData.detailKey(course.id, grade.lit)] = p }
            }
        }
        updatePrefs { prefs in
            prefs.lastSeenGrades = seen
            prefs.lastSeenAt = self.now()
        }
    }

    /// Changes found since the app was last closed, newest first.
    var recentChanges: [GradeChange] {
        let cutoff = prefs.lastSeenAt ?? .distantPast
        let floor = now().addingTimeInterval(-14 * 86_400)
        return data.changes.filter { $0.date > min(cutoff, floor) || $0.date > floor }
    }

    // MARK: Assignments across classes

    struct DatedAssignment: Identifiable, Hashable {
        var course: Course
        var assignment: Assignment
        var lit: String
        var id: String { course.id + "|" + assignment.id }
    }

    private func allAssignments() -> [DatedAssignment] {
        guard let lit = data.currentLit else { return [] }
        var out: [DatedAssignment] = []
        for course in courses {
            guard let detail = detail(course.id, lit) else { continue }
            for a in detail.assignments { out.append(DatedAssignment(course: course, assignment: a, lit: lit)) }
        }
        return out
    }

    /// Work that is posted but not graded yet and due today or later.
    var upcomingAssignments: [DatedAssignment] {
        let today = Calendar.current.startOfDay(for: now())
        return allAssignments()
            .filter { item in
                guard let due = item.assignment.due else { return false }
                return due >= today && !item.assignment.isGraded && !item.assignment.missing
            }
            .sorted { ($0.assignment.due ?? .distantFuture) < ($1.assignment.due ?? .distantFuture) }
    }

    var missingAssignments: [DatedAssignment] {
        allAssignments().filter { $0.assignment.missing }
            .sorted { ($0.assignment.due ?? .distantPast) > ($1.assignment.due ?? .distantPast) }
    }

    /// Skyward work due on one day, for the planner.
    func assignments(dueOn day: Date) -> [DatedAssignment] {
        allAssignments().filter { item in
            guard let due = item.assignment.due else { return false }
            return Calendar.current.isDate(due, inSameDayAs: day)
        }
    }

    // MARK: Changing things

    func save() {
        store.saveState(Store.State(profiles: profiles, settings: settings))
        AccountSync.shared.modelChanged(self)
    }

    // These work on a copy and write it back. Changing the stored value in place
    // would hold exclusive access to it while `change` runs, and a closure that
    // reads anything from the model (as most do) would then crash the app.
    func updateActive(_ change: (inout Profile) -> Void) {
        guard let id = active?.id, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        var profile = profiles[index]
        change(&profile)
        guard let current = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[current] = profile
        save()
    }

    func updatePrefs(_ change: (inout ProfilePrefs) -> Void) {
        updateActive { change(&$0.prefs) }
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        let before = settings
        settings = copy
        save()
        if before.backgroundSync != copy.backgroundSync { updateAwakeActivity() }
        #if os(macOS)
        if before.searchShortcut != copy.searchShortcut {
            QuickSearch.shared.apply(QuickSearch.Shortcut(rawValue: copy.searchShortcut) ?? .off)
        }
        #endif
        if before.notifySummary != copy.notifySummary || before.summaryHour != copy.summaryHour { rescheduleDueReminders() }
    }

    func setActive(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        settings.activeProfileID = id
        whatIfs = [:]
        save()
    }

    func removeProfile(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        for task in profile.prefs.tasks { Notifier.cancel(taskID: task.id) }
        profiles.removeAll { $0.id == id }
        studentData[id] = nil
        syncStates[id] = nil
        store.remove(id)
        // The saved password goes when the last student of that account goes.
        if !profiles.contains(where: { $0.accountKey == profile.accountKey }) {
            if !profile.isDemo { Keychain.remove(profile.accountKey) }
            sessions[profile.accountKey] = nil
            if let engine = qmlativEngines[profile.accountKey] ?? qmlativEngines[profile.address] {
                qmlativEngines[profile.accountKey] = nil
                qmlativEngines[profile.address] = nil
                Task { await engine.signOut() }
            }
            blockedAccounts.remove(profile.accountKey)
        }
        if settings.activeProfileID == id { settings.activeProfileID = profiles.first?.id }
        if profiles.isEmpty { isLocked = false }
        save()
    }

    // MARK: Profile pictures

    func setAvatar(_ pngData: Data?, for id: UUID) {
        let url = store.avatarURL(id)
        if let pngData {
            try? pngData.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index].avatarFile = pngData == nil ? nil : url.lastPathComponent
            save()
        }
        avatarVersion += 1
    }

    func avatarData(for id: UUID) -> Data? {
        guard profiles.first(where: { $0.id == id })?.avatarFile != nil else { return nil }
        return try? Data(contentsOf: store.avatarURL(id))
    }

    // MARK: Signing in

    /// Signs in to a district and adds the student (or every child of a parent account).
    /// Throws `SkywardError.mfaRequired` when Skyward asks for a security code: call
    /// again with the code.
    func signIn(address: String, districtName: String, username: String, password: String,
                securityCode: String? = nil, trustDevice: Bool = false) async throws {
        if SkywardEndpoint.looksLikeQmlativ(address) { throw SkywardError.qmlativ }
        guard let endpoint = SkywardEndpoint.parse(address) else { throw SkywardError.notSkyward }
        let normalized = endpoint.loginURL.absoluteString
        let user = username.trimmingCharacters(in: .whitespaces)
        let key = normalized + "|" + user

        let session = SkywardSession(endpoint: endpoint, transport: URLSessionTransport())
        let saved = Keychain.load(key)
        if let cookie = saved?.deviceCookie { await session.restoreDeviceCookie(cookie) }
        let result = try await session.login(username: user, password: password, securityCode: securityCode, trustDevice: trustDevice)

        Keychain.save(AccountSecret(password: password, deviceCookie: result.deviceCookie ?? saved?.deviceCookie), for: key)
        sessions[key] = session
        blockedAccounts.remove(key)

        var added: [UUID] = []
        if result.home.children.isEmpty {
            added.append(upsertProfile(address: normalized, districtName: districtName, username: user, childID: nil, name: result.home.userName))
        } else {
            for child in result.home.children {
                added.append(upsertProfile(address: normalized, districtName: districtName, username: user, childID: child.id, name: child.name))
            }
        }
        if let first = added.first { settings.activeProfileID = first }
        whatIfs = [:]
        save()
        for id in added { await refresh(id) }
    }

    /// Adopts a session signed in through the embedded SSO web browser.
    func adoptWebSignIn(
        address: String,
        districtName: String,
        codes: SkywardSession.Codes,
        home: SkywardParser.HomeInfo
    ) async throws {
        guard let endpoint = SkywardEndpoint.parse(address) else { throw SkywardError.notSkyward }
        let normalized = endpoint.loginURL.absoluteString
        let user = home.userName.isEmpty ? "SSO Account" : home.userName
        let key = normalized + "|" + user

        let session = SkywardSession(endpoint: endpoint, transport: URLSessionTransport())
        await session.adopt(codes)
        sessions[key] = session
        blockedAccounts.remove(key)

        var added: [UUID] = []
        if home.children.isEmpty {
            added.append(upsertProfile(address: normalized, districtName: districtName, username: user, childID: nil, name: home.userName))
        } else {
            for child in home.children {
                added.append(upsertProfile(address: normalized, districtName: districtName, username: user, childID: child.id, name: child.name))
            }
        }
        if let first = added.first { settings.activeProfileID = first }
        whatIfs = [:]
        save()
        for id in added { await refresh(id) }
    }

    func isQmlativ(_ profile: Profile) -> Bool {
        SkywardEndpoint.looksLikeQmlativ(profile.address)
    }

    var isActiveQmlativ: Bool {
        guard let active else { return false }
        return isQmlativ(active)
    }

    private func qmlativEngine(for profile: Profile) throws -> QmlativEngine {
        if let existing = qmlativEngines[profile.accountKey] {
            return existing
        }
        guard let endpoint = SkywardEndpoint.parse(profile.address) else {
            throw SkywardError.notSkyward
        }
        let baseStr = endpoint.base.absoluteString
        if let byBase = qmlativEngines[baseStr] {
            qmlativEngines[profile.accountKey] = byBase
            return byBase
        }
        let engine = QmlativEngine(base: endpoint.base)
        qmlativEngines[profile.accountKey] = engine
        qmlativEngines[baseStr] = engine
        return engine
    }

    func requestReauth(_ profile: Profile? = nil) {
        let target = profile ?? active
        if let target, isQmlativ(target) {
            beginQmlativSignIn(address: target.address, districtName: target.districtName)
        } else {
            signInRequest = SignInRequest(reauth: target)
        }
    }

    func beginQmlativSignIn(address: String, districtName: String) {
        guard let endpoint = SkywardEndpoint.parse(address) else { return }
        let baseStr = endpoint.base.absoluteString
        let existingProfile = profiles.first { $0.address == baseStr || SkywardEndpoint.parse($0.address)?.base == endpoint.base }
        let engine: QmlativEngine
        if let prof = existingProfile, let e = qmlativEngines[prof.accountKey] {
            engine = e
        } else if let e = qmlativEngines[baseStr] {
            engine = e
        } else {
            let e = QmlativEngine(base: endpoint.base)
            qmlativEngines[baseStr] = e
            if let prof = existingProfile {
                qmlativEngines[prof.accountKey] = e
            }
            engine = e
        }
        signInRequest = nil
        qmlativSignIn = QmlativSignInSession(engine: engine, address: baseStr, districtName: districtName)
        Task {
            await engine.load("")
        }
    }

    func cancelQmlativSignIn() {
        qmlativSignIn = nil
    }

    func finishQmlativSignIn() async {
        guard let pending = qmlativSignIn else { return }
        let st = await pending.engine.state()
        let baseStr = pending.engine.base.absoluteString
        let existingIdx = profiles.firstIndex { $0.address == baseStr || SkywardEndpoint.parse($0.address)?.base == pending.engine.base }
        let fallbackName = existingIdx.map { profiles[$0].skywardName.isEmpty ? profiles[$0].username : profiles[$0].skywardName } ?? "Student"
        let resolvedName = (st?.name.isEmpty == false) ? st!.name : fallbackName

        let profileID: UUID
        if let idx = existingIdx {
            let oldKey = profiles[idx].accountKey
            profiles[idx].address = baseStr
            profiles[idx].username = resolvedName
            profiles[idx].skywardName = resolvedName
            if !pending.districtName.isEmpty {
                profiles[idx].districtName = pending.districtName
            }
            blockedAccounts.remove(oldKey)
            profileID = profiles[idx].id
        } else {
            profileID = upsertProfile(
                address: baseStr,
                districtName: pending.districtName,
                username: resolvedName,
                childID: nil,
                name: resolvedName
            )
        }

        if let prof = profiles.first(where: { $0.id == profileID }) {
            qmlativEngines[prof.accountKey] = pending.engine
            qmlativEngines[baseStr] = pending.engine
            blockedAccounts.remove(prof.accountKey)
        }
        if let school = st?.school, !school.isEmpty {
            var currentData = studentData[profileID] ?? StudentData()
            currentData.profile.name = resolvedName
            currentData.profile.school = school
            studentData[profileID] = currentData
            store.saveData(currentData, profileID)
        }

        settings.activeProfileID = profileID
        whatIfs = [:]
        detailErrors = [:]
        qmlativSignIn = nil
        signInRequest = nil
        save()
        await refresh(profileID)
        if !firstRunActive, let active, !active.isDemo, !active.prefs.onboardingDone {
            showOnboarding = true
        }
    }

    #if DEBUG
    func saveDebugPage() async -> URL? {
        if let pending = qmlativSignIn {
            return await pending.engine.saveDebugPage(in: store.directory)
        }
        guard let profile = active, isQmlativ(profile), let engine = try? qmlativEngine(for: profile) else {
            return nil
        }
        return await engine.saveDebugPage(in: store.directory)
    }
    #endif

    private func upsertProfile(address: String, districtName: String, username: String, childID: String?, name: String) -> UUID {
        if let index = profiles.firstIndex(where: { $0.address == address && $0.username == username && $0.childID == childID }) {
            if !name.isEmpty { profiles[index].skywardName = name }
            if !districtName.isEmpty { profiles[index].districtName = districtName }
            return profiles[index].id
        }
        var profile = Profile(address: address, districtName: districtName, username: username, childID: childID, skywardName: name)
        let used = Set(profiles.map { $0.theme })
        profile.theme = ThemeColor.allCases.first { !used.contains($0) } ?? .sky
        profiles.append(profile)
        return profile.id
    }

    /// A sample student served by the built-in fake Skyward server. Nothing leaves the device.
    func addDemo() async {
        if let existing = profiles.first(where: { $0.isDemo }) {
            setActive(existing.id)
            return
        }
        var profile = Profile(address: FakeSkyward.address, districtName: "Lakeview High School (demo)", username: FakeSkyward.username, isDemo: true)
        profile.skywardName = "Jordan Rivera"
        let used = Set(profiles.map { $0.theme })
        profile.theme = ThemeColor.allCases.first { !used.contains($0) } ?? .sky
        profiles.append(profile)
        settings.activeProfileID = profile.id
        whatIfs = [:]
        save()
        await refresh(profile.id)
    }

    private func session(for profile: Profile) async throws -> SkywardSession {
        let key = profile.accountKey
        let session: SkywardSession
        if let existing = sessions[key] {
            session = existing
        } else {
            guard let endpoint = SkywardEndpoint.parse(profile.address) else { throw SkywardError.notSkyward }
            let transport: SkywardTransport = profile.isDemo ? FakeSkyward(now: now()) : URLSessionTransport()
            session = SkywardSession(endpoint: endpoint, transport: transport)
            sessions[key] = session
        }
        if await !session.isSignedIn {
            if profile.isDemo {
                try await session.login(username: FakeSkyward.username, password: FakeSkyward.password)
            } else {
                guard let secret = Keychain.load(key) else {
                    throw SkywardError.invalidLogin("Enter your Skyward password again to keep syncing.")
                }
                if let cookie = secret.deviceCookie { await session.restoreDeviceCookie(cookie) }
                let result = try await session.login(username: profile.username, password: secret.password)
                if let cookie = result.deviceCookie {
                    Keychain.save(AccountSecret(password: secret.password, deviceCookie: cookie), for: key)
                }
            }
        }
        await session.selectStudent(profile.childID)
        return session
    }

    // MARK: Syncing

    /// Refreshes one student (the active one by default). Students on the same
    /// account take turns, because they share one Skyward session.
    func refresh(_ id: UUID? = nil, background: Bool = false) async {
        guard let profile = profiles.first(where: { $0.id == (id ?? active?.id) }) else { return }
        if syncStates[profile.id]?.isSyncing == true { return }
        if blockedAccounts.contains(profile.accountKey) {
            syncStates[profile.id] = .needsSignIn("Sign in again to keep syncing.")
            return
        }
        syncStates[profile.id] = .syncing("Signing in")
        let previousTask = accountTasks[profile.accountKey]
        let task = Task { [weak self] in
            await previousTask?.value
            await self?.performRefresh(profile.id, background: background)
        }
        accountTasks[profile.accountKey] = task
        await task.value
    }

    func refreshAll() async {
        for profile in profiles { await refresh(profile.id) }
    }

    private func performRefresh(_ id: UUID, background: Bool) async {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        let key = profile.accountKey
        let started = now()
        // In the background, a sign-out right after a good sync means the student
        // signed in to Skyward somewhere else; signing straight back in would kick them.
        let mayReSignIn = !background || started.timeIntervalSince(lastGoodSync[key] ?? .distantPast) > 12 * 60
        let full = !background || started.timeIntervalSince(lastFullSync[id] ?? .distantPast) >= 30 * 60
        do {
            let previous = studentData[id]
            let updated: StudentData
            if isQmlativ(profile) {
                let engine = try qmlativEngine(for: profile)
                do {
                    updated = try await SyncEngine.syncQmlativ(
                        engine: engine, credentials: Keychain.usableDistrict(address: profile.address),
                        previous: previous, now: now(), mayReSignIn: mayReSignIn, full: full
                    ) { [weak self] step in
                        Task { @MainActor in
                            guard let self, self.syncStates[id]?.isSyncing == true else { return }
                            self.syncStates[id] = .syncing(step)
                        }
                    }
                } catch {
                    // A refused saved sign-in is retired for good, not just for this run.
                    if engine.lastSilentRejected { Keychain.markDistrictRejected(address: profile.address) }
                    throw error
                }
            } else {
                let session = try await session(for: profile)
                updated = try await SyncEngine.sync(session: session, previous: previous, now: now()) { [weak self] step in
                    Task { @MainActor in
                        guard let self, self.syncStates[id]?.isSyncing == true else { return }
                        self.syncStates[id] = .syncing(step)
                    }
                }
            }
            studentData[id] = updated
            store.saveData(updated, id)
            afterSync(id, previous: previous, updated: updated)
            syncStates[id] = .idle
            retryAfter[key] = nil
            failureStreak[key] = 0
            lastGoodSync[key] = now()
            if full || !isQmlativ(profile) { lastFullSync[id] = now() }
        } catch let pause as QmlativPause {
            let wait: TimeInterval
            let message: String
            switch pause {
            case .signedInElsewhere:
                wait = 30 * 60
                message = "Skyward is open somewhere else, so checks pause until %@."
            case .signInUnreachable:
                wait = backOff(key)
                message = "Couldn't reach the district sign-in. Trying again at %@."
            }
            let when = now().addingTimeInterval(wait)
            retryAfter[key] = when
            syncStates[id] = .waiting(String(format: message, Fmt.clock(when)))
        } catch let error as SkywardError {
            switch error {
            case .invalidLogin, .mfaRequired, .mfaInvalid, .sessionExpired, .notSignedIn, .ssoOnly:
                blockedAccounts.insert(profile.accountKey)
                sessions[profile.accountKey] = nil
                let message = isQmlativ(profile) ? "Sign in again to keep syncing." : error.localizedDescription
                syncStates[id] = .needsSignIn(message)
            default:
                retryAfter[key] = now().addingTimeInterval(backOff(key))
                syncStates[id] = .failed(error.localizedDescription)
            }
        } catch {
            retryAfter[key] = now().addingTimeInterval(backOff(key))
            syncStates[id] = .failed(error.localizedDescription)
        }
    }

    /// 5, 10, 20, then 30 minutes between automatic tries after failures in a row.
    private func backOff(_ key: String) -> TimeInterval {
        let streak = (failureStreak[key] ?? 0) + 1
        failureStreak[key] = streak
        return TimeInterval(min(30, 5 << min(streak - 1, 3)) * 60)
    }

    private func afterSync(_ id: UUID, previous: StudentData?, updated: StudentData) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        var changed = false
        if profiles[index].skywardName.isEmpty, !updated.profile.name.isEmpty {
            profiles[index].skywardName = updated.profile.name
            changed = true
        }
        // A first bell schedule from the class times Skyward lists.
        if profiles[index].prefs.bell.schedules.isEmpty, let schedule = BellMath.defaultSchedule(from: updated.courses) {
            profiles[index].prefs.bell.schedules = [schedule]
            for weekday in 2...6 { profiles[index].prefs.bell.weekdays[weekday] = schedule.id }
            changed = true
        }
        if profiles[index].prefs.lastSeenAt == nil {
            profiles[index].prefs.lastSeenAt = now()
            changed = true
        }
        if changed { save() }

        if settings.notifyNewGrades, previous?.lastSync != nil {
            let known = Set((previous?.changes ?? []).map { $0.id })
            let fresh = updated.changes.filter { !known.contains($0.id) }
            if !fresh.isEmpty {
                var averages: [String: Double] = [:]
                if let lit = updated.currentLit {
                    for course in updated.courses {
                        if let value = updated.detail(course.id, lit)?.percent ?? course.grade(lit)?.number { averages[course.id] = value }
                    }
                }
                for alert in AlertText.grades(fresh, averages: averages) { Notifier.post(alert) }
            }
        }
        afterSyncFeatures(id, previous: previous, updated: updated)
    }

    /// Loads the assignment list for a class and marking period when it is first opened.
    func ensureDetail(_ courseID: String, _ lit: String, force: Bool = false) async {
        guard let profile = active else { return }
        let key = StudentData.detailKey(courseID, lit)
        if loadingDetails.contains(key) { return }
        if !force, studentData[profile.id]?.details[key] != nil { return }
        guard let course = course(courseID), let grade = course.grade(lit), grade.hasDetail else { return }
        if blockedAccounts.contains(profile.accountKey) {
            if force {
                // The person asked to try again: one attempt, then blocked again if it fails.
                blockedAccounts.remove(profile.accountKey)
            } else {
                // Say why, instead of looking like the class has no assignments.
                detailErrors[key] = "Sign in again to see assignments."
                return
            }
        }
        loadingDetails.insert(key)
        detailErrors[key] = nil
        defer { loadingDetails.remove(key) }
        // One Skyward session per account: wait for a sync that is using it, and
        // make the next sync wait for this. Otherwise the two navigate the same
        // page out from under each other and the class fails to open.
        let previousTask = accountTasks[profile.accountKey]
        let work = Task { @MainActor [weak self] in
            await previousTask?.value
            await self?.fetchDetail(profile: profile, courseID: courseID, lit: lit, key: key)
        }
        accountTasks[profile.accountKey] = work
        await work.value
    }

    private func fetchDetail(profile: Profile, courseID: String, lit: String, key: String) async {
        guard let course = course(courseID), let grade = course.grade(lit) else { return }
        if blockedAccounts.contains(profile.accountKey) {
            detailErrors[key] = "Sign in again to keep syncing."
            return
        }
        do {
            if isQmlativ(profile) {
                guard !grade.bucket.isEmpty else {
                    detailErrors[key] = "Skyward did not return assignments for this marking period."
                    return
                }
                let engine = try qmlativEngine(for: profile)
                let currentPath = (await engine.state())?.path ?? ""
                // Also reload a gradebook first opened in the phone-sized sign-in view:
                // Skyward keeps its narrow layout, and classes won't open in it.
                if !currentPath.localizedCaseInsensitiveContains("/Grading/StudentSection/") || engine.loadedNarrow {
                    await engine.load("Grading/StudentSection/StudentAccess")
                }
                if (await engine.state())?.signedIn != true {
                    if !(await engine.silentSignIn(credentials: Keychain.usableDistrict(address: profile.address))) {
                        if engine.lastSilentRejected { Keychain.markDistrictRejected(address: profile.address) }
                        blockedAccounts.insert(profile.accountKey)
                        syncStates[profile.id] = .needsSignIn("Sign in again to keep syncing.")
                        detailErrors[key] = "Sign in again to keep syncing."
                        return
                    }
                    if !((await engine.state())?.path.localizedCaseInsensitiveContains("/Grading/StudentSection/") ?? false) {
                        await engine.load("Grading/StudentSection/StudentAccess")
                    }
                }
                if (await engine.state())?.mobile == true,
                   !(await engine.replaceMobileSession(credentials: Keychain.usableDistrict(address: profile.address))) {
                    blockedAccounts.insert(profile.accountKey)
                    syncStates[profile.id] = .needsSignIn("Sign in again to keep syncing.")
                    detailErrors[key] = "Sign in again to see assignments."
                    return
                }
                // Wait until the gradebook has actually drawn before clicking into it.
                _ = try await engine.grid()
                var panel: QmlPanel
                do {
                    panel = try await engine.open(bucketID: grade.bucket, weights: true)
                } catch {
                    // The page can be rebuilt with new cell ids since the last sync:
                    // reload it, find this class again, and try once more.
                    await engine.load("Grading/StudentSection/StudentAccess")
                    let fresh = QmlativMapper.gradebook(try await engine.grid())
                    let bucket = fresh.courses.first(where: { $0.id == courseID })?.grade(lit)?.bucket ?? ""
                    panel = try await engine.open(bucketID: bucket.isEmpty ? grade.bucket : bucket, weights: true)
                }
                if var detail = QmlativMapper.detail(panel, courseID: courseID, lit: lit, bucket: grade.bucket, now: now()) {
                    detail.courseName = course.name
                    studentData[profile.id]?.details[key] = detail
                    if !detail.teacher.isEmpty,
                       let cIdx = studentData[profile.id]?.courses.firstIndex(where: { $0.id == courseID }),
                       studentData[profile.id]?.courses[cIdx].teacher.isEmpty == true {
                        studentData[profile.id]?.courses[cIdx].teacher = detail.teacher
                    }
                    if let current = studentData[profile.id] { store.saveData(current, profile.id) }
                } else {
                    detailErrors[key] = "Skyward did not return assignments for this marking period."
                }
            } else {
                let session = try await session(for: profile)
                if let detail = try await SyncEngine.loadDetail(session: session, data: data(for: profile.id), courseID: courseID, lit: lit, now: now()) {
                    studentData[profile.id]?.details[key] = detail
                    if let current = studentData[profile.id] { store.saveData(current, profile.id) }
                } else {
                    detailErrors[key] = "Skyward did not return assignments for this marking period."
                }
            }
        } catch {
            detailErrors[key] = error.localizedDescription
        }
    }

    func isLoadingDetail(_ courseID: String, _ lit: String) -> Bool { loadingDetails.contains(StudentData.detailKey(courseID, lit)) }
    func detailError(_ courseID: String, _ lit: String) -> String? { detailErrors[StudentData.detailKey(courseID, lit)] }

    /// Extra facts Skyward keeps about one assignment (dates, max score, description).
    func assignmentInfo(_ assignment: Assignment) async -> AssignmentInfo? {
        guard let profile = active, !isQmlativ(profile),
              let aid = assignment.aid, let gid = assignment.gid, let sid = assignment.sid,
              !aid.isEmpty, !blockedAccounts.contains(profile.accountKey) else { return nil }
        do {
            let session = try await session(for: profile)
            let info = SkywardParser.assignmentInfo(try await session.assignmentInfoPage(assignmentID: aid, gradebookID: gid, studentID: sid))
            return info.fields.isEmpty ? nil : info
        } catch {
            return nil
        }
    }

    // MARK: Planner

    func saveTask(_ task: PlannerTask) {
        updatePrefs { prefs in
            if let index = prefs.tasks.firstIndex(where: { $0.id == task.id }) {
                prefs.tasks[index] = task
            } else {
                prefs.tasks.append(task)
            }
        }
        let name = task.courseID.flatMap { course($0) }.map { Str.titleCase($0.name) }
        Notifier.schedule(task: task, courseName: name)
    }

    func deleteTask(_ id: UUID) {
        updatePrefs { $0.tasks.removeAll { $0.id == id } }
        Notifier.cancel(taskID: id)
    }

    func toggleTask(_ id: UUID) {
        guard var task = prefs.tasks.first(where: { $0.id == id }) else { return }
        task.done.toggle()
        saveTask(task)
    }

    func toggleAssignmentDone(_ item: DatedAssignment) {
        updatePrefs { prefs in
            if prefs.doneAssignments.contains(item.id) { prefs.doneAssignments.remove(item.id) } else { prefs.doneAssignments.insert(item.id) }
        }
    }

    func tasks(dueOn day: Date) -> [PlannerTask] {
        prefs.tasks.filter { Calendar.current.isDate($0.due, inSameDayAs: day) }
            .sorted { ($0.done ? 1 : 0, $0.due) < ($1.done ? 1 : 0, $1.due) }
    }

    // MARK: Bell schedule

    func updateBell(_ change: (inout BellConfig) -> Void) {
        updatePrefs { change(&$0.bell) }
        Notifier.rescheduleBell(config: prefs.bell)
    }

    // MARK: Teachers

    struct Teacher: Identifiable, Hashable {
        var name: String
        var courses: [Course]
        var email: String?
        var id: String { name }
    }

    var teachers: [Teacher] {
        var order: [String] = []
        var byName: [String: [Course]] = [:]
        for course in courses where !course.teacher.isEmpty {
            if byName[course.teacher] == nil { order.append(course.teacher) }
            byName[course.teacher, default: []].append(course)
        }
        let p = prefs
        return order.map { name in
            let saved = p.teacherEmails[name].flatMap { $0.isEmpty ? nil : $0 }
            return Teacher(name: name, courses: byName[name] ?? [], email: saved ?? p.emailPattern.address(for: name, domain: p.emailDomain))
        }
    }

    // MARK: Lock

    func lockIfNeeded() {
        if settings.biometricLock, !profiles.isEmpty { isLocked = true }
    }

    func unlock() async {
        guard isLocked else { return }
        if await Biometrics.authenticate(reason: "Unlock Skyward Plus") { isLocked = false }
    }
}

/// Number formatting shared by the screens.
enum Fmt {
    /// "94.56" -> "94.6", "95.0" -> "95"
    static func percent(_ value: Double, digits: Int = 1) -> String {
        let scale = pow(10.0, Double(digits))
        let rounded = (value * scale).rounded() / scale
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.\(digits)f", rounded)
    }

    static func points(_ value: Double) -> String { SyncEngine.trim(value) }

    static func signed(_ value: Double, digits: Int = 1) -> String {
        (value >= 0 ? "+" : "−") + percent(abs(value), digits: digits)
    }

    static func gpa(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }

    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    /// "4:10 PM" in the reader's own clock style.
    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func shortDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    /// "Today", "Tomorrow", "Yesterday", or "Wed, Nov 12".
    static func relativeDay(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return day(date)
    }

    /// "today", "tomorrow", "yesterday", or "Wed, Nov 12" for use mid-sentence.
    static func dueDay(_ date: Date, now: Date = Date()) -> String {
        let text = relativeDay(date, now: now)
        return ["Today", "Tomorrow", "Yesterday"].contains(text) ? text.lowercased() : text
    }

    static func ago(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never" }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86_400 { return "\(seconds / 3600) hr ago" }
        return shortDay(date)
    }
}
