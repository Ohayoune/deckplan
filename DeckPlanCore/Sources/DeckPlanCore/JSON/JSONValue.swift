//
//  JSONValue.swift
//  DeckPlanCore
//
//  The Core's one JSON value model and its own parser.
//
//  docs/CANONICAL_JSON.md (canonical JSON), docs/SPEC.md §7 (the data model).
//  The Python reference (`tools/core/canonical.py`)
//  works on JSON-shaped dicts and is the oracle; every plan and every
//  `inputsHash` this package produces has to match it byte for byte, so the
//  Core carries its own value model rather than leaning on Foundation.
//

import Foundation

// MARK: - The value model

/// One JSON value, with integers kept apart from floating-point numbers.
///
/// `JSONSerialization` is deliberately not used to read JSON here: it does not
/// tell `7` from `7.0` — a distinction the canonical encoder needs, since an
/// integer is written `7` and a float with an integral value is written `7`
/// too, while `inputsHash` is taken over the resulting text — and its handling
/// of integers that do not fit `Int64` is undocumented. D9's lesson seed,
/// `13095845880559124262`, is above the signed 64-bit maximum (docs/PLANNER.md
/// §10), so `.uint` exists for exactly that range.
///
/// Objects are a plain dictionary: the canonical encoder sorts keys by Unicode
/// scalar value, so the order they were written in never reaches the output.
/// (Insertion order *is* load-bearing in one place in the Python — the fixture
/// loader's `expand_marks` emits marks "in fixture order", `tools/core/fixtures.py`
/// — but nothing in M4 depends on it; the M6 worker who ports the fixture loader
/// adds an ordered form where that rule needs one.)
///
/// One limit of that dictionary, recorded rather than worked around: Swift's
/// `String` treats *canonically equivalent* spellings as one value, so a
/// precomposed "é" (U+00E9) and a decomposed one ("e" + U+0301) would be one key
/// here and two in Python. No key in this app is ever such a string — ids are
/// slugs of `[a-z0-9-]`, and every other key is an ASCII field name, a zone, a
/// block kind, a swimmer id or a date — and no fixture has a non-ASCII object key
/// at all (`CanonicalTests` pins the behaviour either way).
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    /// A number token with no `.`, `e` or `E` that fits `Int64`.
    case int(Int64)
    /// A number token with no `.`, `e` or `E` that is above `Int64.max` but fits `UInt64`.
    case uint(UInt64)
    /// A number token with a fraction or an exponent — or an integer token too
    /// large for `UInt64`.
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue {

    /// The object's fields, or nil when this is not an object.
    public var objectValue: [String: JSONValue]? {
        if case .object(let fields) = self { return fields }
        return nil
    }

    /// The array's elements, or nil when this is not an array.
    public var arrayValue: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    /// The string, or nil when this is not a string.
    public var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    /// The boolean, or nil when this is not a boolean. A number is never a boolean.
    public var boolValue: Bool? {
        if case .bool(let flag) = self { return flag }
        return nil
    }

    /// Whether this is `null`.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// The number as a `Double`, whatever token kind it arrived as; nil when
    /// this is not a number. `.bool` is never a number (the Python is explicit
    /// about this: `canonical.py`'s `_dump_value` tests `bool` before `int`).
    public var doubleValue: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .uint(let value): return Double(value)
        case .double(let value): return value
        default: return nil
        }
    }

    /// The number as an `Int`, when it is an integer that fits; nil otherwise.
    /// A `.double` counts when its value is integral (`7.0` -> 7), which is the
    /// same leniency `tools/core/curriculum.py`'s `is_int` has on the way in.
    public var intValue: Int? {
        switch self {
        case .int(let value): return Int(exactly: value)
        case .uint(let value): return Int(exactly: value)
        case .double(let value): return value.rounded() == value ? Int(exactly: value.rounded()) : nil
        default: return nil
        }
    }

    /// The number as a `UInt64` — D9's seed and every other `hash(parts)` value
    /// (docs/CANONICAL_JSON.md); nil when this is not a non-negative integer that fits.
    public var uint64Value: UInt64? {
        switch self {
        case .int(let value): return UInt64(exactly: value)
        case .uint(let value): return value
        case .double(let value): return value.rounded() == value ? UInt64(exactly: value.rounded()) : nil
        default: return nil
        }
    }

    /// This value's field `key`, when this is an object that has it.
    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}

// MARK: - Parsing

/// What went wrong while reading JSON text, with the byte offset it went wrong at.
public enum JSONParseError: Error, Equatable, Sendable, CustomStringConvertible {
    case unexpectedEnd(at: Int)
    case unexpectedByte(UInt8, at: Int)
    case invalidNumber(String, at: Int)
    case invalidString(String, at: Int)
    case invalidUTF8(at: Int)
    case trailingContent(at: Int)
    case tooDeep(at: Int)

    public var description: String {
        switch self {
        case .unexpectedEnd(let at):
            return "the JSON ends in the middle of a value (byte \(at))"
        case .unexpectedByte(let byte, let at):
            let shown = (byte >= 0x20 && byte < 0x7F)
                ? "'\(Character(UnicodeScalar(byte)))'"
                : String(format: "0x%02x", byte)
            return "unexpected \(shown) at byte \(at)"
        case .invalidNumber(let text, let at):
            return "\(text) is not a JSON number (byte \(at))"
        case .invalidString(let why, let at):
            return "\(why) (byte \(at))"
        case .invalidUTF8(let at):
            return "the JSON is not valid UTF-8 (byte \(at))"
        case .trailingContent(let at):
            return "there is more text after the JSON value (byte \(at))"
        case .tooDeep(let at):
            return "the JSON nests deeper than \(JSONValue.maximumNestingDepth) levels (byte \(at))"
        }
    }
}

extension JSONValue {

    /// How deep arrays and objects may nest before parsing gives up. A store file
    /// or a restored backup is untrusted input (docs/SPEC.md §8): a bound here
    /// turns a hostile file into a thrown error instead of a stack overflow.
    public static let maximumNestingDepth = 512

    /// Read one JSON value out of UTF-8 `data`, with nothing but whitespace after it.
    ///
    /// Number tokens follow the rule the M4 brief pins, so a round trip through
    /// `Canonical.dumps` is stable: a token with no `.`, `e` or `E` becomes `.int`
    /// when it fits `Int64`, `.uint` when it fits `UInt64` (D9's seed), otherwise
    /// `.double`; a token with a fraction or an exponent is always `.double`.
    /// Strings decode every JSON escape, `\uXXXX` surrogate pairs included.
    /// A repeated object key keeps the last value, as `json.loads` does.
    public static func parse(_ data: Data) throws -> JSONValue {
        var parser = JSONParser(bytes: Array(data))
        return try parser.parseDocument()
    }

    /// Read one JSON value out of `text`.
    public static func parse(_ text: String) throws -> JSONValue {
        var parser = JSONParser(bytes: Array(text.utf8))
        return try parser.parseDocument()
    }
}

/// A recursive-descent JSON reader over UTF-8 bytes (docs/CANONICAL_JSON.md).
private struct JSONParser {
    let bytes: [UInt8]
    var index = 0
    var depth = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func parseDocument() throws -> JSONValue {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        guard index == bytes.count else { throw JSONParseError.trailingContent(at: index) }
        return value
    }

    private mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D: index += 1
            default: return
            }
        }
    }

    private func peek() throws -> UInt8 {
        guard index < bytes.count else { throw JSONParseError.unexpectedEnd(at: index) }
        return bytes[index]
    }

    private mutating func parseValue() throws -> JSONValue {
        switch try peek() {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        case let byte where byte == UInt8(ascii: "-") || (byte >= 0x30 && byte <= 0x39):
            return try parseNumber()
        case let byte:
            throw JSONParseError.unexpectedByte(byte, at: index)
        }
    }

    private mutating func expect(_ literal: String) throws {
        for expected in literal.utf8 {
            guard index < bytes.count else { throw JSONParseError.unexpectedEnd(at: index) }
            guard bytes[index] == expected else {
                throw JSONParseError.unexpectedByte(bytes[index], at: index)
            }
            index += 1
        }
    }

    private mutating func enter() throws {
        depth += 1
        guard depth <= JSONValue.maximumNestingDepth else {
            throw JSONParseError.tooDeep(at: index)
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        try enter()
        defer { depth -= 1 }
        index += 1                                  // '['
        var items: [JSONValue] = []
        skipWhitespace()
        if try peek() == UInt8(ascii: "]") {
            index += 1
            return .array(items)
        }
        while true {
            skipWhitespace()
            items.append(try parseValue())
            skipWhitespace()
            switch try peek() {
            case UInt8(ascii: ","): index += 1
            case UInt8(ascii: "]"): index += 1; return .array(items)
            case let byte: throw JSONParseError.unexpectedByte(byte, at: index)
            }
        }
    }

    private mutating func parseObject() throws -> JSONValue {
        try enter()
        defer { depth -= 1 }
        index += 1                                  // '{'
        var fields: [String: JSONValue] = [:]
        skipWhitespace()
        if try peek() == UInt8(ascii: "}") {
            index += 1
            return .object(fields)
        }
        while true {
            skipWhitespace()
            guard try peek() == UInt8(ascii: "\"") else {
                throw JSONParseError.unexpectedByte(bytes[index], at: index)
            }
            let key = try parseString()
            skipWhitespace()
            guard try peek() == UInt8(ascii: ":") else {
                throw JSONParseError.unexpectedByte(bytes[index], at: index)
            }
            index += 1
            skipWhitespace()
            fields[key] = try parseValue()          // a repeated key keeps the last value
            skipWhitespace()
            switch try peek() {
            case UInt8(ascii: ","): index += 1
            case UInt8(ascii: "}"): index += 1; return .object(fields)
            case let byte: throw JSONParseError.unexpectedByte(byte, at: index)
            }
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        index += 1                                  // '"'
        var out: [UInt8] = []
        while true {
            guard index < bytes.count else { throw JSONParseError.unexpectedEnd(at: index) }
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "\""):
                index += 1
                guard let text = String(bytes: out, encoding: .utf8) else {
                    throw JSONParseError.invalidUTF8(at: start)
                }
                return text
            case UInt8(ascii: "\\"):
                try parseEscape(into: &out)
            case 0x00...0x1F:
                throw JSONParseError.invalidString(
                    "a raw control character is not allowed inside a JSON string", at: index)
            default:
                out.append(byte)
                index += 1
            }
        }
    }

    private mutating func parseEscape(into out: inout [UInt8]) throws {
        index += 1                                  // '\'
        guard index < bytes.count else { throw JSONParseError.unexpectedEnd(at: index) }
        let code = bytes[index]
        index += 1
        switch code {
        case UInt8(ascii: "\""): out.append(UInt8(ascii: "\""))
        case UInt8(ascii: "\\"): out.append(UInt8(ascii: "\\"))
        case UInt8(ascii: "/"): out.append(UInt8(ascii: "/"))
        case UInt8(ascii: "b"): out.append(0x08)
        case UInt8(ascii: "f"): out.append(0x0C)
        case UInt8(ascii: "n"): out.append(0x0A)
        case UInt8(ascii: "r"): out.append(0x0D)
        case UInt8(ascii: "t"): out.append(0x09)
        case UInt8(ascii: "u"):
            let first = try parseHexQuad()
            var scalarValue = UInt32(first)
            if first >= 0xD800 && first <= 0xDBFF {          // a high surrogate needs its low half
                guard index + 1 < bytes.count,
                      bytes[index] == UInt8(ascii: "\\"),
                      bytes[index + 1] == UInt8(ascii: "u") else {
                    throw JSONParseError.invalidString(
                        "a \\u escape for a high surrogate needs a low surrogate after it", at: index)
                }
                index += 2
                let second = try parseHexQuad()
                guard second >= 0xDC00 && second <= 0xDFFF else {
                    throw JSONParseError.invalidString(
                        "a high surrogate must be followed by a low surrogate", at: index)
                }
                scalarValue = 0x10000
                    + (UInt32(first - 0xD800) << 10)
                    + UInt32(second - 0xDC00)
            } else if first >= 0xDC00 && first <= 0xDFFF {
                throw JSONParseError.invalidString(
                    "a lone low surrogate is not a character", at: index)
            }
            guard let scalar = Unicode.Scalar(scalarValue) else {
                throw JSONParseError.invalidString(
                    "\\u escape is not a Unicode scalar", at: index)
            }
            out.append(contentsOf: Array(String(scalar).utf8))
        default:
            throw JSONParseError.invalidString("unknown string escape", at: index - 1)
        }
    }

    private mutating func parseHexQuad() throws -> UInt16 {
        guard index + 3 < bytes.count else { throw JSONParseError.unexpectedEnd(at: index) }
        var value: UInt16 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            let digit: UInt16
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt16(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt16(byte - UInt8(ascii: "a")) + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt16(byte - UInt8(ascii: "A")) + 10
            default:
                throw JSONParseError.invalidString("\\u escape needs four hex digits", at: index)
            }
            value = value << 4 | digit
            index += 1
        }
        return value
    }

    private mutating func parseNumber() throws -> JSONValue {
        let start = index
        var isDouble = false
        if index < bytes.count && bytes[index] == UInt8(ascii: "-") { index += 1 }
        // int part
        guard index < bytes.count else { throw JSONParseError.unexpectedEnd(at: index) }
        if bytes[index] == UInt8(ascii: "0") {
            index += 1
        } else if bytes[index] >= UInt8(ascii: "1") && bytes[index] <= UInt8(ascii: "9") {
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 { index += 1 }
        } else {
            throw JSONParseError.unexpectedByte(bytes[index], at: index)
        }
        // fraction
        if index < bytes.count && bytes[index] == UInt8(ascii: ".") {
            isDouble = true
            index += 1
            let digitsStart = index
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 { index += 1 }
            guard index > digitsStart else {
                throw JSONParseError.invalidNumber(text(from: start), at: start)
            }
        }
        // exponent
        if index < bytes.count && (bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E")) {
            isDouble = true
            index += 1
            if index < bytes.count && (bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-")) {
                index += 1
            }
            let digitsStart = index
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 { index += 1 }
            guard index > digitsStart else {
                throw JSONParseError.invalidNumber(text(from: start), at: start)
            }
        }
        let token = text(from: start)
        if !isDouble {
            if let value = Int64(token) { return .int(value) }
            if let value = UInt64(token) { return .uint(value) }
        }
        guard let value = Double(token) else {
            throw JSONParseError.invalidNumber(token, at: start)
        }
        return .double(value)
    }

    private func text(from start: Int) -> String {
        String(decoding: bytes[start..<index], as: UTF8.self)
    }
}

// MARK: - Codable

extension JSONValue: Codable {

    /// Reading a `JSONValue` through any `Decoder`. Used only so the models can be
    /// `Codable` (docs/SPEC.md §7); the canonical path into the Core is
    /// `JSONValue.parse`, which keeps integers and floats apart.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .uint(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "not a JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .uint(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Literals (for tests and for building values in code)

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension JSONValue: CustomStringConvertible {
    /// The canonical text (docs/CANONICAL_JSON.md), or a note when the value holds a
    /// number JSON cannot write. For diagnostics and test failure messages.
    public var description: String {
        (try? Canonical.dumps(self)) ?? "<JSON with a non-finite number>"
    }
}
