import SwiftUI

/// The planner's month: a full-width grid where each day shows what's due.
/// Roomy windows list the first items by name; narrow ones show dots.
struct PlannerCalendar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.windowMetrics) private var metrics
    @Binding var selection: Date
    @State private var month: Date
    @State private var forward = true

    private var calendar: Calendar { Calendar.current }

    init(selection: Binding<Date>) {
        _selection = selection
        let start = Calendar.current.dateInterval(of: .month, for: selection.wrappedValue)?.start ?? selection.wrappedValue
        _month = State(initialValue: start)
    }

    var body: some View {
        let roomy = metrics.width >= 640
        let days = gridDays
        VStack(alignment: .leading, spacing: roomy ? 14 : 10) {
            header
            HStack(spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(days, id: \.self) { day in
                    PlannerDayCell(
                        day: day,
                        inMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                        selected: calendar.isDate(day, inSameDayAs: selection),
                        roomy: roomy
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            selection = day
                            if !calendar.isDate(day, equalTo: month, toGranularity: .month) { month = startOfMonth(day) }
                        }
                    }
                }
            }
            .id(month)
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .opacity
            ))
        }
        .clipped()
        .padding(roomy ? 18 : 12)
        .bubble(cornerRadius: 20)
        .onChange(of: selection) { _, day in
            if !calendar.isDate(day, equalTo: month, toGranularity: .month) { month = startOfMonth(day) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.display(22))
                .contentTransition(.numericText())
            Spacer()
            Button("Previous month", systemImage: "chevron.left") { shift(-1) }
                .labelStyle(.iconOnly)
            Button("Today") {
                withAnimation(.snappy(duration: 0.2)) {
                    selection = calendar.startOfDay(for: model.now())
                    month = startOfMonth(selection)
                }
            }
            Button("Next month", systemImage: "chevron.right") { shift(1) }
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private func shift(_ months: Int) {
        forward = months > 0
        withAnimation(.snappy(duration: 0.28)) {
            month = calendar.date(byAdding: .month, value: months, to: month) ?? month
        }
    }

    private func startOfMonth(_ day: Date) -> Date {
        calendar.dateInterval(of: .month, for: day)?.start ?? day
    }

    /// Weekday initials starting on the locale's first day of the week.
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Whole weeks covering the month, padded with the neighbouring months' days.
    private var gridDays: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let total = Int(ceil(Double(lead + count) / 7)) * 7
        return (0..<total).compactMap { calendar.date(byAdding: .day, value: $0 - lead, to: interval.start) }
    }
}

/// One day in the planner's month.
private struct PlannerDayCell: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let inMonth: Bool
    let selected: Bool
    let roomy: Bool
    let action: () -> Void
    @State private var hovering = false

    private struct Entry: Identifiable {
        var id: String
        var title: String
        var mine: Bool
        var done: Bool
        var color: Color
    }

    private var entries: [Entry] {
        let tasks = model.tasks(dueOn: day).map { Entry(id: "t" + $0.id.uuidString, title: $0.title, mine: true, done: $0.done, color: model.classColor($0.courseID)) }
        let work = model.assignments(dueOn: day).map {
            Entry(id: "s" + $0.id, title: $0.assignment.name, mine: false, done: model.prefs.doneAssignments.contains($0.id), color: model.classColor($0.course.id))
        }
        return (tasks + work).sorted { ($0.done ? 1 : 0) < ($1.done ? 1 : 0) }
    }

    var body: some View {
        let isToday = Calendar.current.isDate(day, inSameDayAs: model.now())
        let items = entries
        Button(action: action) {
            VStack(alignment: roomy ? .leading : .center, spacing: 4) {
                Text(day.formatted(.dateTime.day()))
                    .font((roomy ? Font.callout : .footnote).weight(isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : inMonth ? Color.primary : Color.secondary.opacity(0.6))
                    .frame(minWidth: roomy ? 26 : 22, minHeight: roomy ? 26 : 22)
                    .background { if isToday { Circle().fill(model.theme.color) } }
                if roomy {
                    ForEach(items.prefix(2)) { entry in
                        Text(entry.title)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .strikethrough(entry.done)
                            .foregroundStyle(.primary)
                            .opacity(entry.done ? 0.5 : 1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(entry.color.opacity(0.2), in: .rect(cornerRadius: 5))
                            .overlay(alignment: .leading) {
                                UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5)
                                    .fill(entry.color)
                                    .frame(width: 3)
                            }
                    }
                    if items.count > 2 {
                        Text("+\(items.count - 2) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                    }
                } else if !items.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(items.prefix(3)) { entry in
                            Circle()
                                .fill(entry.color)
                                .opacity(entry.done ? 0.35 : 1)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(roomy ? 8 : 4)
            .frame(maxWidth: .infinity, minHeight: roomy ? 96 : 50, alignment: roomy ? .topLeading : .top)
            .background {
                RoundedRectangle(cornerRadius: roomy ? 12 : 9, style: .continuous)
                    .fill(selected ? model.theme.color.opacity(0.16) : Color.primary.opacity(hovering ? 0.07 : inMonth ? 0.035 : 0.015))
            }
            .overlay {
                RoundedRectangle(cornerRadius: roomy ? 12 : 9, style: .continuous)
                    .strokeBorder(selected ? model.theme.color.opacity(0.7) : .clear, lineWidth: 1.5)
            }
            .contentShape(.rect(cornerRadius: roomy ? 12 : 9))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (items.isEmpty ? "" : ", \(items.count) due"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
