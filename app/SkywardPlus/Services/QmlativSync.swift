import Foundation

/// Why a background sync stopped without being an error worth a sign-in prompt.
enum QmlativPause: Error, Equatable {
    /// Skyward signed the app out moments after a good sync: someone signed in
    /// elsewhere (Skyward allows one session). Signing straight back in would
    /// sign them out, so wait a while.
    case signedInElsewhere
    /// The district's sign-in page didn't answer. Nothing was typed; try later.
    case signInUnreachable
}

extension SyncEngine {
    /// - Parameters:
    ///   - mayReSignIn: false right after a good sync, when being signed out means
    ///     the student signed in somewhere else.
    ///   - full: false for the frequent background check, which reads the grade
    ///     table and reopens only classes whose grade moved, and skips attendance.
    @MainActor
    static func syncQmlativ(
        engine: QmlativEngine,
        credentials: DistrictCredentials? = nil,
        previous: StudentData?,
        now: Date = Date(),
        mayReSignIn: Bool = true,
        full: Bool = true,
        progress: ((String) -> Void)? = nil
    ) async throws -> StudentData {
        progress?("Loading grades")
        await engine.load("Grading/StudentSection/StudentAccess")

        var currentState = await engine.state()
        if currentState?.signedIn != true {
            guard mayReSignIn else { throw QmlativPause.signedInElsewhere }
            progress?("Signing in")
            switch await engine.signInQuietly(credentials: credentials) {
            case .signedIn: break
            case .noResponse: throw QmlativPause.signInUnreachable
            case .rejected, .needsPerson: throw SkywardError.sessionExpired
            }
            currentState = await engine.state()
            if !(currentState?.path.localizedCaseInsensitiveContains("/Grading/StudentSection/") ?? false) || engine.loadedNarrow {
                await engine.load("Grading/StudentSection/StudentAccess")
                currentState = await engine.state()
            }
        }

        let rawGrid = try await engine.grid()
        let mapped = QmlativMapper.gradebook(rawGrid)
        guard !mapped.courses.isEmpty else {
            throw SkywardError.server("Skyward opened, but the Grades page had no classes.")
        }

        var data = previous ?? StudentData()
        data.buckets = mapped.buckets
        data.skywardCurrentLit = mapped.currentLit
        data.courses = mapped.courses
        data.warnings = []
        data.history = []

        // Preserve previously learned teachers by course ID.
        if let prevCourses = previous?.courses {
            let prevTeachers = Dictionary(
                prevCourses.filter { !$0.teacher.isEmpty }.map { ($0.id, $0.teacher) },
                uniquingKeysWith: { a, _ in a }
            )
            for i in data.courses.indices {
                if let savedTeacher = prevTeachers[data.courses[i].id], !savedTeacher.isEmpty {
                    data.courses[i].teacher = savedTeacher
                }
            }
        }

        let courseIDs = Set(data.courses.map { $0.id })
        data.details = data.details.filter { key, _ in
            guard let id = key.split(separator: "|").first else { return false }
            return courseIDs.contains(String(id))
        }

        // Open each class that hasDetail in the default marking period, one at a time.
        if let lit = data.currentLit {
            var failedCourses: [String] = []
            for i in data.courses.indices {
                let course = data.courses[i]
                guard let grade = course.grade(lit), grade.hasDetail, !grade.bucket.isEmpty else { continue }
                if !full, let old = previous?.courses.first(where: { $0.id == course.id })?.grade(lit),
                   old.text == grade.text, previous?.details[StudentData.detailKey(course.id, lit)] != nil {
                    continue  // Same grade as last time: its assignments are still current enough.
                }
                progress?("Loading \(Str.titleCase(course.name))")
                do {
                    let panel = try await engine.open(bucketID: grade.bucket, weights: true)
                    if var detail = QmlativMapper.detail(panel, courseID: course.id, lit: lit, bucket: grade.bucket, now: now) {
                        detail.courseName = course.name
                        data.details[StudentData.detailKey(course.id, lit)] = detail
                        if !detail.teacher.isEmpty {
                            data.courses[i].teacher = detail.teacher
                        }
                    } else {
                        failedCourses.append(Str.titleCase(course.name))
                    }
                } catch {
                    failedCourses.append(Str.titleCase(course.name))
                }
            }
            if !failedCourses.isEmpty {
                data.warnings.append("Assignments could not be loaded for: " + failedCourses.joined(separator: ", ") + ".")
            }
        }

        // Load attendance page.
        if full {
        progress?("Loading attendance")
        do {
            await engine.load("Attendance/StudentAttendance/StudentAccess")
            let rawAtt = try await engine.attendance()
            data.attendance = QmlativMapper.attendance(rawAtt).sorted { $0.date > $1.date }
        } catch {
            data.warnings.append("Attendance could not be loaded.")
        }
        } else {
            // Keep the last full sync's attendance warning, if any, until the next full one.
            if let old = previous?.warnings.first(where: { $0.hasPrefix("Attendance") }) { data.warnings.append(old) }
        }

        let finalState: QmlState?
        if let currentState {
            finalState = currentState
        } else {
            finalState = await engine.state()
        }
        if let st = finalState {
            if !st.name.isEmpty { data.profile.name = st.name }
            if !st.school.isEmpty { data.profile.school = st.school }
        }
        data.profileSyncedAt = now

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
}
