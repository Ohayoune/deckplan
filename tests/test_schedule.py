"""TEST_CASES.md group S — schedule and lesson dates (M2; SPEC §6.13, D27).

Dates for S1-S4 and S8 are the `S*` fixtures in examples/manifest.json, checked here
against `schedule.lesson_dates` case by case. S5-S7 exercise the edit operations
(skip/cancel/move) on sessions built with `schedule.new_session_lessons`. S9 is chiefly a
UI concern (Today's sort by class order); the optional `today_lessons` helper gets a light
check. S10 reproduces TEST_CASES.md's own worked example for `report_prompts`. A few extra
methods (not tied to a numbered case) cover the rest of the module's interface:
`change_weekdays`, `next_open_lesson`, `last_marked_lesson`, `mid_session_lesson_n`,
`weeks_span` and `describe_session`.
"""

import json
import unittest
from pathlib import Path

from tools.core import schedule as S

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "examples" / "manifest.json"


def load_cases(prefix):
    """The manifest's S* cases whose id is `prefix` or starts with `prefix.` — S1 covers
    S1.mon-wed, S1.tue-thu and S1.worked-example in one call."""
    with MANIFEST.open(encoding="utf-8") as f:
        cases = json.load(f)["cases"]
    return [c for c in cases if c["id"] == prefix or c["id"].startswith(prefix + ".")]


def build_session(start_date, weekdays, count=8):
    lessons = S.new_session_lessons(start_date, weekdays, count)
    return {"startDate": start_date, "lessonCount": count, "skipDates": [], "lessons": lessons}


def mark_lessons(session, *ns):
    """Test helper: flag lesson numbers `ns` as marked (schedule.py only reads the
    `marked` flag; full Mark records are state.py's concern)."""
    lessons = [dict(l, marked=True) if l["n"] in ns else dict(l) for l in session["lessons"]]
    return dict(session, lessons=lessons)


class DatesFromManifestTests(unittest.TestCase):
    """S1-S4, S8: every manifest S* case's inputs through `schedule.lesson_dates`, checked
    against its exact expected date list."""

    def check_cases(self, prefix):
        cases = load_cases(prefix)
        self.assertTrue(cases, "no %s cases in examples/manifest.json" % prefix)
        for case in cases:
            inputs = case["inputs"]
            with self.subTest(case=case["id"]):
                dates = S.lesson_dates(inputs["startDate"], inputs["weekdays"],
                                       inputs["lessonCount"], inputs["skipDates"])
                self.assertEqual(case["expected"]["dates"], dates)

    def test_S1_mon_wed_and_tue_thu(self):
        self.check_cases("S1")

    def test_S2_sat_and_sun(self):
        self.check_cases("S2")

    def test_S3_start_not_a_class_day(self):
        self.check_cases("S3")

    def test_S4_skip_thanksgiving_and_holiday_weekend(self):
        self.check_cases("S4")

    def test_S8_custom_days_and_empty_set_refused(self):
        self.check_cases("S8")
        # an empty weekday set is refused (S8); so is a set of nothing but unrecognized
        # tokens, which would otherwise search forever for a weekday that never matches
        with self.assertRaises(ValueError):
            S.lesson_dates("2026-06-15", [], 8, [])
        with self.assertRaises(ValueError):
            S.lesson_dates("2026-06-15", ["someday"], 8, [])


class SkipDateTests(unittest.TestCase):
    """S5: skipping mid-session re-dates only open lessons on/after the date; marked
    lessons keep their dates; a date holding a marked lesson is refused."""

    def setUp(self):
        self.weekdays = ["mon", "wed"]
        self.session = build_session("2026-09-14", self.weekdays)  # S1.mon-wed's own dates

    def test_S5_skip_redates_only_open_lessons_on_or_after_the_date(self):
        session = mark_lessons(self.session, 1, 2)  # taught: Sep 14, Sep 16
        new_session, problems = S.skip_date(session, self.weekdays, "2026-09-28")  # lesson 5's date
        self.assertEqual([], problems)

        by_n = {l["n"]: l["date"] for l in new_session["lessons"]}
        self.assertEqual("2026-09-14", by_n[1])  # marked: keeps its date
        self.assertEqual("2026-09-16", by_n[2])  # marked: keeps its date
        self.assertEqual("2026-09-21", by_n[3])  # open, before the skip date: untouched
        self.assertEqual("2026-09-23", by_n[4])  # open, before the skip date: untouched
        self.assertEqual("2026-09-30", by_n[5])  # open, on the skip date: moves on
        self.assertEqual("2026-10-05", by_n[6])
        self.assertEqual("2026-10-07", by_n[7])
        self.assertEqual("2026-10-12", by_n[8])
        self.assertEqual(["2026-09-28"], new_session["skipDates"])
        self.assertEqual(8, new_session["lessonCount"])  # still N lessons (D27)

        # the input session is untouched
        self.assertEqual([], session["skipDates"])
        self.assertEqual("2026-09-28", dict((l["n"], l) for l in session["lessons"])[5]["date"])

    def test_S5_skip_a_date_holding_a_marked_lesson_is_refused(self):
        session = mark_lessons(self.session, 1)  # lesson 1: Sep 14
        new_session, problems = S.skip_date(session, self.weekdays, "2026-09-14")
        self.assertEqual(1, len(problems))
        self.assertIn("2026-09-14", problems[0].message)
        self.assertIs(session, new_session)  # refused: unchanged, same object


class CancelLessonTests(unittest.TestCase):
    """S6: cancel keeps `n` and date and flags `cancelled`; later lessons keep their `n`
    and dates. (Attendance, marks and the plan are state.py's concern, not schedule.py's;
    absences-in-a-row skipping a cancelled lesson is tested there.)"""

    def test_S6_cancel_keeps_n_and_date_later_lessons_unchanged(self):
        session = build_session("2026-09-15", ["tue", "thu"])
        new_session = S.cancel_lesson(session, 3)

        by_n = {l["n"]: l for l in new_session["lessons"]}
        self.assertEqual("2026-09-22", by_n[3]["date"])  # keeps its date
        self.assertEqual(3, by_n[3]["n"])                # keeps its n
        self.assertTrue(by_n[3]["cancelled"])
        for n in (1, 2, 4, 5, 6, 7, 8):
            self.assertNotIn("cancelled", by_n[n])
            self.assertEqual(session["lessons"][n - 1]["date"], by_n[n]["date"])

        # the input is untouched
        self.assertNotIn("cancelled", session["lessons"][2])


class MoveLessonTests(unittest.TestCase):
    """S7: an open lesson accepts only a date strictly between its neighbours' dates;
    nothing else changes."""

    def setUp(self):
        self.session = build_session("2026-09-14", ["mon", "wed"])  # S1.mon-wed's own dates

    def test_S7_move_to_a_date_strictly_between_neighbours(self):
        # lesson 5: Sep 28, between lesson 4 (Sep 23) and lesson 6 (Sep 30)
        new_session, problems = S.move_lesson(self.session, 5, "2026-09-25")
        self.assertEqual([], problems)
        by_n = {l["n"]: l["date"] for l in new_session["lessons"]}
        self.assertEqual("2026-09-25", by_n[5])
        for n in (1, 2, 3, 4, 6, 7, 8):
            self.assertEqual(self.session["lessons"][n - 1]["date"], by_n[n])

    def test_S7_move_refused_at_or_past_a_neighbours_date(self):
        for bad_date in ("2026-09-23",   # == lesson 4's date (lower neighbour)
                         "2026-09-30",   # == lesson 6's date (upper neighbour)
                         "2026-10-01",   # past lesson 6
                         "2026-09-22"):  # before lesson 4
            with self.subTest(date=bad_date):
                unchanged, problems = S.move_lesson(self.session, 5, bad_date)
                self.assertEqual(1, len(problems))
                self.assertIs(self.session, unchanged)

    def test_S7_move_refused_for_a_marked_or_a_cancelled_lesson(self):
        marked = mark_lessons(self.session, 5)
        _, problems = S.move_lesson(marked, 5, "2026-09-25")
        self.assertEqual(1, len(problems))

        cancelled = S.cancel_lesson(self.session, 5)
        _, problems = S.move_lesson(cancelled, 5, "2026-09-25")
        self.assertEqual(1, len(problems))

    def test_S7_move_bounded_only_on_the_side_with_a_neighbour(self):
        # lesson 1 (first: no earlier neighbour) — any date before lesson 2 (Sep 16)
        new_session, problems = S.move_lesson(self.session, 1, "2026-09-01")
        self.assertEqual([], problems)
        self.assertEqual("2026-09-01", dict((l["n"], l) for l in new_session["lessons"])[1]["date"])
        # lesson 8 (last: no later neighbour) — any date after lesson 7 (Oct 5)
        new_session, problems = S.move_lesson(self.session, 8, "2026-12-25")
        self.assertEqual([], problems)


class TodayOrderTests(unittest.TestCase):
    """S9 is chiefly a UI case (Today sorts the day's lessons by class order, and two
    classes on the same weekday with the same order get a Class-screen warning, not an
    error — nothing a pure Core function raises or refuses). The optional
    `today_lessons` sort helper gets a light check here."""

    def test_S9_today_lessons_sorts_by_class_order_then_id(self):
        classes = [{"id": "c2", "order": 1}, {"id": "c1", "order": 1}, {"id": "c3", "order": 2}]
        sessions = {"c1": {"lessons": [{"n": 1, "date": "2026-09-15"}]},
                   "c2": {"lessons": [{"n": 1, "date": "2026-09-15"}]},
                   "c3": {"lessons": [{"n": 1, "date": "2026-09-15"}]}}
        rows = S.today_lessons(classes, sessions, "2026-09-15")
        # c1 and c2 share order 1 (the "warning, not an error" case); ties break by classId
        self.assertEqual(["c1", "c2", "c3"], [row["classId"] for row in rows])

    def test_S9_today_lessons_skips_classes_with_no_lesson_that_day(self):
        classes = [{"id": "c1", "order": 1}]
        sessions = {"c1": {"lessons": [{"n": 1, "date": "2026-09-15"}]}}
        self.assertEqual([], S.today_lessons(classes, sessions, "2026-09-16"))


class ReportPromptsTests(unittest.TestCase):
    """S10 (SPEC §6.5): the exact worked example, on S1.mon-wed's dates — lesson 4 on
    Wed Sep 23, lesson 8 on Wed Oct 7."""

    def setUp(self):
        dates = load_cases("S1.mon-wed")[0]["expected"]["dates"]
        lessons = [{"n": n, "date": d} for n, d in enumerate(dates, start=1)]
        self.session = {"lessonCount": 8, "lessons": lessons}

    def test_S10_no_prompt_before_the_mid_session_lesson(self):
        self.assertFalse(S.report_prompts(self.session, "2026-09-22")["midSession"])  # Tue

    def test_S10_mid_session_prompt_on_its_date_only_once_marked_or_cancelled(self):
        on_date = "2026-09-23"  # lesson 4's own date (Wed)
        self.assertFalse(S.report_prompts(self.session, on_date)["midSession"])
        self.assertTrue(S.report_prompts(mark_lessons(self.session, 4), on_date)["midSession"])
        self.assertTrue(S.report_prompts(S.cancel_lesson(self.session, 4), on_date)["midSession"])

    def test_S10_mid_session_prompt_from_the_next_day_regardless(self):
        prompts = S.report_prompts(self.session, "2026-09-24")  # Thu, lesson 4 still unmarked
        self.assertTrue(prompts["midSession"])

    def test_S10_certificate_prompt_on_its_date_only_once_marked(self):
        on_date = "2026-10-07"  # lesson 8's own date (Wed)
        self.assertFalse(S.report_prompts(self.session, on_date)["certificates"])
        self.assertTrue(S.report_prompts(mark_lessons(self.session, 8), on_date)["certificates"])

    def test_S10_certificate_prompt_from_the_next_day_regardless(self):
        prompts = S.report_prompts(self.session, "2026-10-08")  # Thu, lesson 8 still unmarked
        self.assertTrue(prompts["certificates"])


class ChangeWeekdaysTests(unittest.TestCase):
    """SPEC §6.13 "Change the class's days" has no TEST_CASES id of its own, but the
    brief's interface requires it: the open lessons are re-dated from the first open
    lesson's own current date, which may itself move onto a new weekday."""

    def test_change_weekdays_redates_open_lessons_from_first_open_lessons_date(self):
        session = build_session("2026-09-14", ["mon", "wed"])
        session = mark_lessons(session, 1, 2)  # taught: Mon Sep 14, Wed Sep 16

        new_session = S.change_weekdays(session, ["tue", "thu"])
        by_n = {l["n"]: l["date"] for l in new_session["lessons"]}
        self.assertEqual("2026-09-14", by_n[1])  # marked: untouched
        self.assertEqual("2026-09-16", by_n[2])  # marked: untouched
        # lesson 3 was Mon Sep 21; the first Tue/Thu on or after that is Tue Sep 22
        self.assertEqual(["2026-09-22", "2026-09-24", "2026-09-29", "2026-10-01",
                         "2026-10-06", "2026-10-08"], [by_n[n] for n in (3, 4, 5, 6, 7, 8)])


class LookupHelperTests(unittest.TestCase):
    """`next_open_lesson` and `last_marked_lesson` (SPEC §6.14's `lessonN` and its
    fallback), used by the planner and Recommend, not called out by their own S-case."""

    def test_next_open_lesson_and_last_marked_lesson(self):
        session = build_session("2026-09-14", ["mon", "wed"])
        self.assertEqual(1, S.next_open_lesson(session)["n"])
        self.assertIsNone(S.last_marked_lesson(session))

        session = mark_lessons(session, 1, 2)
        session = S.cancel_lesson(session, 3)
        self.assertEqual(4, S.next_open_lesson(session)["n"])
        self.assertEqual(2, S.last_marked_lesson(session)["n"])

    def test_next_open_lesson_is_none_once_every_lesson_is_closed(self):
        lessons = [{"n": 1, "date": "2026-09-14", "marked": True},
                  {"n": 2, "date": "2026-09-16", "cancelled": True}]
        self.assertIsNone(S.next_open_lesson({"lessons": lessons}))


class DescribeAndWeeksSpanTests(unittest.TestCase):
    """`weeks_span` and `describe_session` are "nice to have" (no TEST_CASES id), checked
    against SPEC §6.13's own illustrative example and D27's week counts."""

    def test_weeks_span_matches_spec_6_13_and_d27(self):
        tue_thu = load_cases("S1.tue-thu")[0]["expected"]["dates"]
        self.assertEqual(4, S.weeks_span(tue_thu))  # "Tue Sep 15 - Thu Oct 8 * 4 weeks"

        sat = load_cases("S2.sat")[0]["expected"]["dates"]
        self.assertEqual(8, S.weeks_span(sat))  # D27: Sat x 8 lessons = 8 weeks

    def test_describe_session_matches_spec_6_13_wording(self):
        dates = load_cases("S1.tue-thu")[0]["expected"]["dates"]
        session = {"lessonCount": 8, "lessons": [{"n": n, "date": d} for n, d in enumerate(dates, start=1)]}
        self.assertEqual("8 lessons · Tue Sep 15 – Thu Oct 8 · 4 weeks", S.describe_session(session))

    def test_mid_session_lesson_n_is_ceil_of_half(self):
        self.assertEqual(4, S.mid_session_lesson_n(8))
        self.assertEqual(3, S.mid_session_lesson_n(5))
        self.assertEqual(1, S.mid_session_lesson_n(1))


if __name__ == "__main__":
    unittest.main()
