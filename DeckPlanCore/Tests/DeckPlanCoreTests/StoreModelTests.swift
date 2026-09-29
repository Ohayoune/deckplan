//
//  StoreModelTests.swift
//  DeckPlanCoreTests
//
//  The v2 store and plan records (docs/TEST_CASES.md S1; docs/REDESIGN.md §2,
//  §6), loaded from the fixtures and written back byte for byte — the shapes
//  `tools/core/classes.py`, `day_plan.py` and `finder.py` write.
//

import XCTest
@testable import DeckPlanCore

final class StoreModelTests: XCTestCase {

    /// `value` -> `T` -> JSON says the same thing, and the typed round trip is stable.
    @discardableResult
    private func roundTrip<T: JSONModel>(_ type: T.Type, _ value: JSONValue, _ label: String,
                                         file: StaticString = #filePath, line: UInt = #line) throws -> T {
        let model = try T(json: value)
        assertSameJSONText(try Canonical.dumps(model.json), try Canonical.dumps(value),
                           "\(T.self) \(label)", file: file, line: line)
        XCTAssertEqual(model, try T(json: model.json), "\(T.self) \(label): the typed round trip is not stable",
                       file: file, line: line)
        return model
    }

    // MARK: - S1: the store's records

    func test_S1_the_class_fixture_decodes_and_re_encodes_byte_identical() throws {
        let text = try Fixtures.text("class.stage1.json")
        let file = try Fixtures.json("class.stage1.json")
        XCTAssertEqual("classes/1", file["format"]?.stringValue)
        let items = try XCTUnwrap(file["items"]?.arrayValue)
        XCTAssertEqual(1, items.count)
        let swimClass = try roundTrip(SwimClass.self, items[0], "class.stage1.json")
        let rebuilt: JSONValue = .object(["format": .string("classes/1"), "items": .array([swimClass.json])])
        assertSameJSONText(try Canonical.dumps(rebuilt) + "\n", text, "class.stage1.json")

        XCTAssertEqual("c-stage1-mw", swimClass.id)
        XCTAssertEqual("Stage 1 · Mon Wed", swimClass.name)
        XCTAssertEqual("1", swimClass.stageId)
        XCTAssertEqual("schoolAge", swimClass.ageGroup)
        XCTAssertEqual(8, swimClass.lessons)
        XCTAssertEqual(1, swimClass.order)
        XCTAssertEqual(ClassSchedule(weekdays: ["mon", "wed"], firstDate: "2026-09-14"), swimClass.schedule)
        XCTAssertEqual([1, 2, 3, 4], swimClass.log.map(\.n))
        XCTAssertEqual("2026-09-23", swimClass.log[3].date)
        XCTAssertEqual(["welcome", "warmUp", "review", "introduce", "topic", "wrapUp"],
                       swimClass.log[0].blocks.map(\.kind))
        XCTAssertNil(swimClass.draft)
        XCTAssertEqual(JSONValue.null, swimClass.json["draft"], "a class without a draft still writes the key")
    }

    func test_S1_the_pool_fixture_decodes_and_re_encodes_byte_identical() throws {
        let text = try Fixtures.text("pool.shallow.json")
        let pool = try roundTrip(Pool.self, try Fixtures.firstItem("pool.shallow.json"), "pool.shallow.json")
        let rebuilt: JSONValue = .object(["format": .string("pool/1"), "items": .array([pool.json])])
        assertSameJSONText(try Canonical.dumps(rebuilt) + "\n", text, "pool.shallow.json")
        XCTAssertEqual(["shallow": true, "medium": false, "deep": false], pool.depths)
        XCTAssertFalse(pool.diving)
        XCTAssertTrue(pool.totDock)
        XCTAssertEqual(false, pool.equipment["kickboard"])
        XCTAssertEqual(true, pool.equipment["pool-noodle"])
        XCTAssertNil(pool.equipment["life-jacket"], "a prop is not in the profile (P6)")
        XCTAssertNil(pool.equipment["flotation-device"], "a profile has one key per profile item, never a group")
        XCTAssertEqual(5, pool.equipment.count)
    }

    func test_S1_a_draft_round_trips_and_a_missing_required_field_is_reported() throws {
        var swimClass = try Fixtures.fixtureClass()
        swimClass.draft = Draft(n: 5, blocks: [DraftBlock(kind: "introduce", skillIds: ["1.roll"],
                                                          activityIds: ["dragon-roll"])],
                                shuffleCounts: ["warmUp": 2])
        let reread = try SwimClass(json: swimClass.json)
        XCTAssertEqual(swimClass, reread)
        XCTAssertEqual(["warmUp": 2], reread.draft?.shuffleCounts)
        XCTAssertEqual("{\"blocks\":[{\"activityIds\":[\"dragon-roll\"],\"kind\":\"introduce\",\"skillIds\":[\"1.roll\"]}],"
                       + "\"n\":5,\"shuffleCounts\":{\"warmUp\":2}}",
                       try Canonical.dumps(try XCTUnwrap(swimClass.draft).json))

        var fields = try XCTUnwrap(try Fixtures.firstItem("class.stage1.json").objectValue)
        fields.removeValue(forKey: "schedule")
        XCTAssertThrowsError(try SwimClass(json: .object(fields))) { error in
            XCTAssertEqual(JSONModelError.missingField(type: "SwimClass", field: "schedule"),
                           error as? JSONModelError)
        }
        XCTAssertThrowsError(try Pool(json: ["diving": false, "totDock": true, "equipment": [:]]))
    }

    func test_S1_settings_keep_whatever_they_hold() throws {
        let settings = try roundTrip(Settings.self, ["theme": "light", "lastOpened": "c-stage1-mw"], "settings")
        XCTAssertEqual(.string("light"), settings.extra["theme"])
        XCTAssertEqual(Settings(), try Settings(json: [:]))
        XCTAssertNil(settings.finderStageId)
        XCTAssertNil(settings.json["finderStageId"], "absent until the finder is used (V5)")
        var remembered = settings
        remembered.finderStageId = "2"
        XCTAssertEqual(.string("2"), remembered.json["finderStageId"])
        XCTAssertEqual("2", try Settings(json: remembered.json).finderStageId)
        XCTAssertEqual(.string("light"), try Settings(json: remembered.json).extra["theme"])
    }

    // MARK: - The plan and finder records (their JSON is the Python's)

    func test_the_day_plan_fixture_loads_into_DayPlan_and_re_encodes_byte_for_byte() throws {
        let text = try Fixtures.text("day-plan.stage1.day5.expected.json")
        let plan = try roundTrip(DayPlan.self, try Fixtures.json("day-plan.stage1.day5.expected.json"), "day 5")
        assertSameJSONText(try DayPlans.planJSON(plan) + "\n", text, "day-plan.stage1.day5.expected.json")
        XCTAssertEqual(5, plan.guideLesson)
        XCTAssertEqual("2026-09-28", plan.date)
        XCTAssertFalse(plan.saved)
        XCTAssertFalse(plan.draft)
        let introduce = try XCTUnwrap(plan.block("introduce"))
        XCTAssertTrue(introduce.awaitsPick)
        XCTAssertEqual(9, introduce.skillChoices?.count)
        XCTAssertNil(plan.block("review")?.skillChoices)
        XCTAssertEqual("Being Kind", plan.block("topic")?.topic?.name)
        XCTAssertEqual([1, 4], plan.block("warmUp")?.stepRange)
        XCTAssertNil(plan.block("topic")?.notes)
    }

    func test_the_shuffle_and_finder_fixtures_load_into_their_records() throws {
        let shuffle = try Fixtures.json("shuffle.stage1.day5.expected.json")
        for page in shuffle["warmUp"]?.arrayValue ?? [] {
            try roundTrip(ShuffleResult.self, page, "warmUp shuffle")
        }
        let review = try roundTrip(ShuffleResult.self, try XCTUnwrap(shuffle["review"]), "review shuffle")
        XCTAssertNil(review.message)
        XCTAssertEqual(1, review.activityIds.count)  // one shown, one drawn (D10)

        let finder = try Fixtures.json("finder.stage1.expected.json")
        for query in finder["queries"]?.arrayValue ?? [] {
            for page in query["pages"]?.arrayValue ?? [] {
                let model = try roundTrip(FinderPage.self, page, query["id"]?.stringValue ?? "?")
                XCTAssertEqual("1", model.stageId)
            }
        }
        let browse = try roundTrip(BrowseResult.self, try XCTUnwrap(finder["browse"]), "browse")
        XCTAssertEqual("Greeting", browse.groups.first?.name)
        XCTAssertNil(browse.groups.first?.skillId)
        XCTAssertNil(browse.ageTag)
        XCTAssertEqual(JSONValue.null, browse.json["ageTag"], "a null input is written as null, as the Python does")
        let searches = try (finder["search"]?.arrayValue ?? []).map { try roundTrip(SearchResult.self, $0, "search") }
        XCTAssertEqual(["glide", "GLIDE", "zzz"], searches.map(\.text))
        XCTAssertEqual([2, 2, 0], searches.map(\.groups.count))
    }
}
