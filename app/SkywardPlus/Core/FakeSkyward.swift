import Foundation

/// Built-in fake Skyward server that powers Demo mode and round-trip parser/sync tests.
/// All responses use the exact HTML/XML/JS-literal shapes Skyward Family Access serves.
final class FakeSkyward: SkywardTransport {
    static let address = "https://skyward.lakeview.edu/scripts/wsisa.dll/WService=wsEAplus/seplog01.w"
    static let username = "demo"
    static let password = "demo"

    struct Spec {
        var cni: String
        var section: String
        var gid: String
        var cId: String
        var name: String
        var teacher: String
        var period: String
        var timeRange: String
        var majorWeight: Double
        var minorWeight: Double
        var q1Percent: Double
        var pr1Percent: Double
        var pr2Percent: Double
        var assignments: [FakeAssignment]
    }

    struct FakeAssignment {
        var aid: String
        var name: String
        var category: String
        var dayOffset: Int
        var earned: Double?
        var possible: Double
        var missing: Bool = false
        var noCount: Bool = false
        var absentNote: String = ""
        var specialCode: String? = nil
    }

    private let lock = NSLock()
    private var _cookies: [String: String] = [:]
    private var _log: [SkywardRequest] = []
    private var validEncses: String?
    private var generation = 0

    let now: Date
    var expectedUser = FakeSkyward.username
    var expectedPassword = FakeSkyward.password
    var requiresMFA = false
    var hideTrustDevice = false
    var securityCode = "654321"
    var isParent = false

    init(now: Date = Date()) {
        self.now = now
    }

    var log: [SkywardRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _log
    }

    var cookies: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return _cookies
    }

    func expireSession() {
        lock.lock()
        validEncses = nil
        lock.unlock()
    }

    func setCookie(name: String, value: String, for url: URL) {
        lock.lock()
        _cookies[name] = value
        lock.unlock()
    }

    func send(_ request: SkywardRequest) async throws -> SkywardResponse {
        handle(request)
    }

    private func handle(_ request: SkywardRequest) -> SkywardResponse {
        lock.lock()
        _log.append(request)
        lock.unlock()

        let page = request.url.lastPathComponent
        func ok(_ body: String) -> SkywardResponse {
            SkywardResponse(status: 200, url: request.url, body: body)
        }

        if request.method == "GET" {
            return ok(Self.loginHTML)
        }

        switch page {
        case "skyporthttp.w":
            guard request.value("requestAction") == "eel",
                  request.value("method") == "extrainfo",
                  request.value("codeType") == "tryLogin" else {
                return ok("<li>Invalid login request.</li>")
            }
            guard request.value("login") == expectedUser,
                  request.value("password") == expectedPassword else {
                return ok("<li>Invalid login or password.</li>")
            }
            lock.lock()
            let trusted = _cookies["SkyTrust"] != nil
            lock.unlock()
            if requiresMFA, !trusted, request.value("securityCode") != securityCode {
                return ok(hideTrustDevice ? "<li>Mfa,HideTrustDevice</li>" : "<li>Mfa</li>")
            }
            lock.lock()
            generation += 1
            let enc = "DEMOENC\(generation)"
            validEncses = enc
            lock.unlock()
            let userType = isParent ? "1" : "2"
            var tokens = "841029^491820^98120311^77412980^58192^s58192^\(userType)^sfhome01.w^false^no^no^no^^encTokenDemo^\(enc)"
            if requiresMFA, request.value("cTrustDevice") == "on" {
                tokens += "^SkyTrust^trusted=demo"
            }
            return ok("<li>\(tokens)</li>")

        case "sfhome01.w":
            guard isAuthorized(request) else { return ok(Self.expiredHTML) }
            return ok(homeHTML(encses: request.value("encses") ?? "DEMOENC1"))

        case "sfgradebook001.w":
            guard isAuthorized(request) else { return ok(Self.expiredHTML) }
            if request.value("action") == "viewGradeInfoDialog" {
                let cni = request.value("corNumId") ?? ""
                let bucket = request.value("bucket") ?? "TERM 2"
                let stuId = request.value("stuId") ?? request.value("studentId") ?? "58192"
                return ok(gradeDetailXML(cni: cni, bucket: bucket, studentID: stuId))
            }
            let stuId = request.value("studentId") ?? "58192"
            return ok(gradebookHTML(studentID: stuId))

        case "httploader.p":
            guard isAuthorized(request) else { return ok(Self.expiredHTML) }
            let cni = request.value("corNumId") ?? ""
            let bucket = request.value("bucket") ?? "TERM 2"
            let stuId = request.value("stuId") ?? request.value("studentId") ?? "58192"
            return ok(gradeDetailXML(cni: cni, bucket: bucket, studentID: stuId))

        case "sfdialogs.w":
            guard isAuthorized(request) else { return ok(Self.expiredHTML) }
            let aid = request.value("assignId") ?? ""
            return ok(assignmentInfoXML(aid: aid))

        case "sfacademichistory001.w":
            guard isAuthorized(request) else { return ok(Self.expiredHTML) }
            let stuId = request.value("studentId") ?? "58192"
            return ok(historyHTML(studentID: stuId))

        case "sfattendance001.w":
            guard isAuthorized(request) else { return ok(Self.expiredHTML) }
            return ok(attendanceHTML())

        case "sfstudentinfo001.w":
            guard isAuthorized(request) else { return ok(Self.expiredHTML) }
            let stuId = request.value("studentId") ?? "58192"
            return ok(studentInfoHTML(studentID: stuId))

        default:
            guard isAuthorized(request) else { return ok(Self.expiredHTML) }
            return ok("<html><body>OK</body></html>")
        }
    }

    private func isAuthorized(_ request: SkywardRequest) -> Bool {
        lock.lock()
        let expected = validEncses
        lock.unlock()
        guard let expected else { return false }
        return request.value("encses") == expected
    }

    private func day(_ offset: Int) -> Date {
        SkyDate.calendar.date(byAdding: .day, value: offset, to: now) ?? now
    }

    // MARK: Courses & Assignments

    static let specs: [Spec] = [
        Spec(
            cni: "1010", section: "1", gid: "9001", cId: "clsDescAPCalcBCAA",
            name: "AP CALCULUS BC", teacher: "Dana Whitfield", period: "1", timeRange: "8:15 AM - 9:05 AM",
            majorWeight: 60, minorWeight: 40, q1Percent: 93.8, pr1Percent: 92.5, pr2Percent: 94.0,
            assignments: [
                FakeAssignment(aid: "10101", name: "Unit 3 Exam: Applications of Derivatives", category: "Major", dayOffset: -18, earned: 94, possible: 100),
                FakeAssignment(aid: "10102", name: "Optimization & Related Rates Test", category: "Major", dayOffset: -6, earned: 96, possible: 100),
                FakeAssignment(aid: "10103", name: "FRQ Set: Mean Value Theorem", category: "Minor", dayOffset: -21, earned: 19, possible: 20),
                FakeAssignment(aid: "10104", name: "Implicit Differentiation Quiz", category: "Minor", dayOffset: -14, earned: 24, possible: 25),
                FakeAssignment(aid: "10105", name: "L'Hospital's Rule Practice", category: "Minor", dayOffset: -10, earned: 10, possible: 10),
                FakeAssignment(aid: "10106", name: "Curve Sketching Lab", category: "Minor", dayOffset: -4, earned: 28, possible: 30),
                FakeAssignment(aid: "10107", name: "Warm-Up Check (Dropped)", category: "Minor", dayOffset: -12, earned: 6, possible: 10, specialCode: "Automated Drop Score"),
                FakeAssignment(aid: "10108", name: "Riemann Sums & Definite Integrals HW", category: "Minor", dayOffset: 1, earned: nil, possible: 20),
                FakeAssignment(aid: "10109", name: "Unit 4 Integration Test", category: "Major", dayOffset: 5, earned: nil, possible: 100),
            ]
        ),
        Spec(
            cni: "1020", section: "2", gid: "9002", cId: "clsDescAPEngLitBB",
            name: "AP ENGLISH LITERATURE", teacher: "Marcus Vance", period: "2", timeRange: "9:10 AM - 10:00 AM",
            majorWeight: 60, minorWeight: 40, q1Percent: 91.2, pr1Percent: 90.0, pr2Percent: 92.0,
            assignments: [
                FakeAssignment(aid: "10201", name: "Hamlet Timed Essay (Q3)", category: "Major", dayOffset: -16, earned: 92, possible: 100),
                FakeAssignment(aid: "10202", name: "Metaphysical Poetry Seminar & Analysis", category: "Major", dayOffset: -5, earned: 95, possible: 100),
                FakeAssignment(aid: "10203", name: "Close Reading: John Donne Sonnets", category: "Minor", dayOffset: -20, earned: 45, possible: 50),
                FakeAssignment(aid: "10204", name: "AP Multiple Choice Passage Set 4", category: "Minor", dayOffset: -11, earned: 27, possible: 30),
                FakeAssignment(aid: "10205", name: "Socratic Seminar Prep Notes", category: "Minor", dayOffset: -7, earned: 20, possible: 20),
                FakeAssignment(aid: "10206", name: "Dialectical Journal Check #3", category: "Minor", dayOffset: 2, earned: nil, possible: 30),
            ]
        ),
        Spec(
            cni: "1030", section: "3", gid: "9003", cId: "clsDescAPPhysicsC",
            name: "AP PHYSICS C: MECHANICS", teacher: "Elena Rostova", period: "3", timeRange: "10:05 AM - 10:55 AM",
            majorWeight: 65, minorWeight: 35, q1Percent: 89.4, pr1Percent: 88.0, pr2Percent: 87.5,
            assignments: [
                FakeAssignment(aid: "10301", name: "Work, Energy & Power Exam", category: "Major", dayOffset: -15, earned: 88, possible: 100),
                FakeAssignment(aid: "10302", name: "Linear Momentum & Collisions Test", category: "Major", dayOffset: -3, earned: 91, possible: 100),
                FakeAssignment(aid: "10303", name: "Ballistic Pendulum Lab Report", category: "Minor", dayOffset: -13, earned: 46, possible: 50),
                FakeAssignment(aid: "10304", name: "Center of Mass Problem Set", category: "Minor", dayOffset: -8, earned: 18, possible: 20),
                FakeAssignment(aid: "10305", name: "Impulse-Momentum Lab Data Sheet", category: "Minor", dayOffset: -2, earned: nil, possible: 25, missing: true),
                FakeAssignment(aid: "10306", name: "Pre-Lab Safety Check", category: "Minor", dayOffset: -19, earned: 10, possible: 10, noCount: true),
                FakeAssignment(aid: "10307", name: "Rotational Kinematics WebAssign", category: "Minor", dayOffset: 3, earned: nil, possible: 25),
            ]
        ),
        Spec(
            cni: "1040", section: "1", gid: "9004", cId: "clsDescAPUSHistDD",
            name: "AP US HISTORY", teacher: "Samuel Okafor", period: "4", timeRange: "11:00 AM - 11:50 AM",
            majorWeight: 60, minorWeight: 40, q1Percent: 95.0, pr1Percent: 94.0, pr2Percent: 96.0,
            assignments: [
                FakeAssignment(aid: "10401", name: "Period 5 DBQ: Civil War & Reconstruction", category: "Major", dayOffset: -14, earned: 96, possible: 100),
                FakeAssignment(aid: "10402", name: "Gilded Age Unit Exam", category: "Major", dayOffset: -4, earned: 97, possible: 100),
                FakeAssignment(aid: "10403", name: "Chapter 16 Reading Quiz", category: "Minor", dayOffset: -17, earned: 29, possible: 30),
                FakeAssignment(aid: "10404", name: "Primary Source Analysis: Populist Party", category: "Minor", dayOffset: -9, earned: 20, possible: 20),
                FakeAssignment(aid: "10405", name: "Historical Thinking Skills Map", category: "Minor", dayOffset: -5, earned: 24, possible: 25),
                FakeAssignment(aid: "10406", name: "Chapter 18 Reading Notes", category: "Minor", dayOffset: 4, earned: nil, possible: 30),
            ]
        ),
        Spec(
            cni: "1050", section: "4", gid: "9005", cId: "clsDescSpan3HonEE",
            name: "SPANISH III HONORS", teacher: "Lucia Mendoza", period: "5", timeRange: "12:25 PM - 1:15 PM",
            majorWeight: 50, minorWeight: 50, q1Percent: 96.4, pr1Percent: 96.0, pr2Percent: 97.0,
            assignments: [
                FakeAssignment(aid: "10501", name: "Presentación Oral: Arte Latinoamericano", category: "Major", dayOffset: -12, earned: 98, possible: 100),
                FakeAssignment(aid: "10502", name: "Examen: El Subjuntivo", category: "Major", dayOffset: -3, earned: 95, possible: 100),
                FakeAssignment(aid: "10503", name: "Comprensión Auditiva #4", category: "Minor", dayOffset: -16, earned: 29, possible: 30),
                FakeAssignment(aid: "10504", name: "Diario Cultural", category: "Minor", dayOffset: -7, earned: 20, possible: 20),
                FakeAssignment(aid: "10505", name: "Vocabulario Unidad 3", category: "Minor", dayOffset: 1, earned: nil, possible: 25),
            ]
        ),
        Spec(
            cni: "1060", section: "2", gid: "9006", cId: "clsDescAPCompSciF",
            name: "AP COMPUTER SCIENCE A", teacher: "Keith Chen", period: "6", timeRange: "1:20 PM - 2:10 PM",
            majorWeight: 60, minorWeight: 40, q1Percent: 98.0, pr1Percent: 97.5, pr2Percent: 98.5,
            assignments: [
                FakeAssignment(aid: "10601", name: "2D Arrays & ArrayList Exam", category: "Major", dayOffset: -11, earned: 99, possible: 100),
                FakeAssignment(aid: "10602", name: "PictureLab FRQ Project", category: "Major", dayOffset: -2, earned: 100, possible: 100),
                FakeAssignment(aid: "10603", name: "ArrayList Algorithms Lab", category: "Minor", dayOffset: -15, earned: 49, possible: 50),
                FakeAssignment(aid: "10604", name: "String Processing Quiz", category: "Minor", dayOffset: -8, earned: 29, possible: 30),
                FakeAssignment(aid: "10605", name: "Inheritance Hierarchy Lab", category: "Minor", dayOffset: 6, earned: nil, possible: 50),
            ]
        ),
        Spec(
            cni: "1070", section: "1", gid: "9007", cId: "clsDescChemHonGGG",
            name: "ORGANIC CHEMISTRY HONORS", teacher: "Priya Patel", period: "7", timeRange: "2:15 PM - 3:05 PM",
            majorWeight: 60, minorWeight: 40, q1Percent: 86.2, pr1Percent: 87.0, pr2Percent: 84.5,
            assignments: [
                FakeAssignment(aid: "10701", name: "Stereochemistry & Chirality Exam", category: "Major", dayOffset: -14, earned: 84, possible: 100),
                FakeAssignment(aid: "10702", name: "SN1 / SN2 Mechanisms Test", category: "Major", dayOffset: -4, earned: 87, possible: 100),
                FakeAssignment(aid: "10703", name: "Nomenclature Quiz: Alkenes", category: "Minor", dayOffset: -18, earned: 22, possible: 25),
                FakeAssignment(aid: "10704", name: "Molecular Modeling Lab", category: "Minor", dayOffset: -9, earned: 43, possible: 50),
                FakeAssignment(aid: "10705", name: "Recrystallization Post-Lab Questions", category: "Minor", dayOffset: -1, earned: nil, possible: 20, missing: true),
            ]
        ),
        Spec(
            cni: "1080", section: "1", gid: "9008", cId: "clsDescSymphBandH",
            name: "SYMPHONIC BAND", teacher: "Robert Alvarez", period: "8", timeRange: "3:10 PM - 4:00 PM",
            majorWeight: 50, minorWeight: 50, q1Percent: 99.0, pr1Percent: 99.0, pr2Percent: 100.0,
            assignments: [
                FakeAssignment(aid: "10801", name: "Region Etude Chair Audition", category: "Major", dayOffset: -13, earned: 99, possible: 100),
                FakeAssignment(aid: "10802", name: "Winter Concert Dress Rehearsal", category: "Major", dayOffset: -3, earned: 100, possible: 100),
                FakeAssignment(aid: "10803", name: "Scale Pass-Off: Concert Ab & Db", category: "Minor", dayOffset: -10, earned: 50, possible: 50),
                FakeAssignment(aid: "10804", name: "Sectional Attendance & Sightreading", category: "Minor", dayOffset: -5, earned: 50, possible: 50),
            ]
        ),
    ]

    private func computeTermPercent(_ spec: Spec) -> (percent: Double, majorPct: Double, minorPct: Double, majorEarned: Double, majorPossible: Double, minorEarned: Double, minorPossible: Double) {
        var majE = 0.0, majP = 0.0, minE = 0.0, minP = 0.0
        for a in spec.assignments where !a.noCount && a.specialCode == nil {
            guard let e = a.earned else { continue }
            if a.category == "Major" {
                majE += e; majP += a.possible
            } else {
                minE += e; minP += a.possible
            }
        }
        let majPct = majP > 0 ? (majE / majP * 100) : 100
        let minPct = minP > 0 ? (minE / minP * 100) : 100
        let total = (majPct * spec.majorWeight + minPct * spec.minorWeight) / (spec.majorWeight + spec.minorWeight)
        return (total, majPct, minPct, majE, majP, minE, minP)
    }

    // MARK: HTML builders

    static let loginHTML = MiniSkywardLoginTemplate.html
    static let expiredHTML = "<html><body>Your session has expired and you have been logged out.</body></html>"

    private func homeHTML(encses: String) -> String {
        let childrenBlock = isParent
            ? "<div id='sf_StudentList'><a data-nameid='0' href='#'>All Students</a><a data-nameid='58192' href='#'>Jordan Rivera</a><a data-nameid='58193' href='#'>Casey Rivera</a></div>"
            : ""
        return """
        <html><body>
        <div id="sf_UtilityArea"><ul><li class="sf_utilUser notranslate">Jordan Rivera</li></ul></div>
        \(childrenBlock)
        <script data-rel='sff'>sff.sv('sessionid', '491820\u{15}98120311');sff.sv('encses', '\(encses)');</script>
        </body></html>
        """
    }

    private func gradebookHTML(studentID: String) -> String {
        let bucketDefs: [(lit: String, bkt: String, name: String)] = [
            ("PR1", "PROG 1", "Progress Report 1"),
            ("Q1", "TERM 1", "Quarter 1"),
            ("PR2", "PROG 2", "Progress Report 2"),
            ("Q2", "TERM 2", "Quarter 2"),
            ("EX1", "EXAM 1", "Semester 1 Exam"),
            ("S1", "SEM 1", "Semester 1"),
            ("PR3", "PROG 3", "Progress Report 3"),
            ("Q3", "TERM 3", "Quarter 3"),
            ("Q4", "TERM 4", "Quarter 4"),
            ("S2", "SEM 2", "Semester 2"),
            ("FIN", "FINAL", "Final Grade"),
        ]

        let headerCells: [String] = [
            "{h:'<th>Class</th>'}",
            "{h:'<th></th>'}",
        ] + bucketDefs.map { "{h:'<th><span tooltip=\"\($0.name)\">\($0.lit)</span></th>'}" }

        var descriptions = ""
        var bodyRows: [String] = []

        for spec in Self.specs {
            descriptions += """
            <div id="\(spec.cId)"><div><table>
            <tr><td rowspan="3">&nbsp;</td><td><span class="bld classDesc"><a>\(spec.name)</a></span></td></tr>
            <tr><td><label>Period</label>\(spec.period)<span>(\(spec.timeRange))</span></td></tr>
            <tr><td><a>\(spec.teacher)</a></td></tr>
            </table></div></div>
            """

            let q2 = computeTermPercent(spec).percent
            let s1 = (spec.q1Percent + q2) / 2.0
            let valuesByLit: [String: Double] = [
                "PR1": spec.pr1Percent,
                "Q1": spec.q1Percent,
                "PR2": spec.pr2Percent,
                "Q2": q2,
                "S1": s1,
            ]

            var cells: [String] = [
                "{cId:'\(spec.cId)', h:'<td scope=\"row\" class=\"cCl cMwS\">\(spec.cId)</td>'}",
                "{h:'<td></td>'}",
            ]
            for b in bucketDefs {
                let text = valuesByLit[b.lit].map { String(Int($0.rounded())) } ?? ""
                let cellHTML = "<td class='pB bld'><a id='showGradeInfo' name='showGradeInfo' data-sId='\(studentID)' data-eId='001' data-cNI='\(spec.cni)' data-trk='1' data-sec='\(spec.section)' data-gId='\(spec.gid)' data-bkt='\(b.bkt)' data-lit='\(b.lit)' data-isEoc='no' href='javascript:void(0)'>\(text)</a></td>"
                cells.append("{h:\"\(cellHTML)\"}")
            }
            bodyRows.append("{h:'<tr group-parent=\"\(studentID)_\(spec.cni)_1_\(spec.section)\">', c:[\(cells.joined(separator: ","))]}")
        }

        return """
        <html><body>
        \(descriptions)
        <script data-rel='sff'>
        sff.sv('sf_gridObjects',$.extend((sff.getValue('sf_gridObjects') || {}), {'stuGradesGrid_\(studentID)_001':{th:{r:[{c:[\(headerCells.joined(separator: ","))]}]}, tb:{r:[\(bodyRows.joined(separator: ","))]}}}));
        </script>
        </body></html>
        """
    }

    private func gradeDetailXML(cni: String, bucket: String, studentID: String) -> String {
        guard let spec = Self.specs.first(where: { $0.cni == cni }) ?? Self.specs.first else {
            return "<response><output><![CDATA[]]></output></response>"
        }
        let stats = computeTermPercent(spec)
        let isQ1 = bucket == "TERM 1" || bucket == "Q1"
        let isPR1 = bucket == "PROG 1" || bucket == "PR1"
        let isPR2 = bucket == "PROG 2" || bucket == "PR2"
        let postedPct = isQ1 ? spec.q1Percent : isPR1 ? spec.pr1Percent : isPR2 ? spec.pr2Percent : stats.percent
        let rounded = Int(postedPct.rounded())
        let startStr = SkyDate.long(day(-42))
        let endStr = SkyDate.long(day(21))

        var rowsHTML = """
        <tr>
            <th colspan="2">Due</th>
            <th>Assignment</th>
            <th>Grade</th>
            <th>Score (%)</th>
            <th>Points Earned</th>
            <th>Missing</th>
            <th>No Count</th>
            <th>Absent</th>
        </tr>
        <tr class="sf_Section cat">
            <td></td>
            <td class="nWp noLBdr" colspan="2">Major<br/><span class="fIl fWn fXs">weighted at \(String(format: "%.2f", spec.majorWeight))%</span></td>
            <td>\(Int(stats.majorPct.rounded()))</td>
            <td>\(String(format: "%.2f", stats.majorPct))</td>
            <td>\(SyncEngine.trim(stats.majorEarned)) <span>out of</span> \(SyncEngine.trim(stats.majorPossible))</td>
            <td colspan="3"></td>
        </tr>
        """

        let majors = spec.assignments.filter { $0.category == "Major" }
        let minors = spec.assignments.filter { $0.category != "Major" }

        func renderAssignment(_ a: FakeAssignment) -> String {
            let dueStr = SkyDate.short(day(a.dayOffset))
            let gradeCell: String
            let scoreCell: String
            let pointsCell: String
            if let earned = a.earned {
                let pct = a.possible > 0 ? (earned / a.possible * 100) : 100
                let codeLink = a.specialCode.map { " <a id=\"specCode_\(a.aid)\" data-info=\"\($0)\">*</a>" } ?? ""
                gradeCell = "\(Int(pct.rounded()))\(codeLink)"
                scoreCell = String(format: "%.2f", pct)
                pointsCell = "\(SyncEngine.trim(earned)) out of \(SyncEngine.trim(a.possible))"
            } else {
                gradeCell = ""
                scoreCell = ""
                pointsCell = "* out of \(SyncEngine.trim(a.possible))"
            }
            let missingCell = a.missing ? "<img alt=\"Missing\"/>" : ""
            let noCountCell = a.noCount ? "<img alt=\"No count\"/>" : ""
            let absentCell = a.absentNote
            return """
            <tr>
                <td scope="row" colspan="2">\(dueStr)</td>
                <td class="nWp"><a id="showAssignmentInfo" data-sId="\(studentID)" data-gId="\(spec.gid)" data-aId="\(a.aid)">\(HTMLEntities.escape(a.name))</a></td>
                <td>\(gradeCell)</td>
                <td>\(scoreCell)</td>
                <td>\(pointsCell)</td>
                <td>\(missingCell)</td>
                <td>\(noCountCell)</td>
                <td>\(absentCell)</td>
            </tr>
            """
        }

        for a in majors { rowsHTML += renderAssignment(a) }
        rowsHTML += """
        <tr class="sf_Section cat">
            <td></td>
            <td class="nWp noLBdr" colspan="2">Minor<br/><span class="fIl fWn fXs">weighted at \(String(format: "%.2f", spec.minorWeight))%</span></td>
            <td>\(Int(stats.minorPct.rounded()))</td>
            <td>\(String(format: "%.2f", stats.minorPct))</td>
            <td>\(SyncEngine.trim(stats.minorEarned)) <span>out of</span> \(SyncEngine.trim(stats.minorPossible))</td>
            <td colspan="3"></td>
        </tr>
        """
        for a in minors { rowsHTML += renderAssignment(a) }

        return """
        <response><output><![CDATA[
        <div>
            <h2 class="gb_heading"><span class="fWn"><a>\(spec.name)</a>&nbsp;<span class="fXs">(Period&nbsp;<b>\(spec.period)</b>)</span>&nbsp;<a>\(spec.teacher)</a></span></h2>
            <table id="grid_stuTermSummaryGrid">
                <tr><th>\(bucket) Grade<br/><span>(\(startStr) - \(endStr))</span></th><th>Score (%)</th></tr>
                <tr><td>\(rounded)</td><td>\(String(format: "%.2f", postedPct))</td></tr>
                <tr><td colspan="2">Grade Breakdown:</td></tr>
                <tr><td><div><label>Q1</label></div><div>\(Int(spec.q1Percent.rounded()))</div> (50% of Sem 1 grade)</td><td>\(String(format: "%.2f", spec.q1Percent))</td></tr>
                <tr><td><div><label>Q2</label></div><div>\(rounded)</div> (50% of Sem 1 grade)</td><td>\(String(format: "%.2f", postedPct))</td></tr>
            </table>
            <table id="grid_stuAssignmentSummaryGrid">
                \(rowsHTML)
            </table>
        </div>
        ]]></output></response>
        """
    }

    private func assignmentInfoXML(aid: String) -> String {
        for spec in Self.specs {
            if let a = spec.assignments.first(where: { $0.aid == aid }) {
                let dueStr = SkyDate.long(day(a.dayOffset))
                let assignedStr = SkyDate.long(day(a.dayOffset - 4))
                let weight = a.category == "Major" ? spec.majorWeight : spec.minorWeight
                return """
                <response><output><![CDATA[
                <table>
                    <tr><td>\(HTMLEntities.escape(a.name))</td></tr>
                    <tr><td>Class:</td><td>\(spec.name)</td></tr>
                    <tr><td>Category:</td><td>\(a.category) (\(Int(weight))%)</td></tr>
                    <tr><td>Date Assigned:</td><td>\(assignedStr)</td></tr>
                    <tr><td>Date Due:</td><td>\(dueStr)</td></tr>
                    <tr><td>Max Score:</td><td>\(SyncEngine.trim(a.possible))</td></tr>
                    <tr><td>Description:</td><td>Posted in Skyward Family Access for \(spec.name).</td></tr>
                </table>
                ]]></output></response>
                """
            }
        }
        return "<response><output><![CDATA[<table><tr><td>Assignment</td></tr><tr><td>Max Score:</td><td>100</td></tr></table>]]></output></response>"
    }

    private func historyHTML(studentID: String) -> String {
        let lits = [
            ("Q1", "Quarter 1"), ("Q2", "Quarter 2"), ("S1", "Semester 1"),
            ("Q3", "Quarter 3"), ("Q4", "Quarter 4"), ("S2", "Semester 2"), ("FIN", "Final Grade"),
        ]
        let litCells = [
            "{h:'<td style=\"vertical-align:bottom\">Class</td>'}",
            "{h:'<td style=\"vertical-align:bottom\">Terms</td>'}",
        ] + lits.map { "{h:'<td style=\"vertical-align:bottom\"><span tooltip=\"\($0.1)\">\($0.0)</span></td>'}" }

        func courseRow(_ name: String, _ grades: [String]) -> String {
            let cells = [
                "{h:'<td>\(name)</td>'}",
                "{h:'<td>1 - 4</td>'}",
            ] + grades.map { "{h:'<td>\($0)</td>'}" }
            return "{c:[\(cells.joined(separator: ","))]}"
        }

        let rows: [String] = [
            "{c:[{h:'<td><div>2025 - 2026, Grade 10</div></td>'}]}",
            "{c:[\(litCells.joined(separator: ","))]}",
            courseRow("AP WORLD HISTORY", ["94", "95", "95", "96", "97", "97", "96"]),
            courseRow("PRE-AP PRECALCULUS", ["92", "94", "93", "95", "93", "94", "94"]),
            courseRow("ENGLISH II HONORS", ["91", "93", "92", "94", "92", "93", "93"]),
            courseRow("CHEMISTRY HONORS", ["89", "91", "90", "88", "90", "89", "90"]),
            courseRow("SPANISH II", ["96", "97", "97", "98", "97", "98", "98"]),
            courseRow("AP COMPUTER SCIENCE PRINCIPLES", ["98", "99", "99", "97", "99", "98", "99"]),
            courseRow("SYMPHONIC BAND", ["100", "99", "100", "100", "100", "100", "100"]),
            "{c:[{h:'<td><div>2024 - 2025, Grade 9</div></td>'}]}",
            "{c:[\(litCells.joined(separator: ","))]}",
            courseRow("AP HUMAN GEOGRAPHY", ["91", "93", "92", "94", "95", "95", "94"]),
            courseRow("ALGEBRA II HONORS", ["93", "92", "93", "94", "96", "95", "94"]),
            courseRow("ENGLISH I HONORS", ["90", "92", "91", "93", "94", "94", "93"]),
            courseRow("BIOLOGY HONORS", ["95", "94", "95", "96", "95", "96", "96"]),
            courseRow("SPANISH I", ["97", "96", "97", "98", "99", "99", "98"]),
            courseRow("CONCERT BAND", ["99", "100", "100", "100", "100", "100", "100"]),
        ]

        return """
        <html><body>
        <script data-rel='sff'>
        sff.sv('sf_gridObjects',$.extend((sff.getValue('sf_gridObjects') || {}), {'gradeGrid_\(studentID)_001_2025':{tb:{r:[\(rows.joined(separator: ","))]}}}));
        </script>
        </body></html>
        """
    }

    private func attendanceHTML() -> String {
        let events: [(offset: Int, reason: String, periods: String, course: String)] = [
            (-3, "Tardy - Traffic", "1", "AP CALCULUS BC"),
            (-9, "Medical Appointment (Excused)", "1, 2", "AP CALCULUS BC, AP ENGLISH LITERATURE"),
            (-16, "Excused Illness", "1 - 8", "All Classes"),
            (-24, "Tardy", "5", "SPANISH III HONORS"),
            (-33, "School Activity - Band UIL (Excused)", "6, 7, 8", "AP COMPUTER SCIENCE A, SYMPHONIC BAND"),
        ]
        let rows = events.map { item in
            let dateStr = SkyDate.short(day(item.offset))
            return "<tr class=\"odd\"><td scope=\"row\" style=\"white-space:nowrap\">\(dateStr)</td><td>\(item.reason)</td><td style=\"white-space:nowrap\">\(item.periods)</td><td><a href=\"#\">\(item.course)</a></td></tr>"
        }.joined(separator: "\n")
        return "<html><body><table>\(rows)</table></body></html>"
    }

    private func studentInfoHTML(studentID: String) -> String {
        let name = studentID == "58193" ? "Casey Rivera" : "Jordan Rivera"
        return """
        <html><body>
        <div id="sf_ContentBody">
            <div>
                <span class="sfTag">\(name)</span>
                <table>
                    <tr><td>School:</td><td>Lakeview High School</td><td>Grade Level:</td><td>11</td></tr>
                    <tr><td>Student ID:</td><td>\(studentID)</td><td>Graduation Year:</td><td>2028</td></tr>
                    <tr><td>Counselor:</td><td>Hannah Brooks</td><td>House / Track:</td><td>STEM Academy</td></tr>
                </table>
            </div>
        </div>
        </body></html>
        """
    }
}

private enum MiniSkywardLoginTemplate {
    static let html = """
    <html><head><title>Skyward: Loading page... (05.26.10.00.04-12.8)</title></head><body>
    <form name='detailform' id='detailform' action='' method='post'>
    <input type='text' class='EditInput' name='login' id='login' value='' />
    <input type='password' class='EditInput' name='password' id='password' value='' />
    <input type='text' class='EditInput' name='securityCode' id='securityCode' value='' />
    <input type='checkbox' name='cTrustDevice' id='cTrustDevice' />
    <input type='hidden' name='dwd' value='' />
    <input type='hidden' name='wfaacl' value='' />
    <input type='hidden' name='encses' value='' />
    <input type='hidden' name='nameid' value='-1' />
    <input type='hidden' name='CurrentProgram' value='skyportlogin.w' />
    <input type='hidden' name='duserid' value='-1' />
    <input type='hidden' name='HomePage' value='sepadm01.w' />
    <input type='hidden' name='hAnon' value='demoAnonToken123' />
    <input type='hidden' name='web-data-recid' value='' />
    <input type='hidden' name='wfaacl-recid' value='' />
    <input type='hidden' name='User-Type' value='' />
    <input type='hidden' name='showTracker' value='' />
    <input type='hidden' name='displaySecond' value='' />
    <input type='hidden' name='insecure' value='' />
    <input type='hidden' name='redirectTo' value='' />
    <input type='hidden' name='enc' value='' />
    <input type='hidden' name='hforgotLoginPage' value='seplog01' />
    </form></body></html>
    """
}
