import Foundation

/// A small, forgiving HTML parser. Skyward's pages are machine-generated but not
/// well-formed (unquoted attributes, duplicate attributes, stray end tags), so this
/// accepts anything and never throws.
final class HTMLNode {
    let tag: String                      // lowercase name, "#text" or "#root"
    var attributes: [String: String]
    var children: [HTMLNode] = []
    weak var parent: HTMLNode?
    var value: String = ""               // text of a "#text" node

    init(tag: String, attributes: [String: String] = [:]) {
        self.tag = tag
        self.attributes = attributes
    }

    var isText: Bool { tag == "#text" }
    var isElement: Bool { tag != "#text" && tag != "#root" }

    func attr(_ name: String) -> String? { attributes[name.lowercased()] }
    var id: String? { attributes["id"] }
    var classes: [String] {
        (attributes["class"] ?? "").split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
    }
    func hasClass(_ name: String) -> Bool { classes.contains(name) }

    var elements: [HTMLNode] { children.filter { $0.isElement } }

    /// All text below this node, script and style excluded.
    var text: String {
        var out = ""
        collectText(into: &out)
        return out
    }

    private func collectText(into out: inout String) {
        if isText { out += value; return }
        if tag == "script" || tag == "style" { return }
        if tag == "br" { out += "\n" }
        for c in children { c.collectText(into: &out) }
    }

    /// Text with non-breaking spaces turned into spaces, runs of whitespace collapsed, trimmed.
    var cleanText: String { HTMLNode.clean(text) }

    /// Text that sits directly inside this element, not inside child elements.
    var ownText: String { HTMLNode.clean(children.filter { $0.isText }.map { $0.value }.joined(separator: " ")) }

    static func clean(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var pendingSpace = false
        for ch in s.unicodeScalars {
            if ch == " " || ch == "\n" || ch == "\t" || ch == "\r" || ch == "\u{00A0}" || ch == "\u{000C}" {
                pendingSpace = true
            } else {
                if pendingSpace && !out.isEmpty { out.unicodeScalars.append(" ") }
                pendingSpace = false
                out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    // MARK: Traversal

    /// Every element below this node, in document order.
    func descendants() -> [HTMLNode] {
        var out: [HTMLNode] = []
        collect(into: &out)
        return out
    }

    private func collect(into out: inout [HTMLNode]) {
        for c in children where c.isElement {
            out.append(c)
            c.collect(into: &out)
        }
    }

    func all(_ tagName: String) -> [HTMLNode] { descendants().filter { $0.tag == tagName } }

    func first(where test: (HTMLNode) -> Bool) -> HTMLNode? {
        for c in children where c.isElement {
            if test(c) { return c }
            if let hit = c.first(where: test) { return hit }
        }
        return nil
    }

    func firstTag(_ tagName: String) -> HTMLNode? { first { $0.tag == tagName } }
    func byId(_ id: String) -> HTMLNode? { first { $0.attributes["id"] == id } }

    func ancestor(_ tagName: String) -> HTMLNode? {
        var p = parent
        while let node = p {
            if node.tag == tagName { return node }
            p = node.parent
        }
        return nil
    }

    /// Rows that belong to this table itself, not to tables nested inside it.
    var tableRows: [HTMLNode] {
        descendants().filter { $0.tag == "tr" && $0.ancestor("table") === self }
    }

    /// Cells of this row (td and th), not cells of nested tables.
    var cells: [HTMLNode] { children.filter { $0.tag == "td" || $0.tag == "th" } }

    /// Cells laid out by logical column, honouring colspan. A cell spanning three
    /// columns appears three times.
    var logicalCells: [HTMLNode] {
        var out: [HTMLNode] = []
        for cell in cells {
            let span = max(1, min(40, Int(cell.attr("colspan") ?? "1") ?? 1))
            for _ in 0..<span { out.append(cell) }
        }
        return out
    }

    // MARK: Selectors

    /// Supports tag, #id, .class, [attr], [attr=v], [attr*=v], [attr^=v], [attr$=v],
    /// the descendant combinator (space) and the child combinator (>).
    func select(_ selector: String) -> [HTMLNode] {
        let steps = HTMLSelector.parse(selector)
        guard let last = steps.last else { return [] }
        return descendants().filter { node in
            last.compound.matches(node) && HTMLSelector.matchesAncestors(node, steps: steps, index: steps.count - 1, scope: self)
        }
    }

    func selectFirst(_ selector: String) -> HTMLNode? { select(selector).first }

    // MARK: Parsing

    static func parse(_ html: String) -> HTMLNode {
        var parser = HTMLParser(Array(html.utf8))
        return parser.run()
    }
}

struct HTMLSelector {
    struct AttrTest {
        var name: String
        var op: Character   // "?" exists, "=" equals, "*" contains, "^" prefix, "$" suffix
        var value: String
    }

    struct Compound {
        var tag: String?
        var id: String?
        var classes: [String] = []
        var attrs: [AttrTest] = []

        func matches(_ node: HTMLNode) -> Bool {
            guard node.isElement else { return false }
            if let tag, tag != "*", node.tag != tag { return false }
            if let id, node.attributes["id"] != id { return false }
            if !classes.isEmpty {
                let have = node.classes
                for c in classes where !have.contains(c) { return false }
            }
            for a in attrs {
                guard let v = node.attributes[a.name] else { return false }
                switch a.op {
                case "=": if v != a.value { return false }
                case "*": if !v.contains(a.value) { return false }
                case "^": if !v.hasPrefix(a.value) { return false }
                case "$": if !v.hasSuffix(a.value) { return false }
                default: break
                }
            }
            return true
        }
    }

    struct Step {
        var compound: Compound
        var child: Bool   // true when this step must be a direct child of the previous one
    }

    static func parse(_ selector: String) -> [Step] {
        var steps: [Step] = []
        let chars = Array(selector)
        var i = 0
        var nextIsChild = false
        while i < chars.count {
            let ch = chars[i]
            if ch == " " { i += 1; continue }
            if ch == ">" { nextIsChild = true; i += 1; continue }
            var c = Compound()
            var name = ""
            while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "*" || chars[i] == "-" || chars[i] == "_" {
                name.append(chars[i]); i += 1
            }
            if !name.isEmpty { c.tag = name.lowercased() }
            parts: while i < chars.count {
                switch chars[i] {
                case "#":
                    i += 1
                    var v = ""
                    while i < chars.count, !" >.#[".contains(chars[i]) { v.append(chars[i]); i += 1 }
                    c.id = v
                case ".":
                    i += 1
                    var v = ""
                    while i < chars.count, !" >.#[".contains(chars[i]) { v.append(chars[i]); i += 1 }
                    c.classes.append(v)
                case "[":
                    i += 1
                    var nameA = ""
                    while i < chars.count, !"=*^$]".contains(chars[i]) { nameA.append(chars[i]); i += 1 }
                    var op: Character = "?"
                    var value = ""
                    if i < chars.count, chars[i] != "]" {
                        if chars[i] == "=" { op = "="; i += 1 }
                        else { op = chars[i]; i += 1; if i < chars.count, chars[i] == "=" { i += 1 } }
                        while i < chars.count, chars[i] != "]" { value.append(chars[i]); i += 1 }
                        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
                    }
                    if i < chars.count { i += 1 }
                    c.attrs.append(AttrTest(name: nameA.trimmingCharacters(in: .whitespaces).lowercased(), op: op, value: value))
                default:
                    break parts
                }
            }
            steps.append(Step(compound: c, child: nextIsChild))
            nextIsChild = false
        }
        return steps
    }

    static func matchesAncestors(_ node: HTMLNode, steps: [Step], index: Int, scope: HTMLNode) -> Bool {
        if index == 0 { return true }
        let prev = steps[index - 1]
        if steps[index].child {
            guard let p = node.parent, prev.compound.matches(p) else { return false }
            return matchesAncestors(p, steps: steps, index: index - 1, scope: scope)
        }
        var p = node.parent
        while let candidate = p {
            if prev.compound.matches(candidate), matchesAncestors(candidate, steps: steps, index: index - 1, scope: scope) {
                return true
            }
            if candidate === scope { break }
            p = candidate.parent
        }
        return false
    }
}

private struct HTMLParser {
    let b: [UInt8]
    let n: Int
    var i = 0
    var textStart = 0
    let root = HTMLNode(tag: "#root")
    var stack: [HTMLNode]

    static let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
    static let rawTextTags: Set<String> = ["script", "style", "textarea", "title"]
    static let tableScoped: Set<String> = ["td", "th", "tr", "tbody", "thead", "tfoot"]

    init(_ bytes: [UInt8]) {
        b = bytes
        n = bytes.count
        stack = [root]
    }

    mutating func run() -> HTMLNode {
        while i < n {
            guard b[i] == 0x3C else { i += 1; continue }           // "<"
            if matches("<!--", at: i) {
                flushText(upTo: i)
                i = (find("-->", from: i + 4).map { $0 + 3 }) ?? n
                textStart = i
            } else if matches("<![CDATA[", at: i) {
                flushText(upTo: i)
                let end = find("]]>", from: i + 9) ?? n
                appendText(String(decoding: b[(i + 9)..<end], as: UTF8.self))
                i = min(n, end + 3)
                textStart = i
            } else if i + 1 < n, b[i + 1] == 0x21 || b[i + 1] == 0x3F {   // "<!" or "<?"
                flushText(upTo: i)
                i = (find(">", from: i + 2).map { $0 + 1 }) ?? n
                textStart = i
            } else if i + 1 < n, b[i + 1] == 0x2F {                       // "</"
                var j = i + 2
                while j < n, isNameByte(b[j]) { j += 1 }
                if j == i + 2 { i += 1; continue }
                let name = String(decoding: b[(i + 2)..<j], as: UTF8.self).lowercased()
                flushText(upTo: i)
                closeTag(name)
                i = (find(">", from: j).map { $0 + 1 }) ?? n
                textStart = i
            } else if i + 1 < n, isLetter(b[i + 1]) {
                flushText(upTo: i)
                startTag()
                textStart = i
            } else {
                i += 1
            }
        }
        flushText(upTo: n)
        return root
    }

    private func isLetter(_ c: UInt8) -> Bool { (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) }
    private func isNameByte(_ c: UInt8) -> Bool {
        isLetter(c) || (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x5F || c == 0x3A || c == 0x2E
    }
    private func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x0A || c == 0x09 || c == 0x0D || c == 0x0C }

    private func matches(_ s: String, at pos: Int) -> Bool {
        let u = Array(s.utf8)
        guard pos + u.count <= n else { return false }
        for k in 0..<u.count where b[pos + k] != u[k] { return false }
        return true
    }

    private func find(_ s: String, from: Int) -> Int? {
        let u = Array(s.utf8)
        guard !u.isEmpty, from <= n - u.count else { return nil }
        var p = from
        let lastStart = n - u.count
        while p <= lastStart {
            if b[p] == u[0] {
                var ok = true
                var k = 1
                while k < u.count { if b[p + k] != u[k] { ok = false; break }; k += 1 }
                if ok { return p }
            }
            p += 1
        }
        return nil
    }

    /// Case-insensitive search for "</name".
    private func findClose(_ name: String, from: Int) -> Int? {
        let u = Array(name.utf8)
        var p = from
        while p + 2 + u.count <= n {
            if b[p] == 0x3C, b[p + 1] == 0x2F {
                var ok = true
                for k in 0..<u.count {
                    let c = b[p + 2 + k]
                    let lower = (c >= 0x41 && c <= 0x5A) ? c + 32 : c
                    if lower != u[k] { ok = false; break }
                }
                if ok { return p }
            }
            p += 1
        }
        return nil
    }

    private mutating func flushText(upTo end: Int) {
        guard end > textStart else { return }
        let raw = String(decoding: b[textStart..<end], as: UTF8.self)
        appendText(HTMLEntities.decode(raw))
    }

    private mutating func appendText(_ s: String) {
        guard !s.isEmpty, let top = stack.last else { return }
        let node = HTMLNode(tag: "#text")
        node.value = s
        node.parent = top
        top.children.append(node)
    }

    private mutating func startTag() {
        var j = i + 1
        while j < n, isNameByte(b[j]) { j += 1 }
        let name = String(decoding: b[(i + 1)..<j], as: UTF8.self).lowercased()
        var attrs: [String: String] = [:]
        var selfClosing = false

        while j < n {
            while j < n, isSpace(b[j]) { j += 1 }
            if j >= n { break }
            if b[j] == 0x3E { j += 1; break }                               // ">"
            if b[j] == 0x2F { selfClosing = true; j += 1; continue }        // "/"
            let nameStart = j
            while j < n, !isSpace(b[j]), b[j] != 0x3D, b[j] != 0x3E, b[j] != 0x2F { j += 1 }
            if j == nameStart { j += 1; continue }
            let attrName = String(decoding: b[nameStart..<j], as: UTF8.self).lowercased()
            while j < n, isSpace(b[j]) { j += 1 }
            var attrValue = ""
            if j < n, b[j] == 0x3D {
                j += 1
                while j < n, isSpace(b[j]) { j += 1 }
                if j < n, b[j] == 0x22 || b[j] == 0x27 {
                    let quote = b[j]
                    let valueStart = j + 1
                    j = valueStart
                    while j < n, b[j] != quote { j += 1 }
                    attrValue = HTMLEntities.decode(String(decoding: b[valueStart..<min(j, n)], as: UTF8.self))
                    if j < n { j += 1 }
                } else {
                    let valueStart = j
                    while j < n, !isSpace(b[j]), b[j] != 0x3E { j += 1 }
                    attrValue = HTMLEntities.decode(String(decoding: b[valueStart..<j], as: UTF8.self))
                }
            }
            if attrs[attrName] == nil { attrs[attrName] = attrValue }
            selfClosing = false
        }
        i = j

        closeImplied(for: name)
        let node = HTMLNode(tag: name, attributes: attrs)
        if let top = stack.last {
            node.parent = top
            top.children.append(node)
        }
        if HTMLParser.voidTags.contains(name) || selfClosing { return }

        if HTMLParser.rawTextTags.contains(name) {
            let end = findClose(name, from: i) ?? n
            if end > i {
                let raw = String(decoding: b[i..<end], as: UTF8.self)
                let textNode = HTMLNode(tag: "#text")
                textNode.value = (name == "script" || name == "style") ? raw : HTMLEntities.decode(raw)
                textNode.parent = node
                node.children.append(textNode)
            }
            i = end
            if i < n {
                i = (find(">", from: i).map { $0 + 1 }) ?? n
            }
            return
        }
        stack.append(node)
    }

    @discardableResult
    private mutating func closeOpen(_ tags: Set<String>, barrier: Set<String>) -> Bool {
        var idx = stack.count - 1
        while idx > 0 {
            let t = stack[idx].tag
            if barrier.contains(t) { return false }
            if tags.contains(t) {
                stack.removeSubrange(idx...)
                return true
            }
            idx -= 1
        }
        return false
    }

    private mutating func closeImplied(for name: String) {
        switch name {
        case "tr":
            closeOpen(["tr"], barrier: ["table"])
        case "td", "th":
            closeOpen(["td", "th"], barrier: ["tr", "table"])
        case "tbody", "thead", "tfoot":
            while closeOpen(["tbody", "thead", "tfoot", "tr"], barrier: ["table"]) {}
        case "li":
            closeOpen(["li"], barrier: ["ul", "ol", "table"])
        case "option":
            closeOpen(["option"], barrier: ["select"])
        default:
            break
        }
    }

    private mutating func closeTag(_ name: String) {
        var idx = stack.count - 1
        let scoped = HTMLParser.tableScoped.contains(name)
        while idx > 0 {
            let t = stack[idx].tag
            if t == name {
                stack.removeSubrange(idx...)
                return
            }
            if scoped && t == "table" { return }
            idx -= 1
        }
    }
}

enum HTMLEntities {
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "rsquo": "\u{2019}",
        "lsquo": "\u{2018}", "ldquo": "\u{201C}", "rdquo": "\u{201D}", "copy": "\u{00A9}",
        "reg": "\u{00AE}", "deg": "\u{00B0}", "frac12": "\u{00BD}", "frac14": "\u{00BC}",
        "frac34": "\u{00BE}", "times": "\u{00D7}", "middot": "\u{00B7}", "bull": "\u{2022}",
        "eacute": "\u{00E9}", "ntilde": "\u{00F1}", "aacute": "\u{00E1}", "iacute": "\u{00ED}",
        "oacute": "\u{00F3}", "uacute": "\u{00FA}", "trade": "\u{2122}", "laquo": "\u{00AB}",
        "raquo": "\u{00BB}", "shy": "", "ensp": " ", "emsp": " ", "thinsp": " ",
    ]

    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        let scalars = Array(s.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let ch = scalars[i]
            guard ch == "&" else { out.unicodeScalars.append(ch); i += 1; continue }
            var j = i + 1
            var body = ""
            while j < scalars.count, j - i <= 12, scalars[j] != ";", scalars[j] != "&", scalars[j] != " ", scalars[j] != "<" {
                body.unicodeScalars.append(scalars[j]); j += 1
            }
            let terminated = j < scalars.count && scalars[j] == ";"
            var replacement: String?
            if body.hasPrefix("#") {
                let digits = body.dropFirst()
                var code: UInt32?
                if digits.hasPrefix("x") || digits.hasPrefix("X") { code = UInt32(digits.dropFirst(), radix: 16) }
                else { code = UInt32(digits, radix: 10) }
                if let code, let scalar = Unicode.Scalar(code) { replacement = String(Character(scalar)) }
            } else if terminated, let hit = named[body] {
                replacement = hit
            }
            if let replacement {
                out += replacement
                i = terminated ? j + 1 : j
            } else {
                out.unicodeScalars.append(ch)
                i += 1
            }
        }
        return out
    }

    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }
}
