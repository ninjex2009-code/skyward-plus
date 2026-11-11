import Foundation

/// Turns Skyward Family/Student Access responses into model values.
///
/// Markup facts used here come from Skyward's own login page script and from the
/// behaviour documented by open-source Skyward clients; nothing here executes
/// script from the server.
enum SkywardParser {

    // MARK: Sign-in

    enum LoginOutcome: Equatable {
        case success([String])
        case mfaRequired(hideTrustDevice: Bool)
        case failure(String)
    }

    /// The reply to `skyporthttp.w` is `<li>...</li>`. On success the payload is a
    /// caret-separated list; otherwise it is "Mfa..." or a message for the user.
    static func loginOutcome(_ body: String) -> LoginOutcome {
        var inner = body
        if let open = body.range(of: "<li>", options: .caseInsensitive) {
            let rest = body[open.upperBound...]
            if let close = rest.range(of: "</li>", options: .caseInsensitive) {
                inner = String(rest[..<close.lowerBound])
            } else {
                inner = String(rest)
            }
        }
        inner = inner.replacingOccurrences(of: "&#x005B;", with: "[", options: .caseInsensitive)
            .replacingOccurrences(of: "&#x005D;", with: "]", options: .caseInsensitive)

        if inner.hasPrefix("Mfa") {
            let parts = inner.components(separatedBy: ",")
            return .mfaRequired(hideTrustDevice: parts.count > 1 && parts[1].trimmingCharacters(in: .whitespaces) == "HideTrustDevice")
        }
        guard inner.contains("^") else {
            let message = HTMLNode.parse(inner).cleanText
            return .failure(message.isEmpty ? "Skyward did not accept that sign-in." : message)
        }
        let tokens = inner.components(separatedBy: "^")
        guard tokens.count >= 15 else { return .failure("Skyward sent a sign-in reply this app does not understand.") }
        return .success(tokens)
    }

    struct FormField: Equatable {
        var name: String
        var value: String
        var type: String
    }

    /// Named inputs of one form, in document order. Later duplicates of a name are dropped.
    static func formFields(_ html: String, form formName: String) -> [FormField] {
        let doc = HTMLNode.parse(html)
        guard let form = doc.first(where: { $0.tag == "form" && ($0.attr("name") == formName || $0.id == formName) }) else { return [] }
        var seen = Set<String>()
        var out: [FormField] = []
        for input in form.descendants() where input.tag == "input" {
            guard let name = input.attr("name"), !name.isEmpty, !seen.contains(name) else { continue }
            let type = (input.attr("type") ?? "text").lowercased()
            if type == "submit" || type == "button" || type == "image" { continue }
            seen.insert(name)
            out.append(FormField(name: name, value: input.attr("value") ?? "", type: type))
        }
        return out
    }

    struct LoginPageInfo {
        var fields: [FormField] = []
        var hasPasswordLogin = false
        var hasSSO = false
        var ssoLabel = ""
        var looksLikeSkyward = false
        var title = ""
    }

    static func loginPage(_ html: String) -> LoginPageInfo {
        var info = LoginPageInfo()
        info.fields = formFields(html, form: "detailform")
        info.hasPasswordLogin = info.fields.contains { $0.name == "login" } && info.fields.contains { $0.name == "password" }
        info.looksLikeSkyward = html.contains("skyporthttp") || html.contains("detailform") || html.contains("skyportlogin")
        let doc = HTMLNode.parse(html)
        if let sso = doc.byId("bSSOLogin") {
            info.hasSSO = true
            info.ssoLabel = sso.cleanText
        }
        info.title = doc.firstTag("title")?.cleanText ?? ""
        return info
    }

    struct HomeInfo: Equatable {
        var sessionID: String?
        var encses: String?
        var userName = ""
        var children: [ChildAccount] = []
    }

    private static func sffValue(_ key: String, in html: String) -> String? {
        guard let groups = Str.match("sff\\.sv\\(\\s*'\(key)'\\s*,\\s*'([^']*)'", in: html, options: []) else { return nil }
        let value = groups[1]
            .replacingOccurrences(of: "\\x15", with: "\u{15}")
            .replacingOccurrences(of: "\\u0015", with: "\u{15}")
            .replacingOccurrences(of: "%15", with: "\u{15}")
        return value.isEmpty ? nil : value
    }

    static func home(_ html: String) -> HomeInfo {
        var info = HomeInfo()
        info.sessionID = sffValue("sessionid", in: html)
        info.encses = sffValue("encses", in: html)
        let doc = HTMLNode.parse(html)
        if let user = doc.first(where: { $0.hasClass("sf_utilUser") }) {
            info.userName = user.cleanText
        }
        if let list = doc.byId("sf_StudentList") {
            for a in list.all("a") {
                guard let id = a.attr("data-nameid"), !id.isEmpty else { continue }
                let name = a.cleanText
                if name.lowercased().contains("all students") || id == "0" { continue }
                if !info.children.contains(where: { $0.id == id }) {
                    info.children.append(ChildAccount(id: id, name: name))
                }
            }
        }
        return info
    }

    static func isSessionExpired(_ body: String) -> Bool {
        if body.contains("Your session has expired") { return true }
        if body.contains("class=\"sfLogout\"") || body.contains("class='sfLogout'") { return true }
        if body.contains("status:\"logout\"") || body.contains("status:\\\"logout\\\"") { return true }
        return false
    }

    // MARK: Script grids

    /// Every grid object set through `sff.sv('sf_gridObjects', $.extend(..., {...}))`.
    static func gridObjects(in html: String) -> [(key: String, value: JSValue)] {
        let bytes = Array(html.utf8)
        let marker = Array("sff.getValue('sf_gridObjects')".utf8)
        var out: [(String, JSValue)] = []
        var seen = Set<String>()
        var search = 0
        while let hit = find(marker, in: bytes, from: search) {
            var p = hit + marker.count
            search = p
            // Skip the "|| {})" that closes the first $.extend argument, then find the literal.
            while p < bytes.count, bytes[p] != 0x29 { p += 1 }          // ")"
            while p < bytes.count, bytes[p] != 0x7B {                    // "{"
                if bytes[p] == 0x3B { break }                            // ";" - no literal here
                p += 1
            }
            guard p < bytes.count, bytes[p] == 0x7B else { continue }
            var parser = JSLiteralParser(bytes: bytes, start: p)
            guard let value = parser.parseValue(), case .object(let dict, let keys) = value else { continue }
            search = max(search, parser.i)
            for key in keys {
                guard let v = dict[key], !seen.contains(key) else { continue }
                seen.insert(key)
                out.append((key, v))
            }
        }
        return out
    }

    private static func find(_ needle: [UInt8], in hay: [UInt8], from: Int) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count, from <= hay.count - needle.count else { return nil }
        let first = needle[0]
        var i = from
        let last = hay.count - needle.count
        while i <= last {
            if hay[i] == first {
                var k = 1
                while k < needle.count, hay[i + k] == needle[k] { k += 1 }
                if k == needle.count { return i }
            }
            i += 1
        }
        return nil
    }

    // MARK: Gradebook

    struct GradebookStudent {
        var studentID: String
        var buckets: [TermBucket] = []
        var courses: [Course] = []
    }

    private struct RawCell {
        var index: Int
        var lit: String
        var bucket: String
        var text: String
        var hasDetail: Bool
    }

    static func gradebook(_ html: String) -> [GradebookStudent] {
        let grids = gridObjects(in: html).filter { $0.key.hasPrefix("stuGradesGrid") }
        guard !grids.isEmpty else { return [] }
        let doc = HTMLNode.parse(html)
        var idIndex: [String: HTMLNode] = [:]
        for node in doc.descendants() {
            if let id = node.attributes["id"], idIndex[id] == nil { idIndex[id] = node }
        }

        var students: [GradebookStudent] = []

        for (key, grid) in grids {
            let keyParts = key.split(separator: "_").map(String.init)
            let keyStudent = keyParts.count > 1 ? keyParts[1] : ""
            let keyEntity = keyParts.count > 2 ? keyParts[2] : ""

            // Column headers, when the grid carries them.
            var headers: [(text: String, tooltip: String)] = []
            if let headRow = grid["th"]?["r"]?[0]?["c"]?.array {
                for cell in headRow {
                    let node = HTMLNode.parse(cell["h"]?.string ?? "")
                    let tip = node.first(where: { $0.attr("tooltip") != nil })?.attr("tooltip") ?? ""
                    headers.append((node.cleanText, HTMLNode.clean(tip)))
                }
            }

            var columnLit: [Int: (lit: String, bucket: String)] = [:]
            var pending: [(course: Course, cells: [RawCell])] = []

            for row in grid["tb"]?["r"]?.array ?? [] {
                let cells = row["c"]?.array ?? []
                guard let first = cells.first else { continue }
                let rowTag = row["h"]?.string ?? ""

                if let cId = first["cId"]?.string {
                    var course = Course(id: "", name: "")
                    course.studentID = keyStudent
                    course.entityID = keyEntity
                    let description = idIndex[cId] ?? HTMLNode.parse(first["h"]?.string ?? "")
                    fillClassDescription(&course, from: description)

                    var raw: [RawCell] = []
                    for (index, cell) in cells.enumerated() where index > 0 {
                        guard let h = cell["h"]?.string, !h.isEmpty else { continue }
                        let node = HTMLNode.parse(h)
                        let text = node.cleanText
                        if let link = node.first(where: { $0.attributes["id"] == "showGradeInfo" || $0.attributes["data-bkt"] != nil }) {
                            let lit = link.attr("data-lit") ?? ""
                            let bucket = link.attr("data-bkt") ?? ""
                            if course.cni.isEmpty, let v = link.attr("data-cni"), !v.isEmpty { course.cni = v }
                            if let v = link.attr("data-sid"), !v.isEmpty { course.studentID = v }
                            if let v = link.attr("data-eid"), !v.isEmpty { course.entityID = v }
                            if course.track.isEmpty, let v = link.attr("data-trk") { course.track = v }
                            if course.section.isEmpty, let v = link.attr("data-sec") { course.section = v }
                            if course.gid.isEmpty, let v = link.attr("data-gid"), !v.isEmpty { course.gid = v }
                            if let v = link.attr("data-iseoc"), !v.isEmpty { course.isEoc = v }
                            if !lit.isEmpty { columnLit[index] = (lit, bucket) }
                            raw.append(RawCell(index: index, lit: lit, bucket: bucket, text: text, hasDetail: true))
                        } else if !text.isEmpty {
                            raw.append(RawCell(index: index, lit: "", bucket: "", text: text, hasDetail: false))
                        }
                    }

                    if course.cni.isEmpty, let group = Str.match("group-parent=[\"']([^\"']+)[\"']", in: rowTag) {
                        let parts = group[1].split(separator: "_").map(String.init)
                        if parts.count >= 2 { course.cni = parts[1] }
                        if parts.count >= 3 { course.track = parts[2] }
                        if parts.count >= 4 { course.section = parts[3] }
                    }
                    course.id = course.cni.isEmpty
                        ? "c" + Str.hash(course.name, course.period, course.teacher)
                        : [course.cni, course.track, course.section].filter { !$0.isEmpty }.joined(separator: "_")
                    pending.append((course, raw))
                } else if !pending.isEmpty, let h = first["h"]?.string, h.contains("showAssignmentInfo") {
                    let node = HTMLNode.parse(h)
                    guard let link = node.first(where: { $0.attributes["id"] == "showAssignmentInfo" }) else { continue }
                    var item = InlineAssignment(aid: link.attr("data-aid"), gid: link.attr("data-gid"), name: link.cleanText, due: nil, lit: "", gradeText: "")
                    let rest = node.cleanText
                    if let m = Str.match("(\\d{1,2}/\\d{1,2}/\\d{2,4})", in: rest) { item.due = SkyDate.parse(m[1]) }
                    if let m = Str.match("\\(([A-Za-z0-9 ]{1,8})\\)\\s*$", in: rest) { item.lit = m[1] }
                    for cell in cells.dropFirst() {
                        let text = HTMLNode.parse(cell["h"]?.string ?? "").cleanText
                        if !text.isEmpty { item.gradeText = text; break }
                    }
                    pending[pending.count - 1].course.inline.append(item)
                }
            }

            // How header cells line up with body cells.
            var headerOffset: Int?
            if !headers.isEmpty {
                var votes: [Int: Int] = [:]
                for (index, value) in columnLit {
                    for d in 0...3 where index - d >= 0 && index - d < headers.count && headers[index - d].text == value.lit {
                        votes[d, default: 0] += 1
                    }
                }
                headerOffset = votes.max { $0.value < $1.value }?.key
            }

            func resolve(_ cell: RawCell) -> (lit: String, bucket: String)? {
                if !cell.lit.isEmpty { return (cell.lit, cell.bucket) }
                if let known = columnLit[cell.index] { return known }
                if let d = headerOffset, cell.index - d >= 0, cell.index - d < headers.count {
                    let text = headers[cell.index - d].text
                    if !text.isEmpty { return (text, "") }
                }
                return nil
            }

            var columns: [Int: TermBucket] = [:]
            for (index, value) in columnLit {
                columns[index] = TermBucket(lit: value.lit, bucket: value.bucket, name: "")
            }
            if let d = headerOffset {
                for (h, header) in headers.enumerated() {
                    let index = h + d
                    if var known = columns[index] {
                        known.name = header.tooltip
                        columns[index] = known
                    } else if !header.text.isEmpty, columnLit.values.contains(where: { $0.lit == header.text }) == false,
                              BucketKind.classify(header.text) != .other {
                        columns[index] = TermBucket(lit: header.text, bucket: "", name: header.tooltip)
                    }
                }
            }
            let buckets = columns.keys.sorted().compactMap { columns[$0] }

            var courses: [Course] = []
            for entry in pending {
                var course = entry.course
                for cell in entry.cells {
                    guard let (lit, bucket) = resolve(cell) else { continue }
                    if let existing = course.grades.firstIndex(where: { $0.lit == lit }) {
                        if course.grades[existing].isEmpty, !cell.text.isEmpty {
                            course.grades[existing].text = cell.text
                        }
                    } else {
                        course.grades.append(PostedGrade(lit: lit, bucket: bucket, text: cell.text, hasDetail: cell.hasDetail))
                    }
                }
                courses.append(course)
            }

            let sid = courses.first(where: { !$0.studentID.isEmpty })?.studentID ?? keyStudent
            if let existing = students.firstIndex(where: { $0.studentID == sid }) {
                // A student enrolled in two schools gets one grid per school.
                for b in buckets where !students[existing].buckets.contains(where: { $0.lit == b.lit }) {
                    students[existing].buckets.append(b)
                }
                students[existing].courses.append(contentsOf: courses)
            } else {
                students.append(GradebookStudent(studentID: sid, buckets: buckets, courses: courses))
            }
        }
        return students
    }

    /// Class name, period, time and teacher from the description block that the
    /// gradebook grid points at through `cId`.
    private static func fillClassDescription(_ course: inout Course, from node: HTMLNode) {
        let anchors = node.all("a")
        let cellsText = node.all("td").filter { $0.all("td").isEmpty }.map { $0.cleanText }.filter { !$0.isEmpty }

        if let named = node.first(where: { $0.hasClass("classDesc") }) {
            course.name = named.cleanText
        } else if let first = anchors.first {
            course.name = first.cleanText
        } else if let first = cellsText.first {
            course.name = first
        }

        if let periodCell = node.all("td").first(where: { $0.all("td").isEmpty && $0.cleanText.range(of: "Period", options: .caseInsensitive) != nil }) {
            let text = periodCell.cleanText
            if let m = Str.match("Period\\s*:?\\s*([A-Za-z0-9]+)", in: text) { course.period = m[1] }
            if let m = Str.match("\\(([^)]*\\d[^)]*)\\)", in: text) {
                course.timeRange = m[1]
            } else if let m = Str.match("(\\d{1,2}:\\d{2}\\s*[AP]M\\s*-\\s*\\d{1,2}:\\d{2}\\s*[AP]M)", in: text) {
                course.timeRange = m[1]
            }
        }

        if anchors.count > 1, let last = anchors.last {
            course.teacher = last.cleanText
        } else if cellsText.count >= 3 {
            course.teacher = cellsText[cellsText.count - 1]
        }
        if course.teacher == course.name { course.teacher = "" }
    }

    // MARK: Assignment list for one class and bucket

    /// The HTML carried inside Skyward's XML reply, or the text itself when it is not wrapped.
    static func dialogHTML(_ response: String) -> String {
        guard let open = response.range(of: "<![CDATA[") else { return response }
        let rest = response[open.upperBound...]
        if let close = rest.range(of: "]]>") { return String(rest[..<close.lowerBound]) }
        return String(rest)
    }

    static func gradeDetail(_ response: String, courseID: String, lit: String, bucket: String) -> GradeDetail? {
        let html = dialogHTML(response)
        guard html.contains("grid_stuAssignmentSummaryGrid") || html.contains("grid_stuTermSummaryGrid") || html.contains("gb_heading") else {
            return nil
        }
        let doc = HTMLNode.parse(html)
        var detail = GradeDetail(courseID: courseID, lit: lit, bucket: bucket)

        if let heading = doc.first(where: { $0.hasClass("gb_heading") }) {
            let anchors = heading.all("a")
            detail.courseName = anchors.first?.cleanText ?? ""
            if anchors.count > 1 { detail.teacher = anchors.last?.cleanText ?? "" }
            if let m = Str.match("Period\\s*([A-Za-z0-9]+)", in: heading.cleanText) { detail.period = m[1] }
        }

        if let summary = doc.first(where: { $0.tag == "table" && ($0.id ?? "").contains("grid_stuTermSummaryGrid") }) {
            let rows = summary.tableRows
            if let head = rows.first(where: { $0.cells.contains { $0.tag == "th" } }), let th = head.cells.first {
                let text = th.cleanText
                if let m = Str.match("(\\d{1,2}/\\d{1,2}/\\d{2,4})\\s*-\\s*(\\d{1,2}/\\d{1,2}/\\d{2,4})", in: text) {
                    detail.begin = SkyDate.parse(m[1])
                    detail.end = SkyDate.parse(m[2])
                }
            }
            let body = rows.filter { row in !row.cells.contains { $0.tag == "th" } }
            if let first = body.first {
                let cells = first.cells
                detail.gradeText = cells.first?.cleanText ?? ""
                if cells.count > 1 { detail.percent = Str.number(cells.last?.cleanText) }
            }
            for row in body.dropFirst() {
                let text = row.cleanText
                if text.isEmpty || text.lowercased().hasPrefix("grade breakdown") { continue }
                let cells = row.cells
                if text.lowercased().contains("grade adjustment") {
                    if let m = Str.match("(-?\\d+(?:\\.\\d+)?)\\s*$", in: text) { detail.adjustment = Double(m[1]) }
                    continue
                }
                guard let labelCell = cells.first else { continue }
                let parts = labelCell.elements.flatMap { $0.tag == "div" ? [$0] : $0.all("div") }
                var label = (labelCell.firstTag("label") ?? labelCell.firstTag("a"))?.cleanText ?? parts.first?.cleanText ?? ""
                label = label.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                guard !label.isEmpty, label.count <= 12 else { continue }
                var item = BreakdownItem(lit: label, gradeText: "", percent: nil, weight: nil)
                if parts.count >= 2 { item.gradeText = parts[1].cleanText }
                if let m = Str.match("\\((\\d+(?:\\.\\d+)?)%", in: labelCell.cleanText) { item.weight = Double(m[1]) }
                if cells.count > 1 { item.percent = Str.number(cells.last?.cleanText) }
                detail.breakdown.append(item)
            }
        }

        guard let table = doc.first(where: { $0.tag == "table" && ($0.id ?? "").contains("grid_stuAssignmentSummaryGrid") }) else {
            return detail
        }
        let rows = table.tableRows

        // Logical column positions, read from the header when it is there.
        var colDue = 0, colName = 2, colGrade = 3, colScore = 4, colPoints = 5, colMissing = 6, colNoCount = 7, colAbsent = 8
        if let head = rows.first(where: { $0.cells.contains { $0.tag == "th" } }) {
            var seen = Set<String>()
            for (index, cell) in head.logicalCells.enumerated() {
                let text = cell.cleanText.lowercased()
                func take(_ key: String) -> Bool {
                    if seen.contains(key) { return false }
                    seen.insert(key)
                    return true
                }
                if text.hasPrefix("due"), take("due") { colDue = index }
                else if text.hasPrefix("assignment"), take("name") { colName = index }
                else if text.hasPrefix("grade"), take("grade") { colGrade = index }
                else if text.hasPrefix("score"), take("score") { colScore = index }
                else if text.hasPrefix("points"), take("points") { colPoints = index }
                else if text.hasPrefix("missing"), take("missing") { colMissing = index }
                else if text.hasPrefix("no count"), take("nocount") { colNoCount = index }
                else if text.hasPrefix("absent"), take("absent") { colAbsent = index }
            }
        }

        func points(_ cell: HTMLNode?) -> (earned: Double?, possible: Double?) {
            guard let text = cell?.cleanText, !text.isEmpty else { return (nil, nil) }
            if let m = Str.match("^\\s*(\\S+)\\s*out of\\s*(\\S+)", in: text) {
                return (Str.number(m[1]), Str.number(m[2]))
            }
            return (nil, nil)
        }

        func flagged(_ cell: HTMLNode?) -> Bool {
            guard let cell else { return false }
            return !cell.cleanText.isEmpty || cell.firstTag("img") != nil
        }

        var currentCategory = ""
        for row in rows {
            let cells = row.cells
            if cells.contains(where: { $0.tag == "th" }) || cells.count <= 1 { continue }
            let logical = row.logicalCells
            func cell(_ index: Int) -> HTMLNode? { index < logical.count ? logical[index] : nil }

            if row.hasClass("sf_Section") || row.hasClass("cat") {
                guard let label = cells.first(where: { $0.hasClass("noLBdr") }) ?? (cells.count > 1 ? cells[1] : nil) else { continue }
                let spans = label.all("span")
                // A row for one term of a semester category: its label is a term code with a tooltip.
                if label.ownText.isEmpty, let lead = spans.first, lead.attr("tooltip") != nil { continue }
                var name = label.ownText
                let spanText = spans.map { $0.cleanText }.joined(separator: " ")
                if name.isEmpty {
                    name = label.cleanText.replacingOccurrences(of: spanText, with: "").trimmingCharacters(in: .whitespaces)
                }
                guard !name.isEmpty, name != currentCategory else { continue }
                var category = GradeCategory(name: name)
                let weightText = spanText.isEmpty ? label.cleanText : spanText
                if let m = Str.match("weighted at\\s*(\\d+(?:\\.\\d+)?)\\s*%", in: weightText) { category.weight = Double(m[1]) }
                if let m = Str.match("adjusted to\\s*(\\d+(?:\\.\\d+)?)\\s*%", in: weightText) { category.adjustedWeight = Double(m[1]) }
                category.gradeText = cell(colGrade)?.cleanText ?? ""
                category.percent = Str.number(cell(colScore)?.cleanText)
                let p = points(cell(colPoints))
                category.earned = p.earned
                category.possible = p.possible
                if !detail.categories.contains(where: { $0.name == name }) { detail.categories.append(category) }
                currentCategory = name
                continue
            }

            let link = row.first(where: { $0.attributes["id"] == "showAssignmentInfo" })
            let name = link?.cleanText ?? cell(colName)?.cleanText ?? ""
            guard !name.isEmpty else { continue }
            let due = SkyDate.parse(cell(colDue)?.cleanText ?? "")
            let aid = link?.attr("data-aid")
            var assignment = Assignment(
                id: (aid?.isEmpty == false ? aid! : "a" + Str.hash(name, cell(colDue)?.cleanText ?? "", currentCategory)),
                aid: aid, gid: link?.attr("data-gid"), sid: link?.attr("data-sid"),
                name: name, category: currentCategory, due: due
            )
            let gradeCell = cell(colGrade)
            assignment.gradeText = gradeCell?.cleanText ?? ""
            if let special = gradeCell?.first(where: { ($0.id ?? "").hasPrefix("specCode") }) {
                assignment.specialCode = special.attr("data-info") ?? special.attr("tooltip") ?? "Special code"
            }
            assignment.percent = Str.number(cell(colScore)?.cleanText)
            let p = points(cell(colPoints))
            assignment.earned = p.earned
            assignment.possible = p.possible
            assignment.missing = flagged(cell(colMissing))
            assignment.noCount = flagged(cell(colNoCount))
            let absentCell = cell(colAbsent)
            assignment.absent = flagged(absentCell)
            assignment.absentNote = absentCell?.cleanText ?? ""
            detail.assignments.append(assignment)
        }
        return detail
    }

    // MARK: One assignment

    static func assignmentInfo(_ response: String) -> AssignmentInfo {
        let doc = HTMLNode.parse(dialogHTML(response))
        var info = AssignmentInfo()
        for row in doc.all("tr") {
            let cells = row.cells.filter { $0.all("table").isEmpty }
            if cells.isEmpty { continue }
            if cells.count == 1 {
                let text = cells[0].cleanText
                if info.title.isEmpty, info.fields.isEmpty, !text.isEmpty, text.count < 140 { info.title = text }
                continue
            }
            var index = 0
            while index + 1 < cells.count {
                let key = cells[index].cleanText.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                let value = cells[index + 1].cleanText
                if !key.isEmpty, !value.isEmpty, key.count < 60, !info.fields.contains(where: { $0.key == key }) {
                    info.fields.append(KeyValue(key: key, value: value))
                }
                index += 2
            }
        }
        return info
    }

    // MARK: Academic history

    static func history(_ html: String) -> [HistoryYear] {
        var years: [HistoryYear] = []
        for (key, grid) in gridObjects(in: html) where key.hasPrefix("gradeGrid") {
            var current: HistoryYear?
            func flush() {
                if let year = current, !year.courses.isEmpty { years.append(year) }
                current = nil
            }
            for row in grid["tb"]?["r"]?.array ?? [] {
                let cells = row["c"]?.array ?? []
                guard let first = cells.first?["h"]?.string else { continue }
                let firstNode = HTMLNode.parse(first)
                if firstNode.firstTag("div") != nil, Str.match("\\d{4}\\s*-\\s*\\d{4}", in: firstNode.cleanText) != nil {
                    flush()
                    current = HistoryYear(title: firstNode.cleanText)
                    continue
                }
                guard current != nil else { continue }
                if first.contains("vertical-align:bottom") {
                    var lits: [HistoryLit] = []
                    for cell in cells.dropFirst(2) {
                        let node = HTMLNode.parse(cell["h"]?.string ?? "")
                        let tip = node.first(where: { $0.attr("tooltip") != nil })?.attr("tooltip") ?? ""
                        lits.append(HistoryLit(lit: node.cleanText, name: HTMLNode.clean(tip)))
                    }
                    while let last = lits.last, last.lit.isEmpty { lits.removeLast() }
                    current?.lits = lits
                    continue
                }
                let name = firstNode.cleanText
                guard !name.isEmpty else { continue }
                let terms = cells.count > 1 ? HTMLNode.parse(cells[1]["h"]?.string ?? "").cleanText : ""
                var grades = cells.dropFirst(2).map { HTMLNode.parse($0["h"]?.string ?? "").cleanText }
                let count = current?.lits.count ?? 0
                if count > 0 {
                    if grades.count > count { grades = Array(grades.prefix(count)) }
                    while grades.count < count { grades.append("") }
                }
                current?.courses.append(HistoryCourse(name: name, terms: terms, grades: grades))
            }
            flush()
        }
        return years
    }

    // MARK: Attendance

    static func attendance(_ html: String) -> [AttendanceEvent] {
        var events: [AttendanceEvent] = []
        var seen = Set<String>()

        func add(_ texts: [String], classes: [String]) {
            guard texts.count >= 3, let date = SkyDate.parse(texts[0]) else { return }
            let reason = texts[1]
            guard !reason.isEmpty, reason.count < 80 else { return }
            var listed = classes.filter { !$0.isEmpty && $0.lowercased() != "view classes" }
            if listed.isEmpty, texts.count > 3, !texts[3].isEmpty, texts[3].lowercased() != "view classes" { listed = [texts[3]] }
            let event = AttendanceEvent(date: date, reason: reason, periods: texts[2], classes: listed)
            if !seen.contains(event.id) {
                seen.insert(event.id)
                events.append(event)
            }
        }

        let doc = HTMLNode.parse(html)
        for row in doc.all("tr") {
            let cells = row.cells
            guard cells.count >= 3, cells.allSatisfy({ $0.tag == "td" }) else { continue }
            let classes = cells.count > 3 ? cells[3].all("a").map { $0.cleanText } : []
            add(cells.map { $0.cleanText }, classes: classes)
        }
        if events.isEmpty {
            for (_, grid) in gridObjects(in: html) {
                for row in grid["tb"]?["r"]?.array ?? [] {
                    let nodes = (row["c"]?.array ?? []).map { HTMLNode.parse($0["h"]?.string ?? "") }
                    let classes = nodes.count > 3 ? nodes[3].all("a").map { $0.cleanText } : []
                    add(nodes.map { $0.cleanText }, classes: classes)
                }
            }
        }
        return events.sorted { $0.date > $1.date }
    }

    // MARK: Student profile

    static func studentInfo(_ html: String) -> StudentProfile {
        var profile = StudentProfile()
        let doc = HTMLNode.parse(html)
        let body = doc.byId("sf_ContentBody") ?? doc
        guard let tag = body.first(where: { $0.hasClass("sfTag") }) else { return profile }
        profile.name = tag.cleanText
        let scope = tag.parent ?? body
        if let img = scope.firstTag("img"), let src = img.attr("src"), !src.isEmpty { profile.photoPath = src }
        for row in scope.all("tr") {
            let cells = row.cells.filter { $0.all("table").isEmpty }
            var index = 0
            while index + 1 < cells.count {
                let key = cells[index].cleanText.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                let value = cells[index + 1].cleanText
                if !key.isEmpty, !value.isEmpty, key.count < 40, value.count < 120, !profile.attributes.contains(where: { $0.key == key }) {
                    profile.attributes.append(KeyValue(key: key, value: value))
                }
                index += 2
            }
        }
        for item in profile.attributes {
            let key = item.key.lowercased()
            if profile.gradeLevel.isEmpty, key == "grade" || key.hasPrefix("grade level") || key == "grad yr" { profile.gradeLevel = item.value }
            if profile.school.isEmpty, key.hasPrefix("school") || key.hasPrefix("default entity") { profile.school = item.value }
        }
        return profile
    }
}
