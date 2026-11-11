import Foundation
import SwiftUI
#if os(macOS)
import AppKit
import ServiceManagement
#endif

struct UpdateInfo: Equatable {
    var version: String
    var pageURL: URL
    var downloadURL: URL?
    var notes: String
}

extension AppModel {
    // MARK: Background sync

    /// Checks once a minute whether a background sync is due. The app keeps running
    /// in the menu bar when the window is closed, so this keeps grades fresh all day.
    func startScheduler() {
        schedulerTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncIfDue() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        schedulerTimer = timer
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.syncIfDue()
            self.rescheduleDueReminders()
        }
    }

    /// Syncs every student whose data is older than the chosen interval.
    func syncIfDue() {
        guard settings.backgroundSync, !isLocked, qmlativSignIn == nil else { return }
        let interval = TimeInterval(max(15, settings.syncMinutes) * 60)
        for profile in profiles where !profile.isDemo {
            if syncStates[profile.id]?.isSyncing == true { continue }
            if case .needsSignIn = syncStates[profile.id] ?? .idle { continue }
            if blockedAccounts.contains(profile.accountKey) { continue }
            let last = data(for: profile.id).lastSync ?? .distantPast
            if now().timeIntervalSince(last) >= interval - 30 {
                Task { await self.refresh(profile.id) }
            }
        }
    }

    var nextSyncDate: Date? {
        guard settings.backgroundSync, let last = data.lastSync else { return nil }
        return last.addingTimeInterval(TimeInterval(max(15, settings.syncMinutes) * 60))
    }

    // MARK: After every sync

    func afterSyncFeatures(_ id: UUID, previous: StudentData?, updated: StudentData) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let profile = profiles[index]
        let first = previous?.lastSync == nil
        var prefs = profile.prefs

        // Newly missing work, announced once per assignment.
        if let lit = updated.currentLit {
            var missing: [(course: String, title: String, key: String)] = []
            for course in updated.courses {
                guard let detail = updated.detail(course.id, lit) else { continue }
                for a in detail.assignments where a.missing {
                    let key = course.id + "|" + a.id
                    if !prefs.missingNotified.contains(key) {
                        missing.append((Str.titleCase(course.name), a.name, key))
                    }
                }
            }
            if !missing.isEmpty {
                // The first sync only records what is already missing; it does not alert.
                if !first, settings.notifyDueTomorrow {
                    Notifier.announceMissing(missing.map { ($0.course, $0.title) }, studentName: profile.firstName)
                }
                prefs.missingNotified.formUnion(missing.map { $0.key })
            }
        }

        // Classes that fell under their goal.
        for course in updated.courses {
            guard let goal = prefs.goals[course.id], let lit = updated.currentLit else { continue }
            let percent = updated.detail(course.id, lit)?.percent ?? course.grade(lit)?.number
            guard let percent else { continue }
            if percent + 1e-9 < goal {
                if !prefs.belowGoalNotified.contains(course.id) {
                    if settings.notifyBelowGoal, !first {
                        Notifier.announceBelowGoal(course: Str.titleCase(course.name), percent: percent, goal: goal, studentName: profile.firstName)
                    }
                    prefs.belowGoalNotified.insert(course.id)
                }
            } else {
                prefs.belowGoalNotified.remove(course.id)
            }
        }

        if prefs != profile.prefs {
            profiles[index].prefs = prefs
            save()
        }
        if id == active?.id {
            rescheduleDueReminders()
            exportDueDates()
            publishWidgetSnapshot()
        }
    }

    // MARK: Goals

    func goal(for courseID: String) -> Double? { prefs.goals[courseID] }

    func setGoal(_ value: Double?, for courseID: String) {
        updatePrefs { prefs in
            if let value { prefs.goals[courseID] = value } else { prefs.goals[courseID] = nil }
            prefs.belowGoalNotified.remove(courseID)
        }
    }

    /// Everything due soon that is not done: Skyward work and planner tasks.
    struct DueItem: Identifiable, Hashable {
        var id: String
        var title: String
        var course: String
        var due: Date
        var done: Bool
        var notes: String
    }

    var dueItems: [DueItem] {
        var items: [DueItem] = []
        let today = Calendar.current.startOfDay(for: now())
        for item in upcomingAssignments {
            guard let due = item.assignment.due, due >= today else { continue }
            items.append(DueItem(
                id: "sky|" + item.id, title: item.assignment.name, course: Str.titleCase(item.course.name),
                due: due, done: prefs.doneAssignments.contains(item.id),
                notes: item.assignment.category
            ))
        }
        for task in prefs.tasks where task.due >= today {
            let course = task.courseID.flatMap { course($0) }.map { Str.titleCase($0.name) } ?? ""
            items.append(DueItem(id: "task|" + task.id.uuidString, title: task.title, course: course, due: task.due, done: task.done, notes: task.notes))
        }
        return items.sorted { $0.due < $1.due }
    }

    func rescheduleDueReminders() {
        guard settings.notifyDueTomorrow, let profile = active else {
            Notifier.scheduleDueReminders([], studentName: "")
            return
        }
        Notifier.scheduleDueReminders(dueItems.filter { !$0.done }, studentName: profile.firstName)
    }

    // MARK: Calendar and Reminders

    func exportDueDates() {
        #if os(macOS)
        let target = settings.exportTarget
        let items = dueItems
        let student = active?.firstName ?? ""
        exportTask?.cancel()
        exportTask = Task {
            await CalendarExport.shared.sync(target: target, items: items, student: student)
        }
        #endif
    }

    // MARK: Login item

    func setLaunchAtLogin(_ on: Bool) {
        updateSettings { $0.launchAtLogin = on }
        #if os(macOS)
        LoginItem.sync(on)
        #endif
    }

    // MARK: Updates

    static let releasesAPI = URL(string: "https://api.github.com/repos/ninjex2009-code/skyward-plus/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Looks for a newer GitHub release. Automatic checks run at most once a day and stay quiet.
    func checkForUpdates(manual: Bool) async {
        if !manual, let last = settings.lastUpdateCheck, now().timeIntervalSince(last) < 86_400 { return }
        if manual { updateMessage = "Checking…" }
        var request = URLRequest(url: AppModel.releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SkywardPlus/\(AppModel.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            updateSettings { $0.lastUpdateCheck = self.now() }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
                if manual { updateMessage = "No releases have been published yet." }
                return
            }
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let assets = json["assets"] as? [[String: Any]] ?? []
            let dmg = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
            let download = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))
            if AppModel.isNewer(version, than: AppModel.currentVersion) {
                availableUpdate = UpdateInfo(version: version, pageURL: page, downloadURL: download, notes: json["body"] as? String ?? "")
                if manual { updateMessage = "Version \(version) is available." }
            } else {
                availableUpdate = nil
                if manual { updateMessage = "You're up to date (version \(AppModel.currentVersion))." }
            }
        } catch {
            if manual { updateMessage = "Couldn't reach GitHub. Check your connection and try again." }
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool { AppVersion.isNewer(a, than: b) }
}

#if os(macOS)
enum LoginItem {
    /// Registers or removes the app as a login item. macOS asks the person to
    /// approve it in System Settings the first time.
    static func sync(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on, service.status != .enabled { try service.register() }
            if !on, service.status == .enabled { try service.unregister() }
        } catch {
            // Not fatal: the switch stays as chosen and macOS shows the item under Login Items.
        }
    }

    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
}
#endif

extension AppModel {
    /// New or changed grades the student hasn't looked at since last closing the window.
    var unseenChangeCount: Int {
        let since = prefs.lastSeenAt ?? .distantPast
        return data.changes.filter { ($0.kind == .newGrade || $0.kind == .updatedGrade) && $0.date > since }.count
    }
}

extension AppModel {
    // MARK: Remembered district sign-in

    func hasRememberedSignIn(_ profile: Profile) -> Bool {
        Keychain.loadDistrict(address: profile.address) != nil
    }

    func rememberSignIn(username: String, password: String) {
        guard let profile = active else { return }
        Keychain.saveDistrict(DistrictCredentials(username: username, password: password), address: profile.address)
        blockedAccounts.remove(profile.accountKey)
        if case .needsSignIn = syncStates[profile.id] ?? .idle { syncStates[profile.id] = .idle }
    }

    func forgetSignIn() {
        guard let profile = active else { return }
        Keychain.remove(Keychain.districtKey(profile.address))
    }
}

#if os(macOS)
import WidgetKit
#endif

extension AppModel {
    /// Writes what the desktop widgets show, then asks them to redraw.
    func publishWidgetSnapshot() {
        #if os(macOS)
        guard let profile = active, let lit = selectedLit else { return }
        let list = courses(in: lit).filter { !gradeText($0, lit).isEmpty }
        let numbers = list.compactMap { percent($0, lit) }
        let gpa = GPA.compute(GPA.currentEntries(data: data, lit: lit, settings: prefs.gpa))
        let snapshot = WidgetSnapshot(
            student: profile.firstName,
            period: data.bucket(lit)?.displayName ?? lit,
            average: numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count),
            gpa: gpa.weighted,
            missing: missingAssignments.count,
            courses: list.map { course in
                let p = percent(course, lit)
                let below = goal(for: course.id).map { goal in (p ?? 101) < goal } ?? false
                return .init(name: Str.titleCase(course.name), grade: gradeText(course, lit), percent: p, belowGoal: below)
            },
            due: dueItems.filter { !$0.done }.prefix(10).map { .init(title: $0.title, course: $0.course, due: $0.due) },
            updated: data.lastSync ?? now()
        )
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// skywardplus://grades, skywardplus://planner (from widgets).
    func handle(url: URL) {
        switch url.host {
        case "planner": section = .planner
        case "grades": section = .grades
        default: section = .home
        }
    }
}
