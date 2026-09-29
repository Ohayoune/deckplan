"""Schedule: lesson dates and their edits (SPEC §6.13, D27; TEST_CASES.md group S).

A class's schedule is its weekdays and its place in the day (SPEC §6.13); a session is N
lessons whose dates all come from one pure function, `lesson_dates`, used at session
creation and again by every edit below. Every edit changes only **open** lessons — not
marked, not cancelled (`is_open`): a marked lesson is history and keeps its date; a
cancelled one keeps its date too (it is lost, not moved) but is skipped when replanning.
Lesson numbers never move: only dates do, so session plans, plan snapshots, marks and
reports (keyed by `n`) are untouched by anything here (SPEC §6.13, last paragraph).

The session dict this module reads and writes is the reduced shape the M2 brief pins for
Core-level date arithmetic — not the full SPEC §7 `Session` / `Lesson` (which also carries
a session plan, plan snapshots, attendance and overrides; those live above this module):

    { "startDate": iso, "lessonCount": int, "skipDates": [iso, ...],
      "lessons": [ { "id"?: str, "n": int, "date": iso, "cancelled"?: bool, "marked"?: bool },
                   ... ] }

Dates are ISO "YYYY-MM-DD" strings everywhere in and out of this module; `datetime.date`
is used only inside function bodies, for arithmetic and ordering. Every function here is
pure — no I/O, no globals, nothing read from the clock (`today` is always a parameter) —
and returns fresh dicts and lists rather than mutating its arguments. Refusals are
`curriculum.Problem` entries, not exceptions, with one documented exception: `lesson_dates`
on a weekday set with nothing usable in it, which raises `ValueError` (S8) — it has no
problems channel of its own, since it returns a plain list of dates, not a (value,
problems) pair.
"""

import math
from datetime import date, timedelta

from .curriculum import problem

WEEKDAY_NAMES = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")  # date.weekday(): Mon = 0
_WEEKDAY_ABBR = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
_MONTH_ABBR = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")


def _parse(iso_date):
    return date.fromisoformat(iso_date)


def _iso(value):
    return value.isoformat()


# ---------------------------------------------------------------------------
# open lessons (SPEC §6.13: every operation below "changes only open lessons")

def is_open(lesson):
    """A lesson is open when it is neither marked (it has marks recorded against it) nor
    cancelled (SPEC §6.13). Only open lessons are re-dated by the operations below; a
    marked or a cancelled lesson keeps the date it already has."""
    return not lesson.get("marked") and not lesson.get("cancelled")


# ---------------------------------------------------------------------------
# date arithmetic (SPEC §6.13, D27; S1-S4, S8)

def lesson_dates(start_date, weekdays, count, skip_dates=()):
    """The first `count` dates on or after `start_date` whose weekday is in `weekdays`
    and that are not in `skip_dates` (SPEC §6.13's one pure date function; S1-S4, S8).

    `weekdays` may be any iterable of "mon".."sun"; entries that aren't one of those seven
    names are ignored. A set with nothing recognized in it — S8's empty set, or one of
    nothing but typos — raises `ValueError` with a plain sentence: the one place in this
    module that raises instead of returning a `Problem`, because this function returns a
    bare list of dates, with no second return value to carry a refusal.
    """
    valid = set(weekdays) & set(WEEKDAY_NAMES)
    if not valid:
        raise ValueError("lesson_dates needs at least one weekday (mon..sun) to meet on; "
                         "none were given.")
    if count <= 0:
        return []
    skip = set(skip_dates or ())
    found = []
    current = _parse(start_date)
    one_day = timedelta(days=1)
    while len(found) < count:
        iso = _iso(current)
        if WEEKDAY_NAMES[current.weekday()] in valid and iso not in skip:
            found.append(iso)
        current += one_day
    return found


def new_session_lessons(start_date, weekdays, count, skip_dates=(), id_prefix="L"):
    """A fresh session's lessons, numbered 1..count and dated by `lesson_dates` (SPEC
    §6.13 "New session"; S1-S4, S8): `[{"id": "L1", "n": 1, "date": ...}, ...]`."""
    dates = lesson_dates(start_date, weekdays, count, skip_dates)
    return [{"id": "%s%d" % (id_prefix, n), "n": n, "date": iso} for n, iso in enumerate(dates, start=1)]


# ---------------------------------------------------------------------------
# edits (SPEC §6.13; S5-S7)

def _add_skip_date(existing, new_date):
    return sorted(set(existing or ()) | {new_date})


def skip_date(session, weekdays, date_to_skip):
    """Skip a holiday or closure (SPEC §6.13 "Skip this date"; S5): the date joins
    `skipDates`, and every open lesson dated on or after it is re-dated by `lesson_dates`,
    continuing the weekday pattern from that date (so the session still ends with
    `lessonCount` lessons, just later). A lesson dated before it, and any marked or
    cancelled lesson wherever it falls, keeps its date untouched and reserves it — the
    replanned dates never land on one of those either.

    Refused — `session` returned unchanged — when `date_to_skip` already holds a marked
    lesson: that day was already taught, so it cannot retroactively become a holiday.
    Returns `(session, problems)`.
    """
    lessons = session.get("lessons", [])
    if any(lesson.get("date") == date_to_skip and lesson.get("marked") for lesson in lessons):
        return session, [problem(
            "schedule-skip-marked", date_to_skip,
            "%s already has a marked lesson, so it can't be skipped." % date_to_skip)]

    skip_when = _parse(date_to_skip)
    to_redate = sorted((l for l in lessons if is_open(l) and _parse(l["date"]) >= skip_when),
                       key=lambda l: l["n"])
    reserved = {l["date"] for l in lessons if not is_open(l)}
    new_skip_dates = _add_skip_date(session.get("skipDates"), date_to_skip)
    new_dates = (lesson_dates(date_to_skip, weekdays, len(to_redate), set(new_skip_dates) | reserved)
                if to_redate else [])
    date_by_n = {lesson["n"]: iso for lesson, iso in zip(to_redate, new_dates)}

    new_lessons = [dict(l, date=date_by_n[l["n"]]) if l.get("n") in date_by_n else dict(l)
                   for l in lessons]
    return dict(session, skipDates=new_skip_dates, lessons=new_lessons), []


def cancel_lesson(session, n):
    """Cancel a lesson (SPEC §6.13 "Cancel this lesson"; S6): it keeps its `n` and date and
    is flagged `cancelled` — lost, not taught, and nobody's absence
    (PROGRESS_TRACKING.md §9) — and nothing else moves; the session still ends on time,
    one lesson short of taught. The UI offers this only for a lesson not yet marked (SPEC
    §5.3); this function trusts that and does not itself check or refuse, matching its
    plain-session return (there is no problems channel to refuse through).
    """
    new_lessons = [dict(l, cancelled=True) if l.get("n") == n else dict(l)
                   for l in session.get("lessons", [])]
    return dict(session, lessons=new_lessons)


def move_lesson(session, n, new_date):
    """Move an open lesson to another date (SPEC §6.13 "Move to another date"; S7): only
    to a date strictly between its neighbours' (`n`-1 and `n`+1) current dates, and only
    when lesson `n` itself is open; nothing else changes. A lesson at either end of the
    session is bounded on the one side that has a neighbour. Returns `(session,
    problems)`; a refused move returns `session` unchanged.
    """
    lessons = session.get("lessons", [])
    by_n = {l["n"]: l for l in lessons if "n" in l}
    lesson = by_n.get(n)
    if lesson is None:
        return session, [problem("schedule-move-unknown", "lesson %s" % n,
                                 "There is no lesson %s in this session." % n)]
    if not is_open(lesson):
        return session, [problem(
            "schedule-move-not-open", "lesson %s" % n,
            "Lesson %s is %s, so it can't be moved."
            % (n, "cancelled" if lesson.get("cancelled") else "marked"))]

    new_when = _parse(new_date)
    lower = by_n.get(n - 1)
    if lower is not None and new_when <= _parse(lower["date"]):
        return session, [problem(
            "schedule-move-range", "lesson %s" % n,
            "Lesson %s must move to a date after lesson %s's (%s)." % (n, n - 1, lower["date"]))]
    upper = by_n.get(n + 1)
    if upper is not None and new_when >= _parse(upper["date"]):
        return session, [problem(
            "schedule-move-range", "lesson %s" % n,
            "Lesson %s must move to a date before lesson %s's (%s)." % (n, n + 1, upper["date"]))]

    new_lessons = [dict(l, date=new_date) if l.get("n") == n else dict(l) for l in lessons]
    return dict(session, lessons=new_lessons), []


def change_weekdays(session, weekdays):
    """Change the class's days mid-session (SPEC §6.13 "Change the class's days"): the
    open lessons are re-dated by `lesson_dates`, starting from the first open lesson's own
    current date — which may itself move, if that date no longer falls on one of the new
    weekdays. Marked and cancelled lessons keep their dates and reserve them."""
    lessons = session.get("lessons", [])
    open_lessons = sorted((l for l in lessons if is_open(l)), key=lambda l: l["n"])
    if not open_lessons:
        return dict(session, lessons=[dict(l) for l in lessons])

    reserved = {l["date"] for l in lessons if not is_open(l)}
    skip_dates = set(session.get("skipDates") or ()) | reserved
    new_dates = lesson_dates(open_lessons[0]["date"], weekdays, len(open_lessons), skip_dates)
    date_by_n = {l["n"]: iso for l, iso in zip(open_lessons, new_dates)}

    new_lessons = [dict(l, date=date_by_n[l["n"]]) if l.get("n") in date_by_n else dict(l)
                   for l in lessons]
    return dict(session, lessons=new_lessons)


# ---------------------------------------------------------------------------
# lookups (SPEC §6.4, §6.14)

def next_open_lesson(session):
    """The open lesson with the lowest `n` — a class's next lesson to plan (SPEC §6.14) —
    or `None` when every lesson is marked or cancelled."""
    open_lessons = [l for l in session.get("lessons", []) if is_open(l)]
    return dict(min(open_lessons, key=lambda l: l["n"])) if open_lessons else None


def last_marked_lesson(session):
    """The marked lesson with the highest `n` — the no-repeat window's fallback anchor
    when there is no next open lesson (SPEC §6.14) — or `None` when none is marked yet."""
    marked = [l for l in session.get("lessons", []) if l.get("marked")]
    return dict(max(marked, key=lambda l: l["n"])) if marked else None


# ---------------------------------------------------------------------------
# report prompts (SPEC §6.5, §5.1; S10)

def mid_session_lesson_n(count):
    """Lesson ⌈N/2⌉ — the Mid-Session Report's lesson, 4 of 8 (SPEC §6.5)."""
    return math.ceil(count / 2)


def report_prompts(session, today):
    """Whether the Mid-Session and Certificate prompts are due on Today (SPEC §6.5, §5.1;
    S10): each appears on its own lesson's date once that lesson is marked or cancelled,
    and unconditionally from the next day on, whether or not it ever gets marked. `today`
    is injected, never read from the clock.
    """
    by_n = {l["n"]: l for l in session.get("lessons", []) if "n" in l}
    count = session.get("lessonCount", len(by_n))
    today_when = _parse(today)

    def due(n):
        lesson = by_n.get(n)
        if lesson is None or "date" not in lesson:
            return False
        lesson_when = _parse(lesson["date"])
        if today_when > lesson_when:
            return True
        if today_when == lesson_when:
            return bool(lesson.get("marked") or lesson.get("cancelled"))
        return False

    return {"midSession": due(mid_session_lesson_n(count)), "certificates": due(count)}


# ---------------------------------------------------------------------------
# nice to have: UI-facing summaries (SPEC §6.13, §5.3)

def weeks_span(dates):
    """The number of distinct Mon-Sun weeks the dates fall in (SPEC §6.13's own example,
    "4 weeks", and §2's "twice a week for 4 weeks" / "once a week for 8 weeks"): a Mon/Wed
    pair falls in one shared week, so 8 lessons make 4 weeks; a weekly Saturday starts a
    new week each time, so 8 lessons make 8."""
    return len({_parse(iso).isocalendar()[:2] for iso in dates})


def _describe_date(iso_date):
    d = _parse(iso_date)
    return "%s %s %d" % (_WEEKDAY_ABBR[d.weekday()], _MONTH_ABBR[d.month - 1], d.day)


def describe_session(session):
    """The Class screen's session strip (SPEC §6.13's own phrasing, §5.3), e.g.
    "8 lessons · Tue Sep 15 – Thu Oct 8 · 4 weeks". The count is `lessonCount` —
    unaffected by skipped or cancelled dates, D27 — the range and week count come from
    the lessons' own dates."""
    lessons = sorted(session.get("lessons", []), key=lambda l: l.get("n", 0))
    count = session.get("lessonCount", len(lessons))
    plural = "" if count == 1 else "s"
    dates = [l["date"] for l in lessons if "date" in l]
    if not dates:
        return "%d lesson%s" % (count, plural)
    weeks = weeks_span(dates)
    return "%d lesson%s · %s – %s · %d week%s" % (
        count, plural, _describe_date(dates[0]), _describe_date(dates[-1]),
        weeks, "" if weeks == 1 else "s")


def today_lessons(classes, sessions, on_date):
    """Today's lessons in class order (SPEC §5.1, §6.13 "Order"; S9 covers only this sort
    — the "same weekday, same order" warning is a Class-screen display concern, not
    something this pure function raises or refuses). `classes` is a list of
    `{"id", "order", ...}`; `sessions` maps classId -> session dict. Returns
    `{"classId", "order", "lesson"}` rows, one per class with a lesson dated `on_date`,
    sorted by `order` then `classId` as a stable tie-break.
    """
    rows = []
    for cls in classes:
        session = sessions.get(cls["id"])
        if not session:
            continue
        lesson = next((l for l in session.get("lessons", []) if l.get("date") == on_date), None)
        if lesson is not None:
            rows.append({"classId": cls["id"], "order": cls.get("order", 0), "lesson": dict(lesson)})
    rows.sort(key=lambda row: (row["order"], row["classId"]))
    return rows


def lesson_date(session, class_, n):
    """Lesson n's date: the session's listed lesson when it has one, else the n-th date the
    schedule generates from the session's start date, the class's weekdays and the skip
    dates (SPEC §6.13). A real Session lists every lesson from creation; a compact class
    fixture may list only the lessons taught so far, so a report dated against lesson N
    (the Certificate, SPEC §6.5) and a plan for an unlisted lesson both come here."""
    session = session if isinstance(session, dict) else {}
    class_ = class_ if isinstance(class_, dict) else {}
    for lesson in session.get("lessons") or []:
        if isinstance(lesson, dict) and lesson.get("n") == n and isinstance(lesson.get("date"), str):
            return lesson["date"]
    count = session.get("lessonCount") or n
    dates = lesson_dates(session.get("startDate"), class_.get("weekdays") or [], max(int(count), n),
                         session.get("skipDates") or [])
    return dates[n - 1]
