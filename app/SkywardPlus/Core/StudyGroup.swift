import Foundation

/// A study group: a few friends sharing a to-do list, study sessions and due dates.
/// Stored as plain fields (not one opaque blob) so the database rules can check them.
struct StudyGroup: Codable, Identifiable, Equatable {
    var id: String = ""
    var name: String
    var owner: String
    var code: String
    var createdAt: Double
    var members: [String: Member]?
    /// Eight numbered places ("0"…"7") holding a member's id; joining claims a free one.
    var seats: [String: String]?
    var tasks: [String: Task]?
    var sessions: [String: Session]?
    var dues: [String: Due]?
    /// Class averages, only for members who chose to share them.
    var averages: [String: [String: Double]]?

    static let maxMembers = 8

    struct Member: Codable, Equatable {
        var name: String
        var joinedAt: Double
        /// The invite code they joined with, and the seat they hold (the rules check both).
        var code: String?
        var seat: Int?
    }

    struct Task: Codable, Equatable {
        var title: String
        var done: Bool
        var by: String
        var createdAt: Double
    }

    struct Session: Codable, Equatable {
        var title: String
        var start: Double
        var minutes: Int
        var by: String
    }

    struct Due: Codable, Equatable {
        var title: String
        var course: String
        var due: Double
        var by: String
    }

    var memberList: [(id: String, member: Member)] {
        (members ?? [:]).map { ($0.key, $0.value) }.sorted { $0.member.joinedAt < $1.member.joinedAt }
    }

    var openTasks: [(id: String, task: Task)] {
        (tasks ?? [:]).map { ($0.key, $0.value) }.sorted { ($0.task.done ? 1 : 0, $0.task.createdAt) < ($1.task.done ? 1 : 0, $1.task.createdAt) }
    }

    func upcomingSessions(after now: Date) -> [(id: String, session: Session)] {
        let cutoff = now.timeIntervalSince1970 - 3_600
        return (sessions ?? [:]).filter { $0.value.start >= cutoff }.map { ($0.key, $0.value) }.sorted { $0.session.start < $1.session.start }
    }

    func upcomingDues(after now: Date) -> [(id: String, due: Due)] {
        let start = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        return (dues ?? [:]).filter { $0.value.due >= start }.map { ($0.key, $0.value) }.sorted { $0.due.due < $1.due.due }
    }

    var isFull: Bool { (members?.count ?? 0) >= Self.maxMembers }
}

enum InviteCode {
    /// No 0/O, 1/I/L, so codes read cleanly out loud.
    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    static func make() -> String {
        String((0..<6).map { _ in alphabet.randomElement()! })
    }

    /// Cleans up what someone typed or pasted: case, spaces, dashes, or a whole link.
    static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "join/", options: .backwards) {
            // A pasted invite message: the code is what follows the link.
            text = String(text[range.upperBound...].prefix { $0.isLetter || $0.isNumber })
        }
        let cleaned = text.uppercased().filter { alphabet.contains($0) }
        return cleaned.count == 6 ? cleaned : nil
    }

    static func link(_ code: String) -> String { "skywardplus://join/\(code)" }
}
