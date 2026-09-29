//
//  FinderTests.swift
//  DeckPlanCoreTests
//
//  F1–F7: the activity finder, browse and search (docs/TEST_CASES.md group F) — the
//  Swift half of `tests/test_finder.py`, on the same fixtures; the finder
//  fixture is rebuilt from this port and held byte for byte.
//

import XCTest
@testable import DeckPlanCore

final class FinderTests: XCTestCase {

    static let frontGlideGuidePaired = ["puffin-rocket-ride", "meteor-torpedo", "comet-rocket-ride", "jellybean-express"]

    var curriculum: LoadedCurriculum!
    var pool: Pool!
    var expected: JSONValue!

    override func setUpWithError() throws {
        curriculum = Fixtures.sample()
        pool = try Fixtures.fixturePool()
        expected = try Fixtures.json("finder.stage1.expected.json")
    }

    func query(_ id: String) throws -> [FinderPage] {
        let queries = expected["queries"]?.arrayValue ?? []
        let pages = try XCTUnwrap(queries.first { $0["id"]?.stringValue == id }?["pages"]?.arrayValue)
        return try pages.map(FinderPage.init(json:))
    }

    func candidates(skillId: String? = nil, step: Int? = nil, ageTag: String? = nil,
                    file: StaticString = #filePath, line: UInt = #line) -> [String] {
        let (ordered, problems) = Finder.candidates(curriculum, stageId: "1", pool: pool, skillId: skillId,
                                                    step: step, ageTag: ageTag)
        XCTAssertEqual([], problems, file: file, line: line)
        return ordered
    }

    func find(skillId: String? = nil, step: Int? = nil, ageTag: String? = nil, page: Int = 1,
              file: StaticString = #filePath, line: UInt = #line) throws -> FinderPage {
        let (result, problems) = Finder.find(curriculum, stageId: "1", pool: pool, skillId: skillId, step: step,
                                             ageTag: ageTag, pageNumber: page)
        XCTAssertEqual([], problems, file: file, line: line)
        return try XCTUnwrap(result, file: file, line: line)
    }

    // MARK: - F1

    func test_F1_stage_only_seeded_paged_and_wrapping() throws {
        let ordered = candidates()
        XCTAssertEqual(68, ordered.count)  // 71 in the sample; volcano-ladder (depth), sunflower-home-base, kangaroo-voyage (kickboard)
        XCTAssertEqual(Set(ordered).count, ordered.count)
        for hidden in ["volcano-ladder", "sunflower-home-base", "kangaroo-voyage"] { XCTAssertFalse(ordered.contains(hidden), hidden) }
        XCTAssertEqual(ordered, candidates())
        let page1 = try find()
        let page2 = try find(page: 2)
        XCTAssertEqual(try query("stage"), [page1, page2])
        XCTAssertEqual(Array(ordered[0..<3]), page1.activityIds)
        XCTAssertEqual(Array(ordered[3..<6]), page2.activityIds)
        XCTAssertEqual(1, page1.page)
        XCTAssertEqual(3, page1.pageSize)
        XCTAssertEqual(68, page1.total)
        XCTAssertFalse(page1.wrapped)
        let last = (68 + 2) / 3
        let wrapped = try find(page: last + 1)
        XCTAssertTrue(wrapped.wrapped)
        XCTAssertEqual(page1.activityIds, wrapped.activityIds)  // page 1 again
        let final = try find(page: last)
        XCTAssertEqual(2, final.activityIds.count)  // 68 = 22 * 3 + 2
        XCTAssertFalse(final.wrapped)
        XCTAssertEqual(Finder.Slice(page: 1, pageSize: 3, total: 0, activityIds: [], wrapped: false),
                       Finder.page([], pageNumber: 1))
        XCTAssertEqual(["a", "b"], Finder.page(["a", "b"], pageNumber: 1).activityIds)
        XCTAssertEqual(["a", "b"], Finder.page(["a", "b"], pageNumber: 2).activityIds)
        XCTAssertTrue(Finder.page(["a", "b"], pageNumber: 2).wrapped)
        XCTAssertEqual(["d"], Finder.page(["a", "b", "c", "d"], pageNumber: 2).activityIds)
        XCTAssertEqual(["a", "b", "c"], Finder.page(["a", "b", "c", "d"], pageNumber: 3).activityIds)
    }

    // MARK: - F2

    func test_F2_stage_and_skill() throws {
        let ordered = candidates(skillId: "1.front-glide")
        let skillIds = Set(stringItems(curriculum.skill("1.front-glide")?["activityIds"]))
        XCTAssertEqual(skillIds, Set(ordered))
        XCTAssertEqual(12, ordered.count)
        XCTAssertEqual(try query("skill"), [try find(skillId: "1.front-glide"), try find(skillId: "1.front-glide", page: 2)])
        XCTAssertNotEqual(ordered, Array(candidates().prefix(12)))
        for (skillId, step, code) in [("2.front-glide", nil, "finder-skill"), ("1.front-glide", 9, "finder-step"),
                                      (nil, 2, "finder-step")] as [(String?, Int?, String)] {
            let (_, problems) = Finder.find(curriculum, stageId: "1", pool: pool, skillId: skillId, step: step)
            XCTAssertEqual([code], codes(problems), "\(String(describing: skillId)) \(String(describing: step))")
        }
        let (_, problems) = Finder.find(curriculum, stageId: "9", pool: pool)
        XCTAssertEqual(["finder-stage"], codes(problems))
    }

    // MARK: - F3

    func test_F3_a_step_puts_the_guide_paired_activities_first() throws {
        XCTAssertEqual(Self.frontGlideGuidePaired,
                       Finder.guidePaired(curriculum, stageId: "1", skillId: "1.front-glide", step: 2))
        let ordered = candidates(skillId: "1.front-glide", step: 2)
        XCTAssertEqual(Self.frontGlideGuidePaired, Array(ordered.prefix(4)))
        XCTAssertEqual(12, ordered.count)
        XCTAssertEqual(Set(stringItems(curriculum.skill("1.front-glide")?["activityIds"])), Set(ordered))
        let page1 = try find(skillId: "1.front-glide", step: 2)
        XCTAssertEqual(try query("skill-step"), [page1, try find(skillId: "1.front-glide", step: 2, page: 2)])
        XCTAssertEqual(stringItems(try Fixtures.manifestCase("F1.finder")["expected"]?["frontGlideStep2FirstPage"]),
                       page1.activityIds)
        // the remainder is seeded by the inputs, step included
        XCTAssertNotEqual(candidates(skillId: "1.front-glide"), ordered)
    }

    // MARK: - F4

    func test_F4_age_applies_only_from_a_class() throws {
        let allAges = candidates()
        let schoolAge = candidates(ageTag: "S")
        XCTAssertTrue(allAges.contains("snowflake-hide-and-seek"))
        XCTAssertFalse(schoolAge.contains("snowflake-hide-and-seek"))
        XCTAssertTrue(Set(schoolAge).isStrictSubset(of: Set(allAges)))
        let page1 = try find(skillId: "1.front-glide", ageTag: "S")
        XCTAssertEqual(try query("skill-age"), [page1, try find(skillId: "1.front-glide", ageTag: "S", page: 2)])
        XCTAssertEqual("S", page1.ageTag)
    }

    // MARK: - F5

    func test_F5_detail() throws {
        var withVideo = curriculum!
        withVideo.videos.append(["id": "vimeo:1", "skillIds": ["1.front-glide"], "stageIds": ["1"],
                                 "title": "Front glide", "url": "https://vimeo.com/1"])
        let item = try XCTUnwrap(Finder.detail(withVideo, activityId: "comet-rocket-ride", skillId: "1.front-glide"))
        XCTAssertEqual("Comet Rocket Ride", item.name)
        XCTAssertFalse(item.description.isEmpty)
        XCTAssertEqual(["pool noodle or rescue tube or rope"], item.equipment)
        XCTAssertEqual([], item.equipmentOptional)
        XCTAssertEqual(["P", "S", "A"], item.ages)
        XCTAssertTrue(item.submerges)
        XCTAssertEqual(["Front glide"], item.videos)
        XCTAssertEqual(["Front glide"], Finder.detail(withVideo, activityId: "comet-rocket-ride")?.videos)
        XCTAssertEqual([], Finder.detail(withVideo, activityId: "comet-rocket-ride", skillId: "1.submerge")?.videos)
        let straws = try XCTUnwrap(Finder.detail(withVideo, activityId: "submarine-peekaboo"))
        XCTAssertEqual(["straws"], straws.equipment)
        XCTAssertEqual(["ball", "whistle"], straws.equipmentOptional)
        XCTAssertNil(Finder.detail(withVideo, activityId: "no-such"))
    }

    // MARK: - F6

    func test_F6_browse() throws {
        let (browsed, problems) = Finder.browse(curriculum, stageId: "1", pool: pool)
        XCTAssertEqual([], problems)
        let result = try XCTUnwrap(browsed)
        XCTAssertEqual(try BrowseResult(json: try XCTUnwrap(expected["browse"])), result)
        XCTAssertEqual("Greeting", result.groups[0].name)
        XCTAssertNil(result.groups[0].skillId)
        XCTAssertEqual(curriculum.skillsOf("1").compactMap { $0["id"]?.stringValue },
                       result.groups.dropFirst().map { $0.skillId })
        XCTAssertEqual(try Fixtures.manifestCase("F1.finder")["expected"]?["browseGroupSizes"]?.arrayValue?.compactMap(\.intValue),
                       result.groups.map(\.activityIds.count))
        let position = Activities.catalogPosition(curriculum)
        for group in result.groups {
            let positions = group.activityIds.map { position[$0]! }
            XCTAssertEqual(positions.sorted(), positions, group.name)
        }
        let (adultsResult, _) = Finder.browse(curriculum, stageId: "1", pool: pool, ageTag: "A")
        let adults = try XCTUnwrap(adultsResult)
        let backFloat = try XCTUnwrap(adults.groups.first { $0.skillId == "1.back-float" })
        XCTAssertEqual([], backFloat.activityIds)  // its three activities are all P/S
        XCTAssertEqual(result.groups.count, adults.groups.count)
    }

    // MARK: - F7

    func test_F7_search_by_name_case_and_diacritic_insensitive_grouped_by_skill() throws {
        let (glideResult, problems) = Finder.search(curriculum, stageId: "1", pool: pool, text: "glide")
        XCTAssertEqual([], problems)
        let glide = try XCTUnwrap(glideResult)
        let expectedSearches = try (expected["search"]?.arrayValue ?? []).map(SearchResult.init(json:))
        XCTAssertEqual(3, expectedSearches.count)
        XCTAssertEqual(expectedSearches[0], glide)
        XCTAssertEqual(["1.front-glide", "1.back-glide"], glide.groups.map { $0.skillId })
        let (browsedResult, _) = Finder.browse(curriculum, stageId: "1", pool: pool)
        let browsed = try XCTUnwrap(browsedResult)
        for group in glide.groups {
            XCTAssertFalse(group.activityIds.isEmpty)
            for activityId in group.activityIds {
                XCTAssertTrue(try XCTUnwrap(curriculum.activity(activityId)?["name"]?.stringValue).lowercased().contains("glide"))
            }
            let shown = try XCTUnwrap(browsed.groups.first { $0.skillId == group.skillId }).activityIds
            XCTAssertEqual(shown.filter { curriculum.activity($0)?["name"]?.stringValue?.lowercased().contains("glide") == true },
                           group.activityIds)
        }
        let (upper, _) = Finder.search(curriculum, stageId: "1", pool: pool, text: "GLIDE")
        XCTAssertEqual(glide.groups, upper?.groups)
        XCTAssertEqual(expectedSearches[1], upper)
        let (accented, _) = Finder.search(curriculum, stageId: "1", pool: pool, text: "glidé")
        XCTAssertEqual(glide.groups, accented?.groups)
        let (padded, _) = Finder.search(curriculum, stageId: "1", pool: pool, text: "  glide ")
        XCTAssertEqual(glide.groups, padded?.groups)
        for text in ["zzz", "", "   "] {
            let (result, noProblems) = Finder.search(curriculum, stageId: "1", pool: pool, text: text)
            XCTAssertEqual([], noProblems)
            XCTAssertEqual([], result?.groups, text)
        }
        XCTAssertEqual(expectedSearches[2], Finder.search(curriculum, stageId: "1", pool: pool, text: "zzz").0)
        let manifestGroups = try XCTUnwrap(try Fixtures.manifestCase("F7.search")["expected"]?["groups"]?.arrayValue)
        XCTAssertEqual(manifestGroups[0].arrayValue?.map { stringItems($0["activityIds"]) }, glide.groups.map(\.activityIds))
        XCTAssertEqual([], manifestGroups[2].arrayValue ?? [.null])
        // the age tag applies as in browse
        let (adults, _) = Finder.search(curriculum, stageId: "1", pool: pool, text: "float", ageTag: "A")
        XCTAssertFalse((adults?.groups ?? []).contains { $0.skillId == "1.back-float" })  // its activities are all P/S
        XCTAssertEqual("flotte", Finder.fold("FLOTTÉ"))
        let (none, stageProblems) = Finder.search(curriculum, stageId: "9", pool: pool, text: "glide")
        XCTAssertNil(none)
        XCTAssertEqual(["finder-stage"], codes(stageProblems))
    }

    // MARK: - the fixture, rebuilt from this port

    func test_the_finder_fixture_is_reproduced_byte_for_byte_and_its_hash_matches() throws {
        let queries: [(id: String, skillId: String?, step: Int?, ageTag: String?)] = [
            ("stage", nil, nil, nil),
            ("skill", "1.front-glide", nil, nil),
            ("skill-step", "1.front-glide", 2, nil),
            ("skill-age", "1.front-glide", nil, "S"),
        ]
        var results: [JSONValue] = []
        for query in queries {
            let pages = try [1, 2].map { try find(skillId: query.skillId, step: query.step, ageTag: query.ageTag, page: $0).json }
            results.append(.object(["id": .string(query.id), "pages": .array(pages)]))
        }
        let (browsed, _) = Finder.browse(curriculum, stageId: "1", pool: pool)
        let searches = try ["glide", "GLIDE", "zzz"].map { text in
            try XCTUnwrap(Finder.search(curriculum, stageId: "1", pool: pool, text: text).0).json
        }
        let document: JSONValue = .object(["stageId": .string("1"), "queries": .array(results),
                                           "browse": try XCTUnwrap(browsed).json, "search": .array(searches)])
        let text = try Canonical.dumps(document) + "\n"
        assertSameJSONText(text, try Fixtures.text("finder.stage1.expected.json"), "finder fixture")
        XCTAssertEqual(try Fixtures.manifestCase("F1.finder")["expected"]?["sha256"]?.stringValue,
                       Canonical.sha256Hex(text))
        let expected = try XCTUnwrap(try Fixtures.manifestCase("F1.finder")["expected"])
        XCTAssertEqual(expected["stageTotal"]?.intValue, try find().total)
        XCTAssertEqual(expected["frontGlideTotal"]?.intValue, try find(skillId: "1.front-glide").total)
    }
}
