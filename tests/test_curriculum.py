"""TEST_CASES.md group A — curriculum validation (M1).

One test per case id, on the synthetic mini curriculum in tests/fixtures/curriculum_mini
(made-up content that mirrors the real structure; regenerate with its make_fixture.py),
each negative case a mutation of a temporary copy. Then the made-up samples in examples/, and —
only when curriculum/stages/ exists — the owner's real curriculum, its tracker rows against the
Progress Tracker table in curriculum/_work/benchmarks.json (CURRICULUM_FORMAT.md §4.2).
"""

import hashlib
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.core import cli
from tools.core import curriculum as C
from tools.core import ids

ROOT = Path(__file__).resolve().parents[1]
MINI = ROOT / "tests" / "fixtures" / "curriculum_mini"
EXAMPLES = ROOT / "examples"
SAMPLE = EXAMPLES / "curriculum.stage1.sample.json"
REAL = ROOT / "curriculum"
BENCHMARKS = REAL / "_work" / "benchmarks.json"  # the owner's: toolkit text stays out of git
# The libraries' single-inhalation sentence, held as a digest so its words stay out of git.
SINGLE_INHALATION_SHA256 = "a0e63674a4c560d184bdbf051dd5db4ebc24776e550e6ae80e5e316dc5df12bb"
DATA = ROOT / "tools" / "core" / "data"

CATALOG_ITEMS = ["pool-noodle", "kickboard", "hoop", "rescue-tube", "small-toys", "ball", "rope", "pull-buoy", "fins",
                 "float-belt", "hand-paddles", "dive-rings", "barbell", "life-jacket", "small-tube", "mat", "bucket",
                 "straws", "stopwatch", "pole", "pennies", "goggles", "sunglasses", "newspaper", "balloon",
                 "watering-can", "t-shirt", "whistle"]


def find(items, **fields):
    return next(item for item in items if all(item.get(k) == v for k, v in fields.items()))


def skill_of(stage, skill_id):
    return find(stage["skills"], id=skill_id)


def step_of(stage, step_id):
    return find(skill_of(stage, step_id.rsplit(".", 1)[0])["steps"], id=step_id)


def block_of(stage, n, kind):
    return find(find(stage["lessonTemplates"], n=n)["blocks"], kind=kind)


def tracker_mismatches(curriculum, table):
    """Differences between each loaded stage's trackerRows and a fixture table
    { stage: [ { text, skills, rule, preschool } ] } (A7, A8)."""
    found = []
    for stage_id in curriculum.loaded_stage_ids:
        stage = curriculum.stage(stage_id)
        rows = stage.get("trackerRows") or []
        expected = table.get(stage_id, [])
        if [r.get("text") for r in rows] != [e["text"] for e in expected]:
            found.append("Stage %s rows %s != %s" % (stage_id, [r.get("text") for r in rows], [e["text"] for e in expected]))
            continue
        benchmarks = {s["benchmarkStepId"]: s for s in stage["skills"] if s.get("benchmarkStepId")}
        preschool_steps = set()
        for row, want in zip(rows, expected):
            if row.get("rule") != want["rule"]:
                found.append("Stage %s row %r rule %s != %s" % (stage_id, want["text"], row.get("rule"), want["rule"]))
            slugs = [ids.parse_step_id(s)[1] if ids.parse_step_id(s) else s for s in row.get("stepIds", [])]
            if slugs != want["skills"]:
                found.append("Stage %s row %r skills %s != %s" % (stage_id, want["text"], slugs, want["skills"]))
            for step_id in row.get("stepIds", []):
                if step_id not in benchmarks:
                    found.append("Stage %s row %r names %s, not a benchmark" % (stage_id, want["text"], step_id))
                elif want["preschool"]:
                    preschool_steps.add(step_id)
        with_value = {step["id"] for s in stage["skills"] for step in s["steps"]
                      if "preschoolValue" in (step.get("measure") or {})}
        if with_value != preschool_steps:
            found.append("Stage %s preschoolValue on %s, tracker variants on %s"
                         % (stage_id, sorted(with_value), sorted(preschool_steps)))
    return found


class MiniCase(unittest.TestCase):
    """A temporary copy of the mini curriculum that a test may edit."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name) / "curriculum"
        shutil.copytree(MINI, self.dir, ignore=shutil.ignore_patterns("_work", "*.py", "videos-source.json",
                                                                      "__pycache__"))

    def tearDown(self):
        self._tmp.cleanup()

    def edit(self, relative, change):
        path = self.dir / relative
        data = json.loads(path.read_text(encoding="utf-8"))
        replaced = change(data)
        path.write_text(json.dumps(data if replaced is None else replaced, ensure_ascii=False), encoding="utf-8")

    def check(self):
        return C.check(self.dir)

    def assertProblem(self, problems, code, *fragments, severity=C.ERROR):
        hits = [p for p in problems if p.code == code and p.severity == severity
                and all(f in p.message or f in p.where for f in fragments)]
        if not hits:
            self.fail("no %s %r mentioning %s in:\n%s" % (severity, code, fragments, "\n".join(map(str, problems))))
        return hits[0]

    def assertNoErrors(self, problems):
        self.assertEqual([], [str(p) for p in C.errors(problems)])


class MiniFixtureTests(MiniCase):

    def test_mini_curriculum_validates_clean(self):
        _cur, problems = self.check()
        self.assertEqual([], [str(p) for p in problems])

    def test_A1_all_eight_stages_load_and_counts_are_reported(self):
        cur, problems = self.check()
        self.assertEqual(list(ids.STAGE_IDS), cur.loaded_stage_ids)
        counts = C.summary(cur)
        self.assertEqual({"name": "Stage Five", "skills": 9, "steps": 22, "activityLinks": 19, "greeting": 2,
                          "topics": 8, "templates": 8, "trackerRows": 8}, counts["stages"]["5"])
        self.assertEqual({"ymca": 36, "local": 1}, counts["activities"])
        self.assertEqual({"items": 28, "groups": 1, "local": 1}, counts["equipment"])
        lines = C.format_summary(counts)
        self.assertEqual("Loaded stages: A, B, 1, 2, 3, 4, 5, 6.", lines[0])
        self.assertIn("Stage 5 Stage Five: 9 skills, 22 steps", lines[7])
        out = io.StringIO()
        self.assertEqual(0, cli.main(["curriculum", "validate", "--dir", str(self.dir)], out))
        self.assertIn("Validation: 0 errors, 0 warnings.", out.getvalue())
        # a stage not yet transcribed is simply not loaded; references into it are warnings
        (self.dir / "stages" / "4.json").unlink()
        cur, problems = self.check()
        self.assertNotIn("4", cur.loaded_stage_ids)
        self.assertNoErrors(problems)
        self.assertProblem(problems, "stage-not-loaded", "Stage 4", severity=C.WARNING)
        self.assertProblem(problems, "link-not-loaded", "Stage 4", severity=C.WARNING)

    def test_A2_topics_templates_and_minutes(self):
        cur, _ = self.check()
        self.assertEqual(2, block_of(cur.stage("4"), 2, "review")["minutes"])  # printed "1–2 mins."
        self.assertEqual(40, sum(b["minutes"] for b in find(cur.stage("4")["lessonTemplates"], n=2)["blocks"]))
        self.edit("stages/1.json", lambda s: s.update(topics=s["topics"][:7]))
        self.edit("stages/2.json", lambda s: s.update(lessonTemplates=[t for t in s["lessonTemplates"] if t["n"] != 3]))
        self.edit("stages/4.json", lambda s: block_of(s, 2, "introduce").update(minutes=14))
        self.edit("stages/5.json", lambda s: find(s["lessonTemplates"], n=6).update(minutes=30))
        self.edit("stages/3.json", lambda s: s.update(skills=s["skills"][:7] + s["skills"][8:]))
        _cur, problems = self.check()
        self.assertProblem(problems, "topics", "Stage 1", "topics 1–8")
        self.assertProblem(problems, "templates", "Stage 2", "lesson templates 1–8")
        self.assertProblem(problems, "template-minutes", "lesson template 2", "39", "40")
        self.assertProblem(problems, "template-minutes", "lesson template 6", "30", "40")
        self.assertProblem(problems, "skill-count", "Stage 3 has 7 skills")

    def test_A3_steps_benchmarks_and_step_names(self):
        cur, _ = self.check()
        no_steps = cur.skill("5.skill-eight-left")
        self.assertEqual(([], None), (no_steps["stepIds"], no_steps["benchmarkStepId"]))
        self.assertEqual("1.skill-one", cur.step("1.skill-one.3")["skillId"])

        def mutate(stage):
            step_of(stage, "1.skill-one.3")["n"] = 5
            skill_of(stage, "1.skill-two")["benchmarkStepId"] = "1.skill-two.2"
            step_of(stage, "1.skill-one.2")["name"] = "Skill One, step 1"
            step_of(stage, "1.skill-three.1")["name"] = "Skill One, step 1"  # another skill may repeat a name
            step_of(stage, "1.skill-six.2")["id"] = "1.skill-six.02"
        self.edit("stages/1.json", mutate)
        self.edit("stages/5.json", lambda s: skill_of(s, "5.skill-eight-left").update(benchmarkStepId="5.skill-eight-left.1"))
        _cur, problems = self.check()
        self.assertProblem(problems, "steps", "1.skill-one", "run 1, 2, 3")
        self.assertProblem(problems, "benchmark", "1.skill-two", "last step")
        self.assertProblem(problems, "step-name-duplicate", "1.skill-one.2", "unique within a skill")
        self.assertFalse([p for p in problems if p.code == "step-name-duplicate" and "skill-three" in p.where + p.message])
        self.assertProblem(problems, "steps", "1.skill-six.02", "should be")
        self.assertProblem(problems, "benchmark", "5.skill-eight-left", "must be null")

    def test_A4_prerequisite_and_advanced_links(self):
        cur, _ = self.check()
        self.assertEqual(["4.skill-eight-left.1", "4.skill-eight-left.2"], cur.skill("5.skill-eight-left")["prerequisiteStepIds"])
        self.assertEqual(["6.skill-eight-left.1", "6.skill-eight-left.2"], cur.skill("5.skill-eight-left")["advancedStepIds"])
        self.assertEqual(["4.skill-eight-left.1", "4.skill-eight-left.2"], cur.skill("6.skill-eight-left")["prerequisiteStepIds"])
        self.assertTrue(all(not s["prerequisiteStepIds"] for s in cur.stage("A")["skills"]))
        self.assertTrue(all(not s["advancedStepIds"] for s in cur.stage("6")["skills"]))
        self.edit("stages/6.json", lambda s: skill_of(s, "6.skill-one").update(prerequisiteStepIds=["4.skill-one.4"]))
        self.edit("stages/2.json", lambda s: skill_of(s, "2.skill-one")["prerequisiteStepIds"].append("1.skill-one.9"))
        self.edit("stages/A.json", lambda s: skill_of(s, "A.skill-one").update(prerequisiteStepIds=["B.skill-one.1"]))
        self.edit("stages/3.json", lambda s: skill_of(s, "3.skill-one").update(advancedStepIds=["2.skill-one.1"]))
        _cur, problems = self.check()
        self.assertProblem(problems, "link-unresolved", "6.skill-one", "Stage 5 is nearer")
        self.assertProblem(problems, "link-unresolved", "1.skill-one.9", "not a step of Stage 1")
        self.assertProblem(problems, "link-unresolved", "Stage A is the first stage")
        self.assertProblem(problems, "link-unresolved", "2.skill-one.1", "not in an later stage")
        # a reference into a stage that isn't loaded is a warning, printed without the step's name
        (self.dir / "stages" / "2.json").unlink()
        _cur, problems = self.check()
        self.assertProblem(problems, "link-not-loaded", "1.skill-one", "Stage 2", "2 / Skill one / 1",
                           severity=C.WARNING)
        self.assertEqual("2 / Front glide / 1", ids.step_label("2.front-glide.1"))

    def test_A5_activities_depths_flags_and_template_activities(self):
        cur, _ = self.check()
        self.assertIs(True, cur.step("2.skill-seven.4")["nearWall"])  # like 2.tread-water.4
        self.assertIs(True, cur.step("3.skill-seven.1")["nearWall"])  # like 3.tread-water.1
        self.assertEqual(["bob-game", "dip-game", "float-game"], block_of(cur.stage("4"), 1, "warmUp")["activityIds"])

        def stage_one(stage):
            skill_of(stage, "1.skill-one")["activityIds"].append("no-such-activity")
            step_of(stage, "1.skill-one.2")["depths"] = []
            step_of(stage, "1.skill-one.4")["nearWall"] = "yes"
            block_of(stage, 2, "introduce")["activityIds"].append("six-drill")
            block_of(stage, 3, "welcome")["activityIds"].append("one-drill")
            block_of(stage, 7, "introduce")["depths"] = ["abyss"]
        self.edit("stages/1.json", stage_one)
        self.edit("stages/4.json", lambda s: step_of(s, "4.skill-four.1").update(depths=["medium", "deep"]))

        def activities(entries):
            find(entries, id="one-drill")["ages"] = ["P", "X"]
            find(entries, id="two-drill")["description"] = ""
            find(entries, id="splash-game-4")["depths"] = ["medium", "deep"]
            find(entries, id="toy-hunt")["submerges"] = "no"
            find(entries, id="wade-game")["nearWall"] = True
        self.edit("activities.json", activities)
        _cur, problems = self.check()
        self.assertProblem(problems, "activity-missing", "no-such-activity")
        self.assertProblem(problems, "depths", "1.skill-one.2", "non-empty")
        self.assertProblem(problems, "flag-type", "1.skill-one.4", "nearWall must be true or false")
        self.assertProblem(problems, "template-activity", "lesson template 2", "six-drill")
        self.assertProblem(problems, "template-activity", "lesson template 3", "one-drill", "the Greeting")
        self.assertProblem(problems, "depths", "lesson template 7", "abyss")
        self.assertProblem(problems, "headfirst-depths", "4.skill-four.1")
        self.assertProblem(problems, "activity-shape", "one-drill", "ages")
        self.assertProblem(problems, "activity-shape", "two-drill", "no description")
        self.assertProblem(problems, "headfirst-depths", "splash-game-4")
        self.assertProblem(problems, "flag-type", "toy-hunt", "submerges")
        self.assertProblem(problems, "flag-type", "wade-game", "steps only")

    def test_A6_warm_up_wrap_up_and_step_ranges(self):
        cur, _ = self.check()
        self.assertEqual("4.skill-one", cur.stage("4")["warmUpSkill"])  # Stage 4 warms up with its own skill...
        for n in (1, 2, 3, 4):  # ...but guide lessons 1–4 warm up without one
            self.assertNotIn("skillIds", block_of(cur.stage("4"), n, "warmUp"))
        self.assertEqual([1, 3], block_of(cur.stage("1"), 1, "introduce")["stepRange"])  # skills of 3 and 2 steps

        def mutate(stage):
            stage["warmUpSkill"] = "1.no-such-skill"
            block_of(stage, 1, "warmUp")["stepRange"] = [1, 9]
            block_of(stage, 2, "wrapUp")["stepRange"] = [3, 1]
            block_of(stage, 3, "introduce")["stepRange"] = [4, 4]
        self.edit("stages/1.json", mutate)
        self.edit("stages/2.json", lambda s: s.update(wrapUpSkill="2.skill-nine"))
        _cur, problems = self.check()
        self.assertProblem(problems, "warm-up-wrap-up", "warmUpSkill", "1.no-such-skill")
        self.assertProblem(problems, "warm-up-wrap-up", "wrapUpSkill", "2.skill-nine")
        self.assertProblem(problems, "step-range", "lesson template 1", "ends past")
        self.assertProblem(problems, "step-range", "lesson template 2", "1 ≤ first ≤ last")
        self.assertProblem(problems, "step-range", "lesson template 3", "starts past")

    def test_A7_tracker_rows(self):
        cur, _ = self.check()
        six = cur.stage("6")["trackerRows"]
        self.assertEqual({"text": "Skill Eight, left or right", "rule": "any",
                          "stepIds": ["6.skill-eight-left.2", "6.skill-eight-right.3"]}, six[7])
        self.assertTrue(all(r["rule"] == "all" and len(r["stepIds"]) == 1 for r in six[:7]))
        self.assertNotIn("5.skill-eight-left", [ids.parse_step_id(s)[0] + "." + ids.parse_step_id(s)[1]
                                                for r in cur.stage("5")["trackerRows"] for s in r["stepIds"]])
        self.assertEqual(64, sum(len(cur.stage(s)["trackerRows"]) for s in ids.STAGE_IDS))
        table = {s: [{"text": r["text"], "rule": r["rule"], "preschool": None,
                      "skills": [ids.parse_step_id(x)[1] for x in r["stepIds"]]} for r in cur.stage(s)["trackerRows"]]
                 for s in ids.STAGE_IDS}
        table["2"][1]["preschool"] = table["3"][5]["preschool"] = "variant"
        self.assertEqual([], tracker_mismatches(cur, table))

        def mutate(stage):
            rows = stage["trackerRows"]
            rows[0]["stepIds"] = ["2.skill-one.2"]
            rows[1]["text"] = "Skill Two, step three"
            rows[2]["rule"] = "any"
            del rows[3]
        self.edit("stages/2.json", mutate)
        self.edit("stages/3.json", lambda s: s.update(trackerRows=[]))
        _cur, problems = self.check()
        self.assertProblem(problems, "tracker-row", "2.skill-one.2", "not its skill's benchmark")
        self.assertProblem(problems, "tracker-row", "Skill Two, step three", "differs from its benchmark step's name")
        self.assertProblem(problems, "tracker-row", "\"any\" needs two or more")
        self.assertProblem(problems, "tracker-coverage", "2.skill-four")
        self.assertProblem(problems, "tracker-rows-missing", "Stage 3")

    def test_A8_preschool_values_only_where_the_tracker_prints_them(self):
        cur, _ = self.check()
        with_value = {step["id"] for stage in cur.stages for skill in stage["skills"] for step in skill["steps"]
                      if "preschoolValue" in (step.get("measure") or {})}
        self.assertEqual({"2.skill-two.3", "3.skill-six.3"}, with_value)
        self.assertEqual({"kind": "distance", "value": 10, "unit": "ft", "preschoolValue": 5},
                         cur.step("2.skill-two.3")["measure"])
        self.edit("stages/1.json", lambda s: step_of(s, "1.skill-one.2").update(
            measure={"kind": "time", "value": 20, "unit": "s", "preschoolValue": 10}))
        self.edit("stages/2.json", lambda s: step_of(s, "2.skill-two.3")["measure"].update(preschoolValue=12))
        _cur, problems = self.check()
        self.assertProblem(problems, "preschool-value", "1.skill-one.2", "only a benchmark step")
        self.assertProblem(problems, "preschool-value", "2.skill-two.3", "not less than", severity=C.WARNING)

    def test_A9_unique_ids_and_local_json(self):
        cur, _ = self.check()
        self.assertEqual("local", cur.activity("local-relay")["source"])
        self.assertEqual("foam-dice", cur.equipment[-1]["id"])  # local items come last in catalog order
        self.edit("local.json", lambda local: local.update(
            format="local/2", rules=[],
            activities=local["activities"] + [dict(local["activities"][0], id="one-drill"),
                                              dict(local["activities"][0], id="our-game", source="ymca")],
            equipment=local["equipment"] + [{"id": "our-group", "name": "Our group", "aliases": [], "source": "local",
                                             "kind": "group", "anyOf": ["foam-dice"]}]))
        self.edit("activities.json", lambda entries: entries + [dict(entries[0]), dict(entries[1], id="kickboard")])
        _cur, problems = self.check()
        self.assertProblem(problems, "local-format", "\"local/2\"")
        self.assertProblem(problems, "local-format", "only format, activities and equipment", "rules")
        self.assertProblem(problems, "local-collision", "one-drill")
        self.assertProblem(problems, "local-entry", "our-game", "source \"local\"")
        self.assertProblem(problems, "local-entry", "our-group", "kind \"item\"")
        self.assertProblem(problems, "id-duplicate", "appears twice in activities.json")
        self.assertProblem(problems, "id-duplicate", "kickboard", "both a activity and a equipment item")

    def test_A10_corrupt_or_missing_files_give_a_readable_list(self):
        (self.dir / "stages" / "3.json").write_text("{not json", encoding="utf-8")
        (self.dir / "activities.json").unlink()
        self.edit("stages/5.json", lambda s: s.update(id="6"))
        self.edit("stages/1.json", lambda s: find(s["lessonTemplates"], n=4).update(blocks="TODO-M1"))
        self.edit("stages/2.json", lambda s: s.update(skills="not a list", topics=[1, 2]))
        self.edit("equipment.json", lambda entries: entries + [{"id": "odd", "kind": "item", "anyOf": 5, "aliases": 3}])
        cur, problems = self.check()  # never raises
        self.assertProblem(problems, "file-unreadable", "stages/3.json is not valid JSON (line 1")
        self.assertProblem(problems, "file-missing", "activities.json is missing")
        self.assertProblem(problems, "stage-file-invalid", "stages/5.json has id")
        self.assertProblem(problems, "template-placeholder", "Stage 1 lesson template 4 has no blocks yet")
        self.assertProblem(problems, "stage-shape", "Stage 2 has no skills list")
        self.assertNotIn("3", cur.loaded_stage_ids)
        self.assertFalse(C.can_plan(problems))
        out = io.StringIO()
        self.assertEqual(1, cli.main(["curriculum", "validate", "--dir", str(self.dir), "--errors-only"], out))
        self.assertIn("can't be planned on", out.getvalue())
        # garbage in every shape still gives problems, not an exception
        for garbage in ([], "text", {"id": "1", "skills": [1, {"id": 5, "steps": "x"}], "lessonTemplates": {"n": 1}}):
            (self.dir / "stages" / "1.json").write_text(json.dumps(garbage), encoding="utf-8")
            _cur, problems = self.check()
            self.assertTrue(C.errors(problems))

    def test_A11_continuum_link(self):
        cur, _ = self.check()
        self.assertIn("2.skill-two", C.prerequisite_of(cur, "1.skill-two.3"))  # like 1.front-glide.4 -> 2.front-glide
        self.assertIn("1.skill-two", C.advanced_of(cur, "2.skill-two.1"))
        self.assertTrue(C.prerequisites_satisfied(cur, "2.skill-two", {"1.skill-two.3"}))
        self.assertFalse(C.prerequisites_satisfied(cur, "2.skill-two", {"1.skill-two.2"}))
        self.assertTrue(C.prerequisites_satisfied(cur, "A.skill-one", set()))  # no prerequisite column
        self.assertFalse(C.prerequisites_satisfied(cur, "2.no-such-skill", {"1.skill-two.3"}))

    def test_A12_videos(self):
        cur, _ = self.check()
        self.assertEqual(["5.skill-eight-right"], cur.video("vimeo:100000004")["skillIds"])
        self.assertEqual(["vimeo:100000001"], cur.skill("1.skill-one")["videoIds"])

        def videos(entries):
            entries[0]["url"] = "https://example.com/v/1"
            entries[1]["id"] = "youtube:1"
            entries[2]["url"] = "https://vimeo.com/999"
            entries[3]["skillIds"] = entries[3]["skillIds"] + ["4.no-such-skill"]
            entries[4]["stageIds"] = ["9"]
        self.edit("videos.json", videos)
        self.edit("stages/1.json", lambda s: skill_of(s, "1.skill-two").update(videoIds=["vimeo:999"]))
        _cur, problems = self.check()
        self.assertProblem(problems, "video", "vimeo:100000000", "not a Vimeo url")
        self.assertProblem(problems, "video", "youtube:1", "not vimeo:<number>")
        self.assertProblem(problems, "video", "vimeo:100000002", "Vimeo video 999")
        self.assertProblem(problems, "video-link", "4.no-such-skill")
        self.assertProblem(problems, "video-link", "stage '9'")
        self.assertProblem(problems, "video-link", "vimeo:999", "not in videos.json")

    def test_A13_equipment_catalog(self):
        cur, _ = self.check()
        group = cur.equipment_entry("flotation-device")
        self.assertEqual(("group", ["kickboard", "pool-noodle", "barbell", "float-belt", "life-jacket", "pull-buoy"]),
                         (group["kind"], group["anyOf"]))
        self.assertEqual([["life-jacket", "float-belt"]], cur.step("2.skill-seven.1")["equipment"])
        self.assertEqual([["life-jacket"]], block_of(cur.stage("1"), 7, "introduce")["equipment"])
        catalog = json.loads((DATA / "equipment.json").read_text(encoding="utf-8"))
        self.assertEqual(CATALOG_ITEMS + ["flotation-device"], [e["id"] for e in catalog])
        self.assertTrue(all(e["source"] == "ymca" and e["kind"] == ("group" if e["id"] == "flotation-device" else "item")
                            for e in catalog))

        def activities(entries):
            find(entries, id="one-drill")["equipment"] = [["trampoline"]]
            find(entries, id="two-drill")["equipmentOptional"] = ["confetti"]
        self.edit("activities.json", activities)

        def stage_one(stage):
            step_of(stage, "1.skill-one.1")["equipment"] = [["jetpack"]]
            block_of(stage, 7, "introduce")["equipment"] = [["life-vest"]]
        self.edit("stages/1.json", stage_one)

        def catalog_edit(entries):
            find(entries, id="flotation-device")["anyOf"] = ["kickboard", "flotation-device", "raft"]
            find(entries, id="hoop")["anyOf"] = ["ball"]
        self.edit("equipment.json", catalog_edit)
        self.edit("local.json", lambda local: local["equipment"].append(
            {"id": "kickboard", "name": "Our kickboard", "aliases": [], "source": "local", "kind": "item"}))
        _cur, problems = self.check()
        for missing in ("trampoline", "confetti", "jetpack", "life-vest"):
            self.assertProblem(problems, "equipment-unknown", missing)
        self.assertProblem(problems, "equipment-catalog", "'flotation-device'", "not an item")
        self.assertProblem(problems, "equipment-catalog", "'raft'", "not in the catalog")
        self.assertProblem(problems, "equipment-catalog", "'hoop'", "anyOf is on groups only")
        self.assertProblem(problems, "local-collision", "kickboard")

    def test_A14_safety_rules(self):
        rules = json.loads((MINI / "safety.json").read_text(encoding="utf-8"))
        single = find(rules, id="single-inhalation")
        self.assertEqual(["submerges"], single["tags"])
        self.assertTrue(single["text"].strip())
        self.assertEqual(len(rules), len({r["id"] for r in rules}))
        self.assertTrue(all(set(r) == {"id", "text", "tags"} for r in rules))
        self.edit("safety.json", lambda entries: [dict(e, tags=[]) if e["id"] == "single-inhalation" else e
                                                  for e in entries] + [dict(entries[1]), {"id": "no-text", "tags": []}])
        _cur, problems = self.check()
        self.assertProblem(problems, "safety", "tags must be")
        self.assertProblem(problems, "id-duplicate", "deck-diving")
        self.assertProblem(problems, "safety", "'no-text' has no text")
        self.edit("safety.json", lambda entries: [e for e in entries if e["id"] != "single-inhalation"])
        _cur, problems = self.check()
        self.assertProblem(problems, "safety", "no single-inhalation rule")


class SampleTests(unittest.TestCase):

    def test_sample_loads_and_validates(self):
        cur, problems = C.check(SAMPLE)
        self.assertEqual(["1"], cur.loaded_stage_ids)
        self.assertEqual([], [str(p) for p in C.errors(problems)])
        self.assertTrue(C.can_plan(problems))  # M1 filled templates 2–4 and 6–8 and the tracker rows (A10, D9)
        self.assertEqual([1, 2, 3, 4, 5, 6, 7, 8], [t["n"] for t in cur.stage("1")["lessonTemplates"]])
        self.assertEqual(9, len(cur.stage("1")["trackerRows"]))
        self.assertEqual(["1.front-glide"], cur.activity("comet-rocket-ride")["skillIds"])  # derived from the skills
        self.assertEqual("ymca", cur.activity("comet-rocket-ride")["source"])
        self.assertIn("1.submerge.4", cur.skill("1.submerge")["stepIds"])
        warned = {p.code for p in C.warnings(problems)}
        self.assertLessEqual(warned, {"link-not-loaded"})

    def test_stage2_and_stage4_samples_load_and_validate(self):
        """The Stage 2 and Stage 4 samples (M2's deep-water, dive and 40-minute cases)."""
        for stage_id in ("2", "4"):
            path = EXAMPLES / ("curriculum.stage%s.sample.json" % stage_id)
            with self.subTest(stage=stage_id):
                cur, problems = C.check(path)
                self.assertEqual([stage_id], cur.loaded_stage_ids)
                self.assertEqual([], [str(p) for p in C.errors(problems)])
                self.assertTrue(C.can_plan(problems))


@unittest.skipUnless((REAL / "stages").is_dir(), "curriculum/stages/ does not exist yet (M1 transcription)")
class RealCurriculumTests(unittest.TestCase):
    """The owner's transcription, read-only: validated, and its tracker rows held against
    the Progress Tracker table (CURRICULUM_FORMAT.md §4.2)."""

    @classmethod
    def setUpClass(cls):
        cls.cur, cls.problems = C.check(REAL)
        cls.table = json.loads(BENCHMARKS.read_text(encoding="utf-8"))["stages"] if BENCHMARKS.is_file() else None

    def test_real_curriculum_has_no_errors(self):
        found = [str(p) for p in C.errors(self.problems)]
        self.assertEqual([], found[:30], "%d errors" % len(found))

    def test_A1_real_all_eight_stages_load(self):
        missing = [s for s in ids.STAGE_IDS if s not in self.cur.loaded_stage_ids]
        if missing:
            self.skipTest("M1 in progress: Stages %s not assembled yet" % ", ".join(missing))
        self.assertEqual(list(ids.STAGE_IDS), self.cur.loaded_stage_ids)

    def test_A7_A8_real_tracker_rows_match_the_progress_tracker(self):
        if self.table is None:
            self.skipTest("no Progress Tracker table (curriculum/_work/benchmarks.json)")
        self.assertEqual(69, sum(len(rows) for rows in self.table.values()))
        self.assertEqual([], tracker_mismatches(self.cur, self.table))

    def test_A5_A6_A11_real_landmarks(self):
        checks = {
            "1": lambda: self.assertIn("1.front-glide.4", self.cur.skill("2.front-glide")["prerequisiteStepIds"])
            if self.cur.is_loaded("2") else None,
            "2": lambda: self.assertIs(True, self.cur.step("2.tread-water.4").get("nearWall")),
            "3": lambda: self.assertIs(True, self.cur.step("3.tread-water.1").get("nearWall")),
            "4": lambda: self.assertEqual("4.endurance", self.cur.stage("4")["warmUpSkill"]),
            "5": lambda: self.assertIsNone(self.cur.skill("5.resting-stroke-elementary-backstroke")["benchmarkStepId"]),
        }
        for stage_id, check in checks.items():
            if self.cur.is_loaded(stage_id):
                with self.subTest(stage=stage_id):
                    check()

    def test_A14_real_safety(self):
        self.assertEqual([], [str(p) for p in self.problems if p.code == "safety"])
        single = find(self.cur.safety, id="single-inhalation")
        self.assertEqual(SINGLE_INHALATION_SHA256, hashlib.sha256(single["text"].encode("utf-8")).hexdigest(),
                         "the single-inhalation rule is not the libraries' sentence word for word")


if __name__ == "__main__":
    unittest.main()
