import Foundation
import LocalAuthentication
import Security
import UserNotifications

// MARK: - Keychain

/// Saved sign-in for one Skyward account. Lives only in the Keychain.
struct AccountSecret: Codable {
    var password: String
    var deviceCookie: SkywardSession.DeviceCookie?
}

enum Keychain {
    static let service = "com.skywardplus.app.account"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    static func save(_ secret: AccountSecret, for account: String) -> Bool {
        guard let data = try? JSONEncoder().encode(secret) else { return false }
        SecItemDelete(query(account) as CFDictionary)
        var attributes = query(account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func load(_ account: String) -> AccountSecret? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AccountSecret.self, from: data)
    }

    static func remove(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

/// The student's district (SSO) sign-in, saved only when they turn on "Remember".
struct DistrictCredentials: Codable, Equatable {
    var username: String
    var password: String
    /// Set once the district has refused these details, so they are never sent again.
    var rejected: Bool? = nil
}

extension Keychain {
    static func districtKey(_ address: String) -> String { "district|" + address }

    static func saveDistrict(_ creds: DistrictCredentials, address: String) {
        _ = save(AccountSecret(password: (try? String(data: JSONEncoder().encode(creds), encoding: .utf8)) ?? "", deviceCookie: nil), for: districtKey(address))
    }

    /// The saved sign-in, unless the district has already refused it.
    static func usableDistrict(address: String) -> DistrictCredentials? {
        guard let creds = loadDistrict(address: address), creds.rejected != true else { return nil }
        return creds
    }

    static func markDistrictRejected(address: String) {
        guard var creds = loadDistrict(address: address) else { return }
        creds.rejected = true
        saveDistrict(creds, address: address)
    }

    static func loadDistrict(address: String) -> DistrictCredentials? {
        guard let secret = load(districtKey(address)), let data = secret.password.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DistrictCredentials.self, from: data)
    }
}

// MARK: - Face ID / Touch ID

enum Biometrics {
    /// "Face ID", "Touch ID", "Optic ID", or "Passcode" when there is no biometric sensor.
    static var name: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    static var symbol: String {
        switch name {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default: return "lock"
        }
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Biometrics first; the device passcode or account password is the fallback.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

// MARK: - Notifications

enum Notifier {
    /// Turned off while the app renders screenshots of itself, so no permission prompt appears.
    static var isEnabled = true

    private static var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    @discardableResult
    static func requestPermission() async -> Bool {
        guard isEnabled else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func isAuthorized() async -> Bool {
        guard isEnabled else { return false }
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    // Planner reminders

    static func schedule(task: PlannerTask, courseName: String?) {
        cancel(taskID: task.id)
        guard isEnabled, !task.done, let when = task.remindAt, when > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = task.title
        var parts: [String] = []
        if let courseName, !courseName.isEmpty { parts.append(courseName) }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        parts.append("Due " + formatter.string(from: task.due))
        content.body = parts.joined(separator: " · ")
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
        let request = UNNotificationRequest(
            identifier: "task-" + task.id.uuidString, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        center.add(request)
    }

    static func cancel(taskID: UUID) {
        guard isEnabled else { return }
        center.removePendingNotificationRequests(withIdentifiers: ["task-" + taskID.uuidString])
    }

    // Bell schedule

    /// One repeating weekly alert per period per school day. iOS allows 64 pending
    /// alerts, so a five-day week of eight periods fits with room for reminders.
    static func rescheduleBell(config: BellConfig) {
        guard isEnabled else { return }
        center.getPendingNotificationRequests { requests in
            let old = requests.map { $0.identifier }.filter { $0.hasPrefix("bell-") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard config.notifyBefore > 0 else { return }
            var budget = 48
            for (weekday, scheduleID) in config.weekdays.sorted(by: { $0.key < $1.key }) {
                guard let schedule = config.schedules.first(where: { $0.id == scheduleID }) else { continue }
                for period in schedule.sorted {
                    guard budget > 0 else { return }
                    budget -= 1
                    let fire = max(0, period.start - config.notifyBefore)
                    let content = UNMutableNotificationContent()
                    content.title = period.name + " starts in \(config.notifyBefore) min"
                    content.body = BellMath.format(period.start) + " – " + BellMath.format(period.end)
                    content.sound = .default
                    var components = DateComponents()
                    components.weekday = weekday
                    components.hour = fire / 60
                    components.minute = fire % 60
                    center.add(UNNotificationRequest(
                        identifier: "bell-\(weekday)-\(period.id.uuidString)", content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    ))
                }
            }
        }
    }

    // New grades

    static func announce(_ changes: [GradeChange], studentName: String) {
        guard isEnabled else { return }
        let grades = changes.filter { $0.kind == .newGrade || $0.kind == .updatedGrade }
        guard let first = grades.first else { return }
        let content = UNMutableNotificationContent()
        if grades.count == 1 {
            content.title = "New grade in " + first.courseName
            content.body = first.title + ": " + first.detail
        } else {
            content.title = "\(grades.count) new grades"
            content.body = grades.prefix(3).map { $0.courseName + ": " + $0.title }.joined(separator: "\n")
        }
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "grades-" + UUID().uuidString, content: content, trigger: nil))
    }

    // Missing work and goals

    static func announceMissing(_ items: [(course: String, title: String)], studentName: String) {
        guard isEnabled, let first = items.first else { return }
        let content = UNMutableNotificationContent()
        if items.count == 1 {
            content.title = "Missing in " + first.course
            content.body = first.title + " is marked missing in Skyward."
        } else {
            content.title = "\(items.count) assignments marked missing"
            content.body = items.prefix(3).map { $0.course + ": " + $0.title }.joined(separator: "\n")
        }
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "missing-" + UUID().uuidString, content: content, trigger: nil))
    }

    static func announceBelowGoal(course: String, percent: Double, goal: Double, studentName: String) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = course + " is below your goal"
        content.body = "Now \(Fmt.percent(percent)), goal \(Fmt.percent(goal))."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "goal-" + UUID().uuidString, content: content, trigger: nil))
    }

    /// One evening reminder (7 PM) for each day that has work due the next day.
    static func scheduleDueReminders(_ items: [AppModel.DueItem], studentName: String) {
        guard isEnabled else { return }
        center.getPendingNotificationRequests { requests in
            let old = requests.map { $0.identifier }.filter { $0.hasPrefix("due-") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            let calendar = Calendar.current
            let byDay = Dictionary(grouping: items) { calendar.startOfDay(for: $0.due) }
            for (day, dayItems) in byDay.sorted(by: { $0.key < $1.key }).prefix(10) {
                guard let eve = calendar.date(byAdding: .day, value: -1, to: day),
                      let fire = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: eve),
                      fire > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = dayItems.count == 1 ? "Due tomorrow: " + dayItems[0].title : "\(dayItems.count) things due tomorrow"
                content.body = dayItems.prefix(4).map { $0.course.isEmpty ? $0.title : $0.course + ": " + $0.title }.joined(separator: "\n")
                content.sound = .default
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                center.add(UNNotificationRequest(
                    identifier: "due-\(Int(day.timeIntervalSince1970))", content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                ))
            }
        }
    }
}
