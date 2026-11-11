import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app asks for a reload after each sync; this is only a fallback.
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

private func gradeColor(_ percent: Double?) -> Color {
    guard let percent else { return .secondary }
    switch percent {
    case 89.5...: return Color(red: 0.06, green: 0.73, blue: 0.51)
    case 79.5..<89.5: return Color(red: 0.23, green: 0.51, blue: 0.96)
    case 69.5..<79.5: return Color(red: 0.96, green: 0.62, blue: 0.04)
    case 59.5..<69.5: return Color(red: 0.98, green: 0.45, blue: 0.09)
    default: return Color(red: 0.94, green: 0.27, blue: 0.27)
    }
}

private func shortNumber(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
}

struct GradesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(s.period.isEmpty ? "Grades" : s.period).font(.headline)
                    Spacer()
                    if let average = s.average {
                        Text(shortNumber(average))
                            .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(gradeColor(average))
                    }
                }
                let limit = family == .systemLarge ? 10 : (family == .systemMedium ? 4 : 3)
                ForEach(Array(s.courses.prefix(limit)), id: \.self) { course in
                    HStack {
                        Text(course.name).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 4)
                        if course.belowGoal {
                            Image(systemName: "flag.fill").font(.caption2).foregroundStyle(.orange)
                        }
                        Text(course.grade)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(gradeColor(course.percent))
                    }
                }
                Spacer(minLength: 0)
                if s.missing > 0 {
                    Text("\(s.missing) missing").font(.caption.weight(.medium)).foregroundStyle(.red)
                } else {
                    Text("Updated \(s.updated, style: .relative) ago").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Open Skyward Plus to sign in.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct DueWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                Text("Due Soon").font(.headline)
                if s.due.isEmpty {
                    Spacer()
                    Text("Nothing due this week.").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    let limit = family == .systemLarge ? 8 : (family == .systemMedium ? 3 : 2)
                    ForEach(Array(s.due.prefix(limit)), id: \.self) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text("\(item.course.isEmpty ? "" : item.course + " · ")\(item.due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        } else {
            Text("Open Skyward Plus to sign in.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct GradesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SkywardPlusGrades", provider: SnapshotProvider()) { entry in
            GradesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "skywardplus://grades"))
        }
        .configurationDisplayName("Grades")
        .description("Your classes and averages for the current marking period.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SkywardPlusDue", provider: SnapshotProvider()) { entry in
            DueWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "skywardplus://planner"))
        }
        .configurationDisplayName("Due Soon")
        .description("Skyward assignments and your planner tasks for the week.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct SkywardPlusWidgets: WidgetBundle {
    var body: some Widget {
        GradesWidget()
        DueWidget()
    }
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(
        student: "Jordan", period: "Q2", average: 94.6, gpa: 4.5, missing: 0,
        courses: [
            .init(name: "AP Calculus BC", grade: "95.1", percent: 95.1, belowGoal: false),
            .init(name: "AP English Lit", grade: "92.9", percent: 92.9, belowGoal: false),
            .init(name: "Organic Chemistry", grade: "86", percent: 86, belowGoal: true),
        ],
        due: [.init(title: "Unit 4 Integration Test", course: "AP Calculus BC", due: .now.addingTimeInterval(86_400 * 2))],
        updated: .now
    )
}
