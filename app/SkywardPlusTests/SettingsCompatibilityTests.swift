import Foundation
import Testing

/// Settings and preferences saved by version 1.0 must load unchanged in 1.1,
/// or people lose their setup when they update.
@Suite("Saved settings from older versions")
struct SettingsCompatibilityTests {
    /// The exact keys version 1.0 wrote to state.json.
    static let version10Settings = """
    {"notifyNewGrades":true,"backgroundThemeRaw":"evergreen","biometricLock":false,"appearance":"dark",
     "compactRows":false,"activeProfileID":"363F7361-2DFE-4950-A1AE-8C0286648176","appIcon":"AppIconSunset","colorBubbles":true}
    """

    @Test("1.0 settings keep their values")
    func oldSettingsKeepValues() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(Self.version10Settings.utf8))
        #expect(settings.appearance == .dark)
        #expect(settings.backgroundTheme == .forest, "1.0's Evergreen became Forest in 1.2")
        #expect(settings.appIcon == "AppIconSunset")
        #expect(settings.activeProfileID == UUID(uuidString: "363F7361-2DFE-4950-A1AE-8C0286648176"))
    }

    @Test("New 1.1 settings get their defaults, and upgraders skip the first-launch greeting")
    func newSettingsGetDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(Self.version10Settings.utf8))
        #expect(settings.gradeStyle == .bubble)
        #expect(settings.keepInMenuBar)
        #expect(settings.showMenuBarIcon)
        #expect(settings.launchAtLogin == false)
        #expect(settings.backgroundSync)
        #expect(settings.syncMinutes == 30)
        #expect(settings.exportTarget == .off)
        #expect(settings.helloShown, "people updating from 1.0 have already met the app")
    }

    @Test("Every theme from before 1.2 maps to a new one", arguments: [
        ("standard", BackgroundTheme.graphite), ("tinted", .midnight), ("evergreen", .forest),
        ("espresso", .ember), ("dusk", .sunset), ("oled", .obsidian), ("midnight", .midnight),
        ("aurora", .aurora), ("not-a-theme", .midnight),
    ])
    func legacyThemes(raw: String, expected: BackgroundTheme) throws {
        let json = #"{"backgroundThemeRaw":"\#(raw)"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.backgroundTheme == expected)
    }

    @Test("A brand-new install shows the greeting")
    func freshInstallShowsHello() {
        #expect(AppSettings().helloShown == false)
    }

    @Test("Settings survive a save and reload")
    func roundTrip() throws {
        var settings = AppSettings()
        settings.gradeStyle = .number
        settings.syncMinutes = 120
        settings.exportTarget = .reminders
        settings.helloShown = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test("An unknown value from a future version falls back instead of failing")
    func unknownEnumValueFallsBack() throws {
        let json = #"{"gradeStyle":"sparkles","exportTarget":"carrier-pigeon","syncMinutes":45}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.gradeStyle == .bubble)
        #expect(settings.exportTarget == .off)
        #expect(settings.syncMinutes == 45)
    }

    @Test("Per-student preferences without goals still load, and goals round-trip")
    func goalsAreOptional() throws {
        var prefs = ProfilePrefs()
        let old = try JSONEncoder().encode(prefs)
        let reloaded = try JSONDecoder().decode(ProfilePrefs.self, from: old)
        #expect(reloaded.goals.isEmpty)

        prefs.goals["1070_1_1"] = 92
        prefs.belowGoalNotified.insert("1070_1_1")
        let again = try JSONDecoder().decode(ProfilePrefs.self, from: JSONEncoder().encode(prefs))
        #expect(again.goals["1070_1_1"] == 92)
        #expect(again.belowGoalNotified == ["1070_1_1"])
    }
}

@Suite("Update version comparison")
struct AppVersionTests {
    @Test("Newer versions are detected", arguments: [
        ("1.2", "1.1"), ("1.10", "1.9"), ("2.0", "1.99"), ("v1.1.1", "1.1"), ("1.1.0.1", "1.1"),
    ])
    func newer(candidate: String, current: String) {
        #expect(AppVersion.isNewer(candidate, than: current))
    }

    @Test("Same or older versions are not offered", arguments: [
        ("1.1", "1.1"), ("1.1.0", "1.1"), ("1.0", "1.1"), ("v1.1", "1.1"), ("0.9", "1.0"),
    ])
    func notNewer(candidate: String, current: String) {
        #expect(!AppVersion.isNewer(candidate, than: current))
    }
}

@Suite("Bell schedule times")
struct BellTimeTests {
    @Test("Skyward time ranges parse to minutes", arguments: [
        ("8:15 AM - 9:05 AM", 495, 545),
        ("(12:25 PM - 1:15 PM)", 745, 795),
        ("11:50 - 12:40 PM", 710, 760),
    ])
    func parse(text: String, start: Int, end: Int) throws {
        let range = try #require(BellMath.parseTimeRange(text))
        #expect(range.start == start)
        #expect(range.end == end)
    }

    @Test("Countdown formatting")
    func countdown() {
        #expect(BellMath.countdown(65) == "1:05")
        #expect(BellMath.countdown(3_725) == "1:02:05")
        #expect(BellMath.countdown(-4) == "0:00")
    }
}
