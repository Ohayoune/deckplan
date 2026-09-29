//
//  JSONValueTests.swift
//  DeckPlanCoreTests
//
//  The Core's own JSON reader — the number, string and structure rules the M4
//  brief pins so that `parse` and `Canonical.dumps` are a stable round trip
//  (docs/CANONICAL_JSON.md).
//

import XCTest
@testable import DeckPlanCore

final class JSONValueTests: XCTestCase {

    // MARK: - numbers

    func test_an_integer_token_is_an_integer_not_a_float() throws {
        XCTAssertEqual(JSONValue.int(7), try JSONValue.parse("7"))
        XCTAssertEqual(JSONValue.double(7.0), try JSONValue.parse("7.0"))
        XCTAssertEqual(JSONValue.double(7.0), try JSONValue.parse("7e0"))
        XCTAssertEqual(JSONValue.double(7.0), try JSONValue.parse("7E0"))
        XCTAssertEqual(JSONValue.int(-7), try JSONValue.parse("-7"))
        XCTAssertEqual(JSONValue.int(0), try JSONValue.parse("0"))
        // 7 and 7.0 are different values here, and both write as "7"
        XCTAssertNotEqual(try JSONValue.parse("7"), try JSONValue.parse("7.0"))
        XCTAssertEqual("7", try Canonical.dumps(try JSONValue.parse("7.0")))
    }

    func test_big_integers_stay_exact() throws {
        // D9's lesson seed, above the signed 64-bit maximum (docs/CANONICAL_JSON.md)
        XCTAssertEqual(JSONValue.uint(13095845880559124262),
                       try JSONValue.parse("13095845880559124262"))
        XCTAssertEqual(JSONValue.int(Int64.max), try JSONValue.parse("9223372036854775807"))
        XCTAssertEqual(JSONValue.uint(UInt64(Int64.max) + 1),
                       try JSONValue.parse("9223372036854775808"))
        XCTAssertEqual(JSONValue.int(Int64.min), try JSONValue.parse("-9223372036854775808"))
        XCTAssertEqual(JSONValue.uint(UInt64.max), try JSONValue.parse("18446744073709551615"))
        // past UInt64 it is a double, and says so rather than overflowing
        XCTAssertEqual(JSONValue.double(18446744073709551616),
                       try JSONValue.parse("18446744073709551616"))
        XCTAssertEqual(JSONValue.double(-18446744073709551616),
                       try JSONValue.parse("-18446744073709551616"))
    }

    func test_a_seed_survives_the_round_trip_as_an_integer() throws {
        let text = "{\"seed\":13095845880559124262}"
        XCTAssertEqual(text, try Canonical.dumps(try JSONValue.parse(text)))
    }

    func test_fractions_and_exponents() throws {
        XCTAssertEqual(JSONValue.double(5.75), try JSONValue.parse("5.75"))
        XCTAssertEqual(JSONValue.double(1e-7), try JSONValue.parse("1e-7"))
        XCTAssertEqual(JSONValue.double(1e-7), try JSONValue.parse("1E-07"))
        XCTAssertEqual(JSONValue.double(1.5e300), try JSONValue.parse("1.5e+300"))
        XCTAssertEqual(JSONValue.double(-0.0), try JSONValue.parse("-0.0"))
    }

    func test_malformed_numbers_are_rejected() {
        for text in ["01", "1.", ".5", "+1", "1e", "1e+", "--1", "1.2.3", "0x10", "Infinity"] {
            XCTAssertThrowsError(try JSONValue.parse(text), text)
        }
    }

    // MARK: - strings

    func test_escapes() throws {
        XCTAssertEqual(JSONValue.string("\"\\/\u{08}\u{0C}\n\r\t"),
                       try JSONValue.parse("\"\\\"\\\\\\/\\b\\f\\n\\r\\t\""))
        XCTAssertEqual(JSONValue.string("\u{00}\u{1F}"), try JSONValue.parse("\"\\u0000\\u001f\""))
        XCTAssertEqual(JSONValue.string("é"), try JSONValue.parse("\"\\u00e9\""))
        XCTAssertEqual(JSONValue.string("é"), try JSONValue.parse("\"\\u00E9\""))
        XCTAssertEqual(JSONValue.string("é"), try JSONValue.parse("\"é\""))   // raw UTF-8
    }

    func test_surrogate_pairs() throws {
        XCTAssertEqual(JSONValue.string("🏊"), try JSONValue.parse("\"\\ud83c\\udfca\""))
        XCTAssertEqual(JSONValue.string("𝄞"), try JSONValue.parse("\"\\uD834\\uDD1E\""))
        // and the whole trip: read a pair, write the character itself
        XCTAssertEqual("\"🏊\"", try Canonical.dumps(try JSONValue.parse("\"\\ud83c\\udfca\"")))
    }

    func test_broken_surrogates_and_escapes_are_rejected() {
        for text in ["\"\\ud83c\"",                 // a high surrogate with nothing after it
                     "\"\\ud83cx\"",                // a high surrogate followed by a character
                     "\"\\ud83c\\u0041\"",          // …followed by a non-surrogate escape
                     "\"\\udfca\"",                 // a lone low surrogate
                     "\"\\u00g0\"",                 // not hex
                     "\"\\x41\"",                   // not a JSON escape
                     "\"\u{01}\"",                  // a raw control character
                     "\"unterminated"] {
            XCTAssertThrowsError(try JSONValue.parse(text), text)
        }
    }

    // MARK: - structure

    func test_objects_arrays_and_literals() throws {
        XCTAssertEqual(JSONValue.object([:]), try JSONValue.parse("{}"))
        XCTAssertEqual(JSONValue.array([]), try JSONValue.parse("[]"))
        XCTAssertEqual(JSONValue.object(["a": .array([.int(1), .null, .bool(true)])]),
                       try JSONValue.parse("{\"a\": [1, null, true]}"))
        XCTAssertEqual(JSONValue.bool(false), try JSONValue.parse(" false "))
        XCTAssertEqual(JSONValue.null, try JSONValue.parse("\n\tnull\r\n"))
    }

    func test_a_repeated_key_keeps_the_last_value() throws {
        XCTAssertEqual(JSONValue.object(["a": .int(2)]), try JSONValue.parse("{\"a\":1,\"a\":2}"))
    }

    func test_malformed_documents_are_rejected() {
        for text in ["", "  ", "{", "}", "[1,", "[1,]", "{\"a\"}", "{\"a\":}", "{a:1}",
                     "{'a':1}", "[1] [2]", "nul", "tru", "{\"a\":1,}", "\"a\" trailing"] {
            XCTAssertThrowsError(try JSONValue.parse(text), text)
        }
    }

    func test_trailing_content_is_reported_as_such() {
        XCTAssertThrowsError(try JSONValue.parse("{} x")) { error in
            guard case JSONParseError.trailingContent = error else {
                return XCTFail("expected trailingContent, got \(error)")
            }
        }
    }

    func test_deep_nesting_is_bounded_rather_than_overflowing_the_stack() throws {
        let deep = String(repeating: "[", count: 200) + String(repeating: "]", count: 200)
        XCTAssertNoThrow(try JSONValue.parse(deep))

        let tooDeep = String(repeating: "[", count: 600) + String(repeating: "]", count: 600)
        XCTAssertThrowsError(try JSONValue.parse(tooDeep)) { error in
            guard case JSONParseError.tooDeep = error else {
                return XCTFail("expected tooDeep, got \(error)")
            }
        }
    }

    func test_invalid_utf8_bytes_are_reported() {
        var bytes: [UInt8] = Array("\"a".utf8)
        bytes.append(0xFF)                                  // never a UTF-8 byte
        bytes.append(contentsOf: Array("\"".utf8))
        XCTAssertThrowsError(try JSONValue.parse(Data(bytes)))
    }

    // MARK: - accessors and Codable

    func test_accessors() throws {
        let value = try JSONValue.parse("""
            {"s":"x","i":7,"u":13095845880559124262,"d":1.5,"b":true,"n":null,"a":[1],"o":{}}
            """)
        XCTAssertEqual("x", value["s"]?.stringValue)
        XCTAssertEqual(7, value["i"]?.intValue)
        XCTAssertEqual(13095845880559124262, value["u"]?.uint64Value)
        XCTAssertEqual(1.5, value["d"]?.doubleValue)
        XCTAssertEqual(true, value["b"]?.boolValue)
        XCTAssertEqual(true, value["n"]?.isNull)
        XCTAssertEqual(1, value["a"]?.arrayValue?.count)
        XCTAssertEqual(0, value["o"]?.objectValue?.count)
        XCTAssertNil(value["b"]?.doubleValue)               // a boolean is never a number
        XCTAssertNil(value["missing"])
    }

    func test_codable_round_trip() throws {
        let value = try Repo.json("examples/finder.stage1.expected.json")
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: encoded)
        assertSameJSONText(try Canonical.dumps(decoded), try Canonical.dumps(value),
                           "finder fixture through JSONEncoder/JSONDecoder")
    }

    func test_description_is_the_canonical_text() {
        let value: JSONValue = ["b": 1, "a": [7.0, 1.5, "é/x"]]
        XCTAssertEqual("{\"a\":[7,1.5,\"é/x\"],\"b\":1}", value.description)
    }
}
