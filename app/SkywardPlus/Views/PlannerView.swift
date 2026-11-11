import SwiftUI

struct PlannerView: View {
    private enum FilterMode: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming"
        case byDay = "By Day"
        case completed = "Completed"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var filter: FilterMode = .upcoming
    @State private var selectedDay: Date = Date()
    @State private var editingTask: PlannerTask?
    @State private var creatingTask = false

    var body: some View {
        Screen(title: "Planner") {
            Picker("View", selection: $filter.animation(.snappy)) {
                ForEach(FilterMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity)
            .staggered(0)

            switch filter {
            case .upcoming:
                upcomingContent
                    .staggered(1)
            case .byDay:
                byDayContent
                    .staggered(1)
            case .completed:
                completedContent
                    .staggered(1)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Task", systemImage: "plus") { creatingTask = true }
                    .help("New task (⌘N)")
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .onAppear(perform: takeNewTaskRequest)
        .onChange(of: model.newTaskRequest) { _, _ in takeNewTaskRequest() }
        .sheet(isPresented: $creatingTask) {
            NavigationStack {
                TaskEditorSheet(task: PlannerTask(title: "", due: selectedDay), isNew: true)
            }
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 460)
            #endif
        }
        .sheet(item: $editingTask) { task in
            NavigationStack {
                TaskEditorSheet(task: task, isNew: false)
            }
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 460)
            #endif
        }
    }

    private func takeNewTaskRequest() {
        guard model.newTaskRequest else { return }
        model.newTaskRequest = false
        creatingTask = true
    }

    private var upcomingContent: some View {
        let openTasks = model.prefs.tasks.filter { !$0.done }.sorted { $0.due < $1.due }
        let skywardWork = model.upcomingAssignments.filter { !model.prefs.doneAssignments.contains($0.id) }

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Your Tasks", subtitle: "\(openTasks.count) open")
                if openTasks.isEmpty {
                    Card {
                        EmptyState(
                            symbol: "checklist",
                            title: "No open tasks",
                            message: "Add homework, study goals or test reminders and link them to your classes."
                        )
                    }
                } else {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(openTasks.enumerated()), id: \.element.id) { index, task in
                                HoverRow {
                                    taskRow(task)
                                }
                                .rowDivider(index < openTasks.count - 1)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("From Skyward", subtitle: "\(skywardWork.count) upcoming")
                if skywardWork.isEmpty {
                    Card {
                        EmptyState(
                            symbol: "tray",
                            title: "No upcoming Skyward work",
                            message: "Ungraded assignments with future due dates appear here automatically."
                        )
                    }
                } else {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(skywardWork.enumerated()), id: \.element.id) { index, item in
                                HoverRow {
                                    skywardAssignmentRow(item)
                                }
                                .rowDivider(index < skywardWork.count - 1)
                            }
                        }
                    }
                }
            }
        }
    }

    private var byDayContent: some View {
        let dayTasks = model.tasks(dueOn: selectedDay)
        let daySkyward = model.assignments(dueOn: selectedDay)

        return VStack(alignment: .leading, spacing: 14) {
            Card {
                DatePicker("Select Date", selection: $selectedDay, displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }

            SectionHeader(Fmt.day(selectedDay), subtitle: "\(dayTasks.count + daySkyward.count) items")
            if dayTasks.isEmpty && daySkyward.isEmpty {
                Card {
                    EmptyState(
                        symbol: "calendar",
                        title: "Nothing due on \(Fmt.shortDay(selectedDay))",
                        message: "Use Add Task to schedule work for this day."
                    )
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(dayTasks.enumerated()), id: \.element.id) { index, task in
                            HoverRow {
                                taskRow(task)
                            }
                            .rowDivider(index < dayTasks.count - 1 || !daySkyward.isEmpty)
                        }
                        ForEach(Array(daySkyward.enumerated()), id: \.element.id) { index, item in
                            HoverRow {
                                skywardAssignmentRow(item)
                            }
                            .rowDivider(index < daySkyward.count - 1)
                        }
                    }
                }
            }
        }
    }

    private var completedContent: some View {
        let doneTasks = model.prefs.tasks.filter { $0.done }.sorted { $0.due > $1.due }
        let doneSkyward = model.upcomingAssignments.filter { model.prefs.doneAssignments.contains($0.id) }

        return VStack(alignment: .leading, spacing: 14) {
            if doneTasks.isEmpty && doneSkyward.isEmpty {
                Card {
                    EmptyState(
                        symbol: "checkmark.circle",
                        title: "No completed items yet",
                        message: "Check off tasks or upcoming Skyward assignments as you finish them."
                    )
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(doneTasks.enumerated()), id: \.element.id) { index, task in
                            HoverRow {
                                taskRow(task)
                            }
                            .rowDivider(index < doneTasks.count - 1 || !doneSkyward.isEmpty)
                        }
                        ForEach(Array(doneSkyward.enumerated()), id: \.element.id) { index, item in
                            HoverRow {
                                skywardAssignmentRow(item)
                            }
                            .rowDivider(index < doneSkyward.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func taskRow(_ task: PlannerTask) -> some View {
        let course = task.courseID.flatMap { model.course($0) }
        let courseName = course.map { Str.titleCase($0.name) }
        let tint = model.theme.color

        return HStack(spacing: 12) {
            Button {
                withAnimation(Motion.snappy) {
                    model.toggleTask(task.id)
                }
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.done ? tint : Color.secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.done ? "Mark not done" : "Mark done")

            Button {
                editingTask = task
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(task.title)
                                .font(.body.weight(.medium))
                                .strikethrough(task.done)
                                .foregroundStyle(task.done ? .secondary : .primary)
                        }
                        HStack(spacing: 6) {
                            Text([task.kind.title, courseName ?? "", "due " + Fmt.dueDay(task.due, now: model.now())].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if task.remindAt != nil {
                                Image(systemName: "bell").font(.caption).foregroundStyle(.secondary)
                                    .accessibilityLabel("Reminder set")
                            }
                        }
                        if !task.notes.isEmpty {
                            Text(task.notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                withAnimation(Motion.snappy) {
                    model.deleteTask(task.id)
                }
            } label: {
                Image(systemName: "trash").font(.callout).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete task")
            .accessibilityLabel("Delete \(task.title)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func skywardAssignmentRow(_ item: AppModel.DatedAssignment) -> some View {
        let isDone = model.prefs.doneAssignments.contains(item.id)
        return HStack(spacing: 12) {
            Button {
                withAnimation(Motion.snappy) {
                    model.toggleAssignmentDone(item)
                }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? model.theme.color : Color.secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Mark not done" : "Mark done")

            NavigationLink(value: CourseRoute(courseID: item.course.id)) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.assignment.name)
                                .font(.body.weight(.medium))
                                .strikethrough(isDone)
                                .foregroundStyle(isDone ? .secondary : .primary)
                                .lineLimit(1)
                        }
                        Text("\(Str.titleCase(item.course.name)) · \(item.assignment.category)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let due = item.assignment.due {
                        Text(Fmt.relativeDay(due, now: model.now()))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Calendar.current.isDateInTomorrow(due) || Calendar.current.isDateInToday(due) ? Palette.warn : .secondary)
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

struct TaskEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State var task: PlannerTask
    let isNew: Bool
    @State private var hasReminder: Bool = false
    @State private var reminderDate: Date = Date().addingTimeInterval(3600)

    var body: some View {
        Form {
            Section("Task") {
                TextField("Title", text: $task.title)
                Picker("Type", selection: $task.kind) {
                    ForEach(TaskKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                Picker("Class", selection: Binding(
                    get: { task.courseID ?? "" },
                    set: { task.courseID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("None").tag("")
                    ForEach(model.courses) { course in
                        Text(Str.titleCase(course.name)).tag(course.id)
                    }
                }
                DatePicker("Due Date", selection: $task.due, displayedComponents: .date)
            }

            Section("Reminder") {
                Toggle("Remind Me", isOn: $hasReminder)
                if hasReminder {
                    DatePicker("Alert Time", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                }
            }

            Section("Notes") {
                TextField("Optional notes…", text: $task.notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            if !isNew {
                Section {
                    Button("Delete Task", role: .destructive) {
                        model.deleteTask(task.id)
                        dismiss()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "New Task" : "Edit Task")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    task.remindAt = hasReminder ? reminderDate : nil
                    if hasReminder {
                        Task { await Notifier.requestPermission() }
                    }
                    model.saveTask(task)
                    dismiss()
                }
                .disabled(task.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            if let remind = task.remindAt {
                hasReminder = true
                reminderDate = remind
            }
        }
    }
}
