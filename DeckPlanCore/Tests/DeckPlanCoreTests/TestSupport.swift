//
//  TestSupport.swift
//  DeckPlanCoreTests
//
//  Finding the repository's own fixtures from inside the package.
//
//  The Swift tests read the same files the Python tests do — `examples/` and
//  `tests/fixtures/` — because the manifest is the truth and the Python is the
//  oracle (the "Python first" rule). There is no test bundle to copy them into:
//  the package sits at `<root>/DeckPlanCore/`, so `#filePath` locates the root.
//

import Foundation
import XCTest
@testable import DeckPlanCore

enum Repo {

    /// The repository root, from this file's own path:
    /// `<root>/DeckPlanCore/Tests/DeckPlanCoreTests/TestSupport.swift`.
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()        // DeckPlanCoreTests
        .deletingLastPathComponent()        // Tests
        .deletingLastPathComponent()        // DeckPlanCore
        .deletingLastPathComponent()        // <root>

    /// A path relative to the repository root.
    static func url(_ path: String) -> URL {
        root.appending(path: path, directoryHint: .notDirectory)
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(path).path)
    }

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: url(path))
    }

    static func text(_ path: String) throws -> String {
        try String(contentsOf: url(path), encoding: .utf8)
    }

    static func json(_ path: String) throws -> JSONValue {
        try JSONValue.parse(try data(path))
    }

    /// Every `.json` file under `relative`, depth first, in a stable order —
    /// repository-relative paths, so a failure names the file the way the docs do.
    static func jsonFiles(under relative: String) -> [String] {
        let base = root.appending(path: relative, directoryHint: .isDirectory)
        guard let walker = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var found: [String] = []
        for case let file as URL in walker where file.pathExtension == "json" {
            let path = file.path.hasPrefix(root.path + "/")
                ? String(file.path.dropFirst(root.path.count + 1))
                : file.path
            found.append(path)
        }
        return found.sorted()
    }

    /// Skip a test that needs the transcribed curriculum, which is gitignored
    /// (the "Copyright" rule), exactly as the Python tests skip.
    static func requireCurriculumDirectory() throws {
        guard exists("curriculum/stages") else {
            throw XCTSkip("curriculum/stages is absent (the transcription is gitignored)")
        }
    }
}

/// The v2 fixtures (docs/TEST_CASES.md "Fixtures"), the way `tests/v2support.py`
/// loads them: the Stage 1 sample as the tests' curriculum, the fixture class and
/// pool, and the manifest's facts.
enum Fixtures {

    static let sampleFile = "examples/curriculum.stage1.sample.json"

    /// The Stage 1 sample, validated (the Python asserts the same).
    static func sample(file: StaticString = #filePath, line: UInt = #line) -> LoadedCurriculum {
        let loaded = CurriculumLoader.load(sampleFile: Repo.url(sampleFile))
        let errors = Problem.errors(CurriculumValidator.validate(loaded))
        XCTAssertTrue(errors.isEmpty, "the Stage 1 sample must validate: \(errors)", file: file, line: line)
        return loaded
    }

    static func firstItem(_ name: String) throws -> JSONValue {
        try XCTUnwrap(Repo.json("examples/\(name)")["items"]?.arrayValue?.first, "\(name) has no items")
    }

    /// `examples/class.stage1.json`'s class: Stage 1, school age, Mon/Wed from
    /// 2026-09-14, days 1–4 saved with one activity per block (D10).
    static func fixtureClass() throws -> SwimClass {
        try SwimClass(json: try firstItem("class.stage1.json"))
    }

    /// `examples/pool.shallow.json`: shallow only, diving off, the five profile
    /// items with the kickboard off (P6).
    static func fixturePool() throws -> Pool {
        try Pool(json: try firstItem("pool.shallow.json"))
    }

    static func manifestCase(_ id: String) throws -> JSONValue {
        let cases = try Repo.json("examples/manifest.json")["cases"]?.arrayValue ?? []
        return try XCTUnwrap(cases.first { $0["id"]?.stringValue == id }, "manifest case \(id)")
    }

    /// The bytes of a fixture in `examples/`, as written by `build_fixtures.py`
    /// (canonical JSON plus a trailing newline).
    static func text(_ name: String) throws -> String {
        try Repo.text("examples/\(name)")
    }

    static func json(_ name: String) throws -> JSONValue {
        try Repo.json("examples/\(name)")
    }
}

extension XCTestCase {

    /// Assert two canonical JSON texts are equal, showing the first byte that differs.
    func assertSameJSONText(_ produced: String, _ expected: String,
                            _ label: String, file: StaticString = #filePath,
                            line: UInt = #line) {
        if produced == expected { return }
        let a = Array(produced.utf8), b = Array(expected.utf8)
        var index = 0
        while index < min(a.count, b.count), a[index] == b[index] { index += 1 }
        let window = { (bytes: [UInt8]) -> String in
            String(decoding: bytes[max(0, index - 40)..<min(bytes.count, index + 40)], as: UTF8.self)
        }
        XCTFail("""
            \(label): the canonical JSON differs at byte \(index) \
            (\(a.count) bytes produced, \(b.count) expected)
            produced …\(window(a))…
            expected …\(window(b))…
            """, file: file, line: line)
    }

    /// The problem codes, for "the refusal is X" assertions.
    func codes(_ problems: [Problem]) -> [String] {
        problems.map(\.code)
    }
}
