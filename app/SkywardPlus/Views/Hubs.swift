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
    case cards, transcript
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cards: return "Report Cards"
        case .transcript: return "Transcript"
        }
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

/// Report cards and the transcript under one sidebar row.
struct ReportsHub: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.reportsTab {
            case .cards: ReportCardsView()
            case .transcript: TranscriptView()
            }
        }
        .navigationTitle("Report Cards")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $model.reportsTab) {
                    ForEach(ReportsTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}
