import Foundation

/// Pulls a student's data from Skyward and folds it into what the app already has.
enum SyncEngine {
    /// Assignment lists are fetched a few at a time, the way a person clicking
    /// through the gradebook would load them, not all at once.
    static let maxConcurrent = 3
    static let maxSnapshots = 400
    static let maxChanges = 200

    private static func isSignInProblem(_ error: Error) -> Bool {
        guard let e = error as? SkywardError else { return false }
        switch e {
        case .sessionExpired, .invalidLogin, .mfaRequired, .mfaInvalid, .notSignedIn, .ssoOnly, .qmlativ, .notSkyward:
            return true
        case .network, .server:
            return false
        }
    }

    /// Full refresh for the student selected on `session`.
    ///
    /// The gradebook is required. Assignment lists for the current term, the
    /// transcript, attendance and the profile are each best-effort: one failing
    /// leaves the earlier copy in place and adds a line to `warnings`.
    static func sync(
        session: SkywardSession,
        previous: StudentData?,
        now: Date = Date(),
        progress: ((String) -> Void)? = nil
    ) async throws -> StudentData {
        progress?("Loading gradebook")
        let page = try await session.gradebookPage()
        let students = SkywardParser.gradebook(page)
        let preferred = previous?.courses.first(where: { !$0.studentID.isEmpty })?.studentID
        guard let student = students.first(where: { $0.studentID == preferred }) ?? students.max(by: { $0.courses.count < $1.courses.count }),
              !student.courses.isEmpty else {
            throw SkywardError.server("Skyward opened, but no gradebook came back. Your district may not publish grades in Family Access, or its page is laid out in a way this app does not read yet.")
        }

        var data = previous ?? StudentData()
        data.buckets = student.buckets
        data.courses = student.courses
        data.warnings = []
        let courseIDs = Set(student.courses.map { $0.id })
        data.details = data.details.filter { key, _ in
            guard let id = key.split(separator: "|").first else { return false }
            return courseIDs.contains(String(id))
        }

        // Assignment lists for the marking period people are in right now.
        if let lit = data.currentLit {
            let targets = data.courses.compactMap { course -> (Course, PostedGrade)? in
                guard let grade = course.grade(lit), grade.hasDetail else { return nil }
                return (course, grade)
            }
            progress?("Loading assignments")
            let fetched = try await fetchDetails(session: session, targets: targets, now: now)
            for detail in fetched.details {
                data.details[StudentData.detailKey(detail.courseID, detail.lit)] = detail
            }
            if !fetched.failed.isEmpty {
                data.warnings.append("Assignments could not be loaded for: " + fetched.failed.joined(separator: ", ") + ".")
            }
        }

        // Slow-changing pages are refreshed about once a week.
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        if data.history.isEmpty || (data.historySyncedAt ?? .distantPast) < weekAgo {
            progress?("Loading transcript")
            do {
                let years = SkywardParser.history(try await session.historyPage())
                if !years.isEmpty || data.history.isEmpty { data.history = years }
                data.historySyncedAt = now
            } catch {
                if isSignInProblem(error) { throw error }
                data.warnings.append("The transcript could not be loaded.")
            }
        }

        progress?("Loading attendance")
        do {
            data.attendance = SkywardParser.attendance(try await session.attendancePage())
        } catch {
            if isSignInProblem(error) { throw error }
            data.warnings.append("Attendance could not be loaded.")
        }

        if data.profile.name.isEmpty || (data.profileSyncedAt ?? .distantPast) < weekAgo {
            progress?("Loading profile")
            do {
                let profile = SkywardParser.studentInfo(try await session.studentInfoPage())
                if !profile.name.isEmpty { data.profile = profile }
                data.profileSyncedAt = now
            } catch {
                if isSignInProblem(error) { throw error }
            }
        }

        let fresh = changes(from: previous, to: data, now: now)
        if !fresh.isEmpty {
            let known = Set(data.changes.map { $0.id })
            data.changes = (fresh.filter { !known.contains($0.id) } + data.changes)
            if data.changes.count > maxChanges { data.changes = Array(data.changes.prefix(maxChanges)) }
        }
        appendSnapshot(to: &data, now: now)
        data.lastSync = now
        return data
    }

    /// The assignment list for one class and column, fetched when someone opens it.
    static func loadDetail(session: SkywardSession, data: StudentData, courseID: String, lit: String, now: Date = Date()) async throws -> GradeDetail? {
        guard let course = data.courses.first(where: { $0.id == courseID }), let grade = course.grade(lit) else { return nil }
        let bucket = grade.bucket.isEmpty ? lit : grade.bucket
        let body = try await session.gradeDetailPage(course: course, bucket: bucket)
        var detail = SkywardParser.gradeDetail(body, courseID: courseID, lit: lit, bucket: bucket)
        detail?.fetchedAt = now
        return detail
    }

    private static func fetchDetails(
        session: SkywardSession,
        targets: [(Course, PostedGrade)],
        now: Date
    ) async throws -> (details: [GradeDetail], failed: [String]) {
        var details: [GradeDetail] = []
        var failed: [String] = []
        var fatal: Error?

        await withTaskGroup(of: (Int, Result<GradeDetail?, Error>).self) { group in
            var next = 0
            func startNext() {
                guard next < targets.count else { return }
                let index = next
                next += 1
                let (course, grade) = targets[index]
                group.addTask {
                    do {
                        let bucket = grade.bucket.isEmpty ? grade.lit : grade.bucket
                        let body = try await session.gradeDetailPage(course: course, bucket: bucket)
                        var detail = SkywardParser.gradeDetail(body, courseID: course.id, lit: grade.lit, bucket: bucket)
                        detail?.fetchedAt = now
                        return (index, .success(detail))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for _ in 0..<min(maxConcurrent, targets.count) { startNext() }
            while let (index, result) = await group.next() {
                switch result {
                case .success(let detail):
                    if let detail { details.append(detail) } else { failed.append(targets[index].0.name) }
                case .failure(let error):
                    if isSignInProblem(error) {
                        fatal = error
                        group.cancelAll()
                    } else {
                        failed.append(targets[index].0.name)
                    }
                }
                if fatal == nil { startNext() }
            }
        }
        if let fatal { throw fatal }
        return (details, failed)
    }

    // MARK: Tracking

    /// One snapshot per calendar day; a later sync on the same day replaces it.
    static func appendSnapshot(to data: inout StudentData, now: Date) {
        var grades: [String: Double] = [:]
        for course in data.courses {
            for grade in course.grades {
                let key = StudentData.detailKey(course.id, grade.lit)
                if let exact = data.details[key]?.percent {
                    grades[key] = exact
                } else if let number = grade.number {
                    grades[key] = number
                }
            }
        }
        guard !grades.isEmpty else { return }
        let calendar = SkyDate.calendar
        if let last = data.snapshots.last, calendar.isDate(last.date, inSameDayAs: now) {
            data.snapshots[data.snapshots.count - 1] = GradeSnapshot(date: now, grades: grades)
        } else {
            data.snapshots.append(GradeSnapshot(date: now, grades: grades))
        }
        if data.snapshots.count > maxSnapshots {
            data.snapshots.removeFirst(data.snapshots.count - maxSnapshots)
        }
    }

    /// What is new since the last sync: grades that appeared or changed, newly
    /// posted work, and class averages that moved. The very first sync reports
    /// nothing, since everything would be "new".
    static func changes(from previous: StudentData?, to current: StudentData, now: Date) -> [GradeChange] {
        guard let previous, previous.lastSync != nil else { return [] }
        var out: [GradeChange] = []

        func score(_ a: Assignment) -> String {
            guard let earned = a.earned, let possible = a.possible else { return a.gradeText }
            return "\(trim(earned))/\(trim(possible))"
        }

        for course in current.courses {
            let display = Str.titleCase(course.name)
            for grade in course.grades {
                let key = StudentData.detailKey(course.id, grade.lit)
                if let newDetail = current.details[key], let oldDetail = previous.details[key], newDetail.fetchedAt == now {
                    let oldByID = Dictionary(oldDetail.assignments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    for a in newDetail.assignments {
                        var kind: ChangeKind?
                        var detailText = ""
                        if let old = oldByID[a.id] {
                            if !old.isGraded, a.isGraded {
                                kind = .newGrade
                                detailText = score(a)
                            } else if old.isGraded, a.isGraded, old.earned != a.earned || old.possible != a.possible {
                                kind = .updatedGrade
                                detailText = "\(score(old)) → \(score(a))"
                            }
                        } else if a.isGraded {
                            kind = .newGrade
                            detailText = score(a)
                        } else {
                            kind = .newAssignment
                            detailText = a.due.map { "Due " + SkyDate.short($0) } ?? "Posted"
                        }
                        guard let kind else { continue }
                        out.append(GradeChange(
                            id: Str.hash(kind.rawValue, course.id, grade.lit, a.id, detailText),
                            date: now, kind: kind, courseID: course.id, courseName: display, lit: grade.lit,
                            title: a.name, detail: detailText, assignmentID: a.id,
                            oldValue: oldByID[a.id]?.scorePercent, newValue: a.scorePercent
                        ))
                    }
                }

                // Average moves are reported for the column people are watching.
                guard grade.lit == current.currentLit,
                      let oldCourse = previous.courses.first(where: { $0.id == course.id }),
                      let oldNumber = previous.details[key]?.percent ?? oldCourse.grade(grade.lit)?.number,
                      let newNumber = current.details[key]?.percent ?? grade.number,
                      abs(newNumber - oldNumber) >= 0.005 else { continue }
                let up = newNumber > oldNumber
                out.append(GradeChange(
                    id: Str.hash("avg", course.id, grade.lit, trim(oldNumber), trim(newNumber)),
                    date: now, kind: up ? .averageUp : .averageDown, courseID: course.id, courseName: display, lit: grade.lit,
                    title: display, detail: "\(trim(oldNumber)) → \(trim(newNumber))", assignmentID: nil,
                    oldValue: oldNumber, newValue: newNumber
                ))
            }
        }
        return out
    }

    /// "95", "94.5", "94.56": no trailing zeros.
    static func trim(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }
}
