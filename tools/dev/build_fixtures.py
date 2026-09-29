"""Build the v2 fixtures in examples/ from the Stage 1 sample (TEST_CASES.md "Fixtures").

    python3 tools/dev/build_fixtures.py

Writes, deterministically, from the reference implementation (V5 shapes; DECISIONS_LOG
2026-09-12, the second-review entries and the owner's answers):

  examples/pool.shallow.json                         shallow only, diving off, tot-dock on, the five profile
                                                     items (P6) with kickboard off
  examples/class.stage1.json                         class c-stage1-mw with days 1–4 saved as the app shows
                                                     them: one activity per block (D10)
  examples/day-plan.stage1.day5.expected.json        plan_day(day 5), canonical JSON (D9)
  examples/shuffle.stage1.day5.expected.json         day 5's warm-up shuffled twice, then its review once (D4)
  examples/finder.stage1.expected.json               finder pages, the browse list and three searches (F1–F4, F6, F7)
  examples/manifest.json                             the cases with their facts and hashes: the day-5 plan, the
                                                     shuffle, the finder, the profile items (P6), today by date
                                                     (C7), the days that save themselves (D11); the S* schedule
                                                     cases are carried over

Re-run after any change to the Stage 1 sample or to the algorithms, then read the
diff: the manifest's facts are what the tests hold.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools.core import activities as ACT  # noqa: E402
from tools.core import canonical  # noqa: E402
from tools.core import classes as CL  # noqa: E402
from tools.core import curriculum as C  # noqa: E402
from tools.core import day_plan  # noqa: E402
from tools.core import finder  # noqa: E402

EXAMPLES = ROOT / "examples"
SAMPLE = EXAMPLES / "curriculum.stage1.sample.json"
CLASS_ID = "c-stage1-mw"
POOL_OFF = "kickboard"
TODAY_DATES = ("2026-09-21", "2026-09-28", "2026-09-29", "2026-10-08")
SAVE_THROUGH_DATES = ("2026-09-27", "2026-09-28", "2026-10-05", "2026-10-08")
SEARCHES = ("glide", "GLIDE", "zzz")


def write(name, value):
    text = canonical.dumps(value) + "\n"
    (EXAMPLES / name).write_text(text, encoding="utf-8")
    return canonical.sha256_hex(text)


def fail(problems):
    for item in problems:
        print("%s: %s: %s [%s]" % (item.severity, item.where, item.message, item.code))
    sys.exit(1)


def main():
    curriculum = C.load(SAMPLE)
    problems = C.validate(curriculum)
    if C.errors(problems):
        fail(problems)

    profile = ACT.profile_items(curriculum)
    assert POOL_OFF in profile, "%s must be profile equipment for the fixture pool to hide anything" % POOL_OFF
    pool = ACT.default_pool(curriculum)
    pool["depths"] = {"shallow": True, "medium": False, "deep": False}
    pool["diving"] = False
    pool["equipment"][POOL_OFF] = False
    write("pool.shallow.json", {"format": "pool/1", "items": [pool]})

    class_, problems = CL.new_class(curriculum, "1", ["mon", "wed"], "2026-09-14", age_group="schoolAge",
                                    class_id=CLASS_ID)
    if problems:
        fail(problems)
    for n in (1, 2, 3, 4):
        class_, entry, problems = day_plan.save_day(curriculum, class_, pool, n)
        if entry is None:
            fail(problems)
    assert class_["draft"] is None
    write("class.stage1.json", {"format": "classes/1", "items": [class_]})

    plan, problems = day_plan.plan_day(curriculum, class_, pool, 5)
    if plan is None:
        fail(problems)
    plan_hash = write("day-plan.stage1.day5.expected.json", plan)

    # shuffle: day 5's warm-up (one activity shown) twice, then its review once
    working, first, problems = day_plan.shuffle(curriculum, class_, pool, 5, "warmUp")
    if first is None:
        fail(problems)
    working, second, problems = day_plan.shuffle(curriculum, working, pool, 5, "warmUp")
    if second is None:
        fail(problems)
    working, review, problems = day_plan.shuffle(curriculum, working, pool, 5, "review")
    if review is None:
        fail(problems)
    shuffles = {"classId": CLASS_ID, "n": 5, "warmUp": [first, second], "review": review}
    shuffle_hash = write("shuffle.stage1.day5.expected.json", shuffles)

    queries = [
        {"id": "stage", "skillId": None, "step": None, "ageTag": None},
        {"id": "skill", "skillId": "1.front-glide", "step": None, "ageTag": None},
        {"id": "skill-step", "skillId": "1.front-glide", "step": 2, "ageTag": None},
        {"id": "skill-age", "skillId": "1.front-glide", "step": None, "ageTag": "S"},
    ]
    results = []
    for query in queries:
        pages = []
        for page_number in (1, 2):
            result, problems = finder.find(curriculum, "1", pool, query["skillId"], query["step"], query["ageTag"],
                                           page_number)
            if result is None:
                fail(problems)
            pages.append(result)
        results.append({"id": query["id"], "pages": pages})
    browse, problems = finder.browse(curriculum, "1", pool)
    if browse is None:
        fail(problems)
    searches = []
    for text in SEARCHES:
        result, problems = finder.search(curriculum, "1", pool, text)
        if result is None:
            fail(problems)
        searches.append(result)
    finder_hash = write("finder.stage1.expected.json",
                        {"stageId": "1", "queries": results, "browse": browse, "search": searches})

    today_cases = []
    for date in TODAY_DATES:
        today_cases.append({"date": date, "today": CL.today([class_], date), "next": CL.next_lesson([class_], date),
                            "missed": CL.missed([class_], date)})

    save_cases = []
    for date in SAVE_THROUGH_DATES:
        through, saved_days, problems = day_plan.save_through(curriculum, class_, pool, date)
        if problems:
            fail(problems)
        save_cases.append({"date": date, "saved": saved_days,
                           "entries": [CL.log_entry(through, n) for n in saved_days]})

    existing = {}
    manifest_path = EXAMPLES / "manifest.json"
    if manifest_path.exists():
        existing = json.loads(manifest_path.read_text(encoding="utf-8"))
    schedule_cases = [case for case in existing.get("cases", []) if str(case.get("id", "")).startswith("S")]
    blocks = {b["kind"]: b for b in plan["blocks"]}
    manifest = {
        "format": "manifest/2",
        "note": ("Expected outcomes for the v2 fixtures (V5 shapes), written by tools/dev/build_fixtures.py from "
                 "the reference implementation over examples/curriculum.stage1.sample.json, "
                 "examples/pool.shallow.json (shallow only, diving off, the five profile items with kickboard off) "
                 "and examples/class.stage1.json (Stage 1, school age, Mon/Wed from 2026-09-14, days 1-4 saved "
                 "with one activity per block as the app shows them). The hashes are SHA-256 of the canonical "
                 "JSON files plus a trailing newline; the tests hold the files byte for byte and the facts "
                 "listed here. S* cases: expected dates = schedule.lesson_dates(startDate, weekdays, "
                 "lessonCount, skipDates), carried from v1."),
        "cases": [
            {"id": "D9.day5", "inputs": {"curriculum": SAMPLE.name, "class": "class.stage1.json",
                                          "pool": "pool.shallow.json", "day": 5},
             "expected": {"file": "day-plan.stage1.day5.expected.json", "sha256": plan_hash,
                          "date": plan["date"], "guideLesson": plan["guideLesson"],
                          "blockKinds": [b["kind"] for b in plan["blocks"]],
                          "minutes": [b["minutes"] for b in plan["blocks"]],
                          "welcomeActivityIds": blocks["welcome"]["activityIds"],
                          "warmUpActivityIds": blocks["warmUp"]["activityIds"],
                          "reviewActivityIds": blocks["review"]["activityIds"],
                          "wrapUpActivityIds": blocks["wrapUp"]["activityIds"],
                          "introduceIsAny": True,
                          "doneSetSize": len(CL.done_set(class_))}},
            {"id": "D4.shuffle", "inputs": {"class": "class.stage1.json", "pool": "pool.shallow.json", "day": 5},
             "expected": {"file": "shuffle.stage1.day5.expected.json", "sha256": shuffle_hash,
                          "warmUpFirst": first["activityIds"], "warmUpSecond": second["activityIds"],
                          "reviewActivityIds": review["activityIds"], "reviewMessage": review.get("message")}},
            {"id": "F1.finder", "inputs": {"curriculum": SAMPLE.name, "pool": "pool.shallow.json", "stage": "1"},
             "expected": {"file": "finder.stage1.expected.json", "sha256": finder_hash,
                          "stageTotal": results[0]["pages"][0]["total"],
                          "frontGlideTotal": results[1]["pages"][0]["total"],
                          "frontGlideStep2FirstPage": results[2]["pages"][0]["activityIds"],
                          "browseGroupSizes": [len(g["activityIds"]) for g in browse["groups"]]}},
            {"id": "F7.search", "inputs": {"curriculum": SAMPLE.name, "pool": "pool.shallow.json", "stage": "1",
                                            "texts": list(SEARCHES)},
             "expected": {"file": "finder.stage1.expected.json",
                          "groups": [[{"skillId": g["skillId"], "activityIds": g["activityIds"]} for g in s["groups"]]
                                     for s in searches]}},
            {"id": "P6.profile", "inputs": {"curriculum": SAMPLE.name},
             "expected": {"profileItems": profile, "poolOff": POOL_OFF}},
            {"id": "C7.today", "inputs": {"class": "class.stage1.json", "dates": list(TODAY_DATES)},
             "expected": {"cases": today_cases}},
            {"id": "D11.saveThrough", "inputs": {"curriculum": SAMPLE.name, "class": "class.stage1.json",
                                                  "pool": "pool.shallow.json", "dates": list(SAVE_THROUGH_DATES)},
             "expected": {"cases": save_cases}},
        ] + schedule_cases,
    }
    write("manifest.json", manifest)
    print("Wrote fixtures: day-5 plan %s..., shuffle %s..., finder %s..." % (plan_hash[:12], shuffle_hash[:12], finder_hash[:12]))
    print("profile items:", profile)
    print("done set after days 1-4: %d activities" % len(CL.done_set(class_)))
    print("day 5 shows:", {k: b["activityIds"] for k, b in blocks.items()})
    print("warm-up shuffles:", first["activityIds"], "|", second["activityIds"], "| review:", review)
    for case in today_cases:
        print("today", case)


if __name__ == "__main__":
    main()
