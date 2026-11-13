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
        var dark: Bool { model.settings.backgroundTheme.isDark }

        Notifier.isEnabled = false
        await model.addDemo()
        if let b = args.firstIndex(of: "--bg"), b + 1 < args.count, let theme = BackgroundTheme(rawValue: args[b + 1]) {
            model.settings.backgroundTheme = theme
        }
        if let first = model.courses.first {
            model.setGoal(95, for: first.id)
        }
        model.saveTask(PlannerTask(title: "Finish the free-response set", courseID: model.courses.first?.id, due: model.now().addingTimeInterval(86400), kind: .homework))

        // SKYWARDPLUS_RENDER_SIZE=1900x1150 renders at another window size.
        let defaultSize: CGSize = {
            let parts = (ProcessInfo.processInfo.environment["SKYWARDPLUS_RENDER_SIZE"] ?? "").split(separator: "x").compactMap { Double($0) }
            return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : CGSize(width: 1180, height: 820)
        }()
        func snap<V: View>(_ name: String, _ view: V, size: CGSize? = nil) async {
            let size = size ?? defaultSize
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
        for tab in GradesTab.allCases where want("grades-" + tab.rawValue) {
            model.section = .grades
            model.gradesTab = tab
            await snap("grades-\(tab.rawValue)", MainView())
        }
        model.gradesTab = .classes
        for page in SettingsPage.allCases where want("settings-" + page.rawValue) {
            await snap("settings-\(page.rawValue)", NavigationStack { SettingsPageView(page: page) })
        }
        if want("class"), let firstCourse = model.courses.first {
            await snap("class-detail", NavigationStack { ClassDetailView(courseID: firstCourse.id) })
        }
        if want("themes") {
            // Every theme's living scene at the same moment, for checking the shader.
            let t = Double(ProcessInfo.processInfo.environment["SKYWARDPLUS_SCENE_TIME"] ?? "37") ?? 37
            await snap("themes", LazyVGrid(columns: Array(repeating: GridItem(.fixed(480), spacing: 12), count: 3), spacing: 12) {
                ForEach(BackgroundTheme.allCases) { theme in
                    ThemeField(theme: theme, time: t)
                        .frame(width: 480, height: 300)
                        .overlay(alignment: .topLeading) {
                            Text(theme.title).font(.headline).foregroundStyle(theme.isDark ? .white : .black).padding(10)
                        }
                        .clipShape(.rect(cornerRadius: 12))
                }
            }.padding(12), size: CGSize(width: 1500, height: 1600))
            // The window capture above can't see GPU effects, so also render it directly.
            let gallery = LazyVGrid(columns: Array(repeating: GridItem(.fixed(480), spacing: 12), count: 3), spacing: 12) {
                ForEach(BackgroundTheme.allCases) { theme in
                    ThemeField(theme: theme, time: t)
                        .frame(width: 480, height: 300)
                        .overlay(alignment: .topLeading) {
                            Text(theme.title).font(.headline).foregroundStyle(theme.isDark ? .white : .black).padding(10)
                        }
                        .clipShape(.rect(cornerRadius: 12))
                }
            }.padding(12).frame(width: 1500, height: 1600).background(Color.black)
            let renderer = ImageRenderer(content: gallery)
            renderer.scale = 1
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: outDir.appendingPathComponent("themes-gpu.png"))
            }
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
