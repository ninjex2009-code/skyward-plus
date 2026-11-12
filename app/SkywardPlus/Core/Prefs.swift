import Foundation

// Settings and user-made data. Foundation-only so the logic here can be tested
// without the UI; the SwiftUI side maps these to colours and controls.

// MARK: - Themes and appearance

enum ThemeColor: String, Codable, CaseIterable, Identifiable {
    case sky, indigo, violet, rose, crimson, sunset, amber, forest, teal, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sky: return "Sky"
        case .indigo: return "Indigo"
        case .violet: return "Violet"
        case .rose: return "Rose"
        case .crimson: return "Crimson"
        case .sunset: return "Sunset"
        case .amber: return "Amber"
        case .forest: return "Forest"
        case .teal: return "Teal"
        case .graphite: return "Graphite"
        }
    }

    /// 0xRRGGBB
    var hex: UInt32 {
        switch self {
        case .sky: return 0x2F80ED
        case .indigo: return 0x4F46E5
        case .violet: return 0x8B5CF6
        case .rose: return 0xE64980
        case .crimson: return 0xD92D20
        case .sunset: return 0xF2711C
        case .amber: return 0xD99A00
        case .forest: return 0x1F9D55
        case .teal: return 0x0E9AA7
        case .graphite: return 0x5B6472
        }
    }

    /// Second stop for gradients.
    var hex2: UInt32 {
        switch self {
        case .sky: return 0x56CCF2
        case .indigo: return 0x818CF8
        case .violet: return 0xC084FC
        case .rose: return 0xFF8FAB
        case .crimson: return 0xFF6B5E
        case .sunset: return 0xFFB347
        case .amber: return 0xF6D365
        case .forest: return 0x6FCF97
        case .teal: return 0x5EEAD4
        case .graphite: return 0x9AA5B1
        }
    }
}

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Match system"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Atmospheric page & card background themes that adapt to both Light and Dark mode.
/// The look of the app: a slowly drifting field of colour behind frosted cards.
/// Each theme sets its own light or dark look and its own accent colour.
enum BackgroundTheme: String, Codable, CaseIterable, Identifiable {
    case midnight, obsidian, aurora, sunset, ember, forest, ocean, paper, graphite

    var id: String { rawValue }

    /// Themes from before 1.2 map onto the nearest new one.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BackgroundTheme(rawValue: raw) ?? BackgroundTheme.legacy[raw] ?? .midnight
    }

    static let legacy: [String: BackgroundTheme] = [
        "standard": .graphite, "tinted": .midnight, "evergreen": .forest,
        "espresso": .ember, "dusk": .sunset, "oled": .obsidian,
    ]

    var title: String {
        switch self {
        case .midnight: return "Midnight"
        case .obsidian: return "Obsidian"
        case .aurora: return "Aurora"
        case .sunset: return "Sunset"
        case .ember: return "Ember"
        case .forest: return "Forest"
        case .ocean: return "Ocean"
        case .paper: return "Paper"
        case .graphite: return "Graphite"
        }
    }

    var isDark: Bool {
        switch self {
        case .ocean, .paper, .graphite: return false
        default: return true
        }
    }

    var accent: ThemeColor {
        switch self {
        case .midnight: return .sky
        case .obsidian: return .sky
        case .aurora: return .forest
        case .sunset: return .sunset
        case .ember: return .crimson
        case .forest: return .teal
        case .ocean: return .sky
        case .paper: return .indigo
        case .graphite: return .graphite
        }
    }

    /// The colour under everything, 0xRRGGBB.
    var base: UInt32 {
        switch self {
        case .midnight: return 0x050A1C
        case .obsidian: return 0x040405
        case .aurora: return 0x041311
        case .sunset: return 0x170A1C
        case .ember: return 0x120C0B
        case .forest: return 0x06120D
        case .ocean: return 0xE6F2FB
        case .paper: return 0xF6F1E7
        case .graphite: return 0xECEEF2
        }
    }

    /// Three glows that drift over the base, 0xRRGGBB.
    var glows: [UInt32] {
        switch self {
        case .midnight: return [0x1D4ED8, 0x172B6E, 0x0B6E99]
        case .obsidian: return [0x1B1E25, 0x121418, 0x1E2128]
        case .aurora: return [0x0F766E, 0x15803D, 0x6D28D9]
        case .sunset: return [0x7E22CE, 0xEA580C, 0xBE185D]
        case .ember: return [0xB91C1C, 0xC2620A, 0x5A1F14]
        case .forest: return [0x166534, 0x4D6B12, 0x0F6E6A]
        case .ocean: return [0x7CCBF5, 0x6EE7D6, 0xAFB9FA]
        case .paper: return [0xE6D2AE, 0xF0DFC6, 0xCFDDEB]
        case .graphite: return [0xC5CEDB, 0xDDE3EC, 0xCDD1D8]
        }
    }
}

enum GradeStyle: String, Codable, CaseIterable, Identifiable {
    case bubble, number

    var id: String { rawValue }
    var title: String {
        switch self {
        case .bubble: return "Filled bubbles"
        case .number: return "Coloured numbers"
        }
    }
}

/// Where Skyward due dates and planner tasks are copied.
enum ExportTarget: String, Codable, CaseIterable, Identifiable {
    case off, reminders, calendar

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .reminders: return "Reminders"
        case .calendar: return "Calendar"
        }
    }
}

struct AppSettings: Codable, Hashable {
    var activeProfileID: UUID?
    var appearance: Appearance = .system
    var backgroundThemeRaw: BackgroundTheme?
    var colorBubbles = true
    var biometricLock = false
    var notifyNewGrades = true
    var appIcon = "AppIcon"
    var compactRows = false
    var gradeStyle: GradeStyle = .bubble
    /// Closing the window leaves the app in the menu bar.
    var keepInMenuBar = true
    var showMenuBarIcon = true
    var launchAtLogin = false
    var backgroundSync = true
    var syncMinutes = 5
    var notifyDueTomorrow = true
    var notifyBelowGoal = true
    /// Work newly marked missing in Skyward.
    var notifyMissing = true
    /// One evening note: today's grades, what's missing, what's due tomorrow.
    var notifySummary = true
    /// Hour (0-23) the evening summary and due-tomorrow reminder arrive.
    var summaryHour = 19
    /// ntfy topic the Mac copies every alert to, so it reaches the phone. Empty: off.
    var phoneRelayTopic = ""
    /// Include scores and averages in alerts copied to the phone.
    var phoneRelayScores = true
    /// Shortcut that opens search from any app (Mac). "off", "optionCommandK", "controlOptionK", "commandK".
    var searchShortcut = "optionCommandK"
    var exportTarget: ExportTarget = .off
    var helloShown = false
    var lastUpdateCheck: Date?
    var skippedVersion: String?
    /// The desktop shows faintly through the window.
    var translucentWindow = true
    /// A soft accent-coloured glow around the window that breathes while syncing.
    var windowGlow = true

    var backgroundTheme: BackgroundTheme {
        get { backgroundThemeRaw ?? .midnight }
        set { backgroundThemeRaw = newValue }
    }

    init() {}

    // Every key is optional so settings saved by older versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? d.appearance
        backgroundThemeRaw = try? c.decodeIfPresent(BackgroundTheme.self, forKey: .backgroundThemeRaw)
        colorBubbles = (try? c.decodeIfPresent(Bool.self, forKey: .colorBubbles)) ?? d.colorBubbles
        biometricLock = (try? c.decodeIfPresent(Bool.self, forKey: .biometricLock)) ?? d.biometricLock
        notifyNewGrades = (try? c.decodeIfPresent(Bool.self, forKey: .notifyNewGrades)) ?? d.notifyNewGrades
        appIcon = (try? c.decodeIfPresent(String.self, forKey: .appIcon)) ?? d.appIcon
        compactRows = (try? c.decodeIfPresent(Bool.self, forKey: .compactRows)) ?? d.compactRows
        gradeStyle = (try? c.decodeIfPresent(GradeStyle.self, forKey: .gradeStyle)) ?? d.gradeStyle
        keepInMenuBar = (try? c.decodeIfPresent(Bool.self, forKey: .keepInMenuBar)) ?? d.keepInMenuBar
        showMenuBarIcon = (try? c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon)) ?? d.showMenuBarIcon
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin
        backgroundSync = (try? c.decodeIfPresent(Bool.self, forKey: .backgroundSync)) ?? d.backgroundSync
        syncMinutes = (try? c.decodeIfPresent(Int.self, forKey: .syncMinutes)) ?? d.syncMinutes
        notifyDueTomorrow = (try? c.decodeIfPresent(Bool.self, forKey: .notifyDueTomorrow)) ?? d.notifyDueTomorrow
        notifyBelowGoal = (try? c.decodeIfPresent(Bool.self, forKey: .notifyBelowGoal)) ?? d.notifyBelowGoal
        // Missing work used to share the due-tomorrow switch.
        notifyMissing = (try? c.decodeIfPresent(Bool.self, forKey: .notifyMissing)) ?? notifyDueTomorrow
        notifySummary = (try? c.decodeIfPresent(Bool.self, forKey: .notifySummary)) ?? d.notifySummary
        summaryHour = (try? c.decodeIfPresent(Int.self, forKey: .summaryHour)) ?? d.summaryHour
        phoneRelayTopic = (try? c.decodeIfPresent(String.self, forKey: .phoneRelayTopic)) ?? d.phoneRelayTopic
        phoneRelayScores = (try? c.decodeIfPresent(Bool.self, forKey: .phoneRelayScores)) ?? d.phoneRelayScores
        searchShortcut = (try? c.decodeIfPresent(String.self, forKey: .searchShortcut)) ?? d.searchShortcut
        exportTarget = (try? c.decodeIfPresent(ExportTarget.self, forKey: .exportTarget)) ?? d.exportTarget
        // Anyone upgrading has already seen the app, so the hello only plays on a true first launch.
        helloShown = (try? c.decodeIfPresent(Bool.self, forKey: .helloShown)) ?? true
        lastUpdateCheck = try? c.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        skippedVersion = try? c.decodeIfPresent(String.self, forKey: .skippedVersion)
        translucentWindow = (try? c.decodeIfPresent(Bool.self, forKey: .translucentWindow)) ?? true
        windowGlow = (try? c.decodeIfPresent(Bool.self, forKey: .windowGlow)) ?? true
    }
}

// MARK: - Classes

enum DayPattern: String, Codable, CaseIterable, Identifiable {
    case every, a, b

    var id: String { rawValue }
    var title: String {
        switch self {
        case .every: return "Every day"
        case .a: return "A day"
        case .b: return "B day"
        }
    }
}

/// How a district builds staff e-mail addresses. Skyward does not publish them,
/// so the app fills them in from a pattern the user picks once.
enum EmailPattern: String, Codable, CaseIterable, Identifiable {
    case firstDotLast, firstInitialLast, firstLastInitial, lastDotFirst, lastFirstInitial, firstUnderscoreLast, firstLast

    var id: String { rawValue }

    var example: String {
        switch self {
        case .firstDotLast: return "dana.whitfield"
        case .firstInitialLast: return "dwhitfield"
        case .firstLastInitial: return "danaw"
        case .lastDotFirst: return "whitfield.dana"
        case .lastFirstInitial: return "whitfieldd"
        case .firstUnderscoreLast: return "dana_whitfield"
        case .firstLast: return "danawhitfield"
        }
    }

    /// Splits "Dana Whitfield" or "WHITFIELD, DANA" into lower-case first and last names.
    static func nameParts(_ teacher: String) -> (first: String, last: String)? {
        func tidy(_ s: Substring) -> String { s.lowercased().filter { $0.isLetter || $0 == "-" } }
        let trimmed = teacher.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(",") {
            let parts = trimmed.split(separator: ",", maxSplits: 1)
            guard parts.count == 2, let first = parts[1].split(separator: " ").first else { return nil }
            let f = tidy(first), l = tidy(parts[0].split(separator: " ").joined()[...])
            return f.isEmpty || l.isEmpty ? nil : (f, l)
        }
        let words = trimmed.split(separator: " ").filter { word in
            let w = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return !["mr", "mrs", "ms", "miss", "dr", "coach"].contains(w)
        }
        guard words.count >= 2, let first = words.first, let last = words.last else { return nil }
        let f = tidy(first), l = tidy(last)
        return f.isEmpty || l.isEmpty ? nil : (f, l)
    }

    func address(for teacher: String, domain: String) -> String? {
        let host = domain.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "@", with: "")
        guard !host.isEmpty, host.contains("."), let (first, last) = EmailPattern.nameParts(teacher) else { return nil }
        let local: String
        switch self {
        case .firstDotLast: local = first + "." + last
        case .firstInitialLast: local = String(first.prefix(1)) + last
        case .firstLastInitial: local = first + String(last.prefix(1))
        case .lastDotFirst: local = last + "." + first
        case .lastFirstInitial: local = last + String(first.prefix(1))
        case .firstUnderscoreLast: local = first + "_" + last
        case .firstLast: local = first + last
        }
        return local + "@" + host
    }
}

// MARK: - Planner

enum TaskKind: String, Codable, CaseIterable, Identifiable {
    case homework, test, project, reading, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .homework: return "Homework"
        case .test: return "Test"
        case .project: return "Project"
        case .reading: return "Reading"
        case .other: return "Other"
        }
    }
    var symbol: String {
        switch self {
        case .homework: return "pencil"
        case .test: return "checklist"
        case .project: return "hammer"
        case .reading: return "book"
        case .other: return "circle.dashed"
        }
    }
}

struct PlannerTask: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var notes = ""
    var courseID: String?
    var due: Date
    var kind: TaskKind = .homework
    var remindAt: Date?
    var done = false
    var createdAt = Date()
}

// MARK: - Bell schedule

struct BellPeriod: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var start: Int      // minutes after midnight
    var end: Int
}

struct BellSchedule: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var periods: [BellPeriod] = []

    var sorted: [BellPeriod] { periods.sorted { $0.start < $1.start } }
}

struct BellConfig: Codable, Hashable {
    var schedules: [BellSchedule] = []
    /// Calendar weekday (1 = Sunday ... 7 = Saturday) -> schedule id. A weekday with no entry has no school.
    var weekdays: [Int: UUID] = [:]
    /// Minutes of warning before each period starts. 0 turns the alerts off.
    var notifyBefore = 0
    var abEnabled = false
    var abAnchor: Date?
    var abAnchorIsA = true
}

struct BellStatus: Equatable {
    enum Phase: Equatable {
        case noSchool
        case before          // school has not started yet today
        case during          // inside a period
        case passing         // between two periods
        case after           // the last period is over
    }

    var phase: Phase
    var current: BellPeriod?
    var next: BellPeriod?
    /// Seconds until the current period ends, or until the next one starts.
    var secondsLeft: Int?
    /// 0...1 through the current period.
    var progress: Double?
    var scheduleName = ""
}

enum BellMath {
    static func minutes(of date: Date, calendar: Calendar = SkyDate.calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func schedule(for date: Date, config: BellConfig, calendar: Calendar = SkyDate.calendar) -> BellSchedule? {
        let weekday = calendar.component(.weekday, from: date)
        guard let id = config.weekdays[weekday] else { return nil }
        return config.schedules.first { $0.id == id }
    }

    static func status(at date: Date, config: BellConfig, calendar: Calendar = SkyDate.calendar) -> BellStatus {
        guard let schedule = schedule(for: date, config: config, calendar: calendar), !schedule.periods.isEmpty else {
            return BellStatus(phase: .noSchool)
        }
        let periods = schedule.sorted
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let nowSeconds = (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)

        if let index = periods.firstIndex(where: { nowSeconds >= $0.start * 60 && nowSeconds < $0.end * 60 }) {
            let p = periods[index]
            let length = max(1, (p.end - p.start) * 60)
            return BellStatus(
                phase: .during, current: p, next: index + 1 < periods.count ? periods[index + 1] : nil,
                secondsLeft: p.end * 60 - nowSeconds,
                progress: Double(nowSeconds - p.start * 60) / Double(length),
                scheduleName: schedule.name
            )
        }
        if let upcoming = periods.first(where: { $0.start * 60 > nowSeconds }) {
            let isFirst = upcoming.id == periods.first?.id
            return BellStatus(
                phase: isFirst ? .before : .passing, current: nil, next: upcoming,
                secondsLeft: upcoming.start * 60 - nowSeconds, progress: nil, scheduleName: schedule.name
            )
        }
        return BellStatus(phase: .after, scheduleName: schedule.name)
    }

    /// Whether a date is an A day, counting school days (those with a bell schedule,
    /// or Monday to Friday when none is set up) from the anchor date. Nil when A/B days are off.
    static func isADay(_ date: Date, config: BellConfig, calendar: Calendar = SkyDate.calendar) -> Bool? {
        guard config.abEnabled, let anchor = config.abAnchor else { return nil }
        func isSchoolDay(_ d: Date) -> Bool {
            let weekday = calendar.component(.weekday, from: d)
            if config.weekdays.isEmpty { return weekday >= 2 && weekday <= 6 }
            return config.weekdays[weekday] != nil
        }
        let start = calendar.startOfDay(for: anchor)
        let target = calendar.startOfDay(for: date)
        guard isSchoolDay(target) else { return nil }
        var count = 0
        var cursor = min(start, target)
        let end = max(start, target)
        var guardCounter = 0
        while cursor < end, guardCounter < 800 {
            if isSchoolDay(cursor) { count += 1 }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
            guardCounter += 1
        }
        // School days in [earlier, later): the parity is the same walking either way.
        return count % 2 == 0 ? config.abAnchorIsA : !config.abAnchorIsA
    }

    /// "8:20 AM - 9:10 AM" -> (500, 550)
    static func parseTimeRange(_ text: String) -> (start: Int, end: Int)? {
        guard let m = Str.match("(\\d{1,2}):(\\d{2})\\s*([AP]M)?\\s*-\\s*(\\d{1,2}):(\\d{2})\\s*([AP]M)?", in: text) else { return nil }
        func minutes(_ h: String, _ min: String, _ suffix: String, fallback: String) -> Int? {
            guard var hour = Int(h), let minute = Int(min) else { return nil }
            let ampm = (suffix.isEmpty ? fallback : suffix).uppercased()
            if ampm == "PM", hour < 12 { hour += 12 }
            if ampm == "AM", hour == 12 { hour = 0 }
            return hour * 60 + minute
        }
        guard let end = minutes(m[4], m[5], m[6], fallback: m[3]),
              var start = minutes(m[1], m[2], m[3], fallback: m[6]) else { return nil }
        // "11:50 - 12:40 PM": the shared suffix belongs to the end, so a start
        // that lands after the end is really twelve hours earlier.
        if start >= end, m[3].isEmpty, start >= 720 { start -= 720 }
        return start < end ? (start, end) : nil
    }

    static func format(_ minutes: Int) -> String {
        let h24 = (minutes / 60) % 24
        let m = minutes % 60
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        return String(format: "%d:%02d %@", h12, m, h24 < 12 ? "AM" : "PM")
    }

    /// A starting schedule built from the class times Skyward lists.
    static func defaultSchedule(from courses: [Course]) -> BellSchedule? {
        var seen = Set<String>()
        var periods: [BellPeriod] = []
        for course in courses.sorted(by: { $0.periodNumber < $1.periodNumber }) {
            guard let range = parseTimeRange(course.timeRange) else { continue }
            let key = "\(range.start)-\(range.end)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            periods.append(BellPeriod(name: course.period.isEmpty ? "Period" : "Period " + course.period, start: range.start, end: range.end))
        }
        guard !periods.isEmpty else { return nil }
        return BellSchedule(name: "Regular day", periods: periods.sorted { $0.start < $1.start })
    }

    /// Standard 7-period high school bell schedule preset when Skyward does not list class times.
    static func highSchoolPreset() -> BellSchedule {
        BellSchedule(
            name: "Regular Day",
            periods: [
                BellPeriod(name: "Period 1", start: 7 * 60 + 30, end: 8 * 60 + 20),
                BellPeriod(name: "Period 2", start: 8 * 60 + 26, end: 9 * 60 + 16),
                BellPeriod(name: "Period 3", start: 9 * 60 + 22, end: 10 * 60 + 12),
                BellPeriod(name: "Period 4", start: 10 * 60 + 18, end: 11 * 60 + 12),
                BellPeriod(name: "Period 5", start: 11 * 60 + 48, end: 12 * 60 + 42),
                BellPeriod(name: "Period 6", start: 12 * 60 + 48, end: 13 * 60 + 38),
                BellPeriod(name: "Period 7", start: 13 * 60 + 44, end: 14 * 60 + 35),
            ]
        )
    }

    static func countdown(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Per-student preferences

struct ProfilePrefs: Codable, Hashable {
    /// Marking period on screen. Nil follows the current one.
    var selectedLit: String?
    var courseOrder: [String] = []
    var hiddenCourses: Set<String> = []
    var gradingModes: [String: GradingMode] = [:]
    var gpa = GPASettings()
    var dayPatterns: [String: DayPattern] = [:]
    var teacherEmails: [String: String] = [:]
    var emailDomain = ""
    var emailPattern: EmailPattern = .firstDotLast
    var tasks: [PlannerTask] = []
    /// Skyward assignments the student ticked off in the planner.
    var doneAssignments: Set<String> = []
    var bell = BellConfig()
    /// Averages when the app was last closed, for "since you last looked".
    var lastSeenGrades: [String: Double] = [:]
    var lastSeenAt: Date?
    var hasCompletedOnboarding: Bool?
    /// Target percent per course id.
    var goalsRaw: [String: Double]?
    /// Classes already announced as below goal, so the alert fires once per drop.
    var belowGoalNotifiedRaw: Set<String>?
    /// Notifications already sent for newly missing work.
    var missingNotifiedRaw: Set<String>?

    var goals: [String: Double] {
        get { goalsRaw ?? [:] }
        set { goalsRaw = newValue }
    }

    var belowGoalNotified: Set<String> {
        get { belowGoalNotifiedRaw ?? [] }
        set { belowGoalNotifiedRaw = newValue }
    }

    var missingNotified: Set<String> {
        get { missingNotifiedRaw ?? [] }
        set { missingNotifiedRaw = newValue }
    }

    var onboardingDone: Bool {
        get { hasCompletedOnboarding == true }
        set { hasCompletedOnboarding = newValue }
    }
}

/// One student in the app. A parent account makes one of these per child.
struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var address: String
    var districtName = ""
    var username: String
    var isDemo = false
    var childID: String?
    var skywardName = ""
    var displayName = ""
    var theme: ThemeColor = .sky
    var avatarFile: String?
    var prefs = ProfilePrefs()

    /// Children of one parent account share one saved password.
    var accountKey: String { address + "|" + username }

    var name: String {
        if !displayName.isEmpty { return displayName }
        if !skywardName.isEmpty { return Str.titleCase(skywardName) }
        return username
    }

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }
}


/// Compares dotted version strings ("1.10" is newer than "1.9").
enum AppVersion {
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
