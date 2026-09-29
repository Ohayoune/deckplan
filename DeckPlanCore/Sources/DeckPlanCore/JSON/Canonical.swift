//
//  Canonical.swift
//  DeckPlanCore
//
//  Canonical JSON and the seeded hash — docs/CANONICAL_JSON.md.
//  The byte-for-byte counterpart of `tools/core/canonical.py`, which is the oracle
//  (the "Python first" rule).
//

import Foundation
import CryptoKit

/// The Core's canonical JSON encoder and its one hash.
///
/// `hashParts` is the only hash the Core ever uses on plan-relevant data — never a
/// language's built-in hashing, which Swift, like Python, seeds per process
/// (docs/CANONICAL_JSON.md; the "Determinism" rule). `dumps` is the Core's own
/// encoder: the plan JSON and every `inputsHash` are built from it, so its escaping
/// and number rules are pinned here rather than inherited from `JSONEncoder`.
public enum Canonical {

    /// A value canonical JSON has no way to write.
    public enum Failure: Error, Equatable, Sendable, CustomStringConvertible {
        /// NaN and the infinities are not JSON numbers (`canonical.py` raises
        /// `ValueError` for them).
        case nonFiniteNumber(Double)

        public var description: String {
            switch self {
            case .nonFiniteNumber(let value):
                return "canonical JSON cannot encode the non-finite number \(value)"
            }
        }
    }

    // MARK: - dumps

    /// Canonical JSON text for `value` (docs/CANONICAL_JSON.md).
    ///
    /// UTF-8; object keys sorted by Unicode scalar value; no insignificant
    /// whitespace; a number with an integral value written as an integer (`7`, not
    /// `7.0`), any other number in its shortest round-trip form (`5.75`); strings
    /// escaping only `"`, `\` and U+0000–U+001F, so `/` and non-ASCII characters
    /// stay unescaped; arrays in their given order.
    ///
    /// `dumps(["b": 1, "a": [7.0, 1.5, "é/x"]])` is `{"a":[7,1.5,"é/x"],"b":1}`.
    ///
    /// Throws `Failure.nonFiniteNumber` for NaN and the infinities, as the Python
    /// raises: a plan that cannot be written must never be reported as written
    /// (the "Report outcomes faithfully" rule). The M4 brief drafted this as a
    /// non-throwing call; it throws instead, because there is no way to keep both
    /// that signature and the documented NaN behaviour.
    public static func dumps(_ value: JSONValue) throws -> String {
        var out: [UInt8] = []
        out.reserveCapacity(1024)
        try write(value, into: &out)
        return String(decoding: out, as: UTF8.self)
    }

    /// `dumps` as UTF-8 bytes — what is hashed and what is written to a file.
    public static func dumpsData(_ value: JSONValue) throws -> Data {
        var out: [UInt8] = []
        out.reserveCapacity(1024)
        try write(value, into: &out)
        return Data(out)
    }

    private static func write(_ value: JSONValue, into out: inout [UInt8]) throws {
        switch value {
        case .null:
            out.append(contentsOf: Array("null".utf8))
        case .bool(let flag):
            out.append(contentsOf: Array((flag ? "true" : "false").utf8))
        case .int(let number):
            out.append(contentsOf: Array(String(number).utf8))
        case .uint(let number):
            out.append(contentsOf: Array(String(number).utf8))
        case .double(let number):
            out.append(contentsOf: Array(try numberText(number).utf8))
        case .string(let text):
            writeString(text, into: &out)
        case .array(let items):
            out.append(UInt8(ascii: "["))
            for (offset, item) in items.enumerated() {
                if offset > 0 { out.append(UInt8(ascii: ",")) }
                try write(item, into: &out)
            }
            out.append(UInt8(ascii: "]"))
        case .object(let fields):
            out.append(UInt8(ascii: "{"))
            for (offset, key) in sortedKeys(fields).enumerated() {
                if offset > 0 { out.append(UInt8(ascii: ",")) }
                writeString(key, into: &out)
                out.append(UInt8(ascii: ":"))
                try write(fields[key]!, into: &out)
            }
            out.append(UInt8(ascii: "}"))
        }
    }

    /// An object's keys in Unicode scalar order (docs/CANONICAL_JSON.md: "object keys
    /// sorted by Unicode code point").
    ///
    /// Swift's `<` on `String` compares by Unicode *canonical equivalence*, which
    /// orders "é" written as one scalar and as "e" + a combining accent together and
    /// does not follow code-point order; Python's `str` comparison is code point by
    /// code point. Comparing `unicodeScalars` is the rule that matches.
    static func sortedKeys(_ fields: [String: JSONValue]) -> [String] {
        fields.keys.sorted(by: scalarsPrecede)
    }

    /// `a` before `b` by Unicode scalar value, lexicographically.
    static func scalarsPrecede(_ a: String, _ b: String) -> Bool {
        var left = a.unicodeScalars.makeIterator()
        var right = b.unicodeScalars.makeIterator()
        while true {
            switch (left.next(), right.next()) {
            case (nil, nil): return false                        // equal
            case (nil, _): return true                           // a is a prefix of b
            case (_, nil): return false
            case (let x?, let y?):
                if x.value != y.value { return x.value < y.value }
            }
        }
    }

    /// A JSON string literal escaping only `"`, `\` and U+0000–U+001F (short forms
    /// for `\b \f \n \r \t`, else `\u00xx` in lower-case hex); `/` and non-ASCII
    /// characters are written through unescaped (docs/CANONICAL_JSON.md).
    ///
    /// Working in UTF-8 bytes is safe here because every byte of a multi-byte UTF-8
    /// sequence is ≥ 0x80: no continuation byte can be mistaken for a character that
    /// needs escaping.
    private static func writeString(_ text: String, into out: inout [UInt8]) {
        out.append(UInt8(ascii: "\""))
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "\""):
                out.append(contentsOf: Array("\\\"".utf8))
            case UInt8(ascii: "\\"):
                out.append(contentsOf: Array("\\\\".utf8))
            case 0x08: out.append(contentsOf: Array("\\b".utf8))
            case 0x0C: out.append(contentsOf: Array("\\f".utf8))
            case 0x0A: out.append(contentsOf: Array("\\n".utf8))
            case 0x0D: out.append(contentsOf: Array("\\r".utf8))
            case 0x09: out.append(contentsOf: Array("\\t".utf8))
            case 0x00...0x1F:
                out.append(contentsOf: Array("\\u00".utf8))
                out.append(hexDigit(byte >> 4))
                out.append(hexDigit(byte & 0x0F))
            default:
                out.append(byte)
            }
        }
        out.append(UInt8(ascii: "\""))
    }

    private static func hexDigit(_ nibble: UInt8) -> UInt8 {
        nibble < 10 ? UInt8(ascii: "0") + nibble : UInt8(ascii: "a") + (nibble - 10)
    }

    // MARK: - numbers

    /// Canonical text for a floating-point number (docs/CANONICAL_JSON.md;
    /// `canonical.py`'s `_dump_number`).
    ///
    /// A value with no fractional part is written as an integer — `7.0` -> `7`,
    /// `-0.0` -> `0` — exactly as Python's `str(int(value))` does, which means the
    /// *exact* integer the double stands for however large it is: `1.5e300` is a
    /// 301-digit integer, not `1.5e+300`. Anything else is written with Swift's
    /// `description`, the shortest text that reads back to the same `Double`.
    ///
    /// Swift's `description` and Python's `repr` were compared over 615,000 doubles
    /// (uniform random bit patterns plus a dense sweep of every decimal-point
    /// position from 10⁻⁸ to 10²⁰): they agree on every value with a fractional
    /// part. They disagree only on integral values in [2⁵³, 10¹⁶) — Swift writes
    /// `9729859796341778.0` as `9.729859796341778e+15`, Python as
    /// `9729859796341778.0` — and those never reach `description` here, because an
    /// integral value takes the integer path above. That is what makes this
    /// function equal to `_dump_number` for every finite double.
    public static func numberText(_ value: Double) throws -> String {
        guard value.isFinite else { throw Failure.nonFiniteNumber(value) }
        if value.rounded() == value { return integerText(value) }
        return value.description
    }

    /// The exact integer a finite, integral `Double` stands for, in decimal —
    /// Python's `str(int(value))`, which is unbounded.
    static func integerText(_ value: Double) -> String {
        if value == 0 { return "0" }                        // -0.0 included: int(-0.0) == 0
        if let small = Int64(exactly: value) { return String(small) }

        // |value| > Int64.max, so the value is far above 2^53: it is a normal
        // double whose significand times a non-negative power of two is exact.
        let negative = value < 0
        let magnitude = abs(value)
        let significand = UInt64(magnitude.significandBitPattern) | (UInt64(1) << 52)
        let doublings = magnitude.exponent - 52             // >= 11 in this range
        var digits = Array(String(significand).utf8).map { $0 - UInt8(ascii: "0") }
        if doublings > 0 {
            for _ in 0..<doublings {
                var carry: UInt8 = 0
                for position in stride(from: digits.count - 1, through: 0, by: -1) {
                    let doubled = digits[position] * 2 + carry
                    digits[position] = doubled % 10
                    carry = doubled / 10
                }
                if carry > 0 { digits.insert(carry, at: 0) }
            }
        }
        var out: [UInt8] = negative ? [UInt8(ascii: "-")] : []
        out.append(contentsOf: digits.map { $0 + UInt8(ascii: "0") })
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: - hash

    /// One part of a `hashParts` key: a string as it stands, or an integer as its
    /// decimal string (docs/CANONICAL_JSON.md). There is no boolean case, deliberately:
    /// no documented part is a boolean, and the Python rejects one rather than let
    /// `True` hash as "True" instead of "1".
    public enum HashPart: Sendable, Hashable, ExpressibleByStringLiteral,
                          ExpressibleByIntegerLiteral, CustomStringConvertible {
        case string(String)
        case int(Int64)
        /// For values above the signed 64-bit maximum — a seed fed back in as the
        /// first part of a tie-break (docs/PLANNER.md §7, §10).
        case uint(UInt64)

        public init(stringLiteral value: String) { self = .string(value) }
        public init(integerLiteral value: Int64) { self = .int(value) }

        /// The text this part contributes to the joined string.
        public var description: String {
            switch self {
            case .string(let text): return text
            case .int(let value): return String(value)
            case .uint(let value): return String(value)
            }
        }
    }

    /// The seeded, deterministic hash (docs/CANONICAL_JSON.md).
    ///
    /// The first 8 bytes of SHA-256, read as an unsigned big-endian integer, over
    /// `parts` joined with "|" in UTF-8.
    ///
    /// `hashParts("abc") == 13436514500253700074` (0xba7816bf8f01cfea);
    /// `hashParts(12345, 0, "1.front-glide", "puffin-rocket-ride") == 7132184755009805105`;
    /// `hashParts("L5") == 13095845880559124262`, D9's lesson seed, above the signed
    /// 64-bit maximum. A block without a skill uses its block kind ("welcome") as
    /// the skill part.
    public static func hashParts(_ parts: [HashPart]) -> UInt64 {
        let joined = parts.map(\.description).joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        var result: UInt64 = 0
        for byte in digest.prefix(8) {
            result = result << 8 | UInt64(byte)
        }
        return result
    }

    /// `hashParts` written the way the Python reads: `hashParts("L5")`.
    public static func hashParts(_ parts: HashPart...) -> UInt64 {
        hashParts(parts)
    }

    /// Lower-case hex SHA-256 of `text`, encoded UTF-8 (docs/CANONICAL_JSON.md).
    ///
    /// Used both directly (`localHash`) and over `dumps(...)` output to make
    /// `inputsHash` and the plan's content hashes.
    public static func sha256Hex(_ text: String) -> String {
        sha256Hex(Data(text.utf8))
    }

    /// Lower-case hex SHA-256 of `data`.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
