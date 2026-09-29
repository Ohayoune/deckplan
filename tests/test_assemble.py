"""The assembler, check-work and review (M1), on the synthetic work files in
tests/fixtures/curriculum_mini/_work (made-up content; see make_fixture.py there):
dedupe, suffixing, link resolution, template activity names, videos, determinism against
the golden output beside them, and every check-work rule."""

import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.core import assemble as A
from tools.core import cli
from tools.core import curriculum as C
from tools.core import ids
from tools.core import review as R

ROOT = Path(__file__).resolve().parents[1]
MINI = ROOT / "tests" / "fixtures" / "curriculum_mini"
WORK = MINI / "_work"
VIDEOS = MINI / "videos-source.json"
GOLDEN_FILES = ["activities.json", "equipment.json", "safety.json"] + \
               ["stages/%s.json" % s for s in sorted(ids.STAGE_IDS)] + ["version.json", "videos.json"]


def find(items, **fields):
    return next(item for item in items if all(item.get(k) == v for k, v in fields.items()))


def load_work(stage_id):
    return json.loads((WORK / A.work_file_name(stage_id)).read_text(encoding="utf-8"))


def work_skill(work, slug):
    return find(work["skills"], slug=slug)


def work_block(work, n, kind):
    return find(find(work["lessonTemplates"], n=n)["blocks"], kind=kind)


class ProblemAssertions:
    def assertProblem(self, problems, code, *fragments, severity=C.ERROR):
        hits = [p for p in problems if p.code == code and p.severity == severity
                and all(f in p.message or f in p.where for f in fragments)]
        if not hits:
            self.fail("no %s %r mentioning %s in:\n%s" % (severity, code, fragments, "\n".join(map(str, problems))))
        return hits[0]


class AssembleCase(unittest.TestCase, ProblemAssertions):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.work = base / "work"
        shutil.copytree(WORK, self.work)
        self.out = base / "out"
        self.out.mkdir()
        shutil.copy(MINI / "local.json", self.out / "local.json")

    def tearDown(self):
        self._tmp.cleanup()

    def edit_work(self, stage_id, change):
        path = self.work / A.work_file_name(stage_id)
        data = json.loads(path.read_text(encoding="utf-8"))
        change(data)
        path.write_text(A.dumps(data), encoding="utf-8")

    def run_assemble(self, **options):
        options.setdefault("videos_path", VIDEOS)
        return A.assemble(self.work, self.out, **options)

    def assemble_ok(self, **options):
        result = self.run_assemble(**options)
        self.assertTrue(result.ok, "\n".join(map(str, C.errors(result.problems))))
        return result

    def output(self, relative):
        return json.loads((self.out / relative).read_text(encoding="utf-8"))

    def activities(self):
        return {a["id"]: a for a in self.output("activities.json")}


class AssembleTests(AssembleCase):

    def test_golden_output_byte_for_byte(self):
        result = self.assemble_ok()
        self.assertEqual(GOLDEN_FILES, result.written)
        for relative in GOLDEN_FILES:
            self.assertEqual((MINI / relative).read_bytes(), (self.out / relative).read_bytes(), relative)

    def test_determinism_same_bytes_every_run(self):
        first = self.run_assemble(write=False)
        second = self.run_assemble(write=False)
        self.assertTrue(first.ok)
        self.assertEqual([], first.written)  # write=False writes nothing
        self.assertEqual(first.files, second.files)
        for relative, text in first.files.items():
            self.assertEqual(A.dumps(json.loads(text)), text, relative)  # 2-space JSON, keys sorted
            self.assertTrue(text.endswith("}\n") or text.endswith("]\n"))

    def test_dedupe_same_slug_and_description_merges_skill_ids(self):
        self.assemble_ok()
        acts = self.activities()
        # Stage 2's copy has a doubled space; the normalized descriptions match
        self.assertEqual(["1.skill-three", "1.skill-four", "2.skill-three"], acts["shared-game"]["skillIds"])
        # in ID_ORDER, the order ids are assigned in: stages 1–6, then A and B
        self.assertEqual([ids.skill_id(s, "skill-one") for s in A.ID_ORDER], acts["one-drill"]["skillIds"])
        self.assertEqual([], acts["hello-game"]["skillIds"])  # Greeting only
        for stage_id in ids.STAGE_IDS:
            self.assertEqual(["hello-game", "name-song"], self.output("stages/%s.json" % stage_id)["greetingActivityIds"])
        self.assertEqual(36, len(acts))

    def test_dive_split_with_the_same_description_is_its_own_activity(self):
        result = self.assemble_ok()
        acts = self.activities()
        jump, dive = acts["hoop-leap"], acts["hoop-leap-dive"]
        self.assertEqual(jump["description"], dive["description"])
        self.assertEqual((["1.skill-six", "2.skill-six"], ["1.skill-six", "2.skill-six"]),
                         (jump["skillIds"], dive["skillIds"]))
        self.assertNotIn("headfirst", jump)
        self.assertEqual((True, ["deep"]), (dive["headfirst"], dive["depths"]))
        self.assertEqual([], [str(p) for p in result.problems if p.code == "activity-variant"])
        self.assertTrue(any("dive split" in note and "hoop-leap-dive" in note for note in result.notes))
        # check-work does not call the split a duplicate; a true duplicate still is one
        catalog = A.load_catalog()
        self.assertEqual([], A.check_work(load_work("1"), catalog, "stage-1.json"))
        work = load_work("1")
        work_skill(work, "skill-six")["activities"].append(dict(work_skill(work, "skill-six")["activities"][0]))
        self.assertProblem(A.check_work(work, catalog, "stage-1.json"), "work-shape", "listed twice", severity=C.WARNING)

    def test_a_variant_on_any_occurrence_names_the_id(self):
        second = dict(find(work_skill(load_work("1"), "skill-eight-left")["activities"], name="Twin Game"), variant="back")
        self.edit_work("2", lambda w: work_skill(w, "skill-eight-left")["activities"].append(second))
        self.edit_work("3", lambda w: work_skill(w, "skill-eight-left")["activities"].append(dict(second, variant="ceiling")))
        result = self.assemble_ok()
        acts = self.activities()
        self.assertNotIn("twin-game-1", acts)  # Stage 1's unmarked occurrence takes the later mark
        self.assertEqual(["1.skill-eight-left", "2.skill-eight-left", "3.skill-eight-left"],
                         acts["twin-game-back"]["skillIds"])
        self.assertIn("twin-game-back", find(self.output("stages/1.json")["skills"], id="1.skill-eight-left")["activityIds"])
        self.assertProblem(result.problems, "activity-variant", "'ceiling'", "'back' is used", severity=C.WARNING)
        bad = load_work("1")
        work_skill(bad, "skill-one")["activities"][0]["variant"] = "!!"
        self.assertProblem(A.check_work(bad, A.load_catalog(), "stage-1.json"), "activity-shape", "variant")

    def test_same_slug_other_description_gets_first_stage_suffix(self):
        result = self.assemble_ok()
        acts = self.activities()
        self.assertEqual(["1.skill-two"], acts["twin-game"]["skillIds"])
        self.assertEqual(["1.skill-eight-left"], acts["twin-game-1"]["skillIds"])
        self.assertEqual(["1.skill-four", "2.skill-four", "3.skill-four"], acts["splash-game"]["skillIds"])
        self.assertEqual(["4.skill-four", "5.skill-four", "6.skill-four"], acts["splash-game-4"]["skillIds"])
        self.assertEqual((["deep"], True), (acts["splash-game-4"]["depths"], acts["splash-game-4"]["headfirst"]))
        stage_one = self.output("stages/1.json")
        self.assertIn("twin-game-1", find(stage_one["skills"], id="1.skill-eight-left")["activityIds"])
        self.assertTrue(any("twin-game-1" in note for note in result.notes))

    def test_id_suffix_and_collision_fallbacks(self):
        def change(work):
            work_skill(work, "skill-seven")["activities"].append(
                {"name": "Twin Game", "description": "A third way to play twins.", "ages": [], "page": 16})
            work_skill(work, "skill-one")["activities"].append(
                {"name": "Kickboard", "description": "Kick holding the board.", "ages": [], "page": 4})
        self.edit_work("1", change)
        result = self.assemble_ok()
        acts = self.activities()
        self.assertTrue(acts["circle-game-dive"]["headfirst"])  # the entry's idSuffix
        self.assertIn("circle-game", acts)
        # library order: Skill Seven's page comes before Skill Eight Left's, so it takes twin-game-1
        self.assertEqual(["1.skill-seven"], acts["twin-game-1"]["skillIds"])
        self.assertEqual(["1.skill-eight-left"], acts["twin-game-1-skill-eight-left"]["skillIds"])
        self.assertEqual(["1.skill-one"], acts["kickboard-1"]["skillIds"])  # "kickboard" is an equipment id
        self.assertProblem(result.problems, "activity-id", "twin-game-1-skill-eight-left", severity=C.WARNING)
        self.assertProblem(result.problems, "activity-id", "kickboard-1", severity=C.WARNING)

    def test_same_description_with_different_tags_is_reported(self):
        def change(work):
            entry = find(work_skill(work, "skill-three")["activities"], name="Shared Game")
            entry.update(tags=["game", "song"], ages=["S"])
        self.edit_work("2", change)
        result = self.assemble_ok()
        warning = self.assertProblem(result.problems, "activity-variant", "shared-game", severity=C.WARNING)
        self.assertIn("ages, tags", warning.message)
        self.assertEqual(["game"], self.activities()["shared-game"]["tags"])  # the first is kept

    def test_links_resolve_to_step_ids(self):
        self.assemble_ok()
        one, five, six = (self.output("stages/%s.json" % s) for s in ("1", "5", "6"))
        self.assertEqual(["B.skill-two.1", "B.skill-two.2", "B.skill-two.3"],  # the last one by name
                         find(one["skills"], id="1.skill-two")["prerequisiteStepIds"])
        eight = find(five["skills"], id="5.skill-eight-left")
        self.assertEqual(([], None), (eight["steps"], eight["benchmarkStepId"]))
        self.assertEqual(["4.skill-eight-left.1", "4.skill-eight-left.2"], eight["prerequisiteStepIds"])
        self.assertEqual(["6.skill-eight-left.1", "6.skill-eight-left.2"], eight["advancedStepIds"])
        self.assertEqual(["4.skill-eight-left.1", "4.skill-eight-left.2"],
                         find(six["skills"], id="6.skill-eight-left")["prerequisiteStepIds"])

    def test_link_to_a_missing_step_is_an_error_and_nothing_is_written(self):
        self.edit_work("2", lambda w: work_skill(w, "skill-one")["prerequisite"][0].update(n=9))
        result = self.run_assemble()
        self.assertFalse(result.ok)
        self.assertProblem(result.problems, "link-unresolved", "1.skill-one.9")
        self.assertEqual([], result.written)
        self.assertFalse((self.out / "stages").exists())

    def test_link_name_mismatch_is_a_warning(self):
        self.edit_work("3", lambda w: work_skill(w, "skill-one")["prerequisite"][0].update(name="Skill One, first step"))
        result = self.assemble_ok()
        self.assertProblem(result.problems, "link-name", "2.skill-one.1", "Skill One, first step", severity=C.WARNING)

    def test_name_only_link_needs_the_other_stage_work_file(self):
        (self.work / A.work_file_name("B")).unlink()
        result = self.run_assemble()
        self.assertProblem(result.problems, "link-unresolved", "Stage B has no work file")

    def test_stage_without_work_file_is_skipped_with_a_warning(self):
        (self.work / A.work_file_name("6")).unlink()
        result = self.assemble_ok()
        self.assertEqual(["6"], result.skipped)
        self.assertProblem(result.problems, "stage-skipped", "Stage 6", severity=C.WARNING)
        self.assertNotIn("stages/6.json", result.written)
        five = self.output("stages/5.json")
        self.assertEqual(["6.skill-one.1", "6.skill-one.2", "6.skill-one.3", "6.skill-one.4"],
                         find(five["skills"], id="5.skill-one")["advancedStepIds"])  # kept as ids
        self.assertProblem(result.problems, "link-not-loaded", "Stage 6", severity=C.WARNING)

    def test_stale_stage_file_is_reported(self):
        self.assemble_ok()
        (self.work / A.work_file_name("6")).unlink()
        result = self.assemble_ok()
        self.assertProblem(result.problems, "stale-stage", "stages/6.json", severity=C.WARNING)

    def test_template_activity_names_resolve_to_activity_ids(self):
        self.assemble_ok()
        one, four = self.output("stages/1.json"), self.output("stages/4.json")
        blocks = {b["kind"]: b for b in find(one["lessonTemplates"], n=1)["blocks"]}
        self.assertEqual(["hello-game", "name-song"], blocks["welcome"]["activityIds"])
        self.assertEqual(["two-drill", "three-relay", "twin-game"], blocks["introduce"]["activityIds"])
        self.assertEqual(["four-drill", "splash-game"], blocks["wrapUp"]["activityIds"])
        warm_up = find(find(four["lessonTemplates"], n=1)["blocks"], kind="warmUp")
        self.assertEqual(["bob-game", "dip-game", "float-game"], warm_up["activityIds"])  # from Stages 1–3
        self.assertNotIn("skillIds", warm_up)
        self.assertEqual(["four-drill", "splash-game-4"],  # Stage 4's own variant of the name
                         find(find(four["lessonTemplates"], n=2)["blocks"], kind="wrapUp")["activityIds"])
        self.assertEqual(["any"], find(find(one["lessonTemplates"], n=5)["blocks"], kind="introduce")["skillIds"])

    def test_unresolvable_template_names_are_errors(self):
        self.edit_work("1", lambda w: work_block(w, 2, "introduce")["activities"].append("Missing Game"))
        result = self.run_assemble()
        self.assertProblem(result.problems, "template-activity", "Missing Game")
        self.assertEqual([], result.written)

    def test_skill_less_warm_up_name_missing_everywhere_is_an_error(self):
        self.edit_work("4", lambda w: work_block(w, 1, "warmUp")["activities"].append("Nowhere Game"))
        result = self.run_assemble()
        self.assertProblem(result.problems, "template-activity", "Nowhere Game", "any assembled stage")

    def test_block_and_step_fields_pass_through(self):
        self.assemble_ok()
        one, two, three, four = (self.output("stages/%s.json" % s) for s in ("1", "2", "3", "4"))
        seven = find(find(one["lessonTemplates"], n=7)["blocks"], kind="introduce")
        self.assertEqual([["life-jacket"]], seven["equipment"])
        self.assertEqual(["Wear life jackets first, then take them off."], seven["notes"])
        self.assertEqual(["medium", "deep"], find(find(three["lessonTemplates"], n=7)["blocks"], kind="introduce")["depths"])
        tread = find(two["skills"], id="2.skill-seven")["steps"]
        self.assertEqual([["life-jacket", "float-belt"]], tread[0]["equipment"])
        self.assertEqual((["medium", "deep"], True), (tread[3]["depths"], tread[3]["nearWall"]))
        review = find(find(four["lessonTemplates"], n=2)["blocks"], kind="review")
        self.assertEqual(2, review["minutes"])
        self.assertNotIn("minutesPrinted", review)
        template = find(four["lessonTemplates"], n=2)
        self.assertEqual({"n", "minutes", "blocks"}, set(template))
        self.assertEqual(40, template["minutes"])
        group_game = find(find(one["lessonTemplates"], n=8)["blocks"], kind="wrapUp")
        self.assertEqual({"kind", "minutes", "notes"}, set(group_game))
        self.assertEqual({"text": "Skill Two, step 3", "stepIds": ["2.skill-two.3"], "rule": "all"}, two["trackerRows"][1])

    def test_different_step_ranges_merge_with_a_warning(self):
        self.edit_work("1", lambda w: work_block(w, 1, "introduce")["skills"][1].update(steps=[2, 2]))
        result = self.assemble_ok()
        block = find(find(self.output("stages/1.json")["lessonTemplates"], n=1)["blocks"], kind="introduce")
        self.assertEqual([1, 3], block["stepRange"])
        self.assertProblem(result.problems, "step-range-merged", "[2, 2]", severity=C.WARNING)

    def test_videos_matched_by_title(self):
        result = self.assemble_ok()
        videos = {v["id"]: v for v in self.output("videos.json")}
        self.assertEqual(6, len(videos))  # the SAW copy of 100000001 listed once, the YLG page left out
        self.assertEqual((["1", "2"], ["1.skill-one", "2.skill-one"]),
                         (videos["vimeo:100000001"]["stageIds"], videos["vimeo:100000001"]["skillIds"]))
        self.assertEqual(["A.skill-two", "A.skill-three", "B.skill-two", "B.skill-three"],
                         videos["vimeo:100000002"]["skillIds"])
        self.assertEqual(["4", "5", "6"], videos["vimeo:100000003"]["stageIds"])
        self.assertEqual(["5.skill-eight-right"], videos["vimeo:100000004"]["skillIds"])  # prefix: the one with steps
        self.assertEqual(["3.skill-five", "3.skill-six"], videos["vimeo:100000005"]["skillIds"])  # "L3"
        self.assertEqual([], videos["vimeo:100000000"]["skillIds"])
        notes = " ".join(result.notes)
        self.assertIn("Welcome to the Synthetic Program-HD", notes)
        self.assertIn("same Vimeo video", notes)
        self.assertIn("1 entry from other Yapp pages", notes)
        self.assertEqual(["vimeo:100000003"], find(self.output("stages/4.json")["skills"], id="4.skill-four")["videoIds"])

    def test_parse_video_title(self):
        self.assertEqual((["1", "2", "3"], ["Skill Nine"]), A.parse_video_title("Skill Nine (Stages 1-3)"))
        self.assertEqual((["A", "B"], ["Left", "Right"]), A.parse_video_title("Left & Right (Stages A & B)"))
        self.assertEqual((["1"], ["Skill Ten", "Skill Eleven"]), A.parse_video_title("Skill Ten and Skill Eleven L1"))
        self.assertEqual((["6"], ["Skill Twelve"]), A.parse_video_title("Skill Twelve (Stage 6)"))
        self.assertEqual(([], ["Hello Everyone"]), A.parse_video_title("Hello Everyone-HD"))

    def test_version_equipment_and_safety_files(self):
        local_before = (self.out / "local.json").read_bytes()
        result = self.assemble_ok(version="2027.01")
        self.assertEqual({"format": "curriculum/1", "version": "2027.01", "source": A.VERSION_SOURCE},
                         self.output("version.json"))
        self.assertEqual(A.DEFAULT_EQUIPMENT.read_bytes(), (self.out / "equipment.json").read_bytes())
        self.assertEqual((self.work / A.SAFETY_FILE).read_bytes(), (self.out / "safety.json").read_bytes())
        # local.json is the owner's file: read for the collision check, never written
        self.assertNotIn("local.json", result.written)
        self.assertEqual(local_before, (self.out / "local.json").read_bytes())

    def test_local_collision_blocks_the_write(self):
        local = json.loads((self.out / "local.json").read_text(encoding="utf-8"))
        local["activities"][0]["id"] = "one-drill"
        (self.out / "local.json").write_text(json.dumps(local), encoding="utf-8")
        result = self.run_assemble()
        self.assertProblem(result.problems, "local-collision", "one-drill")
        self.assertEqual([], result.written)

    def test_cli_assemble_and_review(self):
        out = io.StringIO()
        code = cli.main(["curriculum", "assemble", "--work", str(self.work), "--out", str(self.out),
                         "--videos", str(VIDEOS)], out)
        self.assertEqual(0, code, out.getvalue())
        self.assertIn("wrote 13 files", out.getvalue())
        self.edit_work("2", lambda w: work_skill(w, "skill-one")["prerequisite"][0].update(n=9))
        out = io.StringIO()
        self.assertEqual(1, cli.main(["curriculum", "assemble", "--work", str(self.work), "--out", str(self.out),
                                      "--videos", str(VIDEOS)], out))
        self.assertIn("nothing was written", out.getvalue())
        out = io.StringIO()
        self.assertEqual(0, cli.main(["curriculum", "review", "a", "--work", str(self.work),
                                      "--out", str(self.out / "review")], out))
        self.assertTrue((self.out / "review" / "stage-A.md").exists())


class CheckWorkTests(unittest.TestCase, ProblemAssertions):

    @classmethod
    def setUpClass(cls):
        cls.catalog = A.load_catalog()

    def check(self, work, name="stage-1.json"):
        return A.check_work(work, self.catalog, name)

    def test_the_synthetic_work_files_are_clean(self):
        for stage_id in ids.STAGE_IDS:
            with self.subTest(stage=stage_id):
                problems = self.check(load_work(stage_id), A.work_file_name(stage_id))
                self.assertEqual([], [str(p) for p in C.errors(problems)])
                expected = {"template-activity"} if stage_id == "4" else set()
                self.assertEqual(expected, {p.code for p in problems})

    def test_shape_and_slug_rule(self):
        work = load_work("1")
        work["format"] = "curriculum-work/0"
        work_skill(work, "skill-two").update(slug="skill_two")
        work_skill(work, "skill-three").update(slug="three")
        work_skill(work, "skill-six")["order"] = 9
        problems = self.check(work)
        self.assertProblem(problems, "work-shape", "format")
        self.assertProblem(problems, "slug-rule", "skill_two", "'skill-two'")
        self.assertProblem(problems, "slug-rule", "three", "'skill-three'")
        self.assertProblem(problems, "work-shape", "library order")
        self.assertProblem(self.check({"format": A.WORK_FORMAT}), "work-shape", "no stage object")

    def test_steps_contiguous_and_steps_empty_only_without_a_progression(self):
        self.assertEqual([], self.check(load_work("5"), "stage-5.json"))  # skill-eight-left has steps []
        work = load_work("1")
        work_skill(work, "skill-one")["steps"][2]["n"] = 4
        work_skill(work, "skill-six")["steps"] = []
        problems = self.check(work)
        self.assertProblem(problems, "steps", "skill-one", "1, 2, 3")
        self.assertProblem(problems, "tracker-row", "skill-six, which has no steps")

    def test_tracker_rows_name_benchmark_steps(self):
        work = load_work("1")
        rows = work["trackerRows"]
        rows[0]["steps"][0]["n"] = 3
        rows[1]["text"] = "Skill Two, final step"
        rows[2]["rule"] = "any"
        rows[3]["steps"][0]["skill"] = "skill-nine"
        del rows[4]
        problems = self.check(work)
        self.assertProblem(problems, "tracker-row", "trackerRows[0]", "not its last (benchmark) step")
        self.assertProblem(problems, "tracker-row", "Skill Two, final step", "a one-step row's text is the step's name")
        self.assertProblem(problems, "tracker-row", "trackerRows[2]", "two or more steps")
        self.assertProblem(problems, "tracker-row", "skill-nine")
        self.assertProblem(problems, "tracker-coverage", "skill-five")

    def test_preschool_variants_match_the_tracker(self):
        work = load_work("2")
        work["trackerRows"][1]["preschool"] = None  # its step has preschoolValue 5
        work["trackerRows"][0]["preschool"] = "2 ft. preschool"  # its step has none
        work_skill(work, "skill-three")["steps"][0]["measure"] = {"kind": "distance", "value": 5, "unit": "ft",
                                                                   "preschoolValue": 3}
        problems = self.check(work, "stage-2.json")
        self.assertProblem(problems, "preschool-value", "Skill Two, step 3", "no preschool variant")
        self.assertProblem(problems, "preschool-value", "2 ft. preschool", "no measure.preschoolValue")
        self.assertProblem(problems, "preschool-value", "skill-three / step 1", "Only the benchmark")

    def test_flags_are_booleans_and_near_wall_is_for_steps(self):
        work = load_work("2")
        steps = work_skill(work, "skill-seven")["steps"]
        steps[3]["nearWall"] = "yes"
        steps[0]["submerges"] = 1
        activity = work_skill(work, "skill-one")["activities"][0]
        activity.update(nearWall=True, headfirst="true")
        problems = self.check(work, "stage-2.json")
        self.assertProblem(problems, "flag-type", "skill-seven / step 4", "nearWall must be true or false")
        self.assertProblem(problems, "flag-type", "skill-seven / step 1", "submerges must be true or false")
        self.assertProblem(problems, "flag-type", "One Drill", "nearWall is for steps only")
        self.assertProblem(problems, "flag-type", "One Drill", "headfirst must be true or false")

    def test_lesson_minutes_add_up_to_minutes_total(self):
        work = load_work("1")
        work_block(work, 2, "introduce")["minutes"] = 11
        work_block(work, 3, "review")["minutesPrinted"] = "1-3 mins."
        find(work["lessonTemplates"], n=4)["minutesTotal"] = 40
        problems = self.check(work)
        self.assertProblem(problems, "template-minutes", "lesson 2", "add up to 31")
        self.assertProblem(problems, "template-minutes", "lesson 3", "upper value is 3")
        self.assertProblem(problems, "template-minutes", "lesson 4", "stage's lessons are 30")

    def test_equipment_ids_are_in_the_seed_catalog(self):
        work = load_work("1")
        work_skill(work, "skill-one")["activities"][0]["equipment"] = [["trampoline"]]
        work_skill(work, "skill-one")["activities"][1]["equipmentOptional"] = ["confetti"]
        work_skill(work, "skill-two")["steps"][0]["equipment"] = [["jetpack"]]
        work_block(work, 7, "introduce")["equipment"] = [["foam-dice"]]  # a local item is not a seed id
        problems = self.check(work)
        for missing in ("trampoline", "confetti", "jetpack", "foam-dice"):
            self.assertProblem(problems, "equipment-unknown", missing)

    def test_depth_and_age_values_and_headfirst(self):
        work = load_work("1")
        work_skill(work, "skill-one")["activities"][0]["ages"] = ["Q"]
        work_skill(work, "skill-one")["activities"][1]["depths"] = ["abyss"]
        work_skill(work, "skill-two")["steps"][0]["depths"] = []
        work_block(work, 7, "introduce")["depths"] = ["deep", "deep"]
        find(work_skill(work, "skill-three")["activities"], idSuffix="dive")["depths"] = ["medium", "deep"]
        work_skill(work, "skill-four")["steps"][0].update(headfirst=True)
        problems = self.check(work)
        self.assertProblem(problems, "activity-shape", "One Drill", "ages")
        self.assertProblem(problems, "depths", "One Relay", "abyss")
        self.assertProblem(problems, "depths", "skill-two / step 1", "non-empty")
        self.assertProblem(problems, "depths", "lesson 7", "twice")
        self.assertProblem(problems, "headfirst-depths", "Circle Game")
        self.assertProblem(problems, "headfirst-depths", "skill-four / step 1")

    def test_template_activity_names_and_blocks(self):
        work = load_work("1")
        work_block(work, 2, "introduce")["activities"].append("Missing Game")
        work_block(work, 3, "warmUp")["skills"] = [{"slug": "any"}]
        work_block(work, 4, "topic")["topicCode"] = "1.9"
        work_block(work, 5, "introduce")["skills"] = [{"slug": "skill-two", "steps": [1, 5]}]
        problems = self.check(work)
        self.assertProblem(problems, "template-activity", "Missing Game", "not the name of an activity")
        self.assertProblem(problems, "template-block", "lesson 3", "Review and Introduce slots only")
        self.assertProblem(problems, "template-block", "lesson 4", "1.9")
        self.assertProblem(problems, "step-range", "lesson 5", "past its last step 3")
        four = self.check(load_work("4"), "stage-4.json")
        self.assertProblem(four, "template-activity", "lesson 1", "Bob Game", "other stages", severity=C.WARNING)

    def test_links_uncertain_and_unreadable(self):
        work = load_work("2")
        work_skill(work, "skill-one")["prerequisite"].append({"stage": "3", "skill": "skill-one", "n": 1})
        work_skill(work, "skill-one")["advanced"].append({"stage": "1", "skill": "skill-one", "n": 1})
        work_skill(work, "skill-two")["advanced"].append({"stage": "3"})
        work["uncertain"] = [{"where": "skills[1].steps[0]", "issue": "faint print", "page": 5}]
        work_skill(work, "skill-three")["steps"][0]["description"] = "UNREADABLE"
        problems = self.check(work, "stage-2.json")
        self.assertProblem(problems, "link", "not in an earlier stage")
        self.assertProblem(problems, "link", "not in a later stage")
        self.assertProblem(problems, "link", "needs skill and n")
        self.assertProblem(problems, "uncertain", "faint print", severity=C.WARNING)
        self.assertProblem(problems, "placeholder-text", "UNREADABLE", severity=C.WARNING)

    def test_never_raises_on_garbage(self):
        for garbage in (None, [], "x", {"format": A.WORK_FORMAT, "stage": {"id": "1"}, "skills": "x",
                                         "lessonTemplates": [{"n": 1, "blocks": 5}], "trackerRows": [5]}):
            with self.subTest(garbage=garbage):
                self.assertTrue(C.errors(self.check(garbage)))

    def test_cli_check_work_exit_status(self):
        out = io.StringIO()
        self.assertEqual(0, cli.main(["curriculum", "check-work", str(WORK / "stage-1.json")], out))
        self.assertIn("stage-1.json: 0 errors, 0 warnings.", out.getvalue())
        with tempfile.TemporaryDirectory() as tmp:
            broken = load_work("1")
            broken["skills"][0]["steps"][0]["n"] = 7
            path = Path(tmp) / "stage-1.json"
            path.write_text(json.dumps(broken), encoding="utf-8")
            out = io.StringIO()
            self.assertEqual(1, cli.main(["curriculum", "check-work", str(path)], out))
            self.assertIn("error: stage-1.json / skill skill-one:", out.getvalue())
            path.write_text("{", encoding="utf-8")
            self.assertEqual(1, cli.main(["curriculum", "check-work", str(path)], io.StringIO()))


class ReviewTests(unittest.TestCase):

    def test_review_lists_each_skill_with_its_pages_and_a_checklist_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            path, problems = R.write_review("1", WORK, tmp)
            self.assertEqual([], problems)
            text = path.read_text(encoding="utf-8")
            self.assertEqual(Path(tmp) / "stage-1.md", path)
        for skill in load_work("1")["skills"]:
            self.assertIn("- [ ] %s: steps (names, descriptions, measures, depth tags)" % skill["name"], text)
        self.assertIn("### 1. Skill One (`1.skill-one`) — progression p. 3, activities p. 4", text)
        self.assertEqual(8, text.count("### Lesson "))
        self.assertIn("equipment: kickboard + small toys", text)  # Toy Hunt
        self.assertIn("### 1.6 Topic Six (p. 26)", text)
        self.assertIn("## Uncertain (0)", text)
        with tempfile.TemporaryDirectory() as tmp:
            two = R.write_review("2", WORK, tmp)[0].read_text(encoding="utf-8")
            four = R.write_review("4", WORK, tmp)[0].read_text(encoding="utf-8")
        self.assertIn("distance 10 ft (preschool 5 ft)", two)
        self.assertIn("| 2 (printed 1-2 mins.) |", two)
        self.assertIn("| 2 (printed 1–2 mins.) |", four)

    def test_review_without_a_work_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path, problems = R.write_review("3", tmp, tmp)
            self.assertIsNone(path)
            self.assertEqual(["file-missing"], [p.code for p in problems])
            out = io.StringIO()
            self.assertEqual(1, cli.main(["curriculum", "review", "3", "--work", tmp, "--out", tmp], out))
            self.assertIn("could not be read", out.getvalue())


class SlugRuleTests(unittest.TestCase):

    def test_slug_rule_and_id_helpers(self):
        # the rule's own examples (CURRICULUM_FORMAT.md §3 and the work format)
        self.assertEqual("jump-and-return", ids.slug("Jump and Return"))
        self.assertEqual("kick-glide-and-breathe", ids.slug("Kick, Glide & Breathe"))
        self.assertEqual("manatee-glide", ids.slug("Manatee Glide"))
        self.assertEqual("skill-eight-left", ids.slug("Skill  Eight (Left)"))
        self.assertEqual("its-a-game", ids.slug("It’s a Game"))
        self.assertEqual("1.skill-one.3", ids.step_id("1", "skill-one", 3))
        self.assertEqual(("A", "skill-one", 12), ids.parse_step_id("A.skill-one.12"))
        self.assertIsNone(ids.parse_step_id("7.skill-one.1"))
        self.assertEqual(("6", 8), ids.parse_topic_code("6.8"))
        self.assertEqual("100000001", ids.parse_video_id("vimeo:100000001"))
        self.assertEqual("100000009", ids.vimeo_id_from_url("https://vimeo.com/100000009/abc123?share=copy"))
        self.assertIsNone(ids.vimeo_id_from_url("https://example.com/100000009"))
        self.assertEqual("twin-game-1", ids.activity_id("Twin Game", "1"))


if __name__ == "__main__":
    unittest.main()
