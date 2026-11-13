import Foundation

/// The student's study groups, read from and written to the shared account database.
/// Groups load when opened and on pull-to-refresh; nothing streams in the background.
@MainActor
@Observable
final class StudyGroups {
    static let shared = StudyGroups()

    private(set) var groups: [StudyGroup] = []
    private(set) var loading = false
    var message: String?

    private var account: AccountSync { AccountSync.shared }
    var isAvailable: Bool { account.isConfigured && account.isSignedIn }
    var myID: String? { account.userID }

    func group(_ id: String) -> StudyGroup? { groups.first { $0.id == id } }

    // MARK: Loading

    func load() async {
        guard let uid = myID else { groups = []; return }
        loading = true
        defer { loading = false }
        do {
            let ids: [String: Bool] = try await account.plainGet("users/\(uid)/groups") ?? [:]
            var loaded: [StudyGroup] = []
            for id in ids.keys {
                if var group: StudyGroup = try? await account.plainGet("groups/\(id)") {
                    group.id = id
                    loaded.append(group)
                }
            }
            groups = loaded.sorted { $0.createdAt < $1.createdAt }
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func reload(_ id: String) async {
        guard var group: StudyGroup = try? await account.plainGet("groups/\(id)") else {
            groups.removeAll { $0.id == id }
            return
        }
        group.id = id
        if let index = groups.firstIndex(where: { $0.id == id }) { groups[index] = group } else { groups.append(group) }
    }

    // MARK: Membership

    @discardableResult
    func create(name: String, myName: String) async throws -> String {
        guard let uid = myID else { throw AccountError("Sign in to your account first.") }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
        let code = InviteCode.make()
        let now = Date().timeIntervalSince1970
        let group = StudyGroup(name: name, owner: uid, code: code, createdAt: now,
                               members: [uid: .init(name: myName, joinedAt: now, code: code)])
        try await account.plainPut("groups/\(id)", group)
        try await account.plainPut("invites/\(code)", String(id))
        try await account.plainPut("users/\(uid)/groups/\(id)", true)
        await reload(String(id))
        return String(id)
    }

    @discardableResult
    func join(code raw: String, myName: String) async throws -> String {
        guard let uid = myID else { throw AccountError("Sign in to your account first.") }
        guard let code = InviteCode.normalize(raw) else { throw AccountError("That code doesn't look right. Codes are 6 letters and numbers.") }
        guard let id: String = try await account.plainGet("invites/\(code)") else {
            throw AccountError("No group has that code.")
        }
        do {
            try await account.plainPut("groups/\(id)/members/\(uid)",
                                       StudyGroup.Member(name: myName, joinedAt: Date().timeIntervalSince1970, code: code))
        } catch {
            throw AccountError("Couldn't join. The group may be full (\(StudyGroup.maxMembers) people) or the code changed.")
        }
        try await account.plainPut("users/\(uid)/groups/\(id)", true)
        await reload(id)
        return id
    }

    /// Leaving takes you out; when the owner leaves, the whole group is deleted.
    func leave(_ group: StudyGroup) async throws {
        guard let uid = myID else { return }
        if group.owner == uid {
            try await account.plainDelete("invites/\(group.code)")
            try await account.plainDelete("groups/\(group.id)")
        } else {
            try? await account.plainDelete("groups/\(group.id)/averages/\(uid)")
            try await account.plainDelete("groups/\(group.id)/members/\(uid)")
        }
        try await account.plainDelete("users/\(uid)/groups/\(group.id)")
        groups.removeAll { $0.id == group.id }
    }

    func remove(memberID: String, from group: StudyGroup) async throws {
        try? await account.plainDelete("groups/\(group.id)/averages/\(memberID)")
        try await account.plainDelete("groups/\(group.id)/members/\(memberID)")
        await reload(group.id)
    }

    // MARK: Shared things

    private func newKey() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased() }

    func addTask(_ title: String, to group: StudyGroup) async throws {
        guard let uid = myID else { return }
        try await account.plainPut("groups/\(group.id)/tasks/\(newKey())",
                                   StudyGroup.Task(title: title, done: false, by: uid, createdAt: Date().timeIntervalSince1970))
        await reload(group.id)
    }

    func setTask(_ id: String, done: Bool, in group: StudyGroup) async throws {
        guard var task = group.tasks?[id] else { return }
        task.done = done
        try await account.plainPut("groups/\(group.id)/tasks/\(id)", task)
        await reload(group.id)
    }

    func deleteTask(_ id: String, in group: StudyGroup) async throws {
        try await account.plainDelete("groups/\(group.id)/tasks/\(id)")
        await reload(group.id)
    }

    func addSession(_ title: String, start: Date, minutes: Int, to group: StudyGroup) async throws {
        guard let uid = myID else { return }
        try await account.plainPut("groups/\(group.id)/sessions/\(newKey())",
                                   StudyGroup.Session(title: title, start: start.timeIntervalSince1970, minutes: minutes, by: uid))
        await reload(group.id)
    }

    func deleteSession(_ id: String, in group: StudyGroup) async throws {
        try await account.plainDelete("groups/\(group.id)/sessions/\(id)")
        await reload(group.id)
    }

    func addDue(_ title: String, course: String, due: Date, to group: StudyGroup) async throws {
        guard let uid = myID else { return }
        try await account.plainPut("groups/\(group.id)/dues/\(newKey())",
                                   StudyGroup.Due(title: title, course: course, due: due.timeIntervalSince1970, by: uid))
        await reload(group.id)
    }

    func deleteDue(_ id: String, in group: StudyGroup) async throws {
        try await account.plainDelete("groups/\(group.id)/dues/\(id)")
        await reload(group.id)
    }

    /// Shares (or stops sharing) this student's class averages with one group.
    func shareAverages(_ averages: [String: Double]?, in group: StudyGroup) async throws {
        guard let uid = myID else { return }
        if let averages {
            try await account.plainPut("groups/\(group.id)/averages/\(uid)", averages)
        } else {
            try await account.plainDelete("groups/\(group.id)/averages/\(uid)")
        }
        await reload(group.id)
    }

    // MARK: For the planner

    struct PlannerItem: Identifiable, Hashable {
        var id: String
        var title: String
        var detail: String
        var date: Date
        var isSession: Bool
    }

    /// Study sessions and shared due dates from every group, for one day.
    func plannerItems(on day: Date) -> [PlannerItem] {
        let calendar = Calendar.current
        var out: [PlannerItem] = []
        for group in groups {
            for (id, s) in group.sessions ?? [:] where calendar.isDate(Date(timeIntervalSince1970: s.start), inSameDayAs: day) {
                out.append(PlannerItem(id: "gs" + id, title: s.title, detail: group.name, date: Date(timeIntervalSince1970: s.start), isSession: true))
            }
            for (id, d) in group.dues ?? [:] where calendar.isDate(Date(timeIntervalSince1970: d.due), inSameDayAs: day) {
                out.append(PlannerItem(id: "gd" + id, title: d.title, detail: [d.course, group.name].filter { !$0.isEmpty }.joined(separator: " · "),
                                       date: Date(timeIntervalSince1970: d.due), isSession: false))
            }
        }
        return out.sorted { $0.date < $1.date }
    }
}
