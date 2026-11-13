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
                    // Small: the big number leads and the period is a short label.
                    Text(family == .systemSmall ? shortPeriod(s.period) : (s.period.isEmpty ? "Grades" : s.period))
                        .font(family == .systemSmall ? .caption.weight(.semibold) : .headline)
                        .foregroundStyle(family == .systemSmall ? .secondary : .primary)
                        .lineLimit(1)
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
                        Text(family == .systemSmall ? shortName(course.name) : course.name)
                            .font(family == .systemSmall ? .caption : .subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if course.belowGoal {
                            Image(systemName: "flag.fill").font(.caption2).foregroundStyle(.orange)
                        }
                        Text(course.grade)
                            .font((family == .systemSmall ? Font.caption : .subheadline).weight(.semibold).monospacedDigit())
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

#if os(iOS)
/// Lock Screen: the average as a ring, or one line.
struct AverageLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SkywardPlusAverage", provider: SnapshotProvider()) { entry in
            AverageLockView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "skywardplus://grades"))
        }
        .configurationDisplayName("Average")
        .description("Your average for the current marking period.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct AverageLockView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        let average = entry.snapshot?.average
        if family == .accessoryInline {
            Text(average.map { "Average \(shortNumber($0))" } ?? "Skyward Plus")
        } else {
            Gauge(value: min(100, max(60, average ?? 60)), in: 60...100) {
                Text("Avg")
            } currentValueLabel: {
                Text(average.map { shortNumber($0) } ?? "–")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
    }
}

/// Lock Screen: the next thing due.
struct NextDueLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SkywardPlusNextDue", provider: SnapshotProvider()) { entry in
            NextDueLockView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "skywardplus://planner"))
        }
        .configurationDisplayName("Next Due")
        .description("The next assignment or task that's due.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct NextDueLockView: View {
    var entry: SnapshotEntry

    var body: some View {
        if let next = entry.snapshot?.due.first {
            VStack(alignment: .leading, spacing: 1) {
                Text(next.due, format: .dateTime.weekday(.wide))
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(next.title).font(.headline).lineLimit(1)
                if !next.course.isEmpty {
                    Text(next.course).font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Nothing due").font(.headline)
        }
    }
}
#endif

@main
struct SkywardPlusWidgets: WidgetBundle {
    var body: some Widget {
        GradesWidget()
        DueWidget()
        #if os(iOS)
        AverageLockWidget()
        NextDueLockWidget()
        #endif
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

/// "Quarter 2" → "Q2", "Semester 1" → "S1".
func shortPeriod(_ period: String) -> String {
    let parts = period.split(separator: " ")
    guard parts.count == 2, let first = parts.first?.first else { return period.isEmpty ? "Grades" : period }
    return "\(first)\(parts[1])"
}

/// Drops the "AP " / "Honors" noise so a class fits a small widget.
func shortName(_ name: String) -> String {
    var n = name
    for prefix in ["AP ", "Pre-AP ", "IB "] where n.hasPrefix(prefix) { n.removeFirst(prefix.count) }
    for suffix in [" Honors", " Hon"] where n.hasSuffix(suffix) { n.removeLast(suffix.count) }
    return n
}
