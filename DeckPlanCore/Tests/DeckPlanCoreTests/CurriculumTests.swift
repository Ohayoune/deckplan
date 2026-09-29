//
//  CurriculumTests.swift
//  DeckPlanCoreTests
//
//  A1–A14 (docs/TEST_CASES.md), mirroring tests/test_curriculum.py: the
//  synthetic `tests/fixtures/curriculum_mini` (copied to a temporary directory
//  and mutated per case, as the Python does), the Stage 1/2/4 samples under
//  `examples/`, and the real `curriculum/` when present. Assertions are on
//  codes, severities and counts, not on message text (the M4 brief: message
//  wording may differ as long as it names what Python's names).
//

import Foundation
import XCTest
@testable import DeckPlanCore

// MARK: - JSON fixture mutation helpers (test-only: Foundation's JSONSerialization,
// not the Core's own JSONValue, since these only ever produce the *input* files
// the Core is tested against).

enum FixtureError: Error {
    case notAnObject(String)
    case notAnArray(String)
}

/// The first element of `array` whose `"id"` equals `id`.
func findDict(_ array: NSMutableArray, id: String) -> NSMutableDictionary? {
    for case let dict as NSMutableDictionary in array where dict["id"] as? String == id {
        return dict
    }
    return nil
}

/// The skill `id` nested in a mutable stage dictionary (`tests/test_curriculum.py`'s `skill_of`).
func findSkill(_ stage: NSMutableDictionary, _ id: String) -> NSMutableDictionary? {
    guard let skills = stage["skills"] as? NSMutableArray else { return nil }
    return findDict(skills, id: id)
}

/// The step `id` nested in a mutable stage dictionary (`tests/test_curriculum.py`'s `step_of`).
func findStep(_ stage: NSMutableDictionary, _ id: String) -> NSMutableDictionary? {
    guard let skills = stage["skills"] as? NSMutableArray else { return nil }
    for case let skill as NSMutableDictionary in skills {
        guard let steps = skill["steps"] as? NSMutableArray else { continue }
        if let step = findDict(steps, id: id) { return step }
    }
    return nil
}

func findTemplate(_ stage: NSMutableDictionary, n: Int) -> NSMutableDictionary? {
    guard let templates = stage["lessonTemplates"] as? NSMutableArray else { return nil }
    for case let template as NSMutableDictionary in templates where template["n"] as? Int == n {
        return template
    }
    return nil
}

/// The block of kind `kind` in lesson template `n` (`tests/test_curriculum.py`'s `block_of`).
func findBlock(_ stage: NSMutableDictionary, _ n: Int, _ kind: String) -> NSMutableDictionary? {
    guard let template = findTemplate(stage, n: n), let blocks = template["blocks"] as? NSMutableArray else { return nil }
    for case let block as NSMutableDictionary in blocks where block["kind"] as? String == kind {
        return block
    }
    return nil
}

/// The `JSONValue` equivalent of `findBlock`, for querying a *loaded* stage
/// (`cur.stage("4")`) rather than a fixture file being mutated.
func blockOf(_ stage: JSONValue?, _ n: Int, _ kind: String) -> JSONValue? {
    guard let stage else { return nil }
    for template in dictItems(stage["lessonTemplates"]) where template["n"]?.intValue == n {
        for block in dictItems(template["blocks"]) where block["kind"]?.stringValue == kind {
            return block
        }
    }
    return nil
}

// MARK: - The mini fixture test case

/// A temporary copy of `tests/fixtures/curriculum_mini` that a test may edit —
/// `tests/test_curriculum.py`'s `MiniCase`.
class MiniCurriculumCase: XCTestCase {
    var tempRoot: URL!
    var dir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let mini = Repo.url("tests/fixtures/curriculum_mini")
        guard FileManager.default.fileExists(atPath: mini.path) else {
            throw XCTSkip("tests/fixtures/curriculum_mini is absent")
        }
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("deckplan-curriculum-\(UUID().uuidString)")
        dir = tempRoot.appendingPathComponent("curriculum")
        try copyMiniFixture(from: mini, to: dir)
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    /// Copies the mini fixture, skipping its dev-only files (`_work/`,
    /// `make_fixture.py`, `videos-source.json`) the way the Python's
    /// `shutil.copytree(..., ignore=...)` does.
    private func copyMiniFixture(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let skipNames: Set<String> = ["_work", "make_fixture.py", "videos-source.json", "__pycache__"]
        for name in try fm.contentsOfDirectory(atPath: source.path) where !skipNames.contains(name) {
            try fm.copyItem(at: source.appendingPathComponent(name), to: destination.appendingPathComponent(name))
        }
    }

    /// Reads `relative` (a JSON object file) and lets `change` mutate it in
    /// place with plain Foundation collections, then writes it back —
    /// `tests/test_curriculum.py`'s `self.edit(relative, change)`.
    @discardableResult
    func edit(_ relative: String, _ change: (NSMutableDictionary) -> Void) throws -> NSMutableDictionary {
        let path = dir.appendingPathComponent(relative)
        let data = try Data(contentsOf: path)
        guard let dict = try JSONSerialization.jsonObject(
            with: data, options: [.mutableContainers, .mutableLeaves]) as? NSMutableDictionary else {
            throw FixtureError.notAnObject(relative)
        }
        change(dict)
        try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]).write(to: path)
        return dict
    }

    /// The array-file variant (`activities.json`, `equipment.json`, `safety.json`).
    @discardableResult
    func editList(_ relative: String, _ change: (NSMutableArray) -> Void) throws -> NSMutableArray {
        let path = dir.appendingPathComponent(relative)
        let data = try Data(contentsOf: path)
        guard let array = try JSONSerialization.jsonObject(
            with: data, options: [.mutableContainers, .mutableLeaves]) as? NSMutableArray else {
            throw FixtureError.notAnArray(relative)
        }
        change(array)
        try JSONSerialization.data(withJSONObject: array, options: [.sortedKeys]).write(to: path)
        return array
    }

    /// Overwrites `relative` with literal text — corrupting a file, or giving
    /// it a wholly different top-level JSON shape (A10's garbage variants).
    func writeRaw(_ relative: String, _ text: String) throws {
        try text.write(to: dir.appendingPathComponent(relative), atomically: true, encoding: .utf8)
    }

    func deleteFile(_ relative: String) throws {
        try FileManager.default.removeItem(at: dir.appendingPathComponent(relative))
    }

    func check() -> (LoadedCurriculum, [Problem]) {
        CurriculumValidator.check(directory: dir)
    }

    /// Finds a problem with `code`, `severity`, and every fragment appearing in
    /// its message or its `where` — `tests/test_curriculum.py`'s `assertProblem`.
    /// Message wording is this port's own (the M4 brief allows that); the
    /// fragments below are chosen to match what *this* port actually says.
    @discardableResult
    func assertProblem(_ problems: [Problem], _ code: String, _ fragments: String..., severity: Severity = .error,
                        file: StaticString = #filePath, line: UInt = #line) -> Problem? {
        let hit = problems.first { problem in
            problem.code == code && problem.severity == severity
                && fragments.allSatisfy { problem.message.contains($0) || problem.`where`.contains($0) }
        }
        if hit == nil {
            let shown = problems.map(\.description).joined(separator: "\n")
            XCTFail("no \(severity) \(code) mentioning \(fragments) in:\n\(shown)", file: file, line: line)
        }
        return hit
    }

    func assertNoProblem(_ problems: [Problem], _ code: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(problems.contains { $0.code == code },
                        "unexpected \(code) in: \(problems.map(\.description))", file: file, line: line)
    }

    func assertNoErrors(_ problems: [Problem], file: StaticString = #filePath, line: UInt = #line) {
        let errors = Problem.errors(problems)
        XCTAssertTrue(errors.isEmpty, "unexpected errors: \(errors.map(\.description))", file: file, line: line)
    }
}

// MARK: - The clean fixture (sanity: no false positives)

final class MiniFixtureBaselineTests: MiniCurriculumCase {

    func test_mini_curriculum_validates_clean() {
        let (_, problems) = check()
        XCTAssertEqual([], problems.map(\.description))
    }

    /// Once `Problem.canPlan` is true, `LoadedCurriculum.json` bridges to the
    /// typed `Curriculum` (`Models/CurriculumModels.swift`) that a future
    /// consumer (the Planner, M2) can use instead of raw `JSONValue` lookups.
    func test_a_canPlan_curriculum_bridges_to_the_typed_model() throws {
        let (cur, problems) = check()
        XCTAssertTrue(Problem.canPlan(problems))
        let typed = try Curriculum(json: cur.json)
        XCTAssertEqual(cur.version, typed.version)
        XCTAssertEqual(cur.loadedStageIds, typed.stages?.compactMap(\.id))
        XCTAssertEqual(cur.activities.count, typed.activities?.count)
        XCTAssertEqual("1.skill-one", typed.stages?.first { $0.id == "1" }?.skills?.first { $0.id == "1.skill-one" }?.id)
    }
}

// MARK: - A1–A14

final class MiniFixtureTests: MiniCurriculumCase {

    func test_A1_all_eight_stages_load_and_counts_are_reported() throws {
        var (cur, problems) = check()
        XCTAssertEqual(Ids.stageIds, cur.loadedStageIds)
        var counts = CurriculumValidator.summary(cur)
        let stage5 = try XCTUnwrap(counts.stages["5"])
        XCTAssertEqual(CurriculumStageSummary(name: "Stage Five", skills: 9, steps: 22, activityLinks: 19,
                                               greeting: 2, topics: 8, templates: 8, trackerRows: 8), stage5)
        XCTAssertEqual(CurriculumActivitySummary(ymca: 36, local: 1), counts.activities)
        XCTAssertEqual(CurriculumEquipmentSummary(items: 28, groups: 1, local: 1), counts.equipment)
        let lines = CurriculumValidator.formatSummary(counts)
        XCTAssertEqual("Loaded stages: A, B, 1, 2, 3, 4, 5, 6.", lines[0])
        XCTAssertTrue(lines[7].contains("Stage 5 Stage Five: 9 skills, 22 steps"))

        // a stage not yet transcribed is simply not loaded; references into it are warnings
        try deleteFile("stages/4.json")
        (cur, problems) = check()
        XCTAssertFalse(cur.loadedStageIds.contains("4"))
        assertNoErrors(problems)
        assertProblem(problems, "stage-not-loaded", "4", severity: .warning)
        assertProblem(problems, "link-not-loaded", "4", severity: .warning)
        counts = CurriculumValidator.summary(cur)
        XCTAssertEqual(["A", "B", "1", "2", "3", "5", "6"], counts.loaded)
        XCTAssertEqual(["4"], counts.notLoaded)
    }

    func test_A2_topics_templates_and_minutes() throws {
        let (cur, _) = check()
        XCTAssertEqual(2, blockOf(cur.stage("4"), 2, "review")?["minutes"]?.intValue)
        try edit("stages/1.json") { stage in
            (stage["topics"] as? NSMutableArray)?.removeLastObject()
        }
        try edit("stages/2.json") { stage in
            guard let templates = stage["lessonTemplates"] as? NSMutableArray else { return }
            if let index = (0..<templates.count).first(where: { (templates[$0] as? NSDictionary)?["n"] as? Int == 3 }) {
                templates.removeObject(at: index)
            }
        }
        try edit("stages/4.json") { stage in
            findBlock(stage, 2, "introduce")?["minutes"] = 14
        }
        try edit("stages/5.json") { stage in
            findTemplate(stage, n: 6)?["minutes"] = 30
        }
        try edit("stages/3.json") { stage in
            guard let skills = stage["skills"] as? NSMutableArray else { return }
            if let index = (0..<skills.count).first(where: { (skills[$0] as? NSDictionary)?["order"] as? Int == 8 }) {
                skills.removeObject(at: index)
            }
        }
        let (_, problems) = check()
        assertProblem(problems, "topics", "Stage 1")
        assertProblem(problems, "templates", "Stage 2")
        assertProblem(problems, "template-minutes", "lesson template 2")
        assertProblem(problems, "template-minutes", "lesson template 6")
        assertProblem(problems, "skill-count", "Stage 3 has 7 skills")
    }

    func test_A3_steps_benchmarks_and_step_names() throws {
        let (cur, _) = check()
        XCTAssertEqual([], strList(cur.skill("5.skill-eight-left")?["stepIds"]))
        XCTAssertNil(cur.skill("5.skill-eight-left")?["benchmarkStepId"]?.stringValue)
        XCTAssertEqual("1.skill-one", cur.step("1.skill-one.3")?["skillId"]?.stringValue)

        try edit("stages/1.json") { stage in
            findStep(stage, "1.skill-one.3")?["n"] = 5
            findSkill(stage, "1.skill-two")?["benchmarkStepId"] = "1.skill-two.2"
            findStep(stage, "1.skill-one.2")?["name"] = "Skill One, step 1"
            findStep(stage, "1.skill-three.1")?["name"] = "Skill One, step 1"   // another skill may repeat a name
            findStep(stage, "1.skill-six.2")?["id"] = "1.skill-six.02"
        }
        try edit("stages/5.json") { stage in
            findSkill(stage, "5.skill-eight-left")?["benchmarkStepId"] = "5.skill-eight-left.1"
        }
        let (_, problems) = check()
        assertProblem(problems, "steps", "1.skill-one")
        assertProblem(problems, "benchmark", "1.skill-two")
        assertProblem(problems, "step-name-duplicate", "1.skill-one.2")
        XCTAssertFalse(problems.contains { $0.code == "step-name-duplicate" && $0.message.contains("skill-three") })
        assertProblem(problems, "steps", "1.skill-six.02")
        assertProblem(problems, "benchmark", "5.skill-eight-left")
    }

    func test_A4_prerequisite_and_advanced_links() throws {
        let (cur, _) = check()
        XCTAssertEqual(["4.skill-eight-left.1", "4.skill-eight-left.2"], strList(cur.skill("5.skill-eight-left")?["prerequisiteStepIds"]))
        XCTAssertEqual(["6.skill-eight-left.1", "6.skill-eight-left.2"], strList(cur.skill("5.skill-eight-left")?["advancedStepIds"]))
        XCTAssertEqual(["4.skill-eight-left.1", "4.skill-eight-left.2"], strList(cur.skill("6.skill-eight-left")?["prerequisiteStepIds"]))
        XCTAssertTrue(dictItems(cur.stage("A")?["skills"]).allSatisfy { (strList($0["prerequisiteStepIds"]) ?? []).isEmpty })
        XCTAssertTrue(dictItems(cur.stage("6")?["skills"]).allSatisfy { (strList($0["advancedStepIds"]) ?? []).isEmpty })

        try edit("stages/6.json") { stage in
            findSkill(stage, "6.skill-one")?["prerequisiteStepIds"] = ["4.skill-one.4"]
        }
        try edit("stages/2.json") { stage in
            guard let skill = findSkill(stage, "2.skill-one"), let list = skill["prerequisiteStepIds"] as? NSMutableArray else { return }
            list.add("1.skill-one.9")
        }
        try edit("stages/A.json") { stage in
            findSkill(stage, "A.skill-one")?["prerequisiteStepIds"] = ["B.skill-one.1"]
        }
        try edit("stages/3.json") { stage in
            findSkill(stage, "3.skill-one")?["advancedStepIds"] = ["2.skill-one.1"]
        }
        var (_, problems) = check()
        assertProblem(problems, "link-unresolved", "6.skill-one", "Stage 5")
        assertProblem(problems, "link-unresolved", "1.skill-one.9")
        assertProblem(problems, "link-unresolved", "A.skill-one", "first stage")
        assertProblem(problems, "link-unresolved", "3.skill-one", "later")

        // a reference into a stage that isn't loaded is a warning, printed without the step's name
        try deleteFile("stages/2.json")
        (_, problems) = check()
        assertProblem(problems, "link-not-loaded", "1.skill-one", "Stage 2", severity: .warning)
        XCTAssertEqual("2 / Front glide / 1", Ids.stepLabel("2.front-glide.1"))
    }

    func test_A5_activities_depths_flags_and_template_activities() throws {
        let (cur, _) = check()
        XCTAssertEqual(true, cur.step("2.skill-seven.4")?["nearWall"]?.boolValue)
        XCTAssertEqual(true, cur.step("3.skill-seven.1")?["nearWall"]?.boolValue)
        XCTAssertEqual(["bob-game", "dip-game", "float-game"], strList(blockOf(cur.stage("4"), 1, "warmUp")?["activityIds"]))

        try edit("stages/1.json") { stage in
            (findSkill(stage, "1.skill-one")?["activityIds"] as? NSMutableArray)?.add("no-such-activity")
            findStep(stage, "1.skill-one.2")?["depths"] = []
            findStep(stage, "1.skill-one.4")?["nearWall"] = "yes"
            (findBlock(stage, 2, "introduce")?["activityIds"] as? NSMutableArray)?.add("six-drill")
            (findBlock(stage, 3, "welcome")?["activityIds"] as? NSMutableArray)?.add("one-drill")
            findBlock(stage, 7, "introduce")?["depths"] = ["abyss"]
        }
        try edit("stages/4.json") { stage in
            findStep(stage, "4.skill-four.1")?["depths"] = ["medium", "deep"]
        }
        try editList("activities.json") { entries in
            findDict(entries, id: "one-drill")?["ages"] = ["P", "X"]
            findDict(entries, id: "two-drill")?["description"] = ""
            findDict(entries, id: "splash-game-4")?["depths"] = ["medium", "deep"]
            findDict(entries, id: "toy-hunt")?["submerges"] = "no"
            findDict(entries, id: "wade-game")?["nearWall"] = true
        }
        let (_, problems) = check()
        assertProblem(problems, "activity-missing", "no-such-activity")
        assertProblem(problems, "depths", "1.skill-one.2")
        assertProblem(problems, "flag-type", "1.skill-one.4")
        assertProblem(problems, "template-activity", "six-drill")
        assertProblem(problems, "template-activity", "one-drill")
        assertProblem(problems, "depths", "abyss")
        assertProblem(problems, "headfirst-depths", "4.skill-four.1")
        assertProblem(problems, "activity-shape", "one-drill")
        assertProblem(problems, "activity-shape", "two-drill")
        assertProblem(problems, "headfirst-depths", "splash-game-4")
        assertProblem(problems, "flag-type", "toy-hunt")
        assertProblem(problems, "flag-type", "wade-game")
    }

    func test_A6_warm_up_wrap_up_and_step_ranges() throws {
        let (cur, _) = check()
        XCTAssertEqual("4.skill-one", cur.stage("4")?["warmUpSkill"]?.stringValue)
        for n in 1...4 {
            XCTAssertNil(blockOf(cur.stage("4"), n, "warmUp")?["skillIds"])
        }
        XCTAssertEqual([1, 3], blockOf(cur.stage("1"), 1, "introduce")?["stepRange"]?.arrayValue?.compactMap(\.intValue))

        try edit("stages/1.json") { stage in
            stage["warmUpSkill"] = "1.no-such-skill"
            findBlock(stage, 1, "warmUp")?["stepRange"] = [1, 9]
            findBlock(stage, 2, "wrapUp")?["stepRange"] = [3, 1]
            findBlock(stage, 3, "introduce")?["stepRange"] = [4, 4]
        }
        try edit("stages/2.json") { stage in
            stage["wrapUpSkill"] = "2.skill-nine"
        }
        let (_, problems) = check()
        assertProblem(problems, "warm-up-wrap-up", "1.no-such-skill")
        assertProblem(problems, "warm-up-wrap-up", "2.skill-nine")
        assertProblem(problems, "step-range", "lesson template 1", "ends past")
        assertProblem(problems, "step-range", "lesson template 2", "must be [first, last]")
        assertProblem(problems, "step-range", "lesson template 3", "starts past")
    }

    func test_A7_tracker_rows() throws {
        let (cur, _) = check()
        let six = dictItems(cur.stage("6")?["trackerRows"])
        XCTAssertEqual("any", six[7]["rule"]?.stringValue)
        XCTAssertEqual(["6.skill-eight-left.2", "6.skill-eight-right.3"], strList(six[7]["stepIds"]))
        XCTAssertTrue(six[0..<7].allSatisfy { $0["rule"]?.stringValue == "all" && (strList($0["stepIds"])?.count ?? 0) == 1 })
        let totalRows = Ids.stageIds.reduce(0) { $0 + dictItems(cur.stage($1)?["trackerRows"]).count }
        XCTAssertEqual(64, totalRows)

        try edit("stages/2.json") { stage in
            guard let rows = stage["trackerRows"] as? NSMutableArray else { return }
            (rows[0] as? NSMutableDictionary)?["stepIds"] = ["2.skill-one.2"]
            (rows[1] as? NSMutableDictionary)?["text"] = "Skill Two, step three"
            (rows[2] as? NSMutableDictionary)?["rule"] = "any"
            rows.removeObject(at: 3)
        }
        try edit("stages/3.json") { stage in
            stage["trackerRows"] = []
        }
        let (_, problems) = check()
        assertProblem(problems, "tracker-row", "2.skill-one.2", "not its skill's benchmark")
        assertProblem(problems, "tracker-row", "Skill Two, step three", "differs from its benchmark step's name")
        assertProblem(problems, "tracker-row", "needs two or more")
        assertProblem(problems, "tracker-coverage", "2.skill-four")
        assertProblem(problems, "tracker-rows-missing", "Stage 3")
    }

    func test_A8_preschool_values_only_where_the_tracker_prints_them() throws {
        let (cur, _) = check()
        var withValue: Set<String> = []
        for stage in cur.stages {
            for skill in dictItems(stage["skills"]) {
                for step in dictItems(skill["steps"]) where isPresentNonNull(step["measure"]?["preschoolValue"]) {
                    withValue.insert(step["id"]?.stringValue ?? "")
                }
            }
        }
        XCTAssertEqual(["2.skill-two.3", "3.skill-six.3"], withValue)

        try edit("stages/1.json") { stage in
            findStep(stage, "1.skill-one.2")?["measure"] = ["kind": "time", "value": 20, "unit": "s", "preschoolValue": 10]
        }
        try edit("stages/2.json") { stage in
            (findStep(stage, "2.skill-two.3")?["measure"] as? NSMutableDictionary)?["preschoolValue"] = 12
        }
        let (_, problems) = check()
        assertProblem(problems, "preschool-value", "1.skill-one.2")
        assertProblem(problems, "preschool-value", "2.skill-two.3", severity: .warning)
    }

    func test_A9_unique_ids_and_local_json() throws {
        let (cur, _) = check()
        XCTAssertEqual("local", cur.activity("local-relay")?["source"]?.stringValue)
        XCTAssertEqual("foam-dice", cur.equipment.last?["id"]?.stringValue)   // local items come last in catalog order

        try edit("local.json") { local in
            local["format"] = "local/2"
            local["rules"] = []
            if let activities = local["activities"] as? NSMutableArray, let first = activities.firstObject as? NSDictionary {
                let oneDrill = NSMutableDictionary(dictionary: first)
                oneDrill["id"] = "one-drill"
                let ourGame = NSMutableDictionary(dictionary: first)
                ourGame["id"] = "our-game"
                ourGame["source"] = "ymca"
                activities.add(oneDrill)
                activities.add(ourGame)
            }
            if let equipment = local["equipment"] as? NSMutableArray {
                equipment.add(["id": "our-group", "name": "Our group", "aliases": [], "source": "local",
                                "kind": "group", "anyOf": ["foam-dice"]])
            }
        }
        try editList("activities.json") { entries in
            if let first = entries.firstObject as? NSDictionary, let second = entries.object(at: 1) as? NSDictionary {
                entries.add(NSMutableDictionary(dictionary: first))
                let kickboard = NSMutableDictionary(dictionary: second)
                kickboard["id"] = "kickboard"
                entries.add(kickboard)
            }
        }
        let (_, problems) = check()
        assertProblem(problems, "local-format", "local/2")
        assertProblem(problems, "local-format", "rules")
        assertProblem(problems, "local-collision", "one-drill")
        assertProblem(problems, "local-entry", "our-game")
        assertProblem(problems, "local-entry", "our-group")
        assertProblem(problems, "id-duplicate")
        assertProblem(problems, "id-duplicate", "kickboard")
    }

    func test_A10_corrupt_or_missing_files_give_a_readable_list() throws {
        try writeRaw("stages/3.json", "{not json")
        try deleteFile("activities.json")
        try edit("stages/5.json") { stage in stage["id"] = "6" }
        try edit("stages/1.json") { stage in findTemplate(stage, n: 4)?["blocks"] = "TODO-M1" }
        try edit("stages/2.json") { stage in
            stage["skills"] = "not a list"
            stage["topics"] = [1, 2]
        }
        try editList("equipment.json") { entries in
            entries.add(["id": "odd", "kind": "item", "anyOf": 5, "aliases": 3])
        }
        let (cur, problems) = check()   // never crashes
        assertProblem(problems, "file-unreadable", "stages/3.json")
        assertProblem(problems, "file-missing", "activities.json")
        assertProblem(problems, "stage-file-invalid", "stages/5.json")
        assertProblem(problems, "template-placeholder", "Stage 1")
        assertProblem(problems, "stage-shape", "Stage 2")
        XCTAssertFalse(cur.loadedStageIds.contains("3"))
        XCTAssertFalse(Problem.canPlan(problems))

        // garbage in every shape still gives problems, not a crash
        for garbage in ["[]", "\"text\"", "{\"id\": \"1\", \"skills\": [1, {\"id\": 5, \"steps\": \"x\"}], \"lessonTemplates\": {\"n\": 1}}"] {
            try writeRaw("stages/1.json", garbage)
            let (_, problems) = check()
            XCTAssertFalse(Problem.errors(problems).isEmpty, "no error reported for stages/1.json = \(garbage)")
        }
    }

    func test_A11_continuum_link() {
        let (cur, _) = check()
        XCTAssertTrue(cur.prerequisiteOf("1.skill-two.3").contains("2.skill-two"))
        XCTAssertTrue(cur.advancedOf("2.skill-two.1").contains("1.skill-two"))
        XCTAssertTrue(cur.prerequisitesSatisfied("2.skill-two", achievedStepIds: ["1.skill-two.3"]))
        XCTAssertFalse(cur.prerequisitesSatisfied("2.skill-two", achievedStepIds: ["1.skill-two.2"]))
        XCTAssertTrue(cur.prerequisitesSatisfied("A.skill-one", achievedStepIds: []))       // no prerequisite column
        XCTAssertFalse(cur.prerequisitesSatisfied("2.no-such-skill", achievedStepIds: ["1.skill-two.3"]))
    }

    func test_A12_videos() throws {
        let (cur, _) = check()
        XCTAssertEqual(["5.skill-eight-right"], strList(cur.video("vimeo:100000004")?["skillIds"]))
        XCTAssertEqual(["vimeo:100000001"], strList(cur.skill("1.skill-one")?["videoIds"]))

        try editList("videos.json") { entries in
            (entries[0] as? NSMutableDictionary)?["url"] = "https://example.com/v/1"
            (entries[1] as? NSMutableDictionary)?["id"] = "youtube:1"
            (entries[2] as? NSMutableDictionary)?["url"] = "https://vimeo.com/999"
            if let skillIds = (entries[3] as? NSDictionary)?["skillIds"] as? NSMutableArray {
                skillIds.add("4.no-such-skill")
            }
            (entries[4] as? NSMutableDictionary)?["stageIds"] = ["9"]
        }
        try edit("stages/1.json") { stage in
            findSkill(stage, "1.skill-two")?["videoIds"] = ["vimeo:999"]
        }
        let (_, problems) = check()
        assertProblem(problems, "video", "vimeo:100000000")
        assertProblem(problems, "video", "youtube:1")
        assertProblem(problems, "video", "vimeo:100000002", "999")
        assertProblem(problems, "video-link", "4.no-such-skill")
        assertProblem(problems, "video-link", "9")
        assertProblem(problems, "video-link", "vimeo:999")
    }

    func test_A13_equipment_catalog() throws {
        let (cur, _) = check()
        let group = cur.equipmentEntry("flotation-device")
        XCTAssertEqual("group", group?["kind"]?.stringValue)
        XCTAssertEqual(["kickboard", "pool-noodle", "barbell", "float-belt", "life-jacket", "pull-buoy"], strList(group?["anyOf"]))
        XCTAssertEqual([["life-jacket", "float-belt"]],
                        cur.step("2.skill-seven.1")?["equipment"]?.arrayValue?.map { strList($0) ?? [] })
        XCTAssertEqual([["life-jacket"]], blockOf(cur.stage("1"), 7, "introduce")?["equipment"]?.arrayValue?.map { strList($0) ?? [] })

        try editList("activities.json") { entries in
            findDict(entries, id: "one-drill")?["equipment"] = [["trampoline"]]
            findDict(entries, id: "two-drill")?["equipmentOptional"] = ["confetti"]
        }
        try edit("stages/1.json") { stage in
            findStep(stage, "1.skill-one.1")?["equipment"] = [["jetpack"]]
            findBlock(stage, 7, "introduce")?["equipment"] = [["life-vest"]]
        }
        try editList("equipment.json") { entries in
            findDict(entries, id: "flotation-device")?["anyOf"] = ["kickboard", "flotation-device", "raft"]
            findDict(entries, id: "hoop")?["anyOf"] = ["ball"]
        }
        try edit("local.json") { local in
            (local["equipment"] as? NSMutableArray)?.add(
                ["id": "kickboard", "name": "Our kickboard", "aliases": [], "source": "local", "kind": "item"])
        }
        let (_, problems) = check()
        for missing in ["trampoline", "confetti", "jetpack", "life-vest"] {
            assertProblem(problems, "equipment-unknown", missing)
        }
        assertProblem(problems, "equipment-catalog", "flotation-device", "not an item")
        assertProblem(problems, "equipment-catalog", "raft", "not in the catalog")
        assertProblem(problems, "equipment-catalog", "hoop", "anyOf is on groups only")
        assertProblem(problems, "local-collision", "kickboard")
    }

    func test_A14_safety_rules() throws {
        try editList("safety.json") { entries in
            if let single = findDict(entries, id: "single-inhalation") {
                single["tags"] = [String]()
            }
            if let deckDiving = findDict(entries, id: "deck-diving") {
                entries.add(NSMutableDictionary(dictionary: deckDiving))
            }
            entries.add(["id": "no-text", "tags": []])
        }
        var (_, problems) = check()
        assertProblem(problems, "safety", "tags must be")
        assertProblem(problems, "id-duplicate", "deck-diving")
        assertProblem(problems, "safety", "no-text")

        try editList("safety.json") { entries in
            if let index = (0..<entries.count).first(where: { (entries[$0] as? NSDictionary)?["id"] as? String == "single-inhalation" }) {
                entries.removeObject(at: index)
            }
        }
        (_, problems) = check()
        assertProblem(problems, "safety", "no single-inhalation")
    }
}

// MARK: - The compact samples (examples/curriculum.stage{1,2,4}.sample.json)

final class SampleTests: XCTestCase {

    func test_sample_loads_and_validates() throws {
        let path = Repo.url("examples/curriculum.stage1.sample.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path.path), "the Stage 1 sample is absent")
        let (cur, problems) = CurriculumValidator.check(sampleFile: path)
        XCTAssertEqual(["1"], cur.loadedStageIds)
        XCTAssertEqual([], Problem.errors(problems).map(\.description))
        XCTAssertTrue(Problem.canPlan(problems))   // M1 filled templates 2–4 and 6–8 and the tracker rows (A10, D9)
        XCTAssertEqual([1, 2, 3, 4, 5, 6, 7, 8], dictItems(cur.stage("1")?["lessonTemplates"]).compactMap { $0["n"]?.intValue })
        XCTAssertEqual(9, dictItems(cur.stage("1")?["trackerRows"]).count)
        XCTAssertEqual(["1.front-glide"], strList(cur.activity("comet-rocket-ride")?["skillIds"]))
        XCTAssertEqual("ymca", cur.activity("comet-rocket-ride")?["source"]?.stringValue)
        XCTAssertTrue((strList(cur.skill("1.submerge")?["stepIds"]) ?? []).contains("1.submerge.4"))
        let warned = Set(Problem.warnings(problems).map(\.code))
        XCTAssertTrue(warned.isSubset(of: ["link-not-loaded"]))
    }

    func test_every_sample_loads_with_no_errors() throws {
        // The Stage 2 and 4 samples (M2's deep-water, dive and 40-minute cases).
        for (stageId, name) in [("2", "curriculum.stage2.sample.json"), ("4", "curriculum.stage4.sample.json")] {
            let path = Repo.url("examples/\(name)")
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            let (cur, problems) = CurriculumValidator.check(sampleFile: path)
            XCTAssertEqual([stageId], cur.loadedStageIds, name)
            XCTAssertEqual([], Problem.errors(problems).map(\.description), name)
            XCTAssertTrue(Problem.canPlan(problems), name)
        }
    }

    func test_the_samples_load_together_as_one_curriculum() throws {
        // The demo build's bundle (tools/dev/sync_resources.py --demo), given out of order.
        let paths = ["4", "1", "2"].map { Repo.url("examples/curriculum.stage\($0).sample.json") }
        try XCTSkipUnless(paths.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "a sample is absent")
        let (cur, problems) = CurriculumValidator.check(sampleFiles: paths)
        XCTAssertEqual(["1", "2", "4"], cur.loadedStageIds)
        XCTAssertEqual([], Problem.errors(problems).map(\.description))
        XCTAssertTrue(Problem.canPlan(problems))
        XCTAssertEqual(.sample, cur.kind)
        // Each id once, and an activity two stages share lists both stages' skills.
        let activityIds = cur.activities.compactMap { $0["id"]?.stringValue }
        XCTAssertEqual(activityIds.count, Set(activityIds).count)
        XCTAssertEqual(cur.equipment.count, Set(cur.equipment.compactMap { $0["id"]?.stringValue }).count)
        XCTAssertEqual(1, cur.safety.count)
        let one = CurriculumLoader.load(sampleFile: paths[1])
        let two = CurriculumLoader.load(sampleFile: paths[2])
        let shared = try XCTUnwrap(one.activities.compactMap { $0["id"]?.stringValue }
            .first { id in two.activity(id) != nil })
        XCTAssertEqual((strList(one.activity(shared)?["skillIds"]) ?? []) + (strList(two.activity(shared)?["skillIds"]) ?? []),
                       strList(cur.activity(shared)?["skillIds"]))
        // Stage 1's equipment catalog order comes first.
        XCTAssertEqual(one.equipment.compactMap { $0["id"]?.stringValue },
                       Array(cur.equipment.compactMap { $0["id"]?.stringValue }.prefix(one.equipment.count)))
    }

    func test_two_samples_of_one_stage_are_reported() throws {
        let path = Repo.url("examples/curriculum.stage1.sample.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path.path), "the Stage 1 sample is absent")
        let cur = CurriculumLoader.load(sampleFiles: [path, path])
        XCTAssertEqual(["1"], cur.loadedStageIds)
        XCTAssertEqual(["sample-invalid"], cur.loadProblems.map(\.code))
    }
}

// MARK: - The continuum table cross-check (docs/CURRICULUM_FORMAT.md §4.2, A7, A8)

/// Differences between each loaded stage's `trackerRows` and the owner's table
/// `curriculum/_work/benchmarks.json` (gitignored) — a port of `tests/test_curriculum.py`'s
/// `tracker_mismatches`.
func trackerMismatches(_ cur: LoadedCurriculum, _ table: [String: JSONValue]) -> [String] {
    var found: [String] = []
    for stageId in cur.loadedStageIds {
        guard let stage = cur.stage(stageId) else { continue }
        let rows = dictItems(stage["trackerRows"])
        let expected = dictItems(table[stageId])
        let rowTexts = rows.map { $0["text"]?.stringValue ?? "" }
        let expectedTexts = expected.map { $0["text"]?.stringValue ?? "" }
        guard rowTexts == expectedTexts else {
            found.append("Stage \(stageId) rows \(rowTexts) != \(expectedTexts)")
            continue
        }
        var benchmarks: Set<String> = []
        for skill in dictItems(stage["skills"]) {
            if let benchmarkStepId = skill["benchmarkStepId"]?.stringValue { benchmarks.insert(benchmarkStepId) }
        }
        var preschoolSteps: Set<String> = []
        for (row, want) in zip(rows, expected) {
            if row["rule"]?.stringValue != want["rule"]?.stringValue {
                found.append("Stage \(stageId) row \(String(describing: want["text"])) rule \(String(describing: row["rule"])) != \(String(describing: want["rule"]))")
            }
            let stepIds = strList(row["stepIds"]) ?? []
            let slugs = stepIds.map { Ids.parseStepId($0)?.skillSlug ?? $0 }
            let wantSkills = strList(want["skills"]) ?? []
            if slugs != wantSkills {
                found.append("Stage \(stageId) row \(String(describing: want["text"])) skills \(slugs) != \(wantSkills)")
            }
            for stepId in stepIds {
                if !benchmarks.contains(stepId) {
                    found.append("Stage \(stageId) row \(String(describing: want["text"])) names \(stepId), not a benchmark")
                } else if isTruthy(want["preschool"]) {
                    preschoolSteps.insert(stepId)
                }
            }
        }
        var withValue: Set<String> = []
        for skill in dictItems(stage["skills"]) {
            for step in dictItems(skill["steps"]) where isPresentNonNull(step["measure"]?["preschoolValue"]) {
                if let id = step["id"]?.stringValue { withValue.insert(id) }
            }
        }
        if withValue != preschoolSteps {
            found.append("Stage \(stageId) preschoolValue on \(withValue.sorted()), tracker variants on \(preschoolSteps.sorted())")
        }
    }
    return found
}

// MARK: - The owner's real curriculum/ (skipped when it is absent — the "Copyright" rule)

final class RealCurriculumTests: XCTestCase {
    var cur: LoadedCurriculum!
    var problems: [Problem]!
    var table: [String: JSONValue]?

    override func setUpWithError() throws {
        try super.setUpWithError()
        try Repo.requireCurriculumDirectory()
        (cur, problems) = CurriculumValidator.check(directory: Repo.url("curriculum"))
        let benchmarks = "curriculum/_work/benchmarks.json"   // the owner's Progress Tracker table
        if FileManager.default.fileExists(atPath: Repo.url(benchmarks).path) {
            table = try JSONValue.parse(Repo.data(benchmarks))["stages"]?.objectValue ?? [:]
        }
    }

    func test_real_curriculum_has_no_errors() {
        let found = Problem.errors(problems).map(\.description)
        XCTAssertEqual([], Array(found.prefix(30)), "\(found.count) errors")
    }

    func test_A1_real_all_eight_stages_load() throws {
        let missing = Ids.stageIds.filter { !cur.loadedStageIds.contains($0) }
        try XCTSkipUnless(missing.isEmpty, "M1 in progress: Stages \(missing.joined(separator: ", ")) not assembled yet")
        XCTAssertEqual(Ids.stageIds, cur.loadedStageIds)
    }

    func test_A7_A8_real_tracker_rows_match_the_progress_tracker() throws {
        guard let table else { throw XCTSkip("no Progress Tracker table (curriculum/_work/benchmarks.json)") }
        let totalRows = table.values.reduce(0) { $0 + dictItems($1).count }
        XCTAssertEqual(69, totalRows)
        XCTAssertEqual([], trackerMismatches(cur, table))
    }

    func test_A5_A6_A11_real_landmarks() {
        if cur.isLoaded("2") {
            XCTAssertTrue((strList(cur.skill("2.front-glide")?["prerequisiteStepIds"]) ?? []).contains("1.front-glide.4"))
        }
        if cur.isLoaded("2") {
            XCTAssertEqual(true, cur.step("2.tread-water.4")?["nearWall"]?.boolValue)
        }
        if cur.isLoaded("3") {
            XCTAssertEqual(true, cur.step("3.tread-water.1")?["nearWall"]?.boolValue)
        }
        if cur.isLoaded("4") {
            XCTAssertEqual("4.endurance", cur.stage("4")?["warmUpSkill"]?.stringValue)
        }
        if cur.isLoaded("5") {
            XCTAssertNil(cur.skill("5.resting-stroke-elementary-backstroke")?["benchmarkStepId"]?.stringValue)
        }
    }

    func test_A14_real_safety() {
        XCTAssertEqual([], problems.filter { $0.code == "safety" }.map(\.description))
    }
}
