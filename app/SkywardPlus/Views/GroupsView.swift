import SwiftUI

/// Study groups: the list, plus creating and joining.
struct GroupsView: View {
    @Environment(AppModel.self) private var model
    @State private var store = StudyGroups.shared
    @State private var creating = false
    @State private var joining = false
    @State private var nameText = ""
    @State private var codeText = ""
    @State private var error: String?

    var body: some View {
        Screen(title: "Study Groups", maxWidth: 720) {
            if !store.isAvailable {
                Card {
                    EmptyState(symbol: "person.3", title: "Sign in to use groups",
                               message: "Groups live in your Skyward Plus account. Sign in with Google in Settings → Account.")
                }
            } else {
                HStack(spacing: 10) {
                    Button("New Group", systemImage: "plus") { nameText = ""; creating = true }
                        .buttonStyle(.borderedProminent)
                    Button("Join with Code", systemImage: "person.badge.plus") { codeText = ""; joining = true }
                        .buttonStyle(.bordered)
                    Spacer()
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Palette.bad)
                }
                if store.groups.isEmpty && !store.loading {
                    Card {
                        EmptyState(symbol: "person.3", title: "No groups yet",
                                   message: "Make one and send friends the invite, or join with a friend's code.")
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(store.groups.enumerated()), id: \.element.id) { index, group in
                            if index > 0 { RowDivider() }
                            NavigationLink(value: GroupRoute(id: group.id)) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.name).font(.body.weight(.medium))
                                        Text("\(group.members?.count ?? 1) people").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 58)
                                .bubble()
                            }
                            .buttonStyle(BubbleButtonStyle())
                        }
                    }
                    .environment(\.inRowGroup, true)
                    .surface(cornerRadius: 16)
                }
            }
        }
        .refreshable { await store.load() }
        .task { await store.load() }
        .onChange(of: model.pendingGroupCode) { _, code in
            if let code { codeText = code; joining = true; model.pendingGroupCode = nil }
        }
        .onAppear {
            if let code = model.pendingGroupCode { codeText = code; joining = true; model.pendingGroupCode = nil }
        }
        .alert("New Study Group", isPresented: $creating) {
            TextField("Name (e.g. AP Bio crew)", text: $nameText)
            Button("Create") { run { try await store.create(name: nameText.trimmingCharacters(in: .whitespaces), myName: myName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Up to \(StudyGroup.maxMembers) people. You can send the invite next.")
        }
        .alert("Join a Group", isPresented: $joining) {
            TextField("Invite code", text: $codeText)
            Button("Join") { run { try await store.join(code: codeText, myName: myName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste the link or type the 6-character code a friend sent you.")
        }
    }

    private var myName: String { model.active?.firstName ?? "Student" }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work(); error = nil } catch { self.error = error.localizedDescription }
        }
    }
}

struct GroupRoute: Hashable { var id: String }

/// One group: its to-dos, study sessions and due dates, then the people.
struct GroupDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var store = StudyGroups.shared
    let id: String
    @State private var newTask = ""
    @State private var addingSession = false
    @State private var addingDue = false
    @State private var shownMember: String?
    @State private var confirmLeave = false
    @State private var error: String?

    var body: some View {
        if let group = store.group(id) {
            Screen(title: group.name, maxWidth: 720) {
                header(group)
                if let error { Text(error).font(.footnote).foregroundStyle(Palette.bad) }
                tasks(group)
                sessions(group)
                dues(group)
                members(group)
            }
            .refreshable { await store.load() }
            .sheet(isPresented: $addingSession) {
                NavigationStack { GroupSessionSheet(group: group) }
            }
            .sheet(isPresented: $addingDue) {
                NavigationStack { GroupDueSheet(group: group) }
            }
            .sheet(item: Binding(get: { shownMember.map { MemberID(id: $0) } }, set: { shownMember = $0?.id })) { member in
                NavigationStack { MemberAveragesSheet(group: group, memberID: member.id) }
            }
            .confirmationDialog(group.owner == store.myID ? "Delete \(group.name) for everyone?" : "Leave \(group.name)?",
                                isPresented: $confirmLeave, titleVisibility: .visible) {
                Button(group.owner == store.myID ? "Delete Group" : "Leave Group", role: .destructive) {
                    run { try await store.leave(group); dismiss() }
                }
            }
        } else {
            Screen(title: "Study Group") {
                Card { EmptyState(symbol: "person.3", title: "This group is gone", message: "It was deleted or you were removed.") }
            }
        }
    }

    // MARK: Sections

    private func header(_ group: StudyGroup) -> some View {
        let text = "Join my study group “\(group.name)” in Skyward Plus: \(InviteCode.link(group.code)) (code \(group.code))"
        return HStack(spacing: 10) {
            Text("Code \(group.code)").font(.subheadline.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer()
            if !group.isFull {
                ShareLink(item: text) { Label("Invite", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func tasks(_ group: StudyGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("To-do")
            VStack(spacing: 0) {
                ForEach(Array(group.openTasks.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        Button {
                            run { try await store.setTask(item.id, done: !item.task.done, in: group) }
                        } label: {
                            Image(systemName: item.task.done ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(item.task.done ? AnyShapeStyle(model.theme.color) : AnyShapeStyle(.secondary))
                        }
                        .buttonStyle(.plain)
                        Text(item.task.title)
                            .strikethrough(item.task.done)
                            .foregroundStyle(item.task.done ? .secondary : .primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .contextMenu {
                        Button("Delete", role: .destructive) { run { try await store.deleteTask(item.id, in: group) } }
                    }
                }
                if !group.openTasks.isEmpty { RowDivider() }
                HStack(spacing: 12) {
                    Image(systemName: "plus").foregroundStyle(model.theme.color).frame(width: 22)
                    TextField("Add a to-do", text: $newTask)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            let title = newTask.trimmingCharacters(in: .whitespaces)
                            guard !title.isEmpty else { return }
                            newTask = ""
                            run { try await store.addTask(title, to: group) }
                        }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
            }
            .surface(cornerRadius: 16)
        }
    }

    private func sessions(_ group: StudyGroup) -> some View {
        let list = group.upcomingSessions(after: model.now())
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader("Study sessions")
                Spacer()
                Button("Plan", systemImage: "plus") { addingSession = true }.labelStyle(.iconOnly).buttonStyle(.bordered)
            }
            if list.isEmpty {
                Text("Nothing planned.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider() }
                        let start = Date(timeIntervalSince1970: item.session.start)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.session.title).font(.body.weight(.medium))
                                Text(start.formatted(.dateTime.weekday(.wide).hour().minute()) + " · \(item.session.minutes) min")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                        .contextMenu {
                            Button("Delete", role: .destructive) { run { try await store.deleteSession(item.id, in: group) } }
                        }
                    }
                }
                .surface(cornerRadius: 16)
            }
        }
    }

    private func dues(_ group: StudyGroup) -> some View {
        let list = group.upcomingDues(after: model.now())
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader("Due dates")
                Spacer()
                Button("Share a due date", systemImage: "plus") { addingDue = true }.labelStyle(.iconOnly).buttonStyle(.bordered)
            }
            if list.isEmpty {
                Text("None shared yet.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider() }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.due.title).font(.body.weight(.medium))
                                if !item.due.course.isEmpty {
                                    Text(item.due.course).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(Fmt.dueDay(Date(timeIntervalSince1970: item.due.due), now: model.now()))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                        .contextMenu {
                            Button("Delete", role: .destructive) { run { try await store.deleteDue(item.id, in: group) } }
                        }
                    }
                }
                .surface(cornerRadius: 16)
            }
        }
    }

    private func members(_ group: StudyGroup) -> some View {
        let me = store.myID ?? ""
        let sharing = group.averages?[me] != nil
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("People", subtitle: "\(group.members?.count ?? 0) of \(StudyGroup.maxMembers)")
            VStack(spacing: 0) {
                ForEach(Array(group.memberList.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider() }
                    let shares = group.averages?[item.id] != nil
                    Button {
                        if shares { shownMember = item.id }
                    } label: {
                        HStack {
                            Text(item.member.name + (item.id == me ? " (you)" : "")).foregroundStyle(.primary)
                            if item.id == group.owner {
                                Text("Owner").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if shares { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if group.owner == me, item.id != me {
                            Button("Remove from Group", role: .destructive) { run { try await store.remove(memberID: item.id, from: group) } }
                        }
                    }
                }
            }
            .surface(cornerRadius: 16)
            Toggle("Share my class averages with this group", isOn: Binding(
                get: { sharing },
                set: { on in run { try await store.shareAverages(on ? myAverages : nil, in: group) } }
            ))
            .font(.subheadline)
            Button(group.owner == me ? "Delete Group" : "Leave Group", role: .destructive) { confirmLeave = true }
                .font(.subheadline)
                .padding(.top, 4)
        }
    }

    /// This student's current class averages, by class name.
    private var myAverages: [String: Double] {
        guard let lit = model.selectedLit else { return [:] }
        var out: [String: Double] = [:]
        for course in model.courses(in: lit) {
            if let p = model.percent(course, lit) {
                // Firebase keys can't contain . # $ [ ] /
                let key = Str.titleCase(course.name).filter { !".#$[]/".contains($0) }
                out[key] = (p * 10).rounded() / 10
            }
        }
        return out
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work(); error = nil } catch { self.error = error.localizedDescription }
        }
    }
}

private struct MemberID: Identifiable { var id: String }

/// A member's shared averages, shown only when tapped.
private struct MemberAveragesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: StudyGroup
    let memberID: String

    var body: some View {
        let averages = (group.averages?[memberID] ?? [:]).sorted { $0.key < $1.key }
        List {
            ForEach(averages, id: \.key) { name, value in
                LabeledContent(name) {
                    Text(Fmt.percent(value)).monospacedDigit().foregroundStyle(GradeColor.color(percent: value))
                }
            }
        }
        .navigationTitle(group.members?[memberID]?.name ?? "Averages")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

private struct GroupSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: StudyGroup
    @State private var title = "Study session"
    @State private var start = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var minutes = 60

    var body: some View {
        Form {
            TextField("What", text: $title)
            DatePicker("When", selection: $start)
            Picker("Length", selection: $minutes) {
                ForEach([30, 45, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Plan a Session")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    Task { try? await StudyGroups.shared.addSession(title, start: start, minutes: minutes, to: group); dismiss() }
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

private struct GroupDueSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let group: StudyGroup
    @State private var picked = ""

    var body: some View {
        let upcoming = model.dueItems.filter { !$0.done && $0.due >= Calendar.current.startOfDay(for: model.now()) }
        List(upcoming) { item in
            Button {
                Task { try? await StudyGroups.shared.addDue(item.title, course: item.course, due: item.due, to: group); dismiss() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).foregroundStyle(.primary)
                        if !item.course.isEmpty { Text(item.course).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(Fmt.dueDay(item.due, now: model.now())).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .overlay { if upcoming.isEmpty { ContentUnavailableView("Nothing coming up", systemImage: "calendar") } }
        .navigationTitle("Share a Due Date")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}
