//
//  FixtureRoundTripTests.swift
//  DeckPlanCoreTests
//
//  The Swift Core reads the repository's own fixtures and writes them back the
//  way the Python does (the "Python first" rule; docs/CANONICAL_JSON.md).
//
//  The v2 fixtures in `examples/` were written by `tools/dev/build_fixtures.py`
//  through `canonical.dumps` plus a trailing newline, so they *are* canonical
//  JSON: reproducing their bytes from a parse is what proves the number, escaping
//  and key-ordering rules all at once. Producing them from the algorithms is
//  DayPlanTests (D9) and FinderTests.
//

import XCTest
@testable import DeckPlanCore

final class FixtureRoundTripTests: XCTestCase {

    /// The committed canonical files (docs/TEST_CASES.md "Fixtures").
    static let canonicalFixtures = [
        "examples/day-plan.stage1.day5.expected.json",
        "examples/shuffle.stage1.day5.expected.json",
        "examples/finder.stage1.expected.json",
        "examples/class.stage1.json",
        "examples/pool.shallow.json",
        "examples/manifest.json",
    ]

    // MARK: - byte for byte

    func test_the_canonical_fixtures_are_reproduced_byte_for_byte() throws {
        for path in Self.canonicalFixtures {
            let text = try Repo.text(path)
            let parsed = try JSONValue.parse(try Repo.data(path))
            assertSameJSONText(try Canonical.dumps(parsed) + "\n", text, path)
        }
    }

    func test_the_canonical_fixtures_are_read_as_utf8_with_their_own_characters() throws {
        // The plan's notes carry a curly apostrophe and the class name a middle
        // dot; neither is escaped, and "/" is not escaped either.
        let plan = try Repo.text(Self.canonicalFixtures[0])
        XCTAssertTrue(plan.contains("’"), "the plan should carry a raw curly apostrophe")
        XCTAssertFalse(plan.contains("\\u"), "nothing in a canonical plan is \\u-escaped")
        let swimClass = try Repo.text("examples/class.stage1.json")
        XCTAssertTrue(swimClass.contains("Stage 1 · Mon Wed"), "the class name should carry a raw middle dot")
    }

    // MARK: - every fixture

    func test_every_fixture_parses_and_canonicalises_stably() throws {
        var checked = 0
        for path in Repo.jsonFiles(under: "examples") + Repo.jsonFiles(under: "tests/fixtures") {
            let data = try Repo.data(path)
            let parsed: JSONValue
            do {
                parsed = try JSONValue.parse(data)
            } catch {
                XCTFail("\(path) did not parse: \(error)")
                continue
            }
            let text = try Canonical.dumps(parsed)

            // Canonicalising is idempotent: reading back what we wrote and writing
            // it again gives the same bytes.
            let reparsed = try JSONValue.parse(text)
            assertSameJSONText(try Canonical.dumps(reparsed), text, "\(path) (second pass)")

            // …and nothing was lost on the way, judged by an independent reader.
            let fromFile = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let fromOurs = try JSONSerialization.jsonObject(with: Data(text.utf8),
                                                           options: [.fragmentsAllowed])
            XCTAssertTrue((fromFile as AnyObject).isEqual(fromOurs),
                          "\(path): the canonical text does not hold the same content")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 20, "the fixtures were not found")
    }

    func test_the_real_curriculum_files_parse_when_they_are_present() throws {
        try Repo.requireCurriculumDirectory()
        var checked = 0
        for path in Repo.jsonFiles(under: "curriculum") {
            let parsed = try JSONValue.parse(try Repo.data(path))
            let text = try Canonical.dumps(parsed)
            assertSameJSONText(try Canonical.dumps(try JSONValue.parse(text)), text, path)
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 13, "curriculum/ should hold at least 13 JSON files")
    }

    // MARK: - what a canonical file looks like

    func test_a_canonical_file_is_one_line_with_sorted_keys() throws {
        for path in Self.canonicalFixtures {
            let text = try Repo.text(path)
            XCTAssertTrue(text.hasSuffix("\n"), "\(path) ends with one newline")
            XCTAssertFalse(text.dropLast().contains("\n"), "\(path) should be one line")
            XCTAssertTrue(text.hasPrefix("{"), "\(path) should be one object")
        }
        let plan = try JSONValue.parse(try Repo.data(Self.canonicalFixtures[0]))
        XCTAssertEqual(["blocks", "classId", "date", "draft", "guideLesson", "n", "saved"],
                       Canonical.sortedKeys(plan.objectValue ?? [:]))
    }
}
