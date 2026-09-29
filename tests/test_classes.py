"""C1–C4, C6, C7: classes, their order, dates, day numbering and today by date (TEST_CASES.md group C)."""

import unittest

from tools.core import classes as CL

from tests.v2support import fixture_class, manifest_case, sample


class CreateTests(unittest.TestCase):
    def setUp(self):
        self.curriculum = sample()

    def test_C1_defaults(self):
        class_, problems = CL.new_class(self.curriculum, "1", ["wed", "mon"], "2026-09-14", class_id="c1")
        self.assertEqual([], problems)
        self.assertEqual("Stage 1 · Mon Wed", class_["name"])
        self.assertEqual(8, class_["lessons"])
        self.assertEqual("preschool", class_["ageGroup"])
        self.assertEqual(1, class_["order"])
        self.assertEqual({"weekdays": ["mon", "wed"], "firstDate": "2026-09-14"}, class_["schedule"])
        self.assertEqual([], class_["log"])
        self.assertIsNone(class_["draft"])
        self.assertEqual("c1", class_["id"])
        other, _ = CL.new_class(self.curriculum, "1", ["sat"], "2026-09-19",
                                classes=[{"order": 1}, {"order": 4}], name="Saturdays", age_group="schoolAge", lessons=6)
        self.assertEqual((5, "Saturdays", "schoolAge", 6), (other["order"], other["name"], other["ageGroup"], other["lessons"]))
        self.assertNotEqual(class_["id"], other["id"])

    def test_C1_refusals(self):
        cases = {
            "class-stage": dict(stage_id="9", weekdays=["mon"], first_date="2026-09-14"),
            "class-age-group": dict(stage_id="1", weekdays=["mon"], first_date="2026-09-14", age_group="infantToddler"),
            "class-lessons": dict(stage_id="1", weekdays=["mon"], first_date="2026-09-14", lessons=0),
            "class-weekdays": dict(stage_id="1", weekdays=["someday"], first_date="2026-09-14"),
            "class-first-date": dict(stage_id="1", weekdays=["mon"], first_date="14/09/2026"),
        }
        for code, kwargs in cases.items():
            with self.subTest(code=code):
                stage_id = kwargs.pop("stage_id")
                class_, problems = CL.new_class(self.curriculum, stage_id, **kwargs)
                self.assertIsNone(class_)
                self.assertIn(code, [p.code for p in problems])

    def test_C2_list_order(self):
        classes = [{"id": "b", "order": 2, "name": "Beta"}, {"id": "a", "order": 1, "name": "Zulu"},
                   {"id": "c", "order": 2, "name": "Alpha"}]
        self.assertEqual(["a", "c", "b"], [c["id"] for c in CL.sorted_classes(classes)])

    def test_C3_delete_removes_the_class_and_leaves_the_rest_untouched(self):
        keep = fixture_class()
        gone = dict(fixture_class(), id="other", log=[{"n": 1, "date": "2026-01-01", "blocks": []}])
        result = CL.delete_class([keep, gone], "other")
        self.assertEqual([keep], result)
        self.assertIsNone(CL.find_class(result, "other"))


class DatesAndDaysTests(unittest.TestCase):
    def setUp(self):
        self.class_ = fixture_class()

    def test_C4_dates_follow_the_schedule(self):
        dates = CL.lesson_dates(self.class_)
        self.assertEqual(8, len(dates))
        self.assertEqual("2026-09-14", dates[0])
        self.assertEqual("2026-09-28", CL.lesson_date(self.class_, 5))
        self.assertIsNone(CL.lesson_date(self.class_, 9))

    def test_C6_next_day(self):
        self.assertEqual(4, CL.last_day_done(self.class_))
        self.assertEqual(5, CL.next_day(self.class_))
        self.assertFalse(CL.is_complete(self.class_))
        empty = dict(self.class_, log=[])
        self.assertEqual((0, 1), (CL.last_day_done(empty), CL.next_day(empty)))
        gaps = dict(self.class_, log=[{"n": n, "date": "2026-01-01", "blocks": []} for n in (1, 2, 5)])
        self.assertEqual((5, 6), (CL.last_day_done(gaps), CL.next_day(gaps)))
        full = dict(self.class_, log=[{"n": n, "date": "2026-01-01", "blocks": []} for n in range(1, 9)])
        self.assertIsNone(CL.next_day(full))
        self.assertTrue(CL.is_complete(full))

    def test_done_set_is_every_saved_activity(self):
        done = CL.done_set(self.class_)
        self.assertEqual(18, len(done))  # four days, one activity per block, snowflake-welcome twice (D10)
        self.assertIn("otter-bubbles", done)
        self.assertIn("tugboat-treasure-hunt", done)
        self.assertNotIn("sunflower-countdown", done)
        self.assertEqual(set(), CL.done_set(dict(self.class_, log=[])))

    def test_log_writes_replace_by_n_and_keep_the_log_sorted(self):
        entry = {"n": 2, "date": "2026-09-16", "blocks": [{"kind": "welcome", "activityIds": ["iceberg-wave"]}]}
        updated = CL.with_log_entry(self.class_, entry)
        self.assertEqual([1, 2, 3, 4], [e["n"] for e in updated["log"]])
        self.assertEqual(entry, CL.log_entry(updated, 2))
        self.assertEqual(4, len(self.class_["log"]))  # the original is untouched
        later = CL.with_log_entry(dict(self.class_, log=[]), {"n": 3, "date": "x", "blocks": []})
        later = CL.with_log_entry(later, {"n": 1, "date": "x", "blocks": []})
        self.assertEqual([1, 3], [e["n"] for e in later["log"]])

    def test_C7_day_on_today_next_and_missed_take_the_date_as_an_argument(self):
        class_ = self.class_
        self.assertEqual(5, CL.day_on(class_, "2026-09-28"))
        self.assertEqual(3, CL.day_on(class_, "2026-09-21"))  # saved days count too
        self.assertIsNone(CL.day_on(class_, "2026-09-29"))
        self.assertEqual([{"classId": "c-stage1-mw", "n": 5}], CL.today([class_], "2026-09-28"))
        self.assertEqual([], CL.today([class_], "2026-09-29"))
        self.assertEqual({"classId": "c-stage1-mw", "n": 6, "date": "2026-09-30"}, CL.next_lesson([class_], "2026-09-29"))
        self.assertEqual({"classId": "c-stage1-mw", "n": 5, "date": "2026-09-28"}, CL.next_lesson([class_], "2026-09-28"))
        self.assertIsNone(CL.next_lesson([class_], "2026-10-08"))
        self.assertEqual([], CL.missed([class_], "2026-09-28"))
        self.assertEqual([{"classId": "c-stage1-mw", "n": 5, "date": "2026-09-28"}], CL.missed([class_], "2026-09-29"))
        self.assertEqual([5, 6, 7, 8], [m["n"] for m in CL.missed([class_], "2026-10-08")])
        for case in manifest_case("C7.today")["expected"]["cases"]:
            with self.subTest(date=case["date"]):
                self.assertEqual(case["today"], CL.today([class_], case["date"]))
                self.assertEqual(case["next"], CL.next_lesson([class_], case["date"]))
                self.assertEqual(case["missed"], CL.missed([class_], case["date"]))
        # several classes: class order, then date order; a saved past day is not missed
        tue_thu = dict(class_, id="c-tt", name="Stage 1 · Tue Thu", order=2,
                       schedule={"weekdays": ["tue", "thu"], "firstDate": "2026-09-15"}, log=[])
        first = dict(class_, id="c-first", name="Earlier", order=0, log=[])
        classes = [tue_thu, class_, first]
        self.assertEqual([{"classId": "c-first", "n": 5}, {"classId": "c-stage1-mw", "n": 5}], CL.today(classes, "2026-09-28"))
        self.assertEqual({"classId": "c-first", "n": 5, "date": "2026-09-28"}, CL.next_lesson(classes, "2026-09-27"))
        self.assertEqual({"classId": "c-tt", "n": 1, "date": "2026-09-15"}, CL.next_lesson(classes, "2026-09-15"))
        missed = CL.missed(classes, "2026-09-17")
        self.assertEqual([("c-first", 1, "2026-09-14"), ("c-tt", 1, "2026-09-15"), ("c-first", 2, "2026-09-16")],
                         [(m["classId"], m["n"], m["date"]) for m in missed])  # the fixture class's days 1-2 are saved
        self.assertEqual([], CL.missed([], "2026-09-17"))
        self.assertIsNone(CL.next_lesson([], "2026-09-17"))

    def test_validate_class_accepts_the_fixture_and_names_shape_problems(self):
        self.assertEqual([], CL.validate_class(self.class_, sample()))
        broken = dict(self.class_, lessons=0, schedule={"weekdays": [], "firstDate": "2026-09-14"},
                      log=self.class_["log"] + [{"n": 1, "date": "x", "blocks": []}])
        codes = [p.code for p in CL.validate_class(broken)]
        self.assertIn("class-shape", codes)
        self.assertIn("class-log", codes)


if __name__ == "__main__":
    unittest.main()
