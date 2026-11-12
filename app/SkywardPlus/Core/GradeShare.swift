import Foundation

/// Sharing grades between a student's devices through their account. Whichever
/// device read Skyward most recently wins; an older copy can still fill in
/// assignment lists the newer one couldn't load (the iPhone, for example).
enum GradeShare {
    /// Small record stored beside the grades, so devices can tell whether to download them.
    struct Meta: Codable, Equatable {
        var syncedAt: Double
        var hash: String
    }

    /// The warning a sync leaves when some classes' assignments didn't load.
    static let missingWarningPrefix = "Assignments could not be loaded"

    /// Classes in the current marking period that should have an assignment list but don't.
    static func missingDetails(_ data: StudentData) -> [String] {
        guard let lit = data.currentLit else { return [] }
        return data.courses.compactMap { course in
            guard let grade = course.grade(lit), grade.hasDetail, data.details[StudentData.detailKey(course.id, lit)] == nil else { return nil }
            return course.id
        }
    }

    /// What this device should keep after seeing the account's copy, or nil to change nothing.
    static func combine(local: StudentData?, remote: StudentData) -> StudentData? {
        guard let remoteSync = remote.lastSync else { return nil }
        guard let local, let localSync = local.lastSync else { return remote }

        if remoteSync > localSync.addingTimeInterval(1) {
            // The account is newer: take it, keeping anything only this device has.
            var merged = remote
            for (key, detail) in local.details where merged.details[key] == nil { merged.details[key] = detail }
            if merged.history.isEmpty { merged.history = local.history }
            if merged.attendance.isEmpty { merged.attendance = local.attendance }
            if missingDetails(merged).isEmpty {
                merged.warnings.removeAll { $0.hasPrefix(missingWarningPrefix) }
            }
            return merged
        }

        // This device is newer: only fill assignment lists it couldn't load.
        var merged = local
        var filled = false
        for (key, detail) in remote.details where merged.details[key] == nil {
            let courseID = String(key.split(separator: "|").first ?? "")
            guard merged.courses.contains(where: { $0.id == courseID }) else { continue }
            merged.details[key] = detail
            filled = true
        }
        guard filled else { return nil }
        if missingDetails(merged).isEmpty {
            merged.warnings.removeAll { $0.hasPrefix(missingWarningPrefix) }
        }
        return merged
    }

    /// A fingerprint of what matters, so unchanged grades aren't uploaded again.
    static func fingerprint(_ data: StudentData) -> String {
        struct Essentials: Encodable {
            var courses: [Course]
            var details: [String: GradeDetail]
            var attendance: [AttendanceEvent]
            var changes: [GradeChange]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        var details = data.details
        for key in details.keys { details[key]?.fetchedAt = Date(timeIntervalSince1970: 0) }
        let essentials = Essentials(courses: data.courses, details: details, attendance: data.attendance, changes: data.changes)
        let text = (try? encoder.encode(essentials)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return Str.hash(text)
    }
}
