"""C5 (extra days), D1–D10: today's plan, shuffle, edits, save, revisit (TEST_CASES.md group D)."""

import copy
import unittest

from tools.core import activities as ACT
from tools.core import canonical
from tools.core import classes as CL
from tools.core import day_plan as DP

from tests.v2support import fixture_class, fixture_pool, load_json, manifest_case, read_text, sample

REVIEW_DAY5_GUIDE = ["koala-snooze", "walrus-lounge", "lobster-balance", "popcorn-glide", "koala-launch",
                     "walrus-torpedo", "robot-express"]


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.curriculum = sample()
        self.class_ = fixture_class()
        self.pool = fixture_pool()
        self.age = ACT.age_tag(self.class_["ageGroup"])

    def plan(self, n=5, class_=None, pool=None):
        plan, problems = DP.plan_day(self.curriculum, class_ or self.class_, pool or self.pool, n)
        self.assertEqual([], problems)
        return plan

    def block(self, plan, kind):
        return next(b for b in plan["blocks"] if b["kind"] == kind)

    def template_block(self, n, kind):
        return DP._template_block(self.curriculum, self.class_, n, kind)

    def test_D1_day5_is_guide_lesson_5_block_by_block(self):
        plan = self.plan()
        self.assertEqual(("c-stage1-mw", 5, "2026-09-28", 5, False, False),
                         (plan["classId"], plan["n"], plan["date"], plan["guideLesson"], plan["saved"], plan["draft"]))
        self.assertEqual(["welcome", "warmUp", "review", "introduce", "topic", "wrapUp"], [b["kind"] for b in plan["blocks"]])
        self.assertEqual([2, 3, 5, 10, 5, 5], [b["minutes"] for b in plan["blocks"]])
        self.assertEqual(["1.front-float", "1.back-glide"], self.block(plan, "review")["skillIds"])
        self.assertEqual([1, 4], self.block(plan, "review")["stepRange"])
        topic = self.block(plan, "topic")
        self.assertEqual("1.5", topic["topicCode"])
        self.assertEqual("Being Kind", topic["topic"]["name"])
        self.assertEqual([], topic["activityIds"])
        self.assertIn("Check in with quieter swimmers.", self.block(plan, "welcome")["notes"])

    def test_D2_block_candidates_guide_first_then_skills_in_catalog_order_filtered(self):
        review = DP.block_candidates(self.curriculum, self.template_block(5, "review"), self.pool, self.age)
        shown_guide = [a for a in REVIEW_DAY5_GUIDE if a in review]
        self.assertEqual(shown_guide, review[:len(shown_guide)])
        self.assertEqual(REVIEW_DAY5_GUIDE, shown_guide)  # nothing the guide lists is hidden by the fixture pool
        self.assertEqual([], review[len(shown_guide):])  # the guide names every shown activity of both skills
        self.assertEqual(set(review), set(ACT.skill_activity_ids(self.curriculum, ["1.front-float", "1.back-glide"])) & set(review))
        self.assertEqual(len(set(review)), len(review))
        warm_up = DP.block_candidates(self.curriculum, self.template_block(5, "warmUp"), self.pool, self.age)
        self.assertEqual(["otter-bubbles", "rainbow-treasure-hunt"], warm_up[:2])  # the guide's, snowflake-hide-and-seek hidden (P only)
        for hidden in ("snowflake-hide-and-seek", "iceberg-bubble-party", "submarine-peekaboo"):
            self.assertNotIn(hidden, warm_up)
        rest = warm_up[2:]
        self.assertTrue(rest)
        self.assertTrue(set(rest) <= set(ACT.skill_activity_ids(self.curriculum, ["1.submerge"])))
        position = ACT.catalog_position(self.curriculum)
        self.assertEqual(sorted(position[a] for a in rest), [position[a] for a in rest])
        self.assertEqual(len(set(warm_up)), len(warm_up))
        self.assertIn("submarine-peekaboo", ACT.library(self.curriculum, "1"))  # hidden by age, not by its prop
        wrap_up = DP.block_candidates(self.curriculum, self.template_block(5, "wrapUp"), self.pool, self.age)
        self.assertEqual(["canoe-climb", "rainbow-leap", "moonbeam-hop"], wrap_up[:3])
        self.assertNotIn("volcano-ladder", wrap_up)  # medium/deep, hidden by the shallow pool
        self.assertNotIn("sunflower-home-base", DP.block_candidates(self.curriculum, self.template_block(1, "introduce"),
                                                                self.pool, self.age))  # needs the kickboard, off
        self.assertEqual([], DP.block_candidates(self.curriculum, self.template_block(5, "introduce"), self.pool, self.age))

    def test_D10_a_fresh_block_shows_the_first_never_done_candidate(self):
        plan = self.plan()
        done = CL.done_set(self.class_)
        self.assertEqual(manifest_case("D9.day5")["expected"]["doneSetSize"], len(done))
        for kind in ("welcome", "warmUp", "review", "wrapUp"):
            block = self.block(plan, kind)
            candidates = DP.block_candidates(self.curriculum, self.template_block(5, kind), self.pool, self.age)
            self.assertEqual(1, len(block["activityIds"]), kind)
            self.assertEqual(DP.shown_activities(candidates, done), block["activityIds"], kind)
            if kind != "welcome":
                self.assertNotIn(block["activityIds"][0], done, kind)
        # Welcome's three candidates were days 1-3; every one done, so the first again (as on day 4)
        self.assertEqual(["snowflake-welcome"], self.block(plan, "welcome")["activityIds"])
        self.assertEqual(["walrus-lounge"], self.block(plan, "review")["activityIds"])  # koala-snooze was day 4's introduce
        self.assertEqual(["sunflower-countdown"], self.block(plan, "warmUp")["activityIds"])
        self.assertEqual([], self.block(plan, "introduce")["activityIds"])  # ["any"] until the pick
        self.assertEqual(DP.shown_activities(["a", "b"], set()), ["a"])
        self.assertEqual(DP.shown_activities(["a", "b"], {"a"}), ["b"])
        self.assertEqual(DP.shown_activities(["a", "b"], {"a", "b"}), ["a"])
        self.assertEqual(DP.shown_activities([], set()), [])
        # every candidate done: the first candidate
        candidates = DP.block_candidates(self.curriculum, self.template_block(5, "review"), self.pool, self.age)
        all_done = CL.with_log_entry(self.class_, {"n": 4, "date": "2026-09-23",
                                                   "blocks": [{"kind": "review", "activityIds": candidates}]})
        self.assertEqual(candidates[:1], self.block(self.plan(class_=all_done), "review")["activityIds"])
        # day 1 of a new class shows the guide's first activity in every block that has one
        fresh, _ = CL.new_class(self.curriculum, "1", ["mon"], "2026-09-14", age_group="schoolAge", class_id="new")
        day1 = self.plan(1, class_=fresh)
        self.assertEqual(["snowflake-welcome"], self.block(day1, "welcome")["activityIds"])
        self.assertEqual(["otter-bubbles"], self.block(day1, "warmUp")["activityIds"])
        self.assertEqual(["puffin-rocket-ride"], self.block(day1, "introduce")["activityIds"])
        self.assertEqual([], self.block(day1, "review")["activityIds"])  # lesson 1 reviews nothing
        # the fixture's days 1-4 are what the app showed, one per block, saved in turn
        self.assertEqual([["snowflake-welcome"], ["tugboat-hello"], ["iceberg-wave"], ["snowflake-welcome"]],
                         [CL.log_entry(self.class_, n)["blocks"][0]["activityIds"] for n in (1, 2, 3, 4)])

    def test_D3_any_block_waits_for_a_pick_then_shows_one(self):
        plan = self.plan()
        introduce = self.block(plan, "introduce")
        self.assertEqual(["any"], introduce["skillIds"])
        self.assertEqual([], introduce["activityIds"])
        self.assertEqual([s["id"] for s in self.curriculum.skills_of("1")], introduce["skillChoices"])
        self.assertEqual(9, len(introduce["skillChoices"]))
        self.assertNotIn("skillChoices", self.block(plan, "review"))
        updated, problems = DP.pick_skill(self.curriculum, self.class_, self.pool, 5, "introduce", "1.roll")
        self.assertEqual([], problems)
        picked = self.block(self.plan(class_=updated), "introduce")
        self.assertEqual(["1.roll"], picked["skillIds"])
        self.assertEqual(["dragon-roll"], picked["activityIds"])  # the first never-done of the skill's activities
        self.assertNotIn("skillChoices", picked)
        self.assertTrue(self.plan(class_=updated)["draft"])
        done_roll = CL.with_log_entry(self.class_, {"n": 4, "date": "2026-09-23",
                                                    "blocks": [{"kind": "review", "activityIds": ["dragon-roll"]}]})
        updated, _ = DP.pick_skill(self.curriculum, done_roll, self.pool, 5, "introduce", "1.roll")
        self.assertEqual(["meteor-flip"], self.block(self.plan(class_=updated), "introduce")["activityIds"])
        _, problems = DP.pick_skill(self.curriculum, self.class_, self.pool, 5, "introduce", "2.front-glide")
        self.assertEqual(["pick-skill"], [p.code for p in problems])
        _, problems = DP.pick_skill(self.curriculum, self.class_, self.pool, 5, "review", "1.roll")
        self.assertEqual(["pick-not-any"], [p.code for p in problems])
        # Review is "any" in guide lessons 6-8 too
        day6 = self.plan(6)
        self.assertEqual(["any"], self.block(day6, "review")["skillIds"])
        self.assertIn("skillChoices", self.block(day6, "review"))

    def test_C5_extra_day_of_a_ten_lesson_class(self):
        long_class = dict(self.class_, lessons=10)
        plan = self.plan(8, class_=long_class)
        self.assertIsNone(plan["guideLesson"])
        self.assertEqual(["welcome", "warmUp", "review", "introduce", "topic", "wrapUp"], [b["kind"] for b in plan["blocks"]])
        self.assertEqual([2, 3, 5, 10, 5, 5], [b["minutes"] for b in plan["blocks"]])
        self.assertEqual(["any"], self.block(plan, "review")["skillIds"])
        self.assertEqual(["any"], self.block(plan, "introduce")["skillIds"])
        self.assertNotIn("topicCode", self.block(plan, "topic"))
        self.assertEqual([], self.block(plan, "welcome")["activityIds"])  # no guide activities, no skill
        warm_up = self.block(plan, "warmUp")
        self.assertEqual(["1.submerge"], warm_up["skillIds"])
        self.assertNotIn("notes", warm_up)
        self.assertEqual(1, len(warm_up["activityIds"]))
        self.assertEqual(8, self.plan(10, class_=long_class)["guideLesson"])
        _, problems = DP.plan_day(self.curriculum, self.class_, self.pool, 9)
        self.assertEqual(["day-range"], [p.code for p in problems])

    def test_D9_canonical_json_and_hash_match_the_fixture(self):
        plan = self.plan()
        text = DP.plan_json(plan) + "\n"
        self.assertEqual(read_text("day-plan.stage1.day5.expected.json"), text)
        case = manifest_case("D9.day5")
        self.assertEqual(case["expected"]["sha256"], canonical.sha256_hex(text))
        for kind in ("welcome", "warmUp", "review", "wrapUp"):
            self.assertEqual(case["expected"]["%sActivityIds" % kind], self.block(plan, kind)["activityIds"], kind)
        self.assertEqual(case["expected"]["blockKinds"], [b["kind"] for b in plan["blocks"]])


class ShuffleTests(unittest.TestCase):
    def setUp(self):
        self.curriculum = sample()
        self.class_ = fixture_class()
        self.pool = fixture_pool()
        self.age = ACT.age_tag(self.class_["ageGroup"])
        self.expected = load_json("shuffle.stage1.day5.expected.json")

    def candidates(self, n, kind):
        return DP.block_candidates(self.curriculum, DP._template_block(self.curriculum, self.class_, n, kind), self.pool, self.age)

    def test_D4_shuffle_is_seeded_draws_one_never_done_and_matches_the_fixture(self):
        once, first, problems = DP.shuffle(self.curriculum, self.class_, self.pool, 5, "warmUp")
        self.assertEqual([], problems)
        self.assertEqual(self.expected["warmUp"][0], first)
        self.assertEqual(manifest_case("D4.shuffle")["expected"]["warmUpFirst"], first["activityIds"])
        self.assertEqual(1, first["shuffleCount"])
        self.assertNotIn("message", first)
        again, repeat, _ = DP.shuffle(self.curriculum, self.class_, self.pool, 5, "warmUp")
        self.assertEqual(first, repeat)  # same inputs, same draw
        twice, second, _ = DP.shuffle(self.curriculum, once, self.pool, 5, "warmUp")
        self.assertEqual(self.expected["warmUp"][1], second)
        self.assertEqual(manifest_case("D4.shuffle")["expected"]["warmUpSecond"], second["activityIds"])
        self.assertEqual(2, second["shuffleCount"])
        self.assertNotEqual(first["activityIds"], second["activityIds"])
        done = CL.done_set(self.class_)
        candidates = set(self.candidates(5, "warmUp"))
        for result in (first, second):
            self.assertEqual(1, len(result["activityIds"]))  # as many as shown (D10)
            self.assertFalse(set(result["activityIds"]) & done)
            self.assertTrue(set(result["activityIds"]) <= candidates)
        self.assertEqual({"warmUp": 2}, twice["draft"]["shuffleCounts"])
        self.assertEqual(second["activityIds"], next(b for b in twice["draft"]["blocks"] if b["kind"] == "warmUp")["activityIds"])
        self.assertEqual(4, len(twice["log"]))  # nothing saved by a shuffle
        _, review, problems = DP.shuffle(self.curriculum, twice, self.pool, 5, "review")
        self.assertEqual([], problems)
        self.assertEqual(self.expected["review"], review)
        self.assertNotIn("message", review)
        # two activities shown (one added) draw two
        added, _ = DP.add_activity(self.curriculum, self.class_, self.pool, 5, "warmUp", "lighthouse-bubbles")
        _, two, problems = DP.shuffle(self.curriculum, added, self.pool, 5, "warmUp")
        self.assertEqual([], problems)
        self.assertEqual(2, len(two["activityIds"]))

    def test_D4_shuffles_walk_every_never_done_candidate_before_one_comes_back(self):
        plan, _ = DP.plan_day(self.curriculum, self.class_, self.pool, 5)
        shown = next(b for b in plan["blocks"] if b["kind"] == "warmUp")["activityIds"]
        never_done = [a for a in self.candidates(5, "warmUp") if a not in CL.done_set(self.class_)]
        self.assertGreater(len(never_done), 2)
        working, seen = self.class_, list(shown)
        for _ in never_done[1:]:
            working, result, problems = DP.shuffle(self.curriculum, working, self.pool, 5, "warmUp")
            self.assertEqual([], problems)
            self.assertNotIn("message", result)
            self.assertNotIn(result["activityIds"][0], seen)  # never the one shown, nor one already seen
            seen += result["activityIds"]
        self.assertEqual(sorted(never_done), sorted(seen))
        _, result, _ = DP.shuffle(self.curriculum, working, self.pool, 5, "warmUp")
        self.assertEqual(shown, result["activityIds"])  # then the walk starts over

    def test_D4_a_block_with_nothing_in_it_is_not_shuffled(self):
        _, result, problems = DP.shuffle(self.curriculum, self.class_, self.pool, 5, "introduce")
        self.assertIsNone(result)
        self.assertEqual(["shuffle-empty"], [p.code for p in problems])
        _, result, problems = DP.shuffle(self.curriculum, self.class_, self.pool, 5, "topic")
        self.assertEqual(["block-kind"], [p.code for p in problems])

    def test_D5_exhaustion_and_saved_days(self):
        candidates = self.candidates(5, "review")
        all_done = CL.with_log_entry(self.class_, {"n": 4, "date": "2026-09-23",
                                                   "blocks": [{"kind": "review", "activityIds": candidates}]})
        _, review, problems = DP.shuffle(self.curriculum, all_done, self.pool, 5, "review")
        self.assertEqual([], problems)
        self.assertEqual([], review["activityIds"])
        self.assertEqual(DP.SHUFFLE_EXHAUSTED, review["message"])
        # fewer never-done candidates than slots: fill what exists, and say so
        but_one = CL.with_log_entry(self.class_, {"n": 4, "date": "2026-09-23",
                                                  "blocks": [{"kind": "review", "activityIds": candidates[1:]}]})
        added, _ = DP.add_activity(self.curriculum, but_one, self.pool, 5, "review", candidates[1])
        _, two_slots, problems = DP.shuffle(self.curriculum, added, self.pool, 5, "review")
        self.assertEqual([], problems)
        self.assertEqual([candidates[0]], two_slots["activityIds"])
        self.assertEqual(DP.SHUFFLE_EXHAUSTED, two_slots["message"])
        # none but the one shown is never done: it stays, and the block says so
        _, only, problems = DP.shuffle(self.curriculum, but_one, self.pool, 5, "review")
        self.assertEqual([], problems)
        self.assertEqual([candidates[0]], only["activityIds"])
        self.assertEqual(DP.SHUFFLE_EXHAUSTED, only["message"])
        # a saved day shuffles too: never done is in no saved day but this one
        # (DECISIONS_LOG 2026-09-13 "A day saves itself")
        others = {a for e in self.class_["log"] if e["n"] != 4 for b in e["blocks"] for a in b["activityIds"]}
        self.assertEqual(others, CL.done_set(self.class_, 4))
        shown = next(b for b in CL.log_entry(self.class_, 4)["blocks"] if b["kind"] == "warmUp")["activityIds"]
        working, result, problems = DP.shuffle(self.curriculum, self.class_, self.pool, 4, "warmUp")
        self.assertEqual([], problems)
        self.assertNotEqual(shown, result["activityIds"])
        self.assertFalse(set(result["activityIds"]) & others)
        self.assertEqual(self.class_["log"], working["log"])  # the draft holds it until the day is saved again
        _, entry, _ = DP.save_day(self.curriculum, working, self.pool, 4)
        self.assertEqual(result["activityIds"], next(b for b in entry["blocks"] if b["kind"] == "warmUp")["activityIds"])


class EditAndSaveTests(unittest.TestCase):
    def setUp(self):
        self.curriculum = sample()
        self.class_ = fixture_class()
        self.pool = fixture_pool()

    def review_ids(self, class_, n=5):
        plan, problems = DP.plan_day(self.curriculum, class_, self.pool, n)
        self.assertEqual([], problems)
        return next(b for b in plan["blocks"] if b["kind"] == "review")["activityIds"], plan

    def test_D6_edits_live_in_the_draft(self):
        class_, problems = DP.add_activity(self.curriculum, self.class_, self.pool, 5, "review", "volcano-swim")
        self.assertEqual([], problems)
        ids_, plan = self.review_ids(class_)
        self.assertEqual(["walrus-lounge", "volcano-swim"], ids_)  # Add appends to the one shown
        self.assertTrue(plan["draft"])
        self.assertEqual(5, class_["draft"]["n"])
        class_, problems = DP.add_activity(self.curriculum, class_, self.pool, 5, "review", "lobster-balance")
        self.assertEqual([], problems)
        class_, problems = DP.move_activity(self.curriculum, class_, self.pool, 5, "review", 0, 2)
        self.assertEqual([], problems)
        ids_, _ = self.review_ids(class_)
        self.assertEqual(["volcano-swim", "lobster-balance", "walrus-lounge"], ids_)
        class_, problems = DP.remove_activity(self.curriculum, class_, self.pool, 5, "review", "lobster-balance")
        self.assertEqual([], problems)
        ids_, _ = self.review_ids(class_)
        self.assertEqual(["volcano-swim", "walrus-lounge"], ids_)
        for activity_id, code in (("volcano-swim", "edit-duplicate"), ("no-such", "edit-library"), ("2.something", "edit-library")):
            _, problems = DP.add_activity(self.curriculum, class_, self.pool, 5, "review", activity_id)
            self.assertEqual([code], [p.code for p in problems], activity_id)
        _, problems = DP.remove_activity(self.curriculum, class_, self.pool, 5, "review", "no-such")
        self.assertEqual(["edit-missing"], [p.code for p in problems])
        _, problems = DP.move_activity(self.curriculum, class_, self.pool, 5, "review", 0, 99)
        self.assertEqual(["edit-index"], [p.code for p in problems])
        # removing the one shown leaves the block empty; it stays empty (the pick is the app's, once)
        emptied, _ = DP.remove_activity(self.curriculum, self.class_, self.pool, 5, "review", "walrus-lounge")
        self.assertEqual([], self.review_ids(emptied)[0])
        self.assertIsNone(self.class_["draft"])  # the fixture class is untouched

    def test_D6_a_draft_for_another_day_is_dropped_when_the_next_day_is_opened(self):
        class_, _ = DP.remove_activity(self.curriculum, self.class_, self.pool, 5, "review", "walrus-lounge")
        class_, draft, problems = DP.ensure_draft(self.curriculum, class_, self.pool, 6)
        self.assertEqual([], problems)
        self.assertEqual(6, class_["draft"]["n"])
        ids_, plan = self.review_ids(class_, 5)
        self.assertEqual(["walrus-lounge"], ids_)
        self.assertFalse(plan["draft"])

    def test_D7_save(self):
        class_, _ = DP.add_activity(self.curriculum, self.class_, self.pool, 5, "review", "volcano-swim")
        saved, entry, problems = DP.save_day(self.curriculum, class_, self.pool, 5)
        self.assertEqual([], problems)
        self.assertEqual(["blocks", "date", "n"], sorted(entry))
        self.assertEqual((5, "2026-09-28"), (entry["n"], entry["date"]))
        self.assertEqual(["welcome", "warmUp", "review", "introduce", "topic", "wrapUp"], [b["kind"] for b in entry["blocks"]])
        self.assertEqual({"kind", "activityIds"}, set(entry["blocks"][0]))
        self.assertEqual(["walrus-lounge", "volcano-swim"], entry["blocks"][2]["activityIds"])
        self.assertEqual(["snowflake-welcome"], entry["blocks"][0]["activityIds"])  # the one shown is what is logged
        self.assertIsNone(saved["draft"])
        self.assertEqual([1, 2, 3, 4, 5], [e["n"] for e in saved["log"]])
        self.assertEqual(6, CL.next_day(saved))
        self.assertEqual(len(CL.done_set(self.class_)) + 4, len(CL.done_set(saved)))  # three new, snowflake-welcome again, one added
        # the next day moves on: what was taught is done
        day6, _ = DP.plan_day(self.curriculum, saved, self.pool, 6)
        self.assertNotIn("sunflower-countdown", day6["blocks"][1]["activityIds"])  # day 5's warm-up
        self.assertEqual(1, len(day6["blocks"][1]["activityIds"]))
        # re-saving overwrites
        edited, _ = DP.remove_activity(self.curriculum, saved, self.pool, 5, "review", "volcano-swim")
        resaved, entry2, _ = DP.save_day(self.curriculum, edited, self.pool, 5)
        self.assertEqual([1, 2, 3, 4, 5], [e["n"] for e in resaved["log"]])
        self.assertNotIn("volcano-swim", CL.log_entry(resaved, 5)["blocks"][2]["activityIds"])
        self.assertIn("volcano-swim", CL.log_entry(saved, 5)["blocks"][2]["activityIds"])
        _, entry, problems = DP.save_day(self.curriculum, self.class_, self.pool, 0)
        self.assertIsNone(entry)
        self.assertEqual(["day-range"], [p.code for p in problems])

    def test_D8_revisit(self):
        plan, problems = DP.plan_day(self.curriculum, self.class_, self.pool, 1)
        self.assertEqual([], problems)
        self.assertTrue(plan["saved"])
        entry = CL.log_entry(self.class_, 1)
        self.assertEqual([b["activityIds"] for b in entry["blocks"]], [b["activityIds"] for b in plan["blocks"]])
        self.assertEqual(["1.front-glide", "1.water-exit"], plan["blocks"][3]["skillIds"])
        self.assertNotIn("hidden", plan["blocks"][3])
        no_noodle = copy.deepcopy(self.pool)
        no_noodle["equipment"]["pool-noodle"] = False
        plan, _ = DP.plan_day(self.curriculum, self.class_, no_noodle, 1)
        self.assertEqual(["puffin-rocket-ride"], plan["blocks"][3]["activityIds"])  # still shown
        self.assertEqual(["puffin-rocket-ride"], plan["blocks"][3]["hidden"])
        # a draft is the working copy, saved day or not
        edited, _ = DP.add_activity(self.curriculum, self.class_, self.pool, 1, "welcome", "iceberg-wave")
        plan, _ = DP.plan_day(self.curriculum, edited, self.pool, 1)
        self.assertEqual((True, True), (plan["saved"], plan["draft"]))
        self.assertEqual(["snowflake-welcome", "iceberg-wave"], plan["blocks"][0]["activityIds"])

    def first_shown(self, class_, n):
        plan, _ = DP.plan_day(self.curriculum, class_, self.pool, n)
        return next(b for b in plan["blocks"] if b["activityIds"] and b["kind"] != "topic")

    def test_D11_every_day_through_a_date_saves_itself_oldest_first(self):
        # Mon/Wed from 2026-09-14 with days 1-4 saved: day 5 is 09-28, 6 09-30, 7 10-05, 8 10-07
        same, saved, problems = DP.save_through(self.curriculum, self.class_, self.pool, "2026-09-27")
        self.assertEqual(([], []), (saved, problems))
        self.assertEqual(self.class_, same)  # a saved day is not written again
        # a draft for day 6 is what day 6 saves; each day as save_day would, in turn
        block6 = self.first_shown(self.class_, 6)
        edited, problems = DP.remove_activity(self.curriculum, self.class_, self.pool, 6, block6["kind"],
                                              block6["activityIds"][0])
        self.assertEqual([], problems)
        through, saved, problems = DP.save_through(self.curriculum, edited, self.pool, "2026-10-05")
        self.assertEqual(([5, 6, 7], []), (saved, problems))
        chained = edited
        for n in (5, 6, 7):
            chained, _, _ = DP.save_day(self.curriculum, chained, self.pool, n)
        self.assertEqual(chained, through)
        self.assertNotIn(block6["activityIds"][0],
                         next(b for b in CL.log_entry(through, 6)["blocks"] if b["kind"] == block6["kind"])["activityIds"])
        self.assertIsNone(through["draft"])
        self.assertEqual(8, CL.next_day(through))
        # a draft for a later day stays a draft
        block8 = self.first_shown(self.class_, 8)
        later, _ = DP.remove_activity(self.curriculum, self.class_, self.pool, 8, block8["kind"], block8["activityIds"][0])
        kept, saved, _ = DP.save_through(self.curriculum, later, self.pool, "2026-09-28")
        self.assertEqual([5], saved)
        self.assertEqual(8, kept["draft"]["n"])
        # the manifest's facts
        cases = manifest_case("D11.saveThrough")["expected"]["cases"]
        self.assertEqual([[], [5], [5, 6, 7], [5, 6, 7, 8]], [case["saved"] for case in cases])
        for case in cases:
            through, saved, problems = DP.save_through(self.curriculum, self.class_, self.pool, case["date"])
            self.assertEqual(([], case["saved"]), (problems, saved), case["date"])
            self.assertEqual(case["entries"], [CL.log_entry(through, n) for n in saved], case["date"])


if __name__ == "__main__":
    unittest.main()
