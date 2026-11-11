import XCTest

final class QmlativMapperTests: XCTestCase {

    func testHelpersNumberPointsAndPeriod() {
        XCTAssertEqual(QmlativMapper.number("99.00 %"), 99.0)
        XCTAssertEqual(QmlativMapper.number("1,100.00"), 1100.0)
        XCTAssertNil(QmlativMapper.number("   "))

        let pts = QmlativMapper.points("630.00 / 1,100.00")
        XCTAssertEqual(pts.earned, 630.0)
        XCTAssertEqual(pts.possible, 1100.0)

        XCTAssertEqual(QmlativMapper.period("Period 1 - Year"), "1")
        XCTAssertEqual(QmlativMapper.period("Period 4A-4B - Year"), "4A-4B")
        XCTAssertEqual(QmlativMapper.period("Period FLEX - Semester 1"), "FLEX")
    }

    func testGradebookMappingWith19HeadersAndGradelessSectionsDropped() throws {
        let gridJSON = #"""
        {
          "heads": [
            {"text": "Class", "current": false},
            {"text": "Missing Assignments", "current": false},
            {"text": "PR1", "current": false},
            {"text": "PR2", "current": false},
            {"text": "Q1", "current": false},
            {"text": "PR3", "current": false},
            {"text": "PR4", "current": true},
            {"text": "Q2", "current": false},
            {"text": "SE1", "current": false},
            {"text": "S1", "current": false},
            {"text": "PR5", "current": false},
            {"text": "PR6", "current": false},
            {"text": "Q3", "current": false},
            {"text": "PR7", "current": false},
            {"text": "PR8", "current": false},
            {"text": "Q4", "current": false},
            {"text": "SE2", "current": false},
            {"text": "S2", "current": false},
            {"text": "", "current": false}
          ],
          "rows": [
            {
              "section": "359589",
              "student": "5089",
              "name": "English 3 AP GT (Humanities)",
              "code": "LA8ENG3",
              "period": "Period 1 - Year",
              "cells": [
                {"text": "ENGLISH 3 AP GT (HUMANITIES) Period 1 - Year", "id": "", "link": false},
                {"text": "0", "id": "", "link": false},
                {"text": "99", "id": "3125140", "link": true},
                {"text": "97", "id": "3125141", "link": true},
                {"text": "98", "id": "3125142", "link": true},
                {"text": "95", "id": "3125143", "link": true},
                {"text": "96", "id": "3125144", "link": true},
                {"text": "96", "id": "3125145", "link": true},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false}
              ]
            },
            {
              "section": "359590",
              "student": "5089",
              "name": "American Studies AP GT (Humanities)",
              "code": "SS8AMS",
              "period": "Period 4A-4B - Year",
              "cells": [
                {"text": "AMERICAN STUDIES AP GT (HUMANITIES) Period 4A-4B - Year", "id": "", "link": false},
                {"text": "0", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false}
              ]
            },
            {
              "section": "359599",
              "student": "5089",
              "name": "LUNCH",
              "code": "LUNCH",
              "period": "Period 5 - Year",
              "cells": [
                {"text": "LUNCH Period 5 - Year", "id": "", "link": false},
                {"text": "0", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false},
                {"text": "", "id": "", "link": false}
              ]
            }
          ],
          "missing": "1"
        }
        """#

        let grid = try JSONDecoder().decode(QmlGrid.self, from: Data(gridJSON.utf8))
        XCTAssertEqual(grid.heads.count, 19)
        let mapped = QmlativMapper.gradebook(grid)

        XCTAssertEqual(mapped.buckets.map { $0.lit }, [
            "PR1", "PR2", "Q1", "PR3", "PR4", "Q2", "SE1", "S1",
            "PR5", "PR6", "Q3", "PR7", "PR8", "Q4", "SE2", "S2"
        ])
        XCTAssertEqual(mapped.currentLit, "PR4")
        XCTAssertEqual(mapped.courses.count, 1, "Gradeless second section and LUNCH must be dropped")

        let english = mapped.courses[0]
        XCTAssertEqual(english.id, "359589")
        XCTAssertEqual(english.cni, "359589")
        XCTAssertEqual(english.studentID, "5089")
        XCTAssertEqual(english.name, "English 3 AP GT (Humanities)")
        XCTAssertEqual(english.period, "1")
        XCTAssertEqual(english.grade("PR1")?.text, "99")
        XCTAssertEqual(english.grade("PR1")?.bucket, "3125140")
        XCTAssertEqual(english.grade("PR1")?.hasDetail, true)
        XCTAssertEqual(english.grade("Q2")?.text, "96")
    }

    func testPanelMappingWithTwoCategoriesThousandsSeparatorFlaggedZeroAndEmptyAdjustedWeight() throws {
        // 1. Panel where Summative has no graded work yet (empty adjusted weight in modal),
        //    plus a second two-category panel with both Formative (30%) and Summative (70%) graded.
        let singleGradedCatJSON = #"""
        {
          "teacher": "Keith Chen",
          "period": "Period 1 - Year",
          "lit": "PR1",
          "range": "08/13/2026-09/04/2026",
          "grade": "99",
          "percent": "99.00 %",
          "rows": [
            {
              "category": true,
              "name": "Formative",
              "due": "",
              "grade": "99",
              "score": "99.00%",
              "points": "495.00 / 500.00",
              "attempts": "",
              "flagged": false
            },
            {
              "category": false,
              "name": "Class Application Letter",
              "due": "08/14/2026",
              "grade": "100",
              "score": "100.00%",
              "points": "100.00 / 100.00",
              "attempts": "1",
              "flagged": false
            }
          ],
          "weights": [
            {"name": "Formative", "weight": "30.00", "adjusted": "100.00", "percent": "99.00"},
            {"name": "Summative", "weight": "70.00", "adjusted": "", "percent": ""}
          ]
        }
        """#

        let panel1 = try JSONDecoder().decode(QmlPanel.self, from: Data(singleGradedCatJSON.utf8))
        let now = SkyDate.make(2026, 11, 10)
        guard let detail1 = QmlativMapper.detail(panel1, courseID: "359589", lit: "PR1", bucket: "3125140", now: now) else {
            return XCTFail("Expected detail1")
        }
        XCTAssertEqual(detail1.teacher, "Keith Chen")
        XCTAssertEqual(detail1.period, "1")
        XCTAssertEqual(detail1.gradeText, "99")
        XCTAssertEqual(detail1.percent, 99.0)
        XCTAssertEqual(detail1.begin, SkyDate.make(2026, 8, 13))
        XCTAssertEqual(detail1.end, SkyDate.make(2026, 9, 4))
        XCTAssertEqual(detail1.categories.count, 2, "Unrepresented category from weights must still be appended")
        XCTAssertEqual(detail1.categories[0].name, "Formative")
        XCTAssertEqual(detail1.categories[0].weight, 30.0)
        XCTAssertEqual(detail1.categories[0].adjustedWeight, 100.0)
        XCTAssertEqual(detail1.categories[1].name, "Summative")
        XCTAssertEqual(detail1.categories[1].weight, 70.0)
        XCTAssertNil(detail1.categories[1].adjustedWeight)

        // 2. Two-category panel with thousands-separator points ("630.00 / 1,100.00") and a flagged zero assignment.
        //    Formative (30%): 630 / 1100 = 57.2727%
        //    Summative (70%): 190 / 200  = 95.0000%
        //    Weighted average = 0.30 * 57.2727 + 0.70 * 95.0 = 17.1818 + 66.5 = 83.68%
        let twoCatJSON = #"""
        {
          "teacher": "Keith Chen",
          "period": "Period 4A-4B - Year",
          "lit": "Q2",
          "range": "10/19/2026-12/18/2026",
          "grade": "84",
          "percent": "83.68 %",
          "rows": [
            {
              "category": true,
              "name": "Formative",
              "due": "",
              "grade": "57",
              "score": "57.27%",
              "points": "630.00 / 1,100.00",
              "attempts": "",
              "flagged": false
            },
            {
              "category": false,
              "name": "Rhetorical Analysis Check",
              "due": "10/22/2026",
              "grade": "630",
              "score": "63.00%",
              "points": "630.00 / 1,000.00",
              "attempts": "1",
              "flagged": false
            },
            {
              "category": false,
              "name": "Dialectical Journal #4",
              "due": "11/02/2026",
              "grade": "0",
              "score": "0.00%",
              "points": "0.00 / 100.00",
              "attempts": "0",
              "flagged": true
            },
            {
              "category": true,
              "name": "Summative",
              "due": "",
              "grade": "95",
              "score": "95.00%",
              "points": "190.00 / 200.00",
              "attempts": "",
              "flagged": false
            },
            {
              "category": false,
              "name": "Synthesis Timed Writing",
              "due": "10/30/2026",
              "grade": "95",
              "score": "95.00%",
              "points": "95.00 / 100.00",
              "attempts": "1",
              "flagged": false
            },
            {
              "category": false,
              "name": "Unit 2 Seminar Assessment",
              "due": "11/06/2026",
              "grade": "95",
              "score": "95.00%",
              "points": "95.00 / 100.00",
              "attempts": "1",
              "flagged": false
            }
          ],
          "weights": [
            {"name": "Formative", "weight": "30.00", "adjusted": "30.00", "percent": "57.27"},
            {"name": "Summative", "weight": "70.00", "adjusted": "70.00", "percent": "95.00"}
          ]
        }
        """#

        let panel2 = try JSONDecoder().decode(QmlPanel.self, from: Data(twoCatJSON.utf8))
        guard let detail2 = QmlativMapper.detail(panel2, courseID: "359589", lit: "Q2", bucket: "3125145", now: now) else {
            return XCTFail("Expected detail2")
        }
        XCTAssertEqual(detail2.period, "4A-4B")
        XCTAssertEqual(detail2.categories[0].earned, 630.0)
        XCTAssertEqual(detail2.categories[0].possible, 1100.0)
        XCTAssertEqual(detail2.assignments.count, 4)
        XCTAssertEqual(detail2.assignments[0].possible, 1000.0)
        XCTAssertEqual(detail2.assignments[1].missing, true, "Flagged assignment with earned == 0 must be marked missing")
        XCTAssertEqual(detail2.assignments[0].missing, false)

        let computed = GradeMath.compute(detail2)
        XCTAssertNotNil(computed.percent)
        XCTAssertEqual(computed.percent ?? 0, detail2.percent ?? 0, accuracy: 0.6)
        XCTAssertEqual(computed.matchesPosted, true)
    }

    func testAttendanceMappingWithLeadingEmptyCellAndLegend() throws {
        let attJSON = #"""
        {
          "heads": ["", "Date", "1", "2", "3", "4", "5", "6", "FLEX", "7", ""],
          "rows": [
            ["", "", "", "", "", "", "", "", "", "", ""],
            ["", "11/05/2026 Thursday", "", "SA", "SA", "", "PN", "", "TST", "TA", ""]
          ],
          "legend": {
            "PN": "Parent Note",
            "SA": "Student Activity",
            "TA": "Teacher Absence Unexcused",
            "TST": "Testing"
          },
          "totals": "Days Absent6.00Days Excused5.00Days Unexcused1.00Days Other5.00Tardy Count0.00"
        }
        """#

        let page = try JSONDecoder().decode(QmlAttendance.self, from: Data(attJSON.utf8))
        let events = QmlativMapper.attendance(page)
        XCTAssertEqual(events.count, 4)

        XCTAssertEqual(events[0].date, SkyDate.make(2026, 11, 5))
        XCTAssertEqual(events[0].reason, "Student Activity")
        XCTAssertEqual(events[0].periods, "2, 3")
        XCTAssertEqual(events[0].kind, .other)

        XCTAssertEqual(events[1].reason, "Parent Note")
        XCTAssertEqual(events[1].periods, "5")
        XCTAssertEqual(events[1].kind, .excused)

        XCTAssertEqual(events[2].reason, "Testing")
        XCTAssertEqual(events[2].periods, "FLEX")
        XCTAssertEqual(events[2].kind, .other)

        XCTAssertEqual(events[3].reason, "Teacher Absence Unexcused")
        XCTAssertEqual(events[3].periods, "7")
        XCTAssertEqual(events[3].kind, .unexcused)
    }
}
