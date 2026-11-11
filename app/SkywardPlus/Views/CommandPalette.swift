import SwiftUI

/// ⌘K: jump to any screen, class or assignment, or run a command, from the keyboard.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool
    @Namespace private var highlight

    struct Item: Identifiable {
        enum Kind { case section, course, assignment, action }
        var id: String
        var kind: Kind
        var title: String
        var subtitle: String
        var symbol: String
        var trailing: String = ""
        var run: @MainActor (AppModel) -> Void
    }

    var body: some View {
        let results = items
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("Search classes, assignments and screens", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { activate(results) }
                    .onKeyPress(.downArrow) { move(1, count: results.count); return .handled }
                    .onKeyPress(.upArrow) { move(-1, count: results.count); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            if !results.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, selected: index == selection)
                                    .id(index)
                                    .onTapGesture {
                                        selection = index
                                        activate(results)
                                    }
                            }
                        }
                        .padding(6)
                        .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: selection)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selection) { _, value in
                        proxy.scrollTo(value, anchor: nil)
                    }
                }
            } else if !query.isEmpty {
                Divider()
                Text("No matches for “\(query)”")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
            }
        }
        .frame(width: 580)
        .glassSurface(cornerRadius: 18)
        .shadow(color: .black.opacity(0.18), radius: 28, y: 12)
        .onAppear {
            focused = true
            selection = 0
        }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.body)
                .foregroundStyle(selected ? Color.white : model.theme.color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if !item.trailing.isEmpty {
                Text(item.trailing)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.secondary)
            }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            // One highlight that glides between rows instead of blinking from one to the next.
            if selected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(model.theme.color)
                    .matchedGeometryEffect(id: "selection", in: highlight)
            }
        }
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func close() {
        withAnimation(reduceMotion ? nil : Motion.snappy) { model.showPalette = false }
    }

    private func activate(_ results: [Item]) {
        guard results.indices.contains(selection) else { return }
        let item = results[selection]
        close()
        item.run(model)
    }

    private var items: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        func matches(_ parts: String...) -> Bool {
            q.isEmpty || parts.contains { $0.lowercased().contains(q) }
        }
        var out: [Item] = []

        for section in AppSection.sidebar where matches(section.title) {
            out.append(Item(id: "s-" + section.rawValue, kind: .section, title: section.title, subtitle: "", symbol: section.symbol) { model in
                model.section = section
            })
        }
        for tab in [AppSection.bell, .teachers, .transcript] where !q.isEmpty && matches(tab.title) {
            out.append(Item(id: "s-" + tab.rawValue, kind: .section, title: tab.title, subtitle: "", symbol: tab.symbol) { model in
                model.section = tab
            })
        }

        let lit = model.selectedLit
        for course in model.courses where matches(course.name, course.teacher) {
            out.append(Item(
                id: "c-" + course.id, kind: .course, title: Str.titleCase(course.name),
                subtitle: [course.period.isEmpty ? "" : "Period \(course.period)", Str.titleCase(course.teacher)].filter { !$0.isEmpty }.joined(separator: " · "),
                symbol: "book.closed", trailing: lit.map { model.gradeText(course, $0) } ?? ""
            ) { model in
                model.section = .grades
                model.openCourse = course.id
            })
        }

        if !q.isEmpty, let lit {
            for course in model.courses {
                guard let detail = model.detail(course.id, lit) else { continue }
                for a in detail.assignments where matches(a.name) {
                    out.append(Item(
                        id: "a-" + course.id + a.id, kind: .assignment, title: a.name,
                        subtitle: Str.titleCase(course.name) + (a.due.map { " · due " + Fmt.shortDay($0) } ?? ""),
                        symbol: a.missing ? "exclamationmark.circle" : "doc.text",
                        trailing: a.isGraded ? (a.gradeText.isEmpty ? "" : a.gradeText) : ""
                    ) { model in
                        model.section = .grades
                        model.openCourse = course.id
                    })
                }
            }
        }

        let actions: [Item] = [
            Item(id: "x-refresh", kind: .action, title: "Refresh Grades", subtitle: "Sync with Skyward now", symbol: "arrow.clockwise") { model in
                Task { await model.refresh() }
            },
            Item(id: "x-task", kind: .action, title: "New Planner Task", subtitle: "Planner", symbol: "plus.circle") { model in
                model.section = .planner
                model.newTaskRequest = true
            },
            Item(id: "x-report", kind: .action, title: "Export Grade Report", subtitle: "Save a PDF", symbol: "doc.richtext") { model in
                #if os(macOS)
                model.exportReport()
                #endif
            },
            Item(id: "x-settings", kind: .action, title: "Settings", subtitle: "", symbol: "gearshape") { model in
                model.section = .settings
            },
        ]
        out.append(contentsOf: actions.filter { matches($0.title, $0.subtitle) && ($0.id != "x-settings" || !q.isEmpty) })
        return Array(out.prefix(40))
    }
}
