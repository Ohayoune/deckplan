//
//  IdsTests.swift
//  DeckPlanCoreTests
//
//  Mirrors tests/test_assemble.py's `test_slug_rule_and_id_helpers`: same
//  inputs, same outputs (M4 brief, "Curriculum loading + validation").
//

import XCTest
@testable import DeckPlanCore

final class IdsTests: XCTestCase {

    // MARK: - The slug rule (tests/test_assemble.py's test_slug_rule_and_id_helpers)

    func test_slug_rule_examples_match_the_python_test() {
        XCTAssertEqual("jump-and-return", Ids.slug("Jump and Return"))
        XCTAssertEqual("kick-glide-and-breathe", Ids.slug("Kick, Glide & Breathe"))
        XCTAssertEqual("manatee-glide", Ids.slug("Manatee Glide"))
        XCTAssertEqual("skill-eight-left", Ids.slug("Skill  Eight (Left)"))
        XCTAssertEqual("its-a-game", Ids.slug("It\u{2019}s a Game"))   // fancy apostrophe, dropped not kept
    }

    func test_slug_rule_other_cases() {
        XCTAssertEqual("", Ids.slug(nil))
        XCTAssertEqual("", Ids.slug(""))
        XCTAssertEqual("", Ids.slug("!!! ???"))                       // no letters or digits at all
        XCTAssertEqual("cafe", Ids.slug("Café"))                      // NFKD strips the combining accent
        XCTAssertEqual("a-b", Ids.slug("a---b"))                      // collapses repeated dashes
        XCTAssertEqual("a-b", Ids.slug("-a-b-"))                      // trims leading/trailing dashes
        XCTAssertEqual("meteor-torpedo-back", Ids.slug("Meteor Torpedo") + "-" + Ids.slug("Back"))
        XCTAssertEqual("swim-and-rest", Ids.slug("Swim and Rest"))
        XCTAssertEqual("3-2-1-splash", Ids.slug("3\u{2010}2\u{2011}1 Splash!"))  // Unicode dash variants -> space
    }

    func test_isSlug() {
        XCTAssertTrue(Ids.isSlug("front-glide"))
        XCTAssertTrue(Ids.isSlug("a"))
        XCTAssertTrue(Ids.isSlug("manatee-glide"))
        XCTAssertFalse(Ids.isSlug(""))
        XCTAssertFalse(Ids.isSlug(nil))
        XCTAssertFalse(Ids.isSlug("-leading"))
        XCTAssertFalse(Ids.isSlug("trailing-"))
        XCTAssertFalse(Ids.isSlug("double--dash"))
        XCTAssertFalse(Ids.isSlug("Has-Capitals"))
        XCTAssertFalse(Ids.isSlug("has space"))
        XCTAssertFalse(Ids.isSlug("has_underscore"))
    }

    // MARK: - Building and parsing ids

    func test_stage_ids_and_index() {
        XCTAssertEqual(["A", "B", "1", "2", "3", "4", "5", "6"], Ids.stageIds)
        XCTAssertTrue(Ids.isStageId("A"))
        XCTAssertTrue(Ids.isStageId("6"))
        XCTAssertFalse(Ids.isStageId("7"))
        XCTAssertFalse(Ids.isStageId(nil))
        XCTAssertEqual(0, Ids.stageSortKey("A"))
        XCTAssertEqual(7, Ids.stageSortKey("6"))
        XCTAssertEqual(Ids.stageIds.count, Ids.stageSortKey("not-a-stage"))
        XCTAssertLessThan(Ids.stageSortKey("1"), Ids.stageSortKey("2"))
    }

    func test_id_builders() {
        XCTAssertEqual("1.front-glide", Ids.skillId("1", "front-glide"))
        XCTAssertEqual("1.skill-one.3", Ids.stepId("1", "skill-one", 3))
        XCTAssertEqual("1.5", Ids.topicCode("1", 5))
        XCTAssertEqual("vimeo:172429568", Ids.videoId("172429568"))
        XCTAssertEqual("twin-game-1", Ids.activityId(name: "Twin Game", suffix: "1"))
        XCTAssertEqual("twin-game", Ids.activityId(name: "Twin Game"))
        XCTAssertEqual("twin-game", Ids.activityId(name: "Twin Game", suffix: ""))
    }

    func test_parseSkillId() {
        let parsed = Ids.parseSkillId("1.front-glide")
        XCTAssertEqual("1", parsed?.stage)
        XCTAssertEqual("front-glide", parsed?.skillSlug)
        XCTAssertNil(Ids.parseSkillId("7.front-glide"))                // not a stage
        XCTAssertNil(Ids.parseSkillId("1.front-glide.3"))              // that's a step id
        XCTAssertNil(Ids.parseSkillId(nil))
        XCTAssertNil(Ids.parseSkillId("1.Front-Glide"))                // must be lower-case
    }

    func test_parseStepId_matches_the_python_test() {
        let parsed = Ids.parseStepId("A.skill-one.12")
        XCTAssertEqual("A", parsed?.stage)
        XCTAssertEqual("skill-one", parsed?.skillSlug)
        XCTAssertEqual(12, parsed?.n)
        XCTAssertNil(Ids.parseStepId("7.skill-one.1"))
        XCTAssertNil(Ids.parseStepId("A.skill-one.0"))                 // n starts at 1
        XCTAssertNil(Ids.parseStepId("A.skill-one"))
    }

    func test_parseTopicCode_matches_the_python_test() {
        let parsed = Ids.parseTopicCode("6.8")
        XCTAssertEqual("6", parsed?.stage)
        XCTAssertEqual(8, parsed?.n)
        XCTAssertNil(Ids.parseTopicCode("9.1"))
        XCTAssertNil(Ids.parseTopicCode("6.0"))
    }

    func test_parseVideoId_matches_the_python_test() {
        XCTAssertEqual("100000001", Ids.parseVideoId("vimeo:100000001"))
        XCTAssertNil(Ids.parseVideoId("youtube:1"))
        XCTAssertNil(Ids.parseVideoId(nil))
    }

    func test_vimeoIdFromURL_matches_the_python_test() {
        XCTAssertEqual("100000009", Ids.vimeoId(fromURL: "https://vimeo.com/100000009/abc123?share=copy"))
        XCTAssertNil(Ids.vimeoId(fromURL: "https://example.com/100000009"))
        XCTAssertEqual("172429568", Ids.vimeoId(fromURL: "https://vimeo.com/172429568"))
        XCTAssertEqual("999", Ids.vimeoId(fromURL: "https://vimeo.com/album/12345/video/999"))
        XCTAssertNil(Ids.vimeoId(fromURL: nil))
    }

    // MARK: - stepLabel (the renderer's fallback for an unloaded stage, docs/SPEC.md §6.1)

    func test_stepLabel() {
        XCTAssertEqual("2 / Front glide / 1", Ids.stepLabel("2.front-glide.1"))
        XCTAssertEqual("1 / Jump and return / 4", Ids.stepLabel("1.jump-and-return.4"))
        // malformed input is returned as-is, matching the Python's `str(step_id_value)` fallback
        XCTAssertEqual("not-a-step-id", Ids.stepLabel("not-a-step-id"))
    }

    // MARK: - normalizeText and descriptionKey

    func test_normalizeText_folds_quotes_and_dashes_and_collapses_whitespace() {
        XCTAssertEqual("It's a game", Ids.normalizeText("It\u{2019}s a game"))
        XCTAssertEqual("say \"hi\"", Ids.normalizeText("say \u{201C}hi\u{201D}"))
        XCTAssertEqual("front-glide", Ids.normalizeText("front\u{2013}glide"))   // en dash -> hyphen
        XCTAssertEqual("a b c", Ids.normalizeText("  a   b\tc  "))
        XCTAssertEqual("", Ids.normalizeText(nil))
    }

    func test_descriptionKey_is_normalized_and_case_folded() {
        XCTAssertEqual(Ids.descriptionKey("Front Glide"), Ids.descriptionKey("front glide"))
        XCTAssertEqual(Ids.descriptionKey("Skill One, Step 1"), Ids.descriptionKey("skill one, step 1"))
        XCTAssertNotEqual(Ids.descriptionKey("Front Glide"), Ids.descriptionKey("Back Glide"))
    }
}
