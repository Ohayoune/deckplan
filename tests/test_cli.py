"""The command line over the fixtures: each command runs, refuses cleanly, and --json writes
exactly the canonical value the tests hold."""

import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.core import cli

from tests.v2support import EXAMPLES, SAMPLE, read_text


class CliTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.class_file = self.dir / "class.json"
        shutil.copyfile(EXAMPLES / "class.stage1.json", self.class_file)
        self.common = ["--curriculum", str(SAMPLE), "--pool", str(EXAMPLES / "pool.shallow.json")]

    def tearDown(self):
        shutil.rmtree(self.dir)

    def run_cli(self, *argv):
        out = io.StringIO()
        code = cli.main(list(argv), out)
        return code, out.getvalue()

    def test_plan_prints_and_writes_the_fixture_json(self):
        target = self.dir / "plan.json"
        code, text = self.run_cli("plan", "--class", str(self.class_file), "--day", "5", "--json", str(target), *self.common)
        self.assertEqual(0, code, text)
        self.assertIn("Day 5 · 2026-09-28 · guide lesson 5 · new", text)
        self.assertIn("Review · 5 min · Front Float, Back Glide", text)
        self.assertIn("pick a skill:", text)
        self.assertEqual(read_text("day-plan.stage1.day5.expected.json"), target.read_text(encoding="utf-8"))

    def test_shuffle_pick_and_save(self):
        # a saved day shuffles too (DECISIONS_LOG 2026-09-13 "A day saves itself")
        code, text = self.run_cli("shuffle", "--class", str(self.class_file), "--day", "2", "--block", "review", *self.common)
        self.assertEqual(0, code, text)
        self.assertIn("Review · shuffle 1", text)
        code, text = self.run_cli("pick", "--class", str(self.class_file), "--day", "5", "--block", "introduce",
                                  "--skill", "Roll", "--write", *self.common)
        self.assertEqual(0, code, text)
        self.assertIn("Introduce · 10 min · Roll", text)
        saved = json.loads(self.class_file.read_text(encoding="utf-8"))
        self.assertEqual(5, saved["items"][0]["draft"]["n"])
        code, text = self.run_cli("shuffle", "--class", str(self.class_file), "--day", "5", "--block", "warmUp", "--write", *self.common)
        self.assertEqual(0, code, text)
        self.assertIn("Warm-up · shuffle 1", text)
        self.assertNotIn("no more new activities for this block", text)
        code, text = self.run_cli("save", "--class", str(self.class_file), "--day", "5", *self.common)
        self.assertEqual(0, code, text)
        self.assertIn("Day 5 saved (2026-09-28). Next: day 6.", text)
        saved = json.loads(self.class_file.read_text(encoding="utf-8"))["items"][0]
        self.assertIsNone(saved["draft"])
        self.assertEqual([1, 2, 3, 4, 5], [e["n"] for e in saved["log"]])
        self.assertEqual(["dragon-roll"], saved["log"][4]["blocks"][3]["activityIds"])

    def test_pick_refuses_an_unknown_skill_with_the_list(self):
        code, text = self.run_cli("pick", "--class", str(self.class_file), "--day", "5", "--block", "introduce",
                                  "--skill", "butterfly", *self.common)
        self.assertEqual(1, code)
        self.assertIn("front-glide", text)

    def test_class_new_writes_a_classes_document(self):
        target = self.dir / "new.json"
        code, text = self.run_cli("class", "new", "--stage", "1", "--weekdays", "tue,thu", "--first-date", "2026-09-15",
                                  "--out", str(target), "--curriculum", str(SAMPLE))
        self.assertEqual(0, code, text)
        document = json.loads(target.read_text(encoding="utf-8"))
        self.assertEqual("classes/1", document["format"])
        self.assertEqual("Stage 1 · Tue Thu", document["items"][0]["name"])
        code, text = self.run_cli("class", "new", "--stage", "1", "--weekdays", "someday", "--first-date", "2026-09-15",
                                  "--out", str(target), "--curriculum", str(SAMPLE))
        self.assertEqual(1, code)
        self.assertIn("class-weekdays", text)

    def test_find_and_browse(self):
        target = self.dir / "find.json"
        code, text = self.run_cli("find", "--stage", "1", "--skill", "front-glide", "--step", "2", "--json", str(target), *self.common)
        self.assertEqual(0, code, text)
        self.assertIn("Stage 1 · Front Glide · step 2 · page 1 of 12 activities", text)
        self.assertIn("- Puffin Rocket Ride — needs pool noodle", text)
        written = json.loads(target.read_text(encoding="utf-8"))
        fixture = json.loads(read_text("finder.stage1.expected.json"))
        self.assertEqual(next(q for q in fixture["queries"] if q["id"] == "skill-step")["pages"][0], written)
        code, text = self.run_cli("browse", "--stage", "1", "--age", "S", *self.common)
        self.assertEqual(0, code, text)
        self.assertIn("Greeting (11)", text)
        self.assertNotIn("Snowflake Hide and Seek", text)
        code, text = self.run_cli("find", "--stage", "1", "--skill", "nope", *self.common)
        self.assertEqual(1, code)

    def test_search_and_today(self):
        target = self.dir / "search.json"
        code, text = self.run_cli("search", "--stage", "1", "--text", "GLIDE", "--json", str(target), *self.common)
        self.assertEqual(0, code, text)
        self.assertIn("Front Glide (2)", text)
        self.assertIn("  - Manatee Glide", text)
        self.assertNotIn("Greeting", text)
        fixture = json.loads(read_text("finder.stage1.expected.json"))
        self.assertEqual(fixture["search"][1], json.loads(target.read_text(encoding="utf-8")))
        code, text = self.run_cli("search", "--stage", "1", "--text", "zzz", *self.common)
        self.assertEqual(0, code, text)
        self.assertIn("nothing named like 'zzz'", text)
        target = self.dir / "today.json"
        code, text = self.run_cli("today", "--class", str(self.class_file), "--date", "2026-09-29", "--json", str(target),
                                  "--curriculum", str(SAMPLE))
        self.assertEqual(0, code, text)
        self.assertIn("Nothing on 2026-09-29. Next: Stage 1 · Mon Wed · day 6 of 8 on 2026-09-30.", text)
        self.assertIn("Not saved: Stage 1 · Mon Wed · day 5 of 8 on 2026-09-28.", text)
        written = json.loads(target.read_text(encoding="utf-8"))
        self.assertEqual(([], 6, [5]), (written["today"], written["next"]["n"], [m["n"] for m in written["missed"]]))
        code, text = self.run_cli("today", "--class", str(self.class_file), "--date", "2026-09-28", "--curriculum", str(SAMPLE))
        self.assertEqual(0, code, text)
        self.assertIn("Today 2026-09-28: Stage 1 · Mon Wed · day 5 of 8", text)
        self.assertNotIn("Not saved", text)
        code, text = self.run_cli("today", "--class", str(self.class_file), "--date", "2026-10-08", "--curriculum", str(SAMPLE))
        self.assertIn("Nothing on 2026-10-08 and no lesson after it.", text)

    def test_bad_files(self):
        bad = self.dir / "bad.json"
        bad.write_text('{"format": "pool/1"}', encoding="utf-8")
        code, text = self.run_cli("plan", "--class", str(bad), "--day", "1", "--curriculum", str(SAMPLE))
        self.assertEqual(1, code)
        self.assertIn("not a classes/1 document", text)
        code, _ = self.run_cli("plan", "--class", str(self.class_file), "--day", "1", "--curriculum", str(SAMPLE), "--pool", str(bad))
        self.assertEqual(1, code)
        self.assertEqual(2, self.run_cli("plan")[0])


if __name__ == "__main__":
    unittest.main()
