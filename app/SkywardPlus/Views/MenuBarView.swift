#if os(macOS)
import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let unseen = model.unseenChangeCount
        Group {
            if unseen > 0 {
                Label("\(unseen)", systemImage: "graduationcap.fill")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "graduationcap")
            }
        }
        .symbolEffect(.bounce, value: unseen)
    }
}

/// The menu bar window: today's grades at a glance, without opening the app.
struct MenuBarView: View {
    @State private var bannerVisible = false
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner
            if model.active == nil {
                Text("Sign in to Skyward to see your grades here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                content
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 340)
        .tint(model.theme.color)
        .environment(\.colorScheme, model.settings.backgroundTheme.isDark ? .dark : .light)
        .background(model.settings.backgroundTheme.cardTint.opacity(0.5))
    }

    // MARK: Banner

    /// A little window onto the living theme, with who you are and your average.
    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            // Only moves while the menu bar window is open.
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !bannerVisible)) { context in
                ThemeField(theme: model.settings.backgroundTheme, time: SceneClock.seconds(context.date))
            }
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 10) {
                if let profile = model.active {
                    AvatarView(profile: profile, size: 34, scalesWithWindow: false)
                        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                        Text(statusLine).font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    }
                } else {
                    Text("Skyward Plus").font(.display(16, weight: .bold)).foregroundStyle(.white)
                }
                Spacer(minLength: 6)
                if let average {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Fmt.percent(average)).font(.display(24).monospacedDigit()).foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("average").font(.caption2).foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .padding(14)
        }
        .frame(height: 112)
        .onAppear { bannerVisible = true }
        .onDisappear { bannerVisible = false }
        .clipped()
        .overlay(alignment: .topTrailing) {
            Button {
                Task { await model.refresh() }
            } label: {
                SpinningRefreshIcon(spinning: model.syncState.isSyncing)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.black.opacity(0.28)))
            }
            .buttonStyle(.plain)
            .disabled(model.active == nil || model.syncState.isSyncing)
            .help("Refresh grades")
            .padding(10)
        }
    }

    private var average: Double? {
        guard let lit = model.selectedLit else { return nil }
        let numbers = model.courses(in: lit).compactMap { model.percent($0, lit) }
        return numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)
    }

    private var statusLine: String {
        switch model.syncState {
        case .syncing(let step): return step + "…"
        case .failed: return "Last refresh failed"
        case .needsSignIn: return "Sign in again to keep syncing"
        case .waiting: return "Paused · updated " + Fmt.ago(model.data.lastSync, now: model.now())
        case .idle: return "Updated " + Fmt.ago(model.data.lastSync, now: model.now())
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            BellLine()

            if let lit = model.selectedLit {
                let courses = model.courses(in: lit).filter { !model.gradeText($0, lit).isEmpty }
                if courses.isEmpty {
                    Text("No grades in \(lit) yet.").font(.callout).foregroundStyle(.secondary)
                } else {
                    section(model.data.bucket(lit)?.displayName ?? lit) {
                        ForEach(courses) { course in
                            MenuRow {
                                AppDelegate.shared?.showMain(section: .grades)
                                model.openCourse = course.id
                            } content: {
                                Capsule().fill(model.classColor(course.id)).frame(width: 3, height: 18)
                                Text(Str.titleCase(course.name)).lineLimit(1)
                                Spacer(minLength: 8)
                                if let goal = model.goal(for: course.id), let p = model.percent(course, lit), p < goal {
                                    Image(systemName: "flag.fill").font(.caption2).foregroundStyle(Palette.warn)
                                        .help("Below your goal of \(Fmt.percent(goal))")
                                }
                                Text(model.gradeText(course, lit))
                                    .font(.callout.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(GradeColor.color(percent: model.percent(course, lit), text: model.gradeText(course, lit)))
                            }
                        }
                    }
                }
            }

            let today = Calendar.current.startOfDay(for: model.now())
            let upcoming = Array(model.dueItems.filter { !$0.done && $0.due >= today }.sorted { $0.due < $1.due }.prefix(3))
            if !upcoming.isEmpty {
                section("Next up") {
                    ForEach(upcoming) { item in
                        MenuRow {
                            AppDelegate.shared?.showMain(section: .planner)
                        } content: {
                            Circle().fill(courseColor(named: item.course)).frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title).lineLimit(1)
                                if !item.course.isEmpty {
                                    Text(item.course).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(Fmt.relativeDay(item.due, now: model.now()))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Calendar.current.isDateInToday(item.due) || Calendar.current.isDateInTomorrow(item.due) ? Palette.warn : .secondary)
                        }
                    }
                }
            }

            let changes = Array(model.recentChanges.filter { $0.kind == .newGrade || $0.kind == .updatedGrade }.prefix(3))
            if !changes.isEmpty {
                section("New grades") {
                    ForEach(changes) { change in
                        MenuRow {
                            AppDelegate.shared?.showMain(section: .grades)
                            model.openCourse = change.courseID
                        } content: {
                            Capsule().fill(model.classColor(change.courseID)).frame(width: 3, height: 26)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(change.title).lineLimit(1)
                                Text(change.courseName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(change.detail).font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }

            let missing = model.missingAssignments.count
            if missing > 0 {
                Label("\(missing) missing in Skyward", systemImage: "exclamationmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Palette.bad)
            }
        }
        .padding(14)
    }

    private func courseColor(named name: String) -> Color {
        guard let course = model.data.courses.first(where: { Str.titleCase($0.name) == name }) else { return model.theme.color }
        return model.classColor(course.id)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            content()
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Skyward Plus") { AppDelegate.shared?.showMain(section: nil) }
                .keyboardShortcut("o")
            Spacer()
            Button {
                AppDelegate.shared?.showMain(section: .settings)
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit Skyward Plus")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A clickable line in the menu bar popover with a soft hover highlight.
private struct MenuRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { content }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, -8)
    }
}

/// "Period 3 · 12:04 left", refreshed every second while visible.
private struct BellLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = BellMath.status(at: context.date, config: model.prefs.bell)
            switch status.phase {
            case .during:
                if let current = status.current, let left = status.secondsLeft {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(current.name).font(.callout.weight(.semibold))
                            Spacer()
                            Text(BellMath.countdown(left) + " left").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ProgressBar(value: status.progress ?? 0, tint: model.theme.color, height: 4)
                    }
                }
            case .passing, .before:
                if let next = status.next, let left = status.secondsLeft {
                    HStack {
                        Text("\(next.name) starts in").font(.callout)
                        Spacer()
                        Text(BellMath.countdown(left)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            case .after, .noSchool:
                EmptyView()
            }
        }
    }
}
#endif
