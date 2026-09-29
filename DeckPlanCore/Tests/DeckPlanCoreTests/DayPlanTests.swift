//
//  DayPlanTests.swift
//  DeckPlanCoreTests
//
//  C5 (extra days), D1–D10: today's plan, shuffle, edits, save, revisit
//  (docs/TEST_CASES.md group D) — the Swift half of `tests/test_day_plan.py`,
//  on the same fixtures; D9 holds the Python's bytes.
//

import XCTest
@testable import DeckPlanCore

let reviewDay5Guide = ["koala-snooze", "walrus-lounge", "lobster-balance", "popcorn-glide", "koala-launch",
                       "walrus-torpedo", "robot-express"]

final class DayPlanTests: XCTestCase {

    var curriculum: LoadedCurriculum!
    var swimClass: SwimClass!
    var pool: Pool!
    var age: String?

    override func setUpWithError() throws {
        curriculum = Fixtures.sample()
        swimClass = try Fixtures.fixtureClass()
        pool = try Fixtures.fixturePool()
        age = Activities.ageTag(swimClass.ageGroup)
    }

    func plan(_ n: Int = 5, swimClass: SwimClass? = nil, pool: Pool? = nil,
              file: StaticString = #filePath, line: UInt = #line) throws -> DayPlan {
        let (plan, problems) = DayPlans.planDay(curriculum, swimClass: swimClass ?? self.swimClass,
                                                pool: pool ?? self.pool, n: n)
        XCTAssertEqual([], problems, file: file, line: line)
        return try XCTUnwrap(plan, file: file, line: line)
    }

    func block(_ plan: DayPlan, _ kind: String, file: StaticString = #filePath, line: UInt = #line) throws -> PlanBlock {
        try XCTUnwrap(plan.block(kind), kind, file: file, line: line)
    }

    /// D2's full list for a block of the fixture class's day `n`.
    func candidates(_ n: Int, _ kind: String, file: StaticString = #filePath, line: UInt = #line) throws -> [String] {
        let templateBlock = try XCTUnwrap(DayPlans.templateBlock(curriculum, swimClass: swimClass, n: n, kind: kind),
                                          kind, file: file, line: line)
        return DayPlans.blockCandidates(curriculum, templateBlock: templateBlock, pool: pool, ageTag: age)
    }

    /// The fixture class with day 4's review re-logged as `activityIds`.
    func withDay4Review(_ activityIds: [String]) -> SwimClass {
        Classes.withLogEntry(swimClass, LogEntry(n: 4, date: "2026-09-23",
                                                 blocks: [LogBlock(kind: "review", activityIds: activityIds)]))
    }

    func reviewIds(_ swimClass: SwimClass, n: Int = 5) throws -> ([String], DayPlan) {
        let plan = try plan(n, swimClass: swimClass)
        return (try block(plan, "review").activityIds, plan)
    }

    // MARK: - D1–D3, D10, C5, D9

    func test_D1_day5_is_guide_lesson_5_block_by_block() throws {
        let plan = try plan()
        XCTAssertEqual("c-stage1-mw", plan.classId)
        XCTAssertEqual(5, plan.n)
        XCTAssertEqual("2026-09-28", plan.date)
        XCTAssertEqual(5, plan.guideLesson)
        XCTAssertFalse(plan.saved)
        XCTAssertFalse(plan.draft)
        XCTAssertEqual(["welcome", "warmUp", "review", "introduce", "topic", "wrapUp"], plan.blocks.map(\.kind))
        XCTAssertEqual([2, 3, 5, 10, 5, 5], plan.blocks.map(\.minutes))
        XCTAssertEqual(["1.front-float", "1.back-glide"], try block(plan, "review").skillIds)
        XCTAssertEqual([1, 4], try block(plan, "review").stepRange)
        let topic = try block(plan, "topic")
        XCTAssertEqual("1.5", topic.topicCode)
        XCTAssertEqual("Being Kind", topic.topic?.name)
        XCTAssertEqual([], topic.activityIds)
        XCTAssertTrue(try block(plan, "welcome").notes?.contains("Check in with quieter swimmers.") == true)
    }

    func test_D2_block_candidates_guide_first_then_skills_in_catalog_order_filtered() throws {
        let review = try candidates(5, "review")
        XCTAssertEqual(reviewDay5Guide, review)  // the guide names every shown activity of both skills
        XCTAssertEqual(Set(review), Set(review).intersection(Activities.skillActivityIds(curriculum, ["1.front-float", "1.back-glide"])))
        let warmUp = try candidates(5, "warmUp")
        XCTAssertEqual(["otter-bubbles", "rainbow-treasure-hunt"], Array(warmUp.prefix(2)))  // snowflake-hide-and-seek hidden (P only)
        for hidden in ["snowflake-hide-and-seek", "iceberg-bubble-party", "submarine-peekaboo"] {
            XCTAssertFalse(warmUp.contains(hidden), hidden)
        }
        XCTAssertTrue(Activities.library(curriculum, "1").contains("submarine-peekaboo"))  // hidden by age, not its prop
        let rest = Array(warmUp.dropFirst(2))
        XCTAssertFalse(rest.isEmpty)
        XCTAssertTrue(Set(rest).isSubset(of: Activities.skillActivityIds(curriculum, ["1.submerge"])))
        let position = Activities.catalogPosition(curriculum)
        let positions = rest.map { position[$0]! }
        XCTAssertEqual(positions.sorted(), positions)
        XCTAssertEqual(Set(warmUp).count, warmUp.count)
        let wrapUp = try candidates(5, "wrapUp")
        XCTAssertEqual(["canoe-climb", "rainbow-leap", "moonbeam-hop"], Array(wrapUp.prefix(3)))
        XCTAssertFalse(wrapUp.contains("volcano-ladder"))  // medium/deep, hidden by the shallow pool
        XCTAssertFalse(try candidates(1, "introduce").contains("sunflower-home-base"))  // needs the kickboard, off
        XCTAssertEqual([], try candidates(5, "introduce"))
    }

    func test_D10_a_fresh_block_shows_the_first_never_done_candidate() throws {
        let plan = try plan()
        let done = Classes.doneSet(swimClass)
        XCTAssertEqual(try Fixtures.manifestCase("D9.day5")["expected"]?["doneSetSize"]?.intValue, done.count)
        for kind in ["welcome", "warmUp", "review", "wrapUp"] {
            let shown = try block(plan, kind).activityIds
            XCTAssertEqual(1, shown.count, kind)
            XCTAssertEqual(DayPlans.shownActivities(try candidates(5, kind), done: done), shown, kind)
            if kind != "welcome" { XCTAssertFalse(done.contains(shown[0]), kind) }
        }
        // Welcome's three candidates were days 1-3; every one done, so the first again (as on day 4)
        XCTAssertEqual(["snowflake-welcome"], try block(plan, "welcome").activityIds)
        XCTAssertEqual(["walrus-lounge"], try block(plan, "review").activityIds)  // koala-snooze was day 4's introduce
        XCTAssertEqual(["sunflower-countdown"], try block(plan, "warmUp").activityIds)
        XCTAssertEqual([], try block(plan, "introduce").activityIds)  // ["any"] until the pick
        XCTAssertEqual(["a"], DayPlans.shownActivities(["a", "b"], done: []))
        XCTAssertEqual(["b"], DayPlans.shownActivities(["a", "b"], done: ["a"]))
        XCTAssertEqual(["a"], DayPlans.shownActivities(["a", "b"], done: ["a", "b"]))
        XCTAssertEqual([], DayPlans.shownActivities([], done: []))
        // every candidate done: the first candidate
        let review = try candidates(5, "review")
        XCTAssertEqual(Array(review.prefix(1)), try block(try self.plan(swimClass: withDay4Review(review)), "review").activityIds)
        // day 1 of a new class shows the guide's first activity in every block that has one
        let (fresh, problems) = Classes.newClass(curriculum, stageId: "1", weekdays: ["mon"], firstDate: "2026-09-14",
                                                 ageGroup: "schoolAge", classId: "new")
        XCTAssertEqual([], problems)
        let day1 = try self.plan(1, swimClass: try XCTUnwrap(fresh))
        XCTAssertEqual(["snowflake-welcome"], try block(day1, "welcome").activityIds)
        XCTAssertEqual(["otter-bubbles"], try block(day1, "warmUp").activityIds)
        XCTAssertEqual(["puffin-rocket-ride"], try block(day1, "introduce").activityIds)
        XCTAssertEqual([], try block(day1, "review").activityIds)  // lesson 1 reviews nothing
        // the fixture's days 1-4 are what the app showed, one per block, saved in turn
        XCTAssertEqual([["snowflake-welcome"], ["tugboat-hello"], ["iceberg-wave"], ["snowflake-welcome"]],
                       [1, 2, 3, 4].map { Classes.logEntry(swimClass, $0)!.blocks[0].activityIds })
    }

    func test_D3_any_block_waits_for_a_pick_then_shows_one() throws {
        let plan = try plan()
        let introduce = try block(plan, "introduce")
        XCTAssertEqual(["any"], introduce.skillIds)
        XCTAssertEqual([], introduce.activityIds)
        XCTAssertEqual(curriculum.skillsOf("1").compactMap { $0["id"]?.stringValue }, introduce.skillChoices)
        XCTAssertEqual(9, introduce.skillChoices?.count)
        XCTAssertNil(try block(plan, "review").skillChoices)
        let (updated, problems) = DayPlans.pickSkill(curriculum, swimClass: swimClass, pool: pool, n: 5,
                                                     kind: "introduce", skillId: "1.roll")
        XCTAssertEqual([], problems)
        let pickedPlan = try self.plan(swimClass: updated)
        let picked = try block(pickedPlan, "introduce")
        XCTAssertEqual(["1.roll"], picked.skillIds)
        XCTAssertEqual(["dragon-roll"], picked.activityIds)  // the first never-done of the skill's activities
        XCTAssertNil(picked.skillChoices)
        XCTAssertTrue(pickedPlan.draft)
        let (doneRoll, _) = DayPlans.pickSkill(curriculum, swimClass: withDay4Review(["dragon-roll"]), pool: pool,
                                               n: 5, kind: "introduce", skillId: "1.roll")
        XCTAssertEqual(["meteor-flip"], try block(try self.plan(swimClass: doneRoll), "introduce").activityIds)
        let (_, wrongSkill) = DayPlans.pickSkill(curriculum, swimClass: swimClass, pool: pool, n: 5,
                                                 kind: "introduce", skillId: "2.front-glide")
        XCTAssertEqual(["pick-skill"], codes(wrongSkill))
        let (_, notAny) = DayPlans.pickSkill(curriculum, swimClass: swimClass, pool: pool, n: 5,
                                             kind: "review", skillId: "1.roll")
        XCTAssertEqual(["pick-not-any"], codes(notAny))
        // Review is "any" in guide lessons 6-8 too
        let day6 = try self.plan(6)
        XCTAssertEqual(["any"], try block(day6, "review").skillIds)
        XCTAssertNotNil(try block(day6, "review").skillChoices)
    }

    func test_C5_extra_day_of_a_ten_lesson_class() throws {
        var longClass = swimClass!
        longClass.lessons = 10
        let plan = try plan(8, swimClass: longClass)
        XCTAssertNil(plan.guideLesson)
        XCTAssertEqual(["welcome", "warmUp", "review", "introduce", "topic", "wrapUp"], plan.blocks.map(\.kind))
        XCTAssertEqual([2, 3, 5, 10, 5, 5], plan.blocks.map(\.minutes))
        XCTAssertEqual(["any"], try block(plan, "review").skillIds)
        XCTAssertEqual(["any"], try block(plan, "introduce").skillIds)
        XCTAssertNil(try block(plan, "topic").topicCode)
        XCTAssertEqual([], try block(plan, "welcome").activityIds)  // no guide activities, no skill
        let warmUp = try block(plan, "warmUp")
        XCTAssertEqual(["1.submerge"], warmUp.skillIds)
        XCTAssertNil(warmUp.notes)
        XCTAssertEqual(1, warmUp.activityIds.count)
        XCTAssertEqual(8, try self.plan(10, swimClass: longClass).guideLesson)
        let (_, problems) = DayPlans.planDay(curriculum, swimClass: swimClass, pool: pool, n: 9)
        XCTAssertEqual(["day-range"], codes(problems))
    }

    func test_D9_canonical_json_and_hash_match_the_fixture() throws {
        let plan = try plan()
        let text = try DayPlans.planJSON(plan) + "\n"
        assertSameJSONText(text, try Fixtures.text("day-plan.stage1.day5.expected.json"), "day 5")
        let expected = try XCTUnwrap(try Fixtures.manifestCase("D9.day5")["expected"])
        XCTAssertEqual(expected["sha256"]?.stringValue, Canonical.sha256Hex(text))
        for kind in ["welcome", "warmUp", "review", "wrapUp"] {
            XCTAssertEqual(stringItems(expected["\(kind)ActivityIds"]), try block(plan, kind).activityIds, kind)
        }
        XCTAssertEqual(expected["date"]?.stringValue, plan.date)
        XCTAssertEqual(expected["guideLesson"]?.intValue, plan.guideLesson)
        XCTAssertEqual(stringItems(expected["blockKinds"]), plan.blocks.map(\.kind))
        XCTAssertEqual(expected["minutes"]?.arrayValue?.compactMap(\.intValue), plan.blocks.compactMap(\.minutes))
        XCTAssertEqual(true, expected["introduceIsAny"]?.boolValue)
        XCTAssertEqual(try DayPlan(json: try Fixtures.json("day-plan.stage1.day5.expected.json")), plan,
                       "the typed plan equals the fixture read back")
    }

    // MARK: - D4, D5

    func test_D4_shuffle_is_seeded_draws_one_never_done_and_matches_the_fixture() throws {
        let expected = try Fixtures.json("shuffle.stage1.day5.expected.json")
        let expectedWarmUp = try (expected["warmUp"]?.arrayValue ?? []).map(ShuffleResult.init(json:))
        let manifest = try XCTUnwrap(try Fixtures.manifestCase("D4.shuffle")["expected"])
        let (once, first, problems) = DayPlans.shuffle(curriculum, swimClass: swimClass, pool: pool, n: 5, kind: "warmUp")
        XCTAssertEqual([], problems)
        XCTAssertEqual(expectedWarmUp[0], first)
        XCTAssertEqual(stringItems(manifest["warmUpFirst"]), first?.activityIds)
        XCTAssertEqual(1, first?.shuffleCount)
        XCTAssertNil(first?.message)
        let (_, repeat_, _) = DayPlans.shuffle(curriculum, swimClass: swimClass, pool: pool, n: 5, kind: "warmUp")
        XCTAssertEqual(first, repeat_)  // same inputs, same draw
        let (twice, second, _) = DayPlans.shuffle(curriculum, swimClass: once, pool: pool, n: 5, kind: "warmUp")
        XCTAssertEqual(expectedWarmUp[1], second)
        XCTAssertEqual(stringItems(manifest["warmUpSecond"]), second?.activityIds)
        XCTAssertEqual(2, second?.shuffleCount)
        XCTAssertNotEqual(first?.activityIds, second?.activityIds)
        let done = Classes.doneSet(swimClass)
        let warmUpCandidates = Set(try candidates(5, "warmUp"))
        for result in [first, second] {
            XCTAssertEqual(1, result?.activityIds.count)  // as many as shown (D10)
            XCTAssertTrue(done.isDisjoint(with: result?.activityIds ?? []))
            XCTAssertTrue(Set(result?.activityIds ?? []).isSubset(of: warmUpCandidates))
        }
        XCTAssertEqual(["warmUp": 2], twice.draft?.shuffleCounts)
        XCTAssertEqual(second?.activityIds, twice.draft?.blocks.first { $0.kind == "warmUp" }?.activityIds)
        XCTAssertEqual(4, twice.log.count)  // nothing saved by a shuffle
        // the whole shuffle fixture, byte for byte
        let (_, review, reviewProblems) = DayPlans.shuffle(curriculum, swimClass: twice, pool: pool, n: 5, kind: "review")
        XCTAssertEqual([], reviewProblems)
        XCTAssertEqual(try ShuffleResult(json: try XCTUnwrap(expected["review"])), review)
        XCTAssertNil(review?.message)
        let document: JSONValue = .object([
            "classId": .string("c-stage1-mw"), "n": .int(5),
            "warmUp": .array([try XCTUnwrap(first).json, try XCTUnwrap(second).json]),
            "review": try XCTUnwrap(review).json,
        ])
        let text = try Canonical.dumps(document) + "\n"
        assertSameJSONText(text, try Fixtures.text("shuffle.stage1.day5.expected.json"), "shuffle fixture")
        XCTAssertEqual(manifest["sha256"]?.stringValue, Canonical.sha256Hex(text))
        // two activities shown (one added) draw two
        let (added, _) = DayPlans.addActivity(curriculum, swimClass: swimClass, pool: pool, n: 5, kind: "warmUp",
                                              activityId: "lighthouse-bubbles")
        let (_, two, twoProblems) = DayPlans.shuffle(curriculum, swimClass: added, pool: pool, n: 5, kind: "warmUp")
        XCTAssertEqual([], twoProblems)
        XCTAssertEqual(2, two?.activityIds.count)
    }

    func test_D4_shuffles_walk_every_never_done_candidate_before_one_comes_back() throws {
        let plan = try XCTUnwrap(DayPlans.planDay(curriculum, swimClass: swimClass, pool: pool, n: 5).0)
        let shown = try block(plan, "warmUp").activityIds
        let done = Classes.doneSet(swimClass)
        let neverDone = try candidates(5, "warmUp").filter { !done.contains($0) }
        XCTAssertGreaterThan(neverDone.count, 2)
        var working: SwimClass = swimClass
        var seen = shown
        for _ in neverDone.dropFirst() {
            let (updated, result, problems) = DayPlans.shuffle(curriculum, swimClass: working, pool: pool, n: 5,
                                                               kind: "warmUp")
            XCTAssertEqual([], problems)
            XCTAssertNil(result?.message)
            let drawn = try XCTUnwrap(result?.activityIds.first)
            XCTAssertFalse(seen.contains(drawn), "never the one shown, nor one already seen")
            seen.append(drawn)
            working = updated
        }
        XCTAssertEqual(neverDone.sorted(), seen.sorted())
        let (_, again, _) = DayPlans.shuffle(curriculum, swimClass: working, pool: pool, n: 5, kind: "warmUp")
        XCTAssertEqual(shown, again?.activityIds, "then the walk starts over")
    }

    func test_D4_a_block_with_nothing_in_it_is_not_shuffled() {
        let (_, result, problems) = DayPlans.shuffle(curriculum, swimClass: swimClass, pool: pool, n: 5,
                                                     kind: "introduce")
        XCTAssertNil(result)
        XCTAssertEqual(["shuffle-empty"], codes(problems))
        let (_, topicResult, topicProblems) = DayPlans.shuffle(curriculum, swimClass: swimClass, pool: pool, n: 5,
                                                               kind: "topic")
        XCTAssertNil(topicResult)
        XCTAssertEqual(["block-kind"], codes(topicProblems))
    }

    func test_D5_exhaustion_and_saved_days() throws {
        let review = try candidates(5, "review")
        let (_, exhausted, problems) = DayPlans.shuffle(curriculum, swimClass: withDay4Review(review), pool: pool,
                                                        n: 5, kind: "review")
        XCTAssertEqual([], problems)
        XCTAssertEqual([], exhausted?.activityIds)
        XCTAssertEqual(DayPlans.shuffleExhausted, exhausted?.message)
        // fewer never-done candidates than slots: fill what exists, and say so
        let butOne = withDay4Review(Array(review.dropFirst()))
        let (added, _) = DayPlans.addActivity(curriculum, swimClass: butOne, pool: pool, n: 5, kind: "review",
                                              activityId: review[1])
        let (_, twoSlots, twoProblems) = DayPlans.shuffle(curriculum, swimClass: added, pool: pool, n: 5, kind: "review")
        XCTAssertEqual([], twoProblems)
        XCTAssertEqual([review[0]], twoSlots?.activityIds)
        XCTAssertEqual(DayPlans.shuffleExhausted, twoSlots?.message)
        // none but the one shown is never done: it stays, and the block says so
        let (_, only, onlyProblems) = DayPlans.shuffle(curriculum, swimClass: butOne, pool: pool, n: 5, kind: "review")
        XCTAssertEqual([], onlyProblems)
        XCTAssertEqual([review[0]], only?.activityIds)
        XCTAssertEqual(DayPlans.shuffleExhausted, only?.message)
        // a saved day shuffles too: never done is in no saved day but this one
        // (DECISIONS_LOG 2026-09-13, "A day saves itself")
        let others = Set(swimClass.log.filter { $0.n != 4 }.flatMap { $0.blocks.flatMap(\.activityIds) })
        XCTAssertEqual(others, Classes.doneSet(swimClass, except: 4))
        let shown = try XCTUnwrap(Classes.logEntry(swimClass, 4)?.blocks.first { $0.kind == "warmUp" }).activityIds
        let (working, result, savedProblems) = DayPlans.shuffle(curriculum, swimClass: swimClass, pool: pool,
                                                                n: 4, kind: "warmUp")
        XCTAssertEqual([], savedProblems)
        let drawn = try XCTUnwrap(result?.activityIds)
        XCTAssertNotEqual(shown, drawn)
        XCTAssertTrue(others.isDisjoint(with: drawn))
        XCTAssertEqual(swimClass.log, working.log, "the draft holds it until the day is saved again")
        let (_, entry, _) = DayPlans.saveDay(curriculum, swimClass: working, pool: pool, n: 4)
        XCTAssertEqual(drawn, entry?.blocks.first { $0.kind == "warmUp" }?.activityIds)
    }

    // MARK: - D6–D8

    func test_D6_edits_live_in_the_draft() throws {
        var (working, problems) = DayPlans.addActivity(curriculum, swimClass: swimClass, pool: pool, n: 5,
                                                       kind: "review", activityId: "volcano-swim")
        XCTAssertEqual([], problems)
        var (ids, plan) = try reviewIds(working)
        XCTAssertEqual(["walrus-lounge", "volcano-swim"], ids)  // Add appends to the one shown
        XCTAssertTrue(plan.draft)
        XCTAssertEqual(5, working.draft?.n)
        (working, problems) = DayPlans.addActivity(curriculum, swimClass: working, pool: pool, n: 5,
                                                   kind: "review", activityId: "lobster-balance")
        XCTAssertEqual([], problems)
        (working, problems) = DayPlans.moveActivity(curriculum, swimClass: working, pool: pool, n: 5,
                                                    kind: "review", from: 0, to: 2)
        XCTAssertEqual([], problems)
        (ids, _) = try reviewIds(working)
        XCTAssertEqual(["volcano-swim", "lobster-balance", "walrus-lounge"], ids)
        (working, problems) = DayPlans.removeActivity(curriculum, swimClass: working, pool: pool, n: 5,
                                                      kind: "review", activityId: "lobster-balance")
        XCTAssertEqual([], problems)
        (ids, _) = try reviewIds(working)
        XCTAssertEqual(["volcano-swim", "walrus-lounge"], ids)
        for (activityId, code) in [("volcano-swim", "edit-duplicate"), ("no-such", "edit-library"),
                                   ("2.something", "edit-library")] {
            let (_, refused) = DayPlans.addActivity(curriculum, swimClass: working, pool: pool, n: 5,
                                                    kind: "review", activityId: activityId)
            XCTAssertEqual([code], codes(refused), activityId)
        }
        let (_, missing) = DayPlans.removeActivity(curriculum, swimClass: working, pool: pool, n: 5,
                                                   kind: "review", activityId: "no-such")
        XCTAssertEqual(["edit-missing"], codes(missing))
        let (_, index) = DayPlans.moveActivity(curriculum, swimClass: working, pool: pool, n: 5,
                                               kind: "review", from: 0, to: 99)
        XCTAssertEqual(["edit-index"], codes(index))
        // removing the one shown leaves the block empty; it stays empty (the pick is the app's, once)
        let (emptied, _) = DayPlans.removeActivity(curriculum, swimClass: swimClass, pool: pool, n: 5,
                                                   kind: "review", activityId: "walrus-lounge")
        XCTAssertEqual([], try reviewIds(emptied).0)
        XCTAssertNil(swimClass.draft)  // the fixture class is untouched
    }

    func test_D6_a_draft_for_another_day_is_dropped_when_the_next_day_is_opened() throws {
        let (edited, _) = DayPlans.removeActivity(curriculum, swimClass: swimClass, pool: pool, n: 5,
                                                  kind: "review", activityId: "walrus-lounge")
        let (moved, draft, problems) = DayPlans.ensureDraft(curriculum, swimClass: edited, pool: pool, n: 6)
        XCTAssertEqual([], problems)
        XCTAssertEqual(6, draft?.n)
        XCTAssertEqual(6, moved.draft?.n)
        let (ids, plan) = try reviewIds(moved, n: 5)
        XCTAssertEqual(["walrus-lounge"], ids)
        XCTAssertFalse(plan.draft)
    }

    func test_D7_save() throws {
        let (edited, _) = DayPlans.addActivity(curriculum, swimClass: swimClass, pool: pool, n: 5,
                                               kind: "review", activityId: "volcano-swim")
        let (saved, entry, problems) = DayPlans.saveDay(curriculum, swimClass: edited, pool: pool, n: 5)
        XCTAssertEqual([], problems)
        let written = try XCTUnwrap(entry)
        XCTAssertEqual(["blocks", "date", "n"], Canonical.sortedKeys(written.json.objectValue ?? [:]))
        XCTAssertEqual(5, written.n)
        XCTAssertEqual("2026-09-28", written.date)
        XCTAssertEqual(["welcome", "warmUp", "review", "introduce", "topic", "wrapUp"], written.blocks.map(\.kind))
        XCTAssertEqual(["activityIds", "kind"], Canonical.sortedKeys(written.blocks[0].json.objectValue ?? [:]))
        XCTAssertEqual(["walrus-lounge", "volcano-swim"], written.blocks[2].activityIds)
        XCTAssertEqual(["snowflake-welcome"], written.blocks[0].activityIds)  // the one shown is what is logged
        XCTAssertNil(saved.draft)
        XCTAssertEqual([1, 2, 3, 4, 5], saved.log.map(\.n))
        XCTAssertEqual(6, Classes.nextDay(saved))
        XCTAssertEqual(Classes.doneSet(swimClass).count + 4, Classes.doneSet(saved).count)  // three new, snowflake-welcome again, one added
        // the next day moves on: what was taught is done
        let day6 = try plan(6, swimClass: saved)
        XCTAssertFalse(day6.blocks[1].activityIds.contains("sunflower-countdown"))  // day 5's warm-up
        XCTAssertEqual(1, day6.blocks[1].activityIds.count)
        // re-saving overwrites
        let (editedAgain, _) = DayPlans.removeActivity(curriculum, swimClass: saved, pool: pool, n: 5,
                                                       kind: "review", activityId: "volcano-swim")
        let (resaved, _, _) = DayPlans.saveDay(curriculum, swimClass: editedAgain, pool: pool, n: 5)
        XCTAssertEqual([1, 2, 3, 4, 5], resaved.log.map(\.n))
        XCTAssertFalse(Classes.logEntry(resaved, 5)!.blocks[2].activityIds.contains("volcano-swim"))
        XCTAssertTrue(Classes.logEntry(saved, 5)!.blocks[2].activityIds.contains("volcano-swim"))
        let (_, none, dayProblems) = DayPlans.saveDay(curriculum, swimClass: swimClass, pool: pool, n: 0)
        XCTAssertNil(none)
        XCTAssertEqual(["day-range"], codes(dayProblems))
    }

    func test_D8_revisit() throws {
        let plan = try plan(1)
        XCTAssertTrue(plan.saved)
        let entry = try XCTUnwrap(Classes.logEntry(swimClass, 1))
        XCTAssertEqual(entry.blocks.map(\.activityIds), plan.blocks.map(\.activityIds))
        XCTAssertEqual(["1.front-glide", "1.water-exit"], plan.blocks[3].skillIds)
        XCTAssertNil(plan.blocks[3].hidden)
        var noNoodle = pool!
        noNoodle.equipment["pool-noodle"] = false
        let hiddenPlan = try self.plan(1, pool: noNoodle)
        XCTAssertEqual(["puffin-rocket-ride"], hiddenPlan.blocks[3].activityIds)  // still shown
        XCTAssertEqual(["puffin-rocket-ride"], hiddenPlan.blocks[3].hidden)
        // a draft is the working copy, saved day or not
        let (edited, _) = DayPlans.addActivity(curriculum, swimClass: swimClass, pool: pool, n: 1,
                                               kind: "welcome", activityId: "iceberg-wave")
        let draftPlan = try self.plan(1, swimClass: edited)
        XCTAssertTrue(draftPlan.saved)
        XCTAssertTrue(draftPlan.draft)
        XCTAssertEqual(["snowflake-welcome", "iceberg-wave"], draftPlan.blocks[0].activityIds)
    }

    // MARK: - D11

    /// The first block of day n that shows an activity (Topic aside).
    func firstShown(_ swimClass: SwimClass, _ n: Int) throws -> PlanBlock {
        try XCTUnwrap(try plan(n, swimClass: swimClass).blocks.first { !$0.activityIds.isEmpty && $0.kind != "topic" })
    }

    func test_D11_every_day_through_a_date_saves_itself_oldest_first() throws {
        // Mon/Wed from 2026-09-14 with days 1–4 saved: day 5 is 09-28, 6 09-30, 7 10-05, 8 10-07
        let (same, none, noProblems) = DayPlans.saveThrough(curriculum, swimClass: swimClass, pool: pool,
                                                            date: "2026-09-27")
        XCTAssertEqual([], none)
        XCTAssertEqual([], noProblems)
        XCTAssertEqual(swimClass, same, "a saved day is not written again")
        // a draft for day 6 is what day 6 saves; each day as saveDay would, in turn
        let block6 = try firstShown(swimClass, 6)
        let (edited, editProblems) = DayPlans.removeActivity(curriculum, swimClass: swimClass, pool: pool, n: 6,
                                                             kind: block6.kind, activityId: block6.activityIds[0])
        XCTAssertEqual([], editProblems)
        let (through, saved, problems) = DayPlans.saveThrough(curriculum, swimClass: edited, pool: pool,
                                                              date: "2026-10-05")
        XCTAssertEqual([5, 6, 7], saved)
        XCTAssertEqual([], problems)
        var chained: SwimClass = edited
        for n in [5, 6, 7] {
            chained = DayPlans.saveDay(curriculum, swimClass: chained, pool: pool, n: n).0
        }
        XCTAssertEqual(chained, through)
        let logged6 = try XCTUnwrap(Classes.logEntry(through, 6)?.blocks.first { $0.kind == block6.kind })
        XCTAssertFalse(logged6.activityIds.contains(block6.activityIds[0]))
        XCTAssertNil(through.draft)
        XCTAssertEqual(8, Classes.nextDay(through))
        // a draft for a later day stays a draft
        let block8 = try firstShown(swimClass, 8)
        let (later, _) = DayPlans.removeActivity(curriculum, swimClass: swimClass, pool: pool, n: 8,
                                                 kind: block8.kind, activityId: block8.activityIds[0])
        let (kept, keptSaved, _) = DayPlans.saveThrough(curriculum, swimClass: later, pool: pool, date: "2026-09-28")
        XCTAssertEqual([5], keptSaved)
        XCTAssertEqual(8, kept.draft?.n)
        // the manifest's facts, as JSON
        let cases = try XCTUnwrap(try Fixtures.manifestCase("D11.saveThrough")["expected"]?["cases"]?.arrayValue)
        XCTAssertEqual([[], [5], [5, 6, 7], [5, 6, 7, 8]], cases.map { ($0["saved"]?.arrayValue ?? []).compactMap(\.intValue) })
        for testCase in cases {
            let date = try XCTUnwrap(testCase["date"]?.stringValue)
            let (result, days, dayProblems) = DayPlans.saveThrough(curriculum, swimClass: swimClass, pool: pool, date: date)
            XCTAssertEqual([], dayProblems, date)
            XCTAssertEqual(testCase["entries"], .array(days.compactMap { Classes.logEntry(result, $0)?.json }), date)
        }
    }
}
