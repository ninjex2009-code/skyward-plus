#if DEBUG && os(macOS)
import AppKit
import SwiftUI

/// Renders every screen with the demo student to PNGs, for checking the design.
/// `Skyward Plus --render-screens <dir> [--dark] [--bg <theme>]`
@MainActor
enum ScreenRenderer {
    static func run(model: AppModel) async {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--render-screens"), idx + 1 < args.count else { return }
        let outDir = URL(fileURLWithPath: args[idx + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let dark = args.contains("--dark")

        Notifier.isEnabled = false
        await model.addDemo()
        if let b = args.firstIndex(of: "--bg"), b + 1 < args.count, let theme = BackgroundTheme(rawValue: args[b + 1]) {
            model.settings.backgroundTheme = theme
        }
        if let first = model.courses.first {
            model.setGoal(95, for: first.id)
        }
        model.saveTask(PlannerTask(title: "Finish the free-response set", courseID: model.courses.first?.id, due: model.now().addingTimeInterval(86400), kind: .homework))

        func snap<V: View>(_ name: String, _ view: V, size: CGSize = CGSize(width: 1180, height: 820)) async {
            let wrapped = view
                .environment(model)
                .environment(\.backgroundTheme, model.settings.backgroundTheme)
                .environment(\.accentTheme, model.theme)
                .tint(model.theme.color)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(dark ? .dark : .light)
            let hosting = NSHostingView(rootView: wrapped)
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = hosting
            window.displayIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: 600_000_000)
            hosting.layoutSubtreeIfNeeded()
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: outDir.appendingPathComponent("\(name).png"))
                }
            }
            window.orderOut(nil)
        }

        let only = args.firstIndex(of: "--only").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        func want(_ name: String) -> Bool { only.map { name.contains($0) } ?? true }

        if want("signin") { await snap("00-signin", NavigationStack { SignInView(isFirstRun: true) }) }
        for section in AppSection.sidebar where want(section.rawValue) {
            model.section = section
            await snap("section-\(section.rawValue)", MainView())
        }
        for tab in ScheduleTab.allCases where want("schedule-" + tab.rawValue) {
            model.section = .schedule
            model.scheduleTab = tab
            await snap("schedule-\(tab.rawValue)", MainView())
        }
        model.scheduleTab = .classes
        if want("transcript") {
            model.section = .reports
            model.reportsTab = .transcript
            await snap("reports-transcript", MainView())
            model.reportsTab = .cards
        }
        if want("class"), let firstCourse = model.courses.first {
            await snap("class-detail", NavigationStack { ClassDetailView(courseID: firstCourse.id) })
        }
        if want("palette") {
            model.section = .home
            model.showPalette = true
            await snap("palette", MainView())
            model.showPalette = false
        }
        if want("menubar") {
            await snap("menubar", MenuBarView(), size: CGSize(width: 330, height: 520))
        }
        if want("report") {
            let lit = model.selectedLit
            let view = GradeReportView(
                profileName: model.active?.name ?? "", school: model.data.profile.school, data: model.data,
                courses: model.courses, lit: lit,
                gpa: GPA.compute(lit.map { GPA.currentEntries(data: model.data, lit: $0, settings: model.prefs.gpa) } ?? []),
                goals: model.prefs.goals, generated: model.now()
            )
            if let pdf = GradeReportExporter.pdfData(for: view) {
                try? pdf.write(to: outDir.appendingPathComponent("report.pdf"))
            }
        }
        NSApp.terminate(nil)
    }
}
#endif
