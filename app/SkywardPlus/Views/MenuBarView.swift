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
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.active == nil {
                Text("Sign in to Skyward to see your grades here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                content
            }
            Divider()
            footer
        }
        .frame(width: 330)
        .tint(model.theme.color)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let profile = model.active {
                AvatarView(profile: profile, size: 30, scalesWithWindow: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name).font(.headline).lineLimit(1)
                    Text(statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text("Skyward Plus").font(.headline)
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                if model.syncState.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(model.active == nil || model.syncState.isSyncing)
            .help("Refresh grades")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusLine: String {
        switch model.syncState {
        case .syncing(let step): return step + "…"
        case .failed: return "Last refresh failed"
        case .needsSignIn: return "Sign in again to keep syncing"
        case .idle: return "Updated " + Fmt.ago(model.data.lastSync, now: model.now())
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            BellLine()

            if let lit = model.selectedLit {
                let courses = model.courses(in: lit).filter { !model.gradeText($0, lit).isEmpty }
                if courses.isEmpty {
                    Text("No grades in \(lit) yet.").font(.callout).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.data.bucket(lit)?.displayName ?? lit)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                        ForEach(courses) { course in
                            Button {
                                AppDelegate.shared?.showMain(section: .grades)
                                model.openCourse = course.id
                            } label: {
                                HStack {
                                    Text(Str.titleCase(course.name)).lineLimit(1)
                                    Spacer(minLength: 8)
                                    if let goal = model.goal(for: course.id), let p = model.percent(course, lit), p < goal {
                                        Image(systemName: "flag.fill").font(.caption2).foregroundStyle(Palette.warn)
                                            .help("Below your goal of \(Fmt.percent(goal))")
                                    }
                                    Text(model.gradeText(course, lit))
                                        .font(.body.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(GradeColor.color(percent: model.percent(course, lit), text: model.gradeText(course, lit)))
                                }
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            let changes = Array(model.recentChanges.filter { $0.kind == .newGrade || $0.kind == .updatedGrade }.prefix(3))
            if !changes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New grades").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(changes) { change in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(change.title).lineLimit(1)
                                Text(change.courseName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(change.detail).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            let missing = model.missingAssignments.count
            let tomorrow = model.dueItems.filter { !$0.done && Calendar.current.isDateInTomorrow($0.due) }.count
            if missing > 0 || tomorrow > 0 {
                HStack(spacing: 14) {
                    if missing > 0 {
                        Label("\(missing) missing", systemImage: "exclamationmark.circle")
                            .foregroundStyle(Palette.bad)
                    }
                    if tomorrow > 0 {
                        Label("\(tomorrow) due tomorrow", systemImage: "calendar")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
        }
        .padding(14)
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
