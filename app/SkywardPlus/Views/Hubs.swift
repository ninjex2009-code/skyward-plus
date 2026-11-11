import SwiftUI

enum ScheduleTab: String, CaseIterable, Identifiable {
    case classes, bell, teachers
    var id: String { rawValue }
    var title: String {
        switch self {
        case .classes: return "Classes"
        case .bell: return "Bell Schedule"
        case .teachers: return "Teachers"
        }
    }
}

enum ReportsTab: String, CaseIterable, Identifiable {
    case cards, progress, transcript
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cards: return "Report Cards"
        case .progress: return "Progress Reports"
        case .transcript: return "Transcript"
        }
    }
}

enum GradesTab: String, CaseIterable, Identifiable {
    case classes, reportCard, gpa
    var id: String { rawValue }
    var title: String {
        switch self {
        case .classes: return "Classes"
        case .reportCard: return "Report Card"
        case .gpa: return "GPA"
        }
    }
}

/// Everything about grades in one place: this term's classes, report cards and
/// progress reports, and GPA. The switch sits in the toolbar.
struct GradesHub: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.gradesTab {
            case .classes: GradesView()
            case .reportCard: ReportsHub()
            case .gpa: GPAView()
            }
        }
        .navigationTitle(model.gradesTab == .classes ? "Grades" : model.gradesTab.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $model.gradesTab.animation(.snappy)) {
                    ForEach(GradesTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .sensoryFeedback(.selection, trigger: model.gradesTab)
    }
}

/// The picker at the top of the Report Card view.
struct ReportsModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker("Kind", selection: $model.reportsTab.animation(.snappy)) {
            ForEach(ReportsTab.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
    }
}

/// Schedule, bell times and teachers under one sidebar row.
struct ScheduleHub: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.scheduleTab {
            case .classes: ScheduleView()
            case .bell: BellScheduleView()
            case .teachers: TeachersView()
            }
        }
        .navigationTitle("Schedule")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $model.scheduleTab) {
                    ForEach(ScheduleTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

/// Report cards, progress reports and the transcript.
struct ReportsHub: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.reportsTab {
        case .cards, .progress: ReportCardsView()
        case .transcript: TranscriptView()
        }
    }
}
