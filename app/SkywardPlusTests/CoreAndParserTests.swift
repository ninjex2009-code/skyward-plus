import XCTest

final class CoreAndParserTests: XCTestCase {

    // MARK: - HTML & JS Literal

    func testHTMLParserAndSelectors() {
        let html = """
        <div id="wrap" class="outer box">
            <table id="grid_stuTermSummaryGrid_1">
                <tr><th colspan="2">Due</th><th>Assignment &amp; Notes</th></tr>
                <tr class="sf_Section cat"><td></td><td class="nWp noLBdr" colspan="2">Major<br/><span class="fIl">weighted at 60.00%</span></td></tr>
            </table>
        </div>
        """
        let doc = HTMLNode.parse(html)
        XCTAssertEqual(doc.byId("wrap")?.classes, ["outer", "box"])
        XCTAssertEqual(doc.select("table[id*=grid_stuTermSummaryGrid] tr.sf_Section.cat td.noLBdr").first?.ownText, "Major")
        let headRow = doc.select("table tr").first
        XCTAssertEqual(headRow?.logicalCells.count, 3)
        XCTAssertEqual(headRow?.cells.last?.cleanText, "Assignment & Notes")
    }

    func testJSLiteralParser() {
        let js = "{stuGradesGrid_1:{th:{r:[{c:[{h:'<th>Q1</th>'}]}]}, count: 42, flag: true, empty: null}}"
        let parsed = JSLiteralParser.parse(js)
        XCTAssertEqual(parsed?["stuGradesGrid_1"]?["th"]?["r"]?[0]?["c"]?[0]?["h"]?.string, "<th>Q1</th>")
        XCTAssertEqual(parsed?["stuGradesGrid_1"]?["count"]?.string, "42")
        XCTAssertEqual(parsed?["stuGradesGrid_1"]?["flag"]?.string, "true")
    }

    // MARK: - FakeSkyward + SyncEngine Round-Trip

    func testFullSyncAndChangeTrackingWithFakeSkyward() async throws {
        let now = SkyDate.make(2026, 11, 10)
        let fake = FakeSkyward(now: now)
        let endpoint = SkywardEndpoint.parse(FakeSkyward.address)!
        let session = SkywardSession(endpoint: endpoint, transport: fake)

        let login = try await session.login(username: FakeSkyward.username, password: FakeSkyward.password)
        XCTAssertEqual(login.home.userName, "Jordan Rivera")

        var steps: [String] = []
        let firstSync = try await SyncEngine.sync(session: session, previous: nil, now: now) { step in
            steps.append(step)
        }
        XCTAssertTrue(steps.contains("Loading gradebook"))
        XCTAssertEqual(firstSync.courses.count, 8)
        XCTAssertEqual(firstSync.currentLit, "Q2")
        XCTAssertEqual(firstSync.history.count, 2)
        XCTAssertEqual(firstSync.attendance.count, 5)
        XCTAssertEqual(firstSync.profile.name, "Jordan Rivera")
        XCTAssertEqual(firstSync.profile.school, "Lakeview High School")
        XCTAssertEqual(firstSync.snapshots.count, 1)
        XCTAssertTrue(firstSync.changes.isEmpty, "very first sync does not report everything as new")

        // Verify assignment details were loaded for the current term (Q2)
        let calc = firstSync.courses.first { $0.cni == "1010" }!
        let detail = firstSync.detail(calc.id, "Q2")
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.categories.count, 2)
        XCTAssertEqual(detail?.assignments.count, 9)
        XCTAssertEqual(detail?.assignments.first { $0.aid == "10107" }?.dropped, true)

        // Verify assignment info dialog parser
        let infoRaw = try await session.assignmentInfoPage(assignmentID: "10101", gradebookID: calc.gid, studentID: calc.studentID)
        let info = SkywardParser.assignmentInfo(infoRaw)
        XCTAssertEqual(info.title, "Unit 3 Exam: Applications of Derivatives")
        XCTAssertTrue(info.fields.contains { $0.key == "Max Score" && $0.value == "100" })

        // Simulate a grade change between firstSync and a later sync
        var modifiedPrevious = firstSync
        let key = StudentData.detailKey(calc.id, "Q2")
        if var d = modifiedPrevious.details[key], let idx = d.assignments.firstIndex(where: { $0.aid == "10101" }) {
            d.assignments[idx].earned = 80
            d.percent = 88.0
            modifiedPrevious.details[key] = d
        }
        let later = now.addingTimeInterval(3600)
        let secondSync = try await SyncEngine.sync(session: session, previous: modifiedPrevious, now: later)
        XCTAssertFalse(secondSync.changes.isEmpty)
        XCTAssertTrue(secondSync.changes.contains { $0.kind == .updatedGrade && $0.assignmentID == "10101" })
        XCTAssertTrue(secondSync.changes.contains { $0.kind == .averageUp && $0.courseID == calc.id })
    }

    // MARK: - GradeMath

    func testGradeMathWeightedPointsAndWhatIf() {
        let detail = GradeDetail(
            courseID: "c1",
            lit: "Q2",
            bucket: "TERM 2",
            percent: 92.0,
            categories: [
                GradeCategory(name: "Major", weight: 60),
                GradeCategory(name: "Minor", weight: 40),
            ],
            assignments: [
                Assignment(id: "a1", name: "Exam 1", category: "Major", earned: 90, possible: 100),
                Assignment(id: "a2", name: "Quiz 1", category: "Minor", earned: 95, possible: 100),
                Assignment(id: "a3", name: "Dropped Quiz", category: "Minor", earned: 20, possible: 100, specialCode: "Automated Drop Score"),
                Assignment(id: "a4", name: "Practice", category: "Minor", earned: 50, possible: 100, noCount: true),
            ]
        )

        let res = GradeMath.compute(detail, mode: .auto)
        XCTAssertEqual(res.mode, .weighted)
        XCTAssertEqual(res.percent ?? 0, 92.0, accuracy: 0.01)
        XCTAssertEqual(res.matchesPosted, true)
        XCTAssertEqual(res.gradedCount, 2)

        // Impact & Upside
        let impactA1 = GradeMath.impact(of: "a1", in: detail)
        XCTAssertNotNil(impactA1)
        XCTAssertEqual(impactA1 ?? 0, 92.0 - 95.0, accuracy: 0.01)

        let upsideA1 = GradeMath.upside(of: "a1", in: detail)
        XCTAssertEqual(upsideA1 ?? 0, 98.0 - 92.0, accuracy: 0.01)

        // Needed score on next Major test (worth 100) to reach 94.0%
        let needed = GradeMath.needed(target: 94.0, possible: 100, category: "Major", in: detail)
        if case .score(let earned, _) = needed {
            XCTAssertEqual(earned, 96.67, accuracy: 0.05)
        } else {
            XCTFail("Expected .score, got \(needed)")
        }

        // Final exam calculator: 92 current, 20% exam weight, 90 target -> 82%
        let exam = GradeMath.finalExamNeeded(current: 92, examWeight: 20, target: 90)
        XCTAssertEqual(exam, 82.0, accuracy: 0.01)
    }

    // MARK: - GPA

    func testGPALevelGuessingAndComputation() {
        XCTAssertEqual(GPA.guessLevel("PRE-AP PRECALCULUS"), .honors)
        XCTAssertEqual(GPA.guessLevel("ALGEBRA II PAP"), .honors)
        XCTAssertEqual(GPA.guessLevel("AP CALCULUS BC"), .ap)
        XCTAssertEqual(GPA.guessLevel("IB BIOLOGY HL"), .ap)
        XCTAssertEqual(GPA.guessLevel("ENGL 1301 DUAL CREDIT"), .ap)
        XCTAssertEqual(GPA.guessLevel("ENGLISH II HONORS"), .honors)
        XCTAssertEqual(GPA.guessLevel("SYMPHONIC BAND"), .regular)

        var data = StudentData()
        data.buckets = [TermBucket(lit: "Q2", bucket: "TERM 2", name: "Quarter 2")]
        data.courses = [
            Course(id: "1", name: "AP CALCULUS BC", grades: [PostedGrade(lit: "Q2", bucket: "TERM 2", text: "95", hasDetail: true)]),
            Course(id: "2", name: "ENGLISH II HONORS", grades: [PostedGrade(lit: "Q2", bucket: "TERM 2", text: "92", hasDetail: true)]),
            Course(id: "3", name: "SYMPHONIC BAND", grades: [PostedGrade(lit: "Q2", bucket: "TERM 2", text: "85", hasDetail: true)]),
        ]

        let settings = GPASettings()
        let cur = GPA.currentEntries(data: data, lit: "Q2", settings: settings)
        XCTAssertEqual(cur.count, 3)
        let gpa = GPA.compute(cur)
        // Unweighted: A (4.0), A (4.0), B (3.0) -> 11 / 3 = 3.6667
        // Weighted: AP A (5.0), Honors A (4.5), Regular B (3.0) -> 12.5 / 3 = 4.1667
        XCTAssertEqual(gpa.unweighted ?? 0, 11.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(gpa.weighted ?? 0, 12.5 / 3.0, accuracy: 0.001)

        // Transcript semester rule (0.5 credit per semester)
        let history = [
            HistoryYear(
                title: "2025 - 2026, Grade 10",
                lits: [HistoryLit(lit: "S1", name: "Sem 1"), HistoryLit(lit: "S2", name: "Sem 2"), HistoryLit(lit: "FIN", name: "Final")],
                courses: [HistoryCourse(name: "AP WORLD HISTORY", terms: "1 - 4", grades: ["94", "85", "90"])]
            ),
        ]
        let trans = GPA.transcriptEntries(history: history, settings: settings)
        XCTAssertEqual(trans.count, 2)
        XCTAssertEqual(trans.map { $0.credits }, [0.5, 0.5])
        let transGPA = GPA.compute(trans)
        // S1 = 94 (5.0 W, 4.0 UW), S2 = 85 (4.0 W, 3.0 UW) -> mean = 4.5 W, 3.5 UW
        XCTAssertEqual(transGPA.weighted ?? 0, 4.5, accuracy: 0.001)
        XCTAssertEqual(transGPA.unweighted ?? 0, 3.5, accuracy: 0.001)
    }

    // MARK: - DistrictSearch

    func testDistrictSearchParsers() {
        let html = """
        <html><body>
        <form>
            <input type="hidden" name="__VIEWSTATE" value="VS123" />
            <input type="hidden" name="__VIEWSTATEGENERATOR" value="GEN456" />
            <input type="hidden" name="__EVENTVALIDATION" value="EV789" />
            <select id="ddlStates">
                <option value="0">Select a State</option>
                <option value="180">Texas</option>
                <option value="199">Wisconsin</option>
            </select>
        </form>
        <div class="login-flex-container rowCount">
            <div class="login-flex-item"><span>LAKEVIEW ISD</span></div>
            <div class="login-flex-item">
                <strong>Family Access Login</strong>
                <a class="goButton" title="https://skyward.iscorp.com/p12lakeviewtx/web/seplog01.w" href="javascript:WriteCookie('https://skyward.iscorp.com/p12lakeviewtx/web/seplog01.w','LAKEVIEW ISD','Parent');">Go</a>
            </div>
        </div>
        <div class="login-flex-container rowCount">
            <div class="login-flex-item"><span>NORTHRIDGE ISD</span></div>
            <div class="login-flex-item">
                <strong>Family Access Login</strong>
                <a class="goButton" title="https://skyward.iscorp.com/NorthridgeTXStu" href="javascript:WriteCookie('https://skyward.iscorp.com/NorthridgeTXStu','NORTHRIDGE ISD','Parent');">Go</a>
            </div>
        </div>
        </body></html>
        """
        let states = DistrictSearch.parseStates(html)
        XCTAssertEqual(states, [DistrictState(id: "180", name: "Texas"), DistrictState(id: "199", name: "Wisconsin")])

        let tokens = Dictionary(uniqueKeysWithValues: DistrictSearch.parseTokens(html))
        XCTAssertEqual(tokens["__VIEWSTATE"], "VS123")
        XCTAssertEqual(tokens["__EVENTVALIDATION"], "EV789")

        let results = DistrictSearch.parseResults(html)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].name, "LAKEVIEW ISD")
        XCTAssertEqual(results[0].label, "Family Access Login")
        XCTAssertFalse(results[0].isQmlativ)
        XCTAssertTrue(results[1].isQmlativ)
    }

    // MARK: - BellMath & EmailPattern

    func testBellMathAndEmailPattern() {
        XCTAssertEqual(EmailPattern.firstDotLast.address(for: "Dana Whitfield", domain: "lakeview.edu"), "dana.whitfield@lakeview.edu")
        XCTAssertEqual(EmailPattern.firstInitialLast.address(for: "WHITFIELD, DANA", domain: "@lakeview.edu"), "dwhitfield@lakeview.edu")

        let range = BellMath.parseTimeRange("8:15 AM - 9:05 AM")
        XCTAssertEqual(range?.start, 495)
        XCTAssertEqual(range?.end, 545)
        XCTAssertEqual(BellMath.format(495), "8:15 AM")
    }
}
