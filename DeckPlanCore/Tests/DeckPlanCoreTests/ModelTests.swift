//
//  ModelTests.swift
//  DeckPlanCoreTests
//
//  The curriculum models, loaded from the fixture they appear in and written
//  back unchanged (the v2 store and plan records are in StoreModelTests.swift).
//
//  "Written back unchanged" is measured as canonical JSON text, not as `JSONValue`
//  equality: a model holds a measure's value as a `Double`, so a `10` read from a
//  file comes back as `10.0`, which is the same number and the same canonical byte
//  ("10"). Everything a canonical encoder can tell apart — a key present, a key
//  absent, a key explicitly null, the order of an array — the comparison still sees.
//

import XCTest
@testable import DeckPlanCore

final class ModelTests: XCTestCase {

    /// `value` -> `T` -> JSON says the same thing, and the typed round trip is stable.
    @discardableResult
    func assertRoundTrips<T: JSONModel>(_ type: T.Type, _ value: JSONValue,
                                        _ label: String,
                                        file: StaticString = #filePath,
                                        line: UInt = #line) throws -> T {
        let model = try T(json: value)
        assertSameJSONText(try Canonical.dumps(model.json), try Canonical.dumps(value),
                           "\(T.self) \(label)", file: file, line: line)
        XCTAssertEqual(model, try T(json: model.json),
                       "\(T.self) \(label): the typed round trip is not stable",
                       file: file, line: line)
        return model
    }

    // MARK: - Curriculum

    func test_the_curriculum_samples_load_into_their_models() throws {
        for sample in ["examples/curriculum.stage1.sample.json",
                       "examples/curriculum.stage2.sample.json",
                       "examples/curriculum.stage4.sample.json"] {
            let value = try Repo.json(sample)
            let name = (sample as NSString).lastPathComponent

            let stage = try assertRoundTrips(Stage.self, try XCTUnwrap(value["stage"]), name)
            XCTAssertNotNil(stage.id)
            XCTAssertNotNil(stage.name)

            for skill in value["skills"]?.arrayValue ?? [] {
                let model = try assertRoundTrips(Skill.self, skill, name)
                for step in skill["steps"]?.arrayValue ?? [] {
                    try assertRoundTrips(Step.self, step, "\(name) \(model.id ?? "?")")
                    if let measure = step["measure"] {
                        try assertRoundTrips(Measure.self, measure, "\(name) measure")
                    }
                }
            }
            for activity in value["activities"]?.arrayValue ?? [] {
                try assertRoundTrips(Activity.self, activity, name)
            }
            for entry in value["equipment"]?.arrayValue ?? [] {
                try assertRoundTrips(Equipment.self, entry, name)
            }
            for topic in value["topics"]?.arrayValue ?? [] {
                try assertRoundTrips(Topic.self, topic, name)
            }
            for template in value["lessonTemplates"]?.arrayValue ?? [] {
                let model = try assertRoundTrips(LessonTemplate.self, template, name)
                for block in template["blocks"]?.arrayValue ?? [] {
                    try assertRoundTrips(Block.self, block, "\(name) template \(model.n ?? 0)")
                }
            }
            for row in value["trackerRows"]?.arrayValue ?? [] {
                try assertRoundTrips(TrackerRow.self, row, name)
            }
            for rule in value["safety"]?.arrayValue ?? [] {
                try assertRoundTrips(SafetyRule.self, rule, name)
            }
        }
    }

    func test_the_stage_1_sample_reads_as_the_curriculum_it_encodes() throws {
        let value = try Repo.json("examples/curriculum.stage1.sample.json")
        let stage = try Stage(json: try XCTUnwrap(value["stage"]))
        XCTAssertEqual("1", stage.id)
        XCTAssertEqual("Getting Comfortable", stage.name)
        XCTAssertEqual("Beginners", stage.group)
        XCTAssertEqual(30, stage.lessonMinutes)
        XCTAssertEqual("1.submerge", stage.warmUpSkill)
        XCTAssertEqual("1.jump-and-return", stage.wrapUpSkill)

        let skills = try (value["skills"]?.arrayValue ?? []).map(Skill.init(json:))
        XCTAssertEqual(9, skills.count)
        let frontGlide = try XCTUnwrap(skills.first { $0.id == "1.front-glide" })
        XCTAssertEqual("Front Glide", frontGlide.name)
        XCTAssertEqual(4, frontGlide.steps?.count)
        XCTAssertEqual("1.front-glide.4", frontGlide.benchmarkStepId)
        XCTAssertEqual(["B.front-tow.1", "B.front-tow.2"], frontGlide.prerequisiteStepIds)
        XCTAssertEqual(["2.front-glide.1", "2.front-glide.2", "2.front-glide.3",
                        "2.front-glide.4"], frontGlide.advancedStepIds)

        let step4 = try XCTUnwrap(frontGlide.steps?.last)
        XCTAssertEqual("1.front-glide.4", step4.id)
        XCTAssertEqual(4, step4.n)
        XCTAssertEqual("distance", step4.measure?.kind)
        XCTAssertEqual(5, step4.measure?.value)
        XCTAssertEqual("ft", step4.measure?.unit)
        XCTAssertEqual(["shallow"], step4.depths)
    }

    func test_a_skill_keeps_a_key_the_model_does_not_know() throws {
        // the samples carry `videoTitles` on some skills — not a docs/SPEC.md §7
        // field, and it must survive a load and a save all the same.
        let value = try Repo.json("examples/curriculum.stage1.sample.json")
        let withTitles = try XCTUnwrap((value["skills"]?.arrayValue ?? [])
            .first { $0["videoTitles"] != nil })
        let skill = try Skill(json: withTitles)
        XCTAssertNotNil(skill.extra["videoTitles"])
        XCTAssertEqual(withTitles["videoTitles"], skill.json["videoTitles"])
    }

    func test_a_null_field_stays_null_and_an_absent_one_stays_absent() throws {
        // docs/TEST_CASES.md A3: a skill the stage lists for review with no
        // progression has `benchmarkStepId` null — a key with no value.
        let withNull: JSONValue = ["id": "5.resting-stroke", "name": "Resting Stroke",
                                   "benchmarkStepId": .null]
        let skill = try assertRoundTrips(Skill.self, withNull, "a null benchmarkStepId")
        XCTAssertNil(skill.benchmarkStepId)
        XCTAssertEqual(JSONValue.null, skill.json["benchmarkStepId"])

        let without: JSONValue = ["id": "5.resting-stroke", "name": "Resting Stroke"]
        let bare = try assertRoundTrips(Skill.self, without, "no benchmarkStepId at all")
        XCTAssertNil(bare.json["benchmarkStepId"])
    }

    func test_the_videos_and_local_additions_of_the_mini_fixture() throws {
        for video in try Repo.json("tests/fixtures/curriculum_mini/videos.json").arrayValue ?? [] {
            try assertRoundTrips(Video.self, video, "curriculum_mini")
        }
        try assertRoundTrips(LocalAdditions.self,
                             try Repo.json("tests/fixtures/curriculum_mini/local.json"),
                             "curriculum_mini/local.json")
        for stage in Repo.jsonFiles(under: "tests/fixtures/curriculum_mini/stages") {
            try assertRoundTrips(Stage.self, try Repo.json(stage), stage)
        }
    }

    func test_the_real_curriculum_loads_into_the_models_when_it_is_present() throws {
        try Repo.requireCurriculumDirectory()
        for path in Repo.jsonFiles(under: "curriculum/stages") {
            try assertRoundTrips(Stage.self, try Repo.json(path), path)
        }
        for activity in try Repo.json("curriculum/activities.json").arrayValue ?? [] {
            try assertRoundTrips(Activity.self, activity, "curriculum/activities.json")
        }
        for entry in try Repo.json("curriculum/equipment.json").arrayValue ?? [] {
            try assertRoundTrips(Equipment.self, entry, "curriculum/equipment.json")
        }
        for video in try Repo.json("curriculum/videos.json").arrayValue ?? [] {
            try assertRoundTrips(Video.self, video, "curriculum/videos.json")
        }
        for rule in try Repo.json("curriculum/safety.json").arrayValue ?? [] {
            try assertRoundTrips(SafetyRule.self, rule, "curriculum/safety.json")
        }
        try assertRoundTrips(LocalAdditions.self, try Repo.json("curriculum/local.json"),
                             "curriculum/local.json")
    }

    func test_a_whole_Curriculum_round_trips() throws {
        let sample = try Repo.json("examples/curriculum.stage1.sample.json")
        let curriculum = Curriculum(
            version: sample["version"]?.stringValue,
            stages: [try Stage(json: try XCTUnwrap(sample["stage"]))],
            activities: try (sample["activities"]?.arrayValue ?? []).map(Activity.init(json:)),
            equipment: try (sample["equipment"]?.arrayValue ?? []).map(Equipment.init(json:)),
            videos: [],
            safety: try (sample["safety"]?.arrayValue ?? []).map(SafetyRule.init(json:)),
            local: .empty)
        XCTAssertEqual(curriculum, try Curriculum(json: curriculum.json))
        XCTAssertEqual("sample-2026.09", curriculum.version)

        // the empty local/1 object D9 hashes over (docs/CANONICAL_JSON.md, manifest D9)
        XCTAssertEqual("{\"activities\":[],\"equipment\":[],\"format\":\"local/1\"}",
                       try Canonical.dumps(LocalAdditions.empty.json))
    }

}
