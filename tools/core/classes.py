"""Classes and their lesson logs (REDESIGN.md §2, §5; TEST_CASES C1–C7).

    Class  { "id", "name", "stageId", "ageGroup", "lessons": N, "order",
             "schedule": {"weekdays": ["mon", ...], "firstDate": "YYYY-MM-DD"},
             "log":   [ {"n", "date", "blocks": [{"kind", "activityIds"}]}, ... ]  sorted by n,
             "draft": null | {"n", "blocks": [{"kind", "skillIds", "activityIds"}],
                              "shuffleCounts": {"<kind>": int}} }

Every function is pure: it returns fresh dicts and never mutates its arguments.
Refusals are `curriculum.Problem` entries (never exceptions) so the CLI, the tests
and the Swift port report them the same way.
"""

from __future__ import annotations

import uuid
from typing import Any, Iterable

from . import ids
from . import schedule
from .curriculum import dict_items, problem

Class = dict[str, Any]

DEFAULT_LESSONS = 8
WEEKDAY_LABELS = {"mon": "Mon", "tue": "Tue", "wed": "Wed", "thu": "Thu", "fri": "Fri", "sat": "Sat", "sun": "Sun"}


# ---------------------------------------------------------------------------
# create, list, delete (C1–C3)

def ordered_weekdays(weekdays: Iterable[str]) -> list[str]:
    """The recognized weekdays in week order (mon..sun), deduped."""
    wanted = set(weekdays or ())
    return [day for day in schedule.WEEKDAY_NAMES if day in wanted]


def default_name(stage_id: str, weekdays: Iterable[str]) -> str:
    """"Stage 1 · Mon Wed" (C1)."""
    days = " ".join(WEEKDAY_LABELS[day] for day in ordered_weekdays(weekdays))
    return "Stage %s · %s" % (stage_id, days) if days else "Stage %s" % stage_id


def next_order(classes: Iterable[Class]) -> int:
    orders = [c.get("order") for c in classes or [] if isinstance(c.get("order"), int)]
    return (max(orders) + 1) if orders else 1


def new_class(curriculum, stage_id: str, weekdays: Iterable[str], first_date: str, *,
              classes: Iterable[Class] = (), name: str | None = None, age_group: str | None = None,
              lessons: int = DEFAULT_LESSONS, class_id: str | None = None) -> tuple[Class | None, list]:
    """A class with REDESIGN §5's defaults filled in, or None with the problems that
    stop it (an unloaded stage, an age group the stage has not, lessons < 1, no usable
    weekday, a bad date). `class_id` defaults to a fresh UUID."""
    problems = []
    stage = curriculum.stage(stage_id)
    if stage is None:
        problems.append(problem("class-stage", "class", "Stage %r is not in the curriculum." % (stage_id,)))
        return None, problems
    stage_ages = [g for g in stage.get("ageGroups") or [] if isinstance(g, str)]
    if age_group is None:
        age_group = stage_ages[0] if stage_ages else None
    if age_group not in stage_ages:
        problems.append(problem("class-age-group", "class", "Stage %s has no age group %r; it has %s."
                                % (stage_id, age_group, ", ".join(stage_ages) or "none")))
    if not isinstance(lessons, int) or isinstance(lessons, bool) or lessons < 1:
        problems.append(problem("class-lessons", "class", "A class needs at least one lesson, not %r." % (lessons,)))
    days = ordered_weekdays(weekdays)
    if not days:
        problems.append(problem("class-weekdays", "class", "A class needs at least one weekday (mon..sun) to meet on."))
    try:
        schedule.lesson_dates(first_date, days or ["mon"], 1)
    except (ValueError, TypeError):
        problems.append(problem("class-first-date", "class", "%r is not a date (YYYY-MM-DD)." % (first_date,)))
    if problems:
        return None, problems
    return {
        "id": class_id or str(uuid.uuid4()),
        "name": name or default_name(stage_id, days),
        "stageId": stage_id,
        "ageGroup": age_group,
        "lessons": lessons,
        "order": next_order(classes),
        "schedule": {"weekdays": days, "firstDate": first_date},
        "log": [],
        "draft": None,
    }, []


def sorted_classes(classes: Iterable[Class]) -> list[Class]:
    """By order, then name (C2)."""
    return sorted(classes, key=lambda c: (c.get("order") if isinstance(c.get("order"), int) else 0,
                                          str(c.get("name") or ""), str(c.get("id") or "")))


def delete_class(classes: Iterable[Class], class_id: str) -> list[Class]:
    """Every class but the one; its log and draft go with it (C3)."""
    return [c for c in classes if c.get("id") != class_id]


def find_class(classes: Iterable[Class], class_id: str) -> Class | None:
    for c in classes:
        if c.get("id") == class_id:
            return c
    return None


# ---------------------------------------------------------------------------
# dates and day numbering (C4, C6)

def lesson_dates(class_: Class) -> list[str]:
    sched = class_.get("schedule") or {}
    return schedule.lesson_dates(sched.get("firstDate"), sched.get("weekdays") or [], int(class_.get("lessons") or 0))


def lesson_date(class_: Class, n: int) -> str | None:
    dates = lesson_dates(class_)
    return dates[n - 1] if isinstance(n, int) and 1 <= n <= len(dates) else None


def log_entries(class_: Class) -> list[dict[str, Any]]:
    return [entry for entry in dict_items(class_.get("log")) if isinstance(entry.get("n"), int)]


def log_entry(class_: Class, n: int) -> dict[str, Any] | None:
    for entry in log_entries(class_):
        if entry["n"] == n:
            return entry
    return None


def last_day_done(class_: Class) -> int:
    """The highest saved day, 0 when none (C6)."""
    return max((entry["n"] for entry in log_entries(class_)), default=0)


def next_day(class_: Class) -> int | None:
    """Last done + 1, or None when every day is saved (the class is complete)."""
    following = last_day_done(class_) + 1
    return following if following <= int(class_.get("lessons") or 0) else None


def is_complete(class_: Class) -> bool:
    return next_day(class_) is None


# ---------------------------------------------------------------------------
# today by date (C7; DECISIONS_LOG 2026-09-12 "Today is the lesson dated today" and
# the owner's answers). The Core takes the date as an argument and never reads the
# clock; the app passes the device's calendar day as "YYYY-MM-DD".

def day_on(class_: Class, iso_date: str) -> int | None:
    """The n whose scheduled date (C4) is `iso_date`, else None."""
    for position, date in enumerate(lesson_dates(class_)):
        if date == iso_date:
            return position + 1
    return None


def today(classes: Iterable[Class], iso_date: str) -> list[dict[str, Any]]:
    """[{classId, n}] for every class with a day on `iso_date`, saved or not, in class
    order (C2)."""
    found = []
    for class_ in sorted_classes(classes):
        n = day_on(class_, iso_date)
        if n is not None:
            found.append({"classId": class_.get("id"), "n": n})
    return found


def next_lesson(classes: Iterable[Class], iso_date: str) -> dict[str, Any] | None:
    """The nearest {classId, n, date} on or after `iso_date` across the classes, ties
    by class order; None when every class is past its last date."""
    best = None
    for position, class_ in enumerate(sorted_classes(classes)):
        for index, date in enumerate(lesson_dates(class_)):
            if date >= iso_date:
                key = (date, position)
                if best is None or key < best[0]:
                    best = (key, {"classId": class_.get("id"), "n": index + 1, "date": date})
                break
    return best[1] if best else None


def missed(classes: Iterable[Class], iso_date: str) -> list[dict[str, Any]]:
    """[{classId, n, date}] for every day dated before `iso_date` that has no log entry
    (a missed day), oldest first, ties by class order."""
    found = []
    for position, class_ in enumerate(sorted_classes(classes)):
        saved = {entry["n"] for entry in log_entries(class_)}
        for index, date in enumerate(lesson_dates(class_)):
            if date < iso_date and index + 1 not in saved:
                found.append(((date, position, index), {"classId": class_.get("id"), "n": index + 1, "date": date}))
    return [item for _, item in sorted(found, key=lambda pair: pair[0])]


def done_set(class_: Class, except_n: int | None = None) -> set[str]:
    """Every activity id in the class's saved days (REDESIGN §2 "Done set"); without
    day `except_n`'s own entry when given, so a saved day's shuffle and pick count as
    done only what another day holds (DECISIONS_LOG 2026-09-13 "A day saves itself")."""
    done: set[str] = set()
    for entry in log_entries(class_):
        if entry["n"] == except_n:
            continue
        for block in dict_items(entry.get("blocks")):
            done.update(a for a in block.get("activityIds") or [] if isinstance(a, str))
    return done


# ---------------------------------------------------------------------------
# writes (return a new class)

def with_log_entry(class_: Class, entry: dict[str, Any]) -> Class:
    """The class with `entry` in its log, replacing any entry with the same n; the
    log stays sorted by n."""
    kept = [e for e in log_entries(class_) if e["n"] != entry["n"]]
    updated = dict(class_)
    updated["log"] = sorted(kept + [entry], key=lambda e: e["n"])
    return updated


def with_draft(class_: Class, draft: dict[str, Any] | None) -> Class:
    updated = dict(class_)
    updated["draft"] = draft
    return updated


def draft_for(class_: Class, n: int) -> dict[str, Any] | None:
    draft = class_.get("draft")
    return draft if isinstance(draft, dict) and draft.get("n") == n else None


# ---------------------------------------------------------------------------
# validation (for files read from disk)

def validate_class(class_: Any, curriculum=None) -> list:
    """Shape problems of one class record; with a curriculum, its stage and age group
    are checked too."""
    problems = []
    where = "class %s" % (class_.get("id") if isinstance(class_, dict) else "?")
    if not isinstance(class_, dict):
        return [problem("class-shape", where, "A class must be an object.")]
    for key in ("id", "name", "stageId", "ageGroup"):
        if not isinstance(class_.get(key), str) or not class_[key]:
            problems.append(problem("class-shape", where, "`%s` must be a non-empty string." % key))
    if not isinstance(class_.get("lessons"), int) or class_["lessons"] < 1:
        problems.append(problem("class-shape", where, "`lessons` must be an integer of at least 1."))
    if not isinstance(class_.get("order"), int):
        problems.append(problem("class-shape", where, "`order` must be an integer."))
    sched = class_.get("schedule")
    if not isinstance(sched, dict) or not ordered_weekdays(sched.get("weekdays") or []) \
            or not isinstance(sched.get("firstDate"), str):
        problems.append(problem("class-shape", where, "`schedule` needs `weekdays` (mon..sun) and `firstDate`."))
    else:
        try:
            schedule.lesson_dates(sched["firstDate"], sched["weekdays"], 1)
        except (ValueError, TypeError):
            problems.append(problem("class-shape", where, "`schedule.firstDate` is not a date (YYYY-MM-DD)."))
    seen = set()
    for entry in dict_items(class_.get("log")):
        n = entry.get("n")
        if not isinstance(n, int) or n < 1 or (isinstance(class_.get("lessons"), int) and n > class_["lessons"]):
            problems.append(problem("class-log", where, "A log entry's `n` (%r) is not a day of the class." % (n,)))
        elif n in seen:
            problems.append(problem("class-log", where, "Day %d has two log entries." % n))
        seen.add(n)
        for block in dict_items(entry.get("blocks")):
            if block.get("kind") not in ids.BLOCK_KINDS or not isinstance(block.get("activityIds"), list):
                problems.append(problem("class-log", where, "Day %r has a block without a kind or activityIds." % (n,)))
    draft = class_.get("draft")
    if draft is not None and (not isinstance(draft, dict) or not isinstance(draft.get("n"), int)
                              or not isinstance(draft.get("blocks"), list)):
        problems.append(problem("class-draft", where, "`draft` must be null or {n, blocks, shuffleCounts}."))
    if curriculum is not None and isinstance(class_.get("stageId"), str):
        stage = curriculum.stage(class_["stageId"])
        if stage is None:
            problems.append(problem("class-stage", where, "Stage %r is not in the curriculum." % class_["stageId"]))
        elif class_.get("ageGroup") not in (stage.get("ageGroups") or []):
            problems.append(problem("class-age-group", where, "Stage %s has no age group %r."
                                    % (class_["stageId"], class_.get("ageGroup"))))
    return problems
