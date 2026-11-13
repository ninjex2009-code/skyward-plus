import SwiftUI

/// The planner's month: a full-width grid where each day shows what's due.
/// Roomy windows list the first items by name; narrow ones show dots.
struct PlannerCalendar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.windowMetrics) private var metrics
    @Binding var selection: Date
    @State private var month: Date
    @State private var forward = true
    /// Month or week, remembered.
    @AppStorage("planner.span") private var span = "month"
    private var isWeek: Bool { span == "week" }

    private var calendar: Calendar { Calendar.current }

    init(selection: Binding<Date>) {
        _selection = selection
        let start = Calendar.current.dateInterval(of: .month, for: selection.wrappedValue)?.start ?? selection.wrappedValue
        _month = State(initialValue: start)
    }

    var body: some View {
        let roomy = metrics.width >= 640
        let days = isWeek ? weekDays : gridDays
        VStack(alignment: .leading, spacing: roomy ? 14 : 10) {
            header
            if isWeek && !roomy {
                // A phone's week: one line per day, the work beside it.
                VStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        if index > 0 { RowDivider() }
                        PlannerWeekRow(day: day, selected: calendar.isDate(day, inSameDayAs: selection)) {
                            withAnimation(.snappy(duration: 0.2)) { selection = day }
                        }
                    }
                }
                .id(weekStart)
                .transition(.opacity)
            } else {
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
                        inMonth: isWeek || calendar.isDate(day, equalTo: month, toGranularity: .month),
                        selected: calendar.isDate(day, inSameDayAs: selection),
                        roomy: roomy,
                        limit: isWeek ? 6 : 2,
                        minHeight: isWeek ? 260 : nil
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            selection = day
                            if !calendar.isDate(day, equalTo: month, toGranularity: .month) { month = startOfMonth(day) }
                        }
                    }
                }
            }
            .id(isWeek ? weekStart : month)
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .opacity
            ))
            }
        }
        .clipped()
        .padding(roomy ? 18 : 12)
        .bubble(cornerRadius: 20)
        .onChange(of: selection) { _, day in
            if !calendar.isDate(day, equalTo: month, toGranularity: .month) { month = startOfMonth(day) }
        }
    }

    private var header: some View {
        let roomy = metrics.width >= 640
        let spanPicker = Picker("View", selection: Binding(get: { span }, set: { value in withAnimation(.snappy(duration: 0.25)) { span = value } })) {
            Text("Month").tag("month")
            Text("Week").tag("week")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(isWeek ? weekTitle : month.formatted(.dateTime.month(.wide).year()))
                    .font(.display(22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Spacer(minLength: 8)
                if roomy { spanPicker.fixedSize() }
                Button("Previous", systemImage: "chevron.left") { shift(-1) }
                    .labelStyle(.iconOnly)
                Button("Today") {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = calendar.startOfDay(for: model.now())
                        month = startOfMonth(selection)
                    }
                }
                .fixedSize()
                Button("Next", systemImage: "chevron.right") { shift(1) }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            // On a phone the switch gets its own row instead of squeezing the title.
            if !roomy { spanPicker }
        }
    }

    private func shift(_ step: Int) {
        forward = step > 0
        withAnimation(.snappy(duration: 0.28)) {
            if isWeek {
                selection = calendar.date(byAdding: .day, value: 7 * step, to: selection) ?? selection
                month = startOfMonth(selection)
            } else {
                month = calendar.date(byAdding: .month, value: step, to: month) ?? month
            }
        }
    }

    /// The first day of the selected day's week.
    private var weekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: selection)?.start ?? calendar.startOfDay(for: selection)
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// "Nov 9 – 15" or "Nov 30 – Dec 6".
    private var weekTitle: String {
        guard let end = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return "" }
        let sameMonth = calendar.isDate(weekStart, equalTo: end, toGranularity: .month)
        let start = weekStart.formatted(.dateTime.month(.abbreviated).day())
        let finish = sameMonth ? end.formatted(.dateTime.day()) : end.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(finish)"
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
    var limit = 2
    var minHeight: CGFloat? = nil
    let action: () -> Void
    @State private var hovering = false

    struct Entry: Identifiable {
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
        let shared = StudyGroups.shared.plannerItems(on: day).map {
            Entry(id: $0.id, title: $0.title, mine: false, done: false, color: model.theme.color)
        }
        return (tasks + work + shared).sorted { ($0.done ? 1 : 0) < ($1.done ? 1 : 0) }
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
                    ForEach(items.prefix(limit)) { entry in
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
                    if items.count > limit {
                        Text("+\(items.count - limit) more")
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
            .frame(maxWidth: .infinity, minHeight: minHeight ?? (roomy ? 96 : 50), alignment: roomy ? .topLeading : .top)
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

/// One day of the week on a phone: the date on the left, what's due beside it.
private struct PlannerWeekRow: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let isToday = Calendar.current.isDate(day, inSameDayAs: model.now())
        let tasks = model.tasks(dueOn: day).map { ($0.title, $0.done, model.classColor($0.courseID)) }
        let work = model.assignments(dueOn: day).map { ($0.assignment.name, model.prefs.doneAssignments.contains($0.id), model.classColor($0.course.id)) }
        let shared = StudyGroups.shared.plannerItems(on: day).map { ($0.title, false, model.theme.color) }
        let items = tasks + work + shared
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isToday ? model.theme.color : .secondary)
                    Text(day.formatted(.dateTime.day()))
                        .font(.title3.weight(isToday ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(isToday ? model.theme.color : .primary)
                }
                .frame(width: 40)
                VStack(alignment: .leading, spacing: 6) {
                    if items.isEmpty {
                        Text("Nothing due").font(.subheadline).foregroundStyle(.tertiary)
                    }
                    ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 8) {
                            Circle().fill(item.2).frame(width: 6, height: 6)
                            Text(item.0)
                                .font(.subheadline)
                                .lineLimit(1)
                                .strikethrough(item.1)
                                .foregroundStyle(item.1 ? .secondary : .primary)
                        }
                    }
                    if items.count > 3 {
                        Text("+\(items.count - 3) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(model.theme.color.opacity(0.1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (items.isEmpty ? ", nothing due" : ", \(items.count) due"))
    }
}
