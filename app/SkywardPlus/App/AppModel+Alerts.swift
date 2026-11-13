import Foundation
import UserNotifications

extension AppModel {
    // MARK: Evening summary

    /// The evening the next summary belongs to: today until the summary hour, then tomorrow.
    func nextEveningDay() -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        let fire = calendar.date(bySettingHour: settings.summaryHour, minute: 0, second: 0, of: today) ?? today
        return now() < fire ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today)
    }

    /// What the evening note says for the given day, from what the app knows now.
    func eveningAlert(for day: Date) -> Alert? {
        let calendar = Calendar.current
        let changesToday = data.changes.filter {
            calendar.isDate($0.date, inSameDayAs: day) && ($0.kind == .newGrade || $0.kind == .updatedGrade)
        }
        var classes: [String] = []
        for change in changesToday where !classes.contains(change.courseName) { classes.append(change.courseName) }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        let due = dueItems.filter { !$0.done && calendar.isDate($0.due, inSameDayAs: tomorrow) }
        var underGoal: [(course: String, percent: Double, goal: Double)] = []
        if let lit = data.currentLit {
            for course in data.courses {
                guard let goal = prefs.goals[course.id],
                      let percent = detail(course.id, lit)?.percent ?? course.grade(lit)?.number,
                      percent + 1e-9 < goal else { continue }
                underGoal.append((Str.titleCase(course.name), percent, goal))
            }
        }
        let facts = AlertText.EveningFacts(
            newGradesToday: changesToday.count,
            changedClasses: classes,
            missing: missingAssignments.map { $0.assignment.name },
            dueTomorrow: due.map { ($0.title, $0.course) },
            underGoal: underGoal,
            checkedToday: data.lastSync.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        )
        return AlertText.evening(facts)
    }

    /// One quick check of every student, for iOS background refresh.
    func backgroundCheck() async {
        guard settings.backgroundSync, !isLocked else { return }
        // Grades another device already read are the cheapest, kindest update:
        // no Skyward sign-in, so no one gets signed out.
        await AccountSync.shared.sync(model: self)
        for profile in profiles where !profile.isDemo {
            let last = data(for: profile.id).lastSync ?? .distantPast
            if now().timeIntervalSince(last) < syncInterval { continue }
            if blockedAccounts.contains(profile.accountKey) { continue }
            if let wait = retryAfter[profile.accountKey], now() < wait { continue }
            if Task.isCancelled { return }
            await refresh(profile.id, background: true)
        }
    }

    // MARK: Phone relay

    var phoneRelayConfig: PhoneRelay.Config? {
        let topic = settings.phoneRelayTopic.trimmingCharacters(in: .whitespaces)
        guard PhoneRelay.isValid(topic) else { return nil }
        return PhoneRelay.Config(topic: topic, includeScores: settings.phoneRelayScores)
    }

    /// Scheduled alerts fire on this Mac by themselves; the phone copy of the
    /// evening note is sent from here when its time comes (checked every minute).
    func relayScheduledAlerts() {
        #if os(macOS)
        Notifier.relay = phoneRelayConfig
        guard let config = phoneRelayConfig, active != nil else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        guard let fire = calendar.date(bySettingHour: settings.summaryHour, minute: 0, second: 0, of: today),
              now() >= fire, now().timeIntervalSince(fire) < 3 * 3600 else { return }
        let stamp = "relay.evening." + ISO8601DateFormatter().string(from: today)
        guard !UserDefaults.standard.bool(forKey: stamp) else { return }
        UserDefaults.standard.set(true, forKey: stamp)

        if settings.notifySummary, let alert = eveningAlert(for: today) {
            PhoneRelay.send(alert, config: config)
        } else if settings.notifyDueTomorrow {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            let due = dueItems.filter { !$0.done && calendar.isDate($0.due, inSameDayAs: tomorrow) }
            guard !due.isEmpty else { return }
            let title = due.count == 1 ? "Due tomorrow: " + due[0].title : "\(due.count) things due tomorrow"
            let body = due.prefix(4).map { $0.course.isEmpty ? $0.title : $0.course + ": " + $0.title }.joined(separator: "\n")
            PhoneRelay.send(Alert(id: stamp, title: title, body: body, plainTitle: title, plainBody: body, courseID: nil, thread: "due"), config: config)
        }
        #endif
    }

    // MARK: Permission and testing

    /// Asks once, the first time the app runs with any alert switched on.
    func askForNotificationsIfNeeded() async {
        Notifier.relay = phoneRelayConfig
        Notifier.gradeSound = settings.soundsOn && settings.soundGradeChimes
            ? UNNotificationSound(named: UNNotificationSoundName("chime.wav")) : nil
        let anyOn = settings.notifyNewGrades || settings.notifyMissing || settings.notifyDueTomorrow
            || settings.notifyBelowGoal || settings.notifySummary
        guard anyOn, active != nil, settings.helloShown else { return }
        if await Notifier.authorizationStatus() == .notDetermined {
            await Notifier.requestPermission()
        }
    }

    /// Posts a sample alert (and sends it to the phone when that is set up).
    func sendTestAlert() async -> Bool {
        let allowed = await Notifier.requestPermission()
        let relay = phoneRelayConfig
        #if os(macOS)
        Notifier.post(AlertText.test(relaying: relay != nil), relay: .some(relay))
        #else
        Notifier.post(AlertText.test(relaying: false))
        #endif
        return allowed
    }

    /// Opens a class from a tapped alert or a skywardplus://class/<id> link.
    func openClassFromAlert(_ courseID: String?) {
        #if os(macOS)
        AppDelegate.shared?.showMain(section: .grades)
        #endif
        section = .grades
        if let courseID, courses.contains(where: { $0.id == courseID }) { openCourse = courseID }
    }
}

/// Shows alerts while the app is open too, and opens the class when one is tapped.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    @MainActor private weak var model: AppModel?

    @MainActor func attach(_ model: AppModel) {
        self.model = model
        guard Notifier.isEnabled else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // With the app open, a grade alert's sound is the in-app chime instead.
        let chimes = await MainActor.run { model?.settings.soundsOn == true && model?.settings.soundGradeChimes == true }
        if chimes, notification.request.content.threadIdentifier.hasPrefix("grades") { return [.banner, .list] }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let courseID = response.notification.request.content.userInfo["courseID"] as? String
        await MainActor.run { model?.openClassFromAlert(courseID) }
    }
}
