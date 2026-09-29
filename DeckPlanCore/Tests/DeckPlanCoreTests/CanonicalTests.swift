//
//  CanonicalTests.swift
//  DeckPlanCoreTests
//
//  The hash and canonical JSON (docs/CANONICAL_JSON.md).
//
//  The Swift counterpart of `tests/test_canonical.py`, case for case: the same
//  literal values, the same escaping, sorting and number rules, plus the cases
//  where Swift's own number formatting had to be checked against Python's `repr`
//  before it could be trusted.
//

import XCTest
@testable import DeckPlanCore

final class CanonicalTests: XCTestCase {

    // MARK: - The literal values

    func test_D11_hash_and_canonical_json() throws {
        // hashParts: the three literal values (docs/CANONICAL_JSON.md).
        XCTAssertEqual(13436514500253700074, Canonical.hashParts("abc"))   // 0xba7816bf8f01cfea
        XCTAssertEqual(7132184755009805105,
                       Canonical.hashParts(12345, 0, "1.front-glide", "puffin-rocket-ride"))
        XCTAssertEqual(13095845880559124262, Canonical.hashParts("L5"))    // D9: seed = hash(lesson.id)

        // an unsigned 64-bit integer, including above the signed 64-bit max.
        XCTAssertGreaterThan(Canonical.hashParts("L5"), UInt64(Int64.max))
        XCTAssertLessThan(Canonical.hashParts("L5"), UInt64.max)

        // canonical JSON: the literal dumps() example.
        XCTAssertEqual("{\"a\":[7,1.5,\"é/x\"],\"b\":1}",
                       try Canonical.dumps(["b": 1, "a": [7.0, 1.5, "é/x"]]))
    }

    func test_D11_a_block_without_a_skill_hashes_its_block_kind() throws {
        // "A block without a skill uses its block kind ("welcome") as the skill part."
        let seed = Canonical.hashParts("L5")
        XCTAssertEqual(Canonical.hashParts(.uint(seed), 0, "welcome", "snowflake-welcome"),
                       Canonical.hashParts([.uint(seed), .int(0), .string("welcome"),
                                            .string("snowflake-welcome")]))
    }

    func test_hash_parts_matches_the_first_8_bytes_of_its_own_sha256() {
        // The two functions' shared rule (docs/CANONICAL_JSON.md).
        let hex = Canonical.sha256Hex("abc")
        XCTAssertEqual(Canonical.hashParts("abc"), UInt64(hex.prefix(16), radix: 16))
    }

    func test_sha256_hex_of_empty_string() {
        XCTAssertEqual("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                       Canonical.sha256Hex(""))
    }

    func test_hash_parts_joins_with_a_pipe_in_utf8() {
        XCTAssertEqual(Canonical.hashParts("12345|0|1.front-glide|puffin-rocket-ride"),
                       Canonical.hashParts(12345, 0, "1.front-glide", "puffin-rocket-ride"))
        // a part's own text is used as it stands, non-ASCII included
        XCTAssertEqual(UInt64(Canonical.sha256Hex("é|x").prefix(16), radix: 16),
                       Canonical.hashParts("é", "x"))
    }

    // MARK: - numbers

    func test_integral_floats_become_integers() throws {
        XCTAssertEqual("7", try Canonical.dumps(.double(7.0)))
        XCTAssertEqual("-7", try Canonical.dumps(.double(-7.0)))
        XCTAssertEqual("0", try Canonical.dumps(.double(0.0)))
        XCTAssertEqual("0", try Canonical.dumps(.double(-0.0)))
        XCTAssertEqual("123456789", try Canonical.dumps(.double(123456789.0)))
        XCTAssertEqual("1", try Canonical.dumps(.int(1)))       // a plain int is never a float
    }

    func test_non_integral_floats_keep_shortest_round_trip_form() throws {
        for value in [5.75, 0.1, 1e-7, 0.25, 1.0000000000000002, -5.75, 3.14159] {
            let rendered = try Canonical.dumps(.double(value))
            XCTAssertEqual(value, Double(rendered), "\(value) -> \(rendered)")
        }
        XCTAssertEqual("5.75", try Canonical.dumps(.double(5.75)))
        XCTAssertEqual("0.1", try Canonical.dumps(.double(0.1)))
        XCTAssertEqual("1e-07", try Canonical.dumps(.double(1e-7)))
    }

    /// Every case where Swift's `Double.description` had to be checked against
    /// Python's `repr` before `numberText` could lean on it, with the exact string
    /// `tools/core/canonical.py`'s `dumps` produces for the same value.
    ///
    /// The two agree on every value with a fractional part (measured over 615,000
    /// doubles). They disagree only on integral values in [2⁵³, 10¹⁶) — Swift writes
    /// `9729859796341778.0` as `9.729859796341778e+15` — and those go down the
    /// integer path here instead, which is the rule that makes the two equal. Above
    /// `Int64.max` that path is an exact big-integer expansion, as Python's
    /// `str(int(value))` is: `1.5e300` is a 301-digit integer, never `1.5e+300`.
    func test_number_text_matches_python_repr_case_for_case() throws {
        let cases: [(Double, String)] = [
            (5.75, "5.75"),
            (0.1, "0.1"),
            (1e-7, "1e-07"),
            (0.25, "0.25"),
            (1.0000000000000002, "1.0000000000000002"),
            (-5.75, "-5.75"),
            (3.14159, "3.14159"),
            (7.0, "7"),
            (-7.0, "-7"),
            (0.0, "0"),
            (-0.0, "0"),
            (123456789.0, "123456789"),
            (1e15, "1000000000000000"),
            (1e16, "10000000000000000"),
            (1e17, "100000000000000000"),
            (1e21, "1000000000000000000000"),
            (1e22, "10000000000000000000000"),
            (1e23, "99999999999999991611392"),
            (5e-324, "5e-324"),
            (2.2250738585072014e-308, "2.2250738585072014e-308"),
            (1e-5, "1e-05"),
            (0.0001, "0.0001"),
            (1234567890123456.8, "1234567890123456.8"),
            (0.3333333333333333, "0.3333333333333333"),
            (2.5, "2.5"),
            // the band where Swift's description and Python's repr disagree:
            // integral, 16 digits, above 2^53
            (9007199254740992.0, "9007199254740992"),
            (9729859796341778.0, "9729859796341778"),
            // exactly at and above the signed/unsigned 64-bit limits
            (9223372036854775808.0, "9223372036854775808"),
            (18446744073709551616.0, "18446744073709551616"),
        ]
        for (value, expected) in cases {
            XCTAssertEqual(expected, try Canonical.numberText(value), "\(value)")
            XCTAssertEqual(expected, try Canonical.dumps(.double(value)), "\(value)")
        }
    }

    func test_a_huge_integral_double_is_written_out_in_full() throws {
        // Python: str(int(1.5e300)) — 301 digits, the exact value of the double.
        let expected15e300 = "1500000000000000078757140382806630373056702871662238732373"
            + "781173267703686983362293679557062620671796065556665749325817265413784853040645863467"
            + "188277180060474272580801389863705606745350692182135089053429852456199917621678558451"
            + "461320111979114170213741868888183230085264257173504208294580298189100810240"
        XCTAssertEqual(expected15e300, try Canonical.numberText(1.5e300))
        XCTAssertEqual(301, expected15e300.count)

        let expectedMax = "179769313486231570814527423731704356798070567525844996598917"
            + "476803157260780028538760589558632766878171540458953514382464234321326889464182768467"
            + "546703537516986049910576551282076245490090389328944075868508455133942304583236903222"
            + "948165808559332123348274797826204144723168738177180919299881250404026184124858368"
        XCTAssertEqual(expectedMax, try Canonical.numberText(.greatestFiniteMagnitude))
        XCTAssertEqual("-" + expectedMax, try Canonical.numberText(-.greatestFiniteMagnitude))
    }

    func test_an_integral_double_always_reads_back_to_the_same_double() throws {
        for value in [1e15, 1e16, 1e23, 1.5e300, 9729859796341778.0,
                      9223372036854775808.0, Double.greatestFiniteMagnitude] {
            let text = try Canonical.numberText(value)
            XCTAssertEqual(value, Double(text), text)
        }
    }

    func test_integers_are_written_as_integers_at_the_64_bit_edges() throws {
        XCTAssertEqual("9223372036854775807", try Canonical.dumps(.int(Int64.max)))
        XCTAssertEqual("-9223372036854775808", try Canonical.dumps(.int(Int64.min)))
        XCTAssertEqual("18446744073709551615", try Canonical.dumps(.uint(UInt64.max)))
        XCTAssertEqual("13095845880559124262", try Canonical.dumps(.uint(13095845880559124262)))
    }

    func test_bool_is_never_written_as_a_number() throws {
        XCTAssertEqual("true", try Canonical.dumps(.bool(true)))
        XCTAssertEqual("false", try Canonical.dumps(.bool(false)))
        XCTAssertEqual("[true,1,false,0]", try Canonical.dumps([true, 1, false, 0]))
    }

    func test_null() throws {
        XCTAssertEqual("null", try Canonical.dumps(.null))
        XCTAssertEqual("{\"a\":null}", try Canonical.dumps(["a": .null]))
    }

    func test_nan_and_infinity_throw() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try Canonical.dumps(.double(value))) { error in
                guard case Canonical.Failure.nonFiniteNumber = error else {
                    return XCTFail("expected nonFiniteNumber, got \(error)")
                }
            }
        }
        // nested, not just at the top level
        XCTAssertThrowsError(try Canonical.dumps(["x": [1, .double(.nan)]]))
    }

    // MARK: - strings

    func test_control_characters_escape_as_the_rule_says() throws {
        XCTAssertEqual("\"\\b\\f\\n\\r\\t\"", try Canonical.dumps(.string("\u{08}\u{0C}\n\r\t")))
        XCTAssertEqual("\"\\u0000\\u0001\\u001f\"",
                       try Canonical.dumps(.string("\u{00}\u{01}\u{1F}")))
        XCTAssertEqual("\"\\\"\\\\\"", try Canonical.dumps(.string("\"\\")))
    }

    func test_slash_and_non_ascii_stay_unescaped() throws {
        XCTAssertEqual("\"a/b\"", try Canonical.dumps(.string("a/b")))
        XCTAssertEqual("\"é\"", try Canonical.dumps(.string("é")))
        XCTAssertEqual("\"日本語\"", try Canonical.dumps(.string("日本語")))
        // the characters the curriculum actually carries (en dash, em dash, arrow …)
        XCTAssertEqual("\"1–2 mins. — steps 2, 3 → 2 groups ≥ 5\"",
                       try Canonical.dumps(.string("1–2 mins. — steps 2, 3 → 2 groups ≥ 5")))
        // outside the BMP: written through as its own UTF-8, never as a surrogate pair
        XCTAssertEqual("\"🏊\"", try Canonical.dumps(.string("🏊")))
    }

    // MARK: - objects and arrays

    func test_keys_sorted_by_code_point() throws {
        // "Z" (U+005A) < "a" (U+0061) < "z" (U+007A) < "é" (U+00E9)
        XCTAssertEqual("{\"Z\":2,\"a\":3,\"z\":1,\"é\":4}",
                       try Canonical.dumps(["z": 1, "Z": 2, "a": 3, "é": 4]))
    }

    /// Swift's `<` on `String` is not code-point order: it compares normalized
    /// text, so "a" + a combining acute sorts *after* "b" even though its first
    /// code point is smaller. Python compares code point by code point, so the
    /// encoder sorts on `unicodeScalars` instead. This is the case that tells the
    /// two apart — with Swift's own order, the key would come out last.
    func test_sorting_is_by_scalar_not_by_swifts_string_order() throws {
        let combining = "a\u{0301}"                               // a + U+0301, not "á"
        XCTAssertFalse(combining < "b")                           // Swift's own order
        XCTAssertTrue(Canonical.scalarsPrecede(combining, "b"))   // code-point order
        XCTAssertEqual("{\"a\u{0301}\":1,\"b\":2}",
                       try Canonical.dumps(.object([combining: 1, "b": 2])))

        // a key that is a prefix of another sorts first
        XCTAssertEqual("{\"a\":1,\"ab\":2}", try Canonical.dumps(["ab": 2, "a": 1]))
        // and the plain cases still hold
        XCTAssertEqual("{\"Z\":1,\"a\":2,\"z\":3,\"é\":4}",
                       try Canonical.dumps(["é": 4, "z": 3, "a": 2, "Z": 1]))
    }

    /// The one place where a Swift dictionary cannot hold what Python's `dict`
    /// holds: `String` keys that are *canonically equivalent* — a precomposed "é"
    /// (U+00E9) and a decomposed one ("e" + U+0301) — are one key to Swift and two
    /// to Python. Nothing in this app writes such a key (every id is a slug of
    /// `[a-z0-9-]`, every other key is an ASCII field name, a zone, a block kind or
    /// a date; no fixture has a non-ASCII object key at all), so this is recorded
    /// rather than worked around — but it is recorded, so it is not a surprise.
    func test_canonically_equivalent_keys_collapse_which_python_would_keep_apart() throws {
        var fields: [String: JSONValue] = [:]
        fields["\u{00E9}"] = 1
        fields["e\u{0301}"] = 2
        XCTAssertEqual(1, fields.count, "Swift folds the two spellings into one key")
        XCTAssertEqual("{\"é\":2}", try Canonical.dumps(.object(fields)))
    }

    func test_nested_structures() throws {
        let value: JSONValue = ["x": ["y": [1, 2, ["z": .null, "w": [true, false]]]], "a": []]
        XCTAssertEqual("{\"a\":[],\"x\":{\"y\":[1,2,{\"w\":[true,false],\"z\":null}]}}",
                       try Canonical.dumps(value))
    }

    func test_lists_keep_their_given_order() throws {
        XCTAssertEqual("[3,1,2]", try Canonical.dumps([3, 1, 2]))
    }

    func test_no_insignificant_whitespace() throws {
        let rendered = try Canonical.dumps(["a": 1, "b": [1, 2], "c": "x y"])
        XCTAssertEqual("{\"a\":1,\"b\":[1,2],\"c\":\"x y\"}", rendered)
        XCTAssertFalse(rendered.contains("\n"))
        XCTAssertFalse(rendered.contains("\t"))
    }

    func test_dumps_data_is_the_utf8_of_dumps() throws {
        let value: JSONValue = ["é": "a/b", "n": 1.5]
        XCTAssertEqual(Data(try Canonical.dumps(value).utf8), try Canonical.dumpsData(value))
    }
}
