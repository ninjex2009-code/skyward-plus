import Foundation

/// A value from a JavaScript object literal. Skyward ships its grids as script
/// (`sff.sv('sf_gridObjects', $.extend(..., {...}))`), which is not strict JSON:
/// keys may be bare, strings may be single-quoted. This reads it without ever
/// executing anything the server sent.
indirect enum JSValue {
    case object([String: JSValue], keys: [String])
    case array([JSValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    subscript(key: String) -> JSValue? {
        if case .object(let dict, _) = self { return dict[key] }
        return nil
    }

    subscript(index: Int) -> JSValue? {
        if case .array(let items) = self, index >= 0, index < items.count { return items[index] }
        return nil
    }

    var array: [JSValue] {
        if case .array(let items) = self { return items }
        return []
    }

    var keys: [String] {
        if case .object(_, let keys) = self { return keys }
        return []
    }

    var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let d):
            return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
}

struct JSLiteralParser {
    private let b: [UInt8]
    private let n: Int
    private(set) var i: Int
    private var depth = 0

    init(bytes: [UInt8], start: Int = 0) {
        b = bytes
        n = bytes.count
        i = start
    }

    static func parse(_ text: String) -> JSValue? {
        var p = JSLiteralParser(bytes: Array(text.utf8))
        return p.parseValue()
    }

    private mutating func skipSpace() {
        while i < n {
            let c = b[i]
            if c == 0x20 || c == 0x0A || c == 0x09 || c == 0x0D { i += 1; continue }
            if c == 0x2F, i + 1 < n, b[i + 1] == 0x2F {                 // line comment
                while i < n, b[i] != 0x0A { i += 1 }
                continue
            }
            if c == 0x2F, i + 1 < n, b[i + 1] == 0x2A {                 // block comment
                i += 2
                while i + 1 < n, !(b[i] == 0x2A && b[i + 1] == 0x2F) { i += 1 }
                i = min(n, i + 2)
                continue
            }
            break
        }
    }

    mutating func parseValue() -> JSValue? {
        skipSpace()
        guard i < n, depth < 200 else { return nil }
        switch b[i] {
        case 0x7B: return parseObject()
        case 0x5B: return parseArray()
        case 0x22, 0x27: return parseString().map { .string($0) }
        default:
            if b[i] == 0x2D || b[i] == 0x2B || b[i] == 0x2E || (b[i] >= 0x30 && b[i] <= 0x39) {
                let start = i
                i += 1
                while i < n, (b[i] >= 0x30 && b[i] <= 0x39) || b[i] == 0x2E || b[i] == 0x65 || b[i] == 0x45 || b[i] == 0x2B || b[i] == 0x2D { i += 1 }
                let text = String(decoding: b[start..<i], as: UTF8.self)
                return .number(Double(text) ?? 0)
            }
            let start = i
            while i < n, isIdentByte(b[i]) { i += 1 }
            let word = String(decoding: b[start..<i], as: UTF8.self)
            switch word {
            case "true": return .bool(true)
            case "false": return .bool(false)
            case "null", "undefined": return .null
            default:
                // An expression we do not model (a function, a call). Skip it.
                skipExpression()
                return .null
            }
        }
    }

    private func isIdentByte(_ c: UInt8) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x5F || c == 0x24 || c >= 0x80
    }

    private mutating func skipExpression() {
        var nest = 0
        while i < n {
            let c = b[i]
            if c == 0x22 || c == 0x27 { _ = parseString(); continue }
            if c == 0x28 || c == 0x7B || c == 0x5B { nest += 1 }
            else if c == 0x29 || c == 0x7D || c == 0x5D {
                if nest == 0 { return }
                nest -= 1
            } else if c == 0x2C, nest == 0 { return }
            i += 1
        }
    }

    private mutating func parseObject() -> JSValue? {
        depth += 1
        defer { depth -= 1 }
        i += 1
        var dict: [String: JSValue] = [:]
        var keys: [String] = []
        while i < n {
            skipSpace()
            guard i < n else { break }
            if b[i] == 0x7D { i += 1; return .object(dict, keys: keys) }
            if b[i] == 0x2C { i += 1; continue }
            var key: String
            if b[i] == 0x22 || b[i] == 0x27 {
                guard let k = parseString() else { return nil }
                key = k
            } else {
                let start = i
                while i < n, b[i] != 0x3A, b[i] != 0x20, b[i] != 0x0A, b[i] != 0x09, b[i] != 0x0D, b[i] != 0x7D, b[i] != 0x2C { i += 1 }
                key = String(decoding: b[start..<i], as: UTF8.self)
            }
            skipSpace()
            guard i < n, b[i] == 0x3A else {
                // A key with no value; tolerate it.
                if dict[key] == nil { keys.append(key) }
                dict[key] = .null
                continue
            }
            i += 1
            guard let value = parseValue() else { return nil }
            if dict[key] == nil { keys.append(key) }
            dict[key] = value
        }
        return .object(dict, keys: keys)
    }

    private mutating func parseArray() -> JSValue? {
        depth += 1
        defer { depth -= 1 }
        i += 1
        var items: [JSValue] = []
        while i < n {
            skipSpace()
            guard i < n else { break }
            if b[i] == 0x5D { i += 1; return .array(items) }
            if b[i] == 0x2C { i += 1; continue }
            guard let value = parseValue() else { return nil }
            items.append(value)
        }
        return .array(items)
    }

    private mutating func parseString() -> String? {
        let quote = b[i]
        i += 1
        var out: [UInt8] = []
        var segmentStart = i
        func hexValue(_ c: UInt8) -> UInt32? {
            switch c {
            case 0x30...0x39: return UInt32(c - 0x30)
            case 0x41...0x46: return UInt32(c - 0x41 + 10)
            case 0x61...0x66: return UInt32(c - 0x61 + 10)
            default: return nil
            }
        }
        func appendScalar(_ code: UInt32, to out: inout [UInt8]) {
            guard let scalar = Unicode.Scalar(code) else { return }
            out.append(contentsOf: Array(String(Character(scalar)).utf8))
        }
        while i < n {
            let c = b[i]
            if c == quote {
                out.append(contentsOf: b[segmentStart..<i])
                i += 1
                return String(decoding: out, as: UTF8.self)
            }
            guard c == 0x5C else { i += 1; continue }                   // backslash
            out.append(contentsOf: b[segmentStart..<i])
            i += 1
            guard i < n else { break }
            let e = b[i]
            i += 1
            switch e {
            case 0x6E: out.append(0x0A)      // n
            case 0x72: out.append(0x0D)      // r
            case 0x74: out.append(0x09)      // t
            case 0x62: out.append(0x08)      // b
            case 0x66: out.append(0x0C)      // f
            case 0x76: out.append(0x0B)      // v
            case 0x30: out.append(0x00)      // 0
            case 0x0A: break                 // line continuation
            case 0x0D: if i < n, b[i] == 0x0A { i += 1 }
            case 0x78:                       // \xHH
                if i + 1 < n, let h = hexValue(b[i]), let l = hexValue(b[i + 1]) {
                    appendScalar(h * 16 + l, to: &out)
                    i += 2
                }
            case 0x75:                       // \uHHHH or \u{...}
                if i < n, b[i] == 0x7B {
                    var j = i + 1
                    var code: UInt32 = 0
                    while j < n, let h = hexValue(b[j]) { code = code * 16 + h; j += 1 }
                    if j < n, b[j] == 0x7D { j += 1 }
                    appendScalar(code, to: &out)
                    i = j
                } else if i + 3 < n, let a = hexValue(b[i]), let b2 = hexValue(b[i + 1]), let c2 = hexValue(b[i + 2]), let d = hexValue(b[i + 3]) {
                    var code = a << 12 | b2 << 8 | c2 << 4 | d
                    i += 4
                    // Surrogate pair.
                    if code >= 0xD800, code <= 0xDBFF, i + 5 < n, b[i] == 0x5C, b[i + 1] == 0x75,
                       let a2 = hexValue(b[i + 2]), let b3 = hexValue(b[i + 3]), let c3 = hexValue(b[i + 4]), let d2 = hexValue(b[i + 5]) {
                        let low = a2 << 12 | b3 << 8 | c3 << 4 | d2
                        if low >= 0xDC00, low <= 0xDFFF {
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                            i += 6
                        }
                    }
                    appendScalar(code, to: &out)
                }
            default:
                out.append(e)                // \' \" \\ \/ and anything else: the character itself
            }
            segmentStart = i
        }
        return nil
    }
}
