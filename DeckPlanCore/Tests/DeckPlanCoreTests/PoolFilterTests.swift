//
//  PoolFilterTests.swift
//  DeckPlanCoreTests
//
//  P1–P6: the pool profile, the one filter and the profile items
//  (docs/TEST_CASES.md group P) — the Swift half of `tests/test_pool.py`, on
//  the same fixtures.
//

import XCTest
@testable import DeckPlanCore

final class PoolFilterTests: XCTestCase {

    static let profileSample = ["pool-noodle", "kickboard", "hoop", "small-toys", "ball"]
    static let profileLibrary = ["pool-noodle", "kickboard", "hoop", "small-toys", "pull-buoy"]

    var curriculum: LoadedCurriculum!
    var pool: Pool!

    override func setUpWithError() throws {
        curriculum = Fixtures.sample()
        pool = try Fixtures.fixturePool()
    }

    func activity(_ id: String) throws -> JSONValue {
        try XCTUnwrap(curriculum.activity(id), "the sample has \(id)")
    }

    func with(_ pool: Pool, depths: [String: Bool]? = nil, diving: Bool? = nil,
              equipment: [String: Bool] = [:]) -> Pool {
        var changed = pool
        if let depths { changed.depths = depths }
        if let diving { changed.diving = diving }
        for (item, on) in equipment { changed.equipment[item] = on }
        return changed
    }

    func hiddenKind(_ activity: JSONValue, _ pool: Pool, ageTag: String? = nil) -> String? {
        switch Activities.hiddenReason(activity, pool: pool, curriculum: curriculum, ageTag: ageTag) {
        case .equipment?: return "equipment"
        case .depth?: return "depth"
        case .diving?: return "diving"
        case .age?: return "age"
        case nil: return nil
        }
    }

    // MARK: - P1

    func test_P1_default_profile_has_everything_on_and_one_key_per_profile_item() {
        let pool = Activities.defaultPool(curriculum)
        XCTAssertEqual(["shallow": true, "medium": true, "deep": true], pool.depths)
        XCTAssertTrue(pool.diving)
        XCTAssertTrue(pool.totDock)
        XCTAssertEqual(Set(Self.profileSample), Set(pool.equipment.keys))
        XCTAssertNil(pool.equipment["flotation-device"])
        XCTAssertNil(pool.equipment["goggles"])  // a prop
        XCTAssertTrue(pool.equipment.values.allSatisfy { $0 })
    }

    func test_P1_missing_keys_read_as_off_and_prop_and_unknown_keys_are_dropped() throws {
        let partial: JSONValue = ["equipment": ["kickboard": 1, "jetpack": true, "goggles": false],
                                  "depths": ["shallow": true]]
        let pool = Activities.normalizePool(partial, curriculum)
        XCTAssertEqual(["shallow": true, "medium": false, "deep": false], pool.depths)
        XCTAssertFalse(pool.diving)
        XCTAssertFalse(pool.totDock)
        XCTAssertEqual(true, pool.equipment["kickboard"])
        XCTAssertEqual(false, pool.equipment["pool-noodle"])
        XCTAssertNil(pool.equipment["jetpack"])
        XCTAssertNil(pool.equipment["goggles"])
        XCTAssertEqual(Set(Self.profileSample), Set(pool.equipment.keys))
        XCTAssertEqual(Activities.normalizePool(nil, curriculum), Activities.normalizePool(.object([:]), curriculum))
        XCTAssertEqual(Activities.normalizePool(Pool(), curriculum), Activities.normalizePool(nil, curriculum))
        // the fixture pool is already in shape
        XCTAssertEqual(try Fixtures.fixturePool(), Activities.normalizePool(try Fixtures.fixturePool(), curriculum))
        // a stored profile's own missing keys read as off too
        XCTAssertFalse(Activities.depthOn(Pool(), "shallow"))
        XCTAssertFalse(Activities.isOn(Pool(), "kickboard", curriculum))
    }

    // MARK: - P6

    func test_P6_profile_items_are_the_five_most_required_in_catalog_order() throws {
        XCTAssertEqual(Self.profileSample, Activities.profileItems(curriculum))
        XCTAssertEqual(stringItems(try Fixtures.manifestCase("P6.profile")["expected"]?["profileItems"]), Self.profileSample)
        let counts = Activities.requirementCounts(curriculum.activities, catalog: curriculum.equipment)
        XCTAssertEqual(counts["ball"], counts["float-belt"])  // ball wins its tie by catalog order
        let catalog = Activities.catalogItems(curriculum.equipment)
        XCTAssertLessThan(try XCTUnwrap(catalog.firstIndex(of: "ball")), try XCTUnwrap(catalog.firstIndex(of: "float-belt")))
        let fifth = try XCTUnwrap(Self.profileSample.map { counts[$0] ?? 0 }.min())
        for item in catalog where !Self.profileSample.contains(item) {
            XCTAssertLessThanOrEqual(counts[item] ?? 0, fifth, item)
        }
        XCTAssertTrue(Activities.isProp(curriculum, "goggles"))
        XCTAssertTrue(Activities.isProp(curriculum, "life-jacket"))
        XCTAssertFalse(Activities.isProp(curriculum, "kickboard"))
        XCTAssertFalse(Activities.isProp(curriculum, "flotation-device"))  // a group, not an item
        XCTAssertFalse(Activities.isProp(curriculum, "no-such-thing"))
        // a group requirement counts toward each of its anyOf members, once per activity
        let needsGroup = try XCTUnwrap(curriculum.activities.first { activity in
            (activity["equipment"]?.arrayValue ?? []).contains { stringItems($0) == ["flotation-device"] }
        })
        let group = try XCTUnwrap(curriculum.equipmentEntry("flotation-device"))
        let only = Activities.requirementCounts([needsGroup], catalog: curriculum.equipment)
        for item in stringItems(group["anyOf"]) {
            XCTAssertEqual(1, only[item], item)
        }
        let twice = Activities.requirementCounts([["equipment": [["kickboard"], ["kickboard"], ["kickboard", "hoop"]]]],
                                                 catalog: curriculum.equipment)
        XCTAssertEqual(["kickboard": 1], twice)
    }

    func test_P6_the_full_library() throws {
        guard Repo.exists("curriculum/equipment.json") else {
            throw XCTSkip("curriculum/ is not checked out (copyright, v1 D20)")
        }
        let library = CurriculumLoader.load(directory: Repo.url("curriculum"))
        XCTAssertTrue(Problem.errors(CurriculumValidator.validate(library)).isEmpty)
        XCTAssertEqual(Self.profileLibrary, Activities.profileItems(library))
    }

    // MARK: - P2

    func test_P2_a_required_group_with_nothing_on_hides_optional_never_does() throws {
        let everything = Activities.defaultPool(curriculum)
        let nap = try activity("kangaroo-voyage")          // [["kickboard"]]
        let chest = try activity("sunflower-home-base")       // [["small-toys"], ["kickboard"]]
        XCTAssertNil(Activities.hiddenReason(nap, pool: everything, curriculum: curriculum))
        let off = with(everything, equipment: ["kickboard": false])
        XCTAssertEqual(.equipment(missing: [["kickboard"]]), Activities.hiddenReason(nap, pool: off, curriculum: curriculum))
        XCTAssertEqual("equipment", hiddenKind(chest, off))
        XCTAssertEqual("equipment", hiddenKind(nap, pool))  // the fixture pool
        // optional equipment never hides
        let superhero = try activity("dragon-launch")  // optional kickboard, no requirement
        XCTAssertEqual([], superhero["equipment"]?.arrayValue ?? [])
        XCTAssertNil(Activities.hiddenReason(superhero, pool: off, curriculum: curriculum))
    }

    func test_P2_a_prop_never_hides() throws {
        let everything = Activities.defaultPool(curriculum)
        let straws = try activity("submarine-peekaboo")  // [["straws"]], a prop
        XCTAssertNil(Activities.hiddenReason(straws, pool: everything, curriculum: curriculum))
        let propsOff = with(everything, equipment: ["straws": false, "goggles": false])
        XCTAssertNil(Activities.hiddenReason(straws, pool: propsOff, curriculum: curriculum))
        XCTAssertTrue(Activities.isOn(propsOff, "straws", curriculum))
        XCTAssertTrue(Activities.isOn(Pool(), "goggles", curriculum))
        XCTAssertFalse(Activities.isOn(Pool(), "kickboard", curriculum))  // a missing profile key is off
        // with nothing on, an activity is hidden for equipment exactly when a group offers no prop at all
        let profile = Set(Activities.profileItems(curriculum))
        func profileOnly(_ group: [String]) -> Bool {
            for item in group {
                guard let entry = curriculum.equipmentEntry(item) else { continue }
                if entry["kind"]?.stringValue == "item", !profile.contains(item) { return false }
                if entry["kind"]?.stringValue == "group",
                   stringItems(entry["anyOf"]).contains(where: { !profile.contains($0) }) { return false }
            }
            return true
        }
        var hiddenForEquipment = 0
        for activity in curriculum.activities {
            let expected = (activity["equipment"]?.arrayValue ?? []).contains { profileOnly(stringItems($0)) }
            XCTAssertEqual(expected, hiddenKind(activity, Pool()) == "equipment", activity["id"]?.stringValue ?? "?")
            if expected { hiddenForEquipment += 1 }
        }
        XCTAssertTrue(hiddenForEquipment > 0 && hiddenForEquipment < curriculum.activities.count)
    }

    func test_P2_a_group_entry_is_on_when_any_of_its_items_is() throws {
        let everything = Activities.defaultPool(curriculum)
        let group = try XCTUnwrap(curriculum.equipmentEntry("flotation-device"))
        let anyOf = stringItems(group["anyOf"])
        let needsGroup = curriculum.activities.filter { activity in
            (activity["equipment"]?.arrayValue ?? []).contains { stringItems($0) == ["flotation-device"] }
        }
        XCTAssertFalse(needsGroup.isEmpty, "the sample has an activity that needs a flotation device")
        let activity = needsGroup[0]
        let profileMembers = anyOf.filter { everything.equipment[$0] != nil }
        let propMembers = anyOf.filter { everything.equipment[$0] == nil }
        XCTAssertFalse(profileMembers.isEmpty || propMembers.isEmpty, "the group mixes profile items and props")
        var noneOn = everything
        for key in everything.equipment.keys { noneOn.equipment[key] = !anyOf.contains(key) }
        // a prop member (float belt, life jacket) is always on, so the group is on and nothing hides
        XCTAssertTrue(Activities.isOn(noneOn, "flotation-device", curriculum))
        XCTAssertNil(Activities.hiddenReason(activity, pool: noneOn, curriculum: curriculum))
        XCTAssertFalse(Activities.isOn(noneOn, "no-such-thing", curriculum))
        // a group of profile items only
        let onlyProfile: JSONValue = ["id": "x", "equipment": [["kickboard", "pool-noodle"]]]
        let bothOff = with(noneOn, equipment: ["kickboard": false])
        XCTAssertEqual(.equipment(missing: [["kickboard", "pool-noodle"]]),
                       Activities.hiddenReason(onlyProfile, pool: bothOff, curriculum: curriculum))
        XCTAssertNil(Activities.hiddenReason(onlyProfile, pool: with(bothOff, equipment: ["kickboard": true]),
                                             curriculum: curriculum))
    }

    // MARK: - P3

    func test_P3_depth_and_diving() throws {
        let hoopJump = try activity("volcano-ladder")     // depths medium, deep
        let shark = try activity("iceberg-climb")    // depths shallow
        let plain = try activity("heron-roll-call")        // no depths
        XCTAssertEqual(.depth(["medium", "deep"]), Activities.hiddenReason(hoopJump, pool: pool, curriculum: curriculum))
        XCTAssertNil(Activities.hiddenReason(shark, pool: pool, curriculum: curriculum))
        let allDepthsOff = with(pool, depths: ["shallow": false, "medium": false, "deep": false])
        XCTAssertNil(Activities.hiddenReason(plain, pool: allDepthsOff, curriculum: curriculum))
        let deepOn = with(pool, depths: ["shallow": true, "medium": false, "deep": true])
        XCTAssertNil(Activities.hiddenReason(hoopJump, pool: deepOn, curriculum: curriculum))
        let dive: JSONValue = ["id": "x-dive", "name": "Dive", "ages": [], "depths": ["deep"], "headfirst": true]
        XCTAssertEqual(.diving, Activities.hiddenReason(dive, pool: deepOn, curriculum: curriculum))
        XCTAssertEqual(.depth(["deep"]), Activities.hiddenReason(dive, pool: pool, curriculum: curriculum))
        XCTAssertNil(Activities.hiddenReason(dive, pool: with(deepOn, diving: true), curriculum: curriculum))
    }

    // MARK: - P4

    func test_P4_plan_shuffle_finder_search_and_browse_produce_nothing_the_filter_rejects() throws {
        let swimClass = try Fixtures.fixtureClass()
        let age = Activities.ageTag(swimClass.ageGroup)
        let everything = Activities.defaultPool(curriculum)
        let propsOff = with(everything, equipment: ["goggles": false, "life-jacket": false, "straws": false])
        func shownIds(_ pool: Pool) -> Set<String> {
            Set(Activities.poolFilter(curriculum.activities, pool: pool, curriculum: curriculum, ageTag: age)
                .compactMap { $0["id"]?.stringValue })
        }
        for pool in [pool!, Activities.normalizePool(nil, curriculum), everything, propsOff] {
            let label = "\(pool.equipment.filter { !$0.value }.keys.sorted()) \(pool.depths)"
            let shown = shownIds(pool)
            let (plan, problems) = DayPlans.planDay(curriculum, swimClass: swimClass, pool: pool, n: 5)
            XCTAssertEqual([], problems, label)
            for block in plan?.blocks ?? [] {
                XCTAssertTrue(Set(block.activityIds).isSubset(of: shown), "\(label) \(block.kind)")
            }
            let (picked, _) = DayPlans.pickSkill(curriculum, swimClass: swimClass, pool: pool, n: 5,
                                                 kind: "introduce", skillId: "1.roll")
            let (_, result, _) = DayPlans.shuffle(curriculum, swimClass: picked, pool: pool, n: 5, kind: "warmUp")
            if let result {
                XCTAssertTrue(Set(result.activityIds).isSubset(of: shown), label)
            }
            let (found, _) = Finder.find(curriculum, stageId: "1", pool: pool, ageTag: age)
            XCTAssertTrue(Set(found?.activityIds ?? []).isSubset(of: shown), label)
            let (browsed, _) = Finder.browse(curriculum, stageId: "1", pool: pool, ageTag: age)
            for group in browsed?.groups ?? [] {
                XCTAssertTrue(Set(group.activityIds).isSubset(of: shown), "\(label) \(group.name)")
            }
            let (searched, _) = Finder.search(curriculum, stageId: "1", pool: pool, text: "a", ageTag: age)
            for group in searched?.groups ?? [] {
                XCTAssertTrue(Set(group.activityIds).isSubset(of: shown), "\(label) \(group.name)")
            }
        }
        // a prop's toggle changes nothing anywhere
        XCTAssertEqual(shownIds(everything), shownIds(propsOff))
        XCTAssertEqual(Finder.browse(curriculum, stageId: "1", pool: everything, ageTag: age).0,
                       Finder.browse(curriculum, stageId: "1", pool: propsOff, ageTag: age).0)
        XCTAssertEqual(DayPlans.planDay(curriculum, swimClass: swimClass, pool: everything, n: 5).0,
                       DayPlans.planDay(curriculum, swimClass: swimClass, pool: propsOff, n: 5).0)
    }

    // MARK: - P5

    func test_P5_age() throws {
        XCTAssertEqual("P", Activities.ageTag("preschool"))
        XCTAssertEqual("S", Activities.ageTag("schoolAge"))
        XCTAssertEqual("A", Activities.ageTag("teen"))
        XCTAssertEqual("A", Activities.ageTag("adult"))
        XCTAssertNil(Activities.ageTag("infantToddler"))
        XCTAssertNil(Activities.ageTag(nil))
        let magicSoap = try activity("snowflake-hide-and-seek")   // ["P"]
        let everything = Activities.defaultPool(curriculum)
        XCTAssertEqual(.age(["P"]), Activities.hiddenReason(magicSoap, pool: everything, curriculum: curriculum, ageTag: "S"))
        XCTAssertNil(Activities.hiddenReason(magicSoap, pool: everything, curriculum: curriculum, ageTag: "P"))
        XCTAssertNil(Activities.hiddenReason(magicSoap, pool: everything, curriculum: curriculum, ageTag: nil))
        let noAges = try activity("tugboat-hello")
        XCTAssertEqual([], stringItems(noAges["ages"]))
        for tag in Ids.ageTags {
            XCTAssertNil(Activities.hiddenReason(noAges, pool: everything, curriculum: curriculum, ageTag: tag))
        }
    }
}
