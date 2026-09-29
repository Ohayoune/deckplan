"""Today's plan: a class's day k from the guide, its shuffle, edits and save.

REDESIGN.md §3; TEST_CASES C5, D1–D10. Pure functions over the curriculum, a class
(`classes.py`) and a pool profile (`activities.py`); every write returns a new
class. Refusals are `curriculum.Problem` entries.

A block's **candidates** (D2) are the guide's own activities, then the activities
of the block's skills, pool- and age-filtered; a fresh block **shows** one of them
(D10; DECISIONS_LOG 2026-09-12 "A block shows one activity, the app's pick"): the
first candidate the class has never done, or the first candidate when every one
is done. An ["any"] block shows nothing until its pick (D3), then the same rule
over the pick. Shuffle draws from the candidates (as many as shown, so one); Add
appends; Save logs what is shown. The plan's `activityIds` is the shown list;
candidates are not serialised.

Plan (the value the screen shows; canonical JSON for D9):

    { "classId", "n", "date", "guideLesson": int | null, "saved": bool, "draft": bool,
      "blocks": [ { "kind", "minutes", "skillIds": [...],          skillIds as the guide has them, ["any"] until a pick
                    "stepRange"?: [a, b], "notes"?: [...],          carried from the guide
                    "topicCode"?, "topic"?: {"code", "name", "summary"},
                    "skillChoices"?: [skill id, ...],               an "any" block, before the pick
                    "activityIds": [...],                           what the block shows (D10)
                    "hidden"?: [...] } ] }                           saved or drafted ids the pool now hides

Optional keys are left out when empty so the JSON is the same from Python and Swift.

Where a day's blocks come from (D8): the class's draft when it is for this day
(the working copy: edits, picks, shuffles); else the saved log entry; else fresh
from the guide (D1–D2). A saved day is edited, picked and shuffled through the
same draft and re-saved; its own entry is not "done" for it. Every day dated on or
before a given date saves itself, oldest first (D11; DECISIONS_LOG 2026-09-13 "A
day saves itself").
"""

from __future__ import annotations

import copy
from typing import Any

from . import activities as ACT
from . import canonical
from . import classes as CL
from . import ids
from . import session_plan
from .curriculum import dict_items, problem

Plan = dict[str, Any]

EXTRA_DAY_GUIDE_LESSON = 7  # an extra day (N > 8) borrows guide lesson 7's shape (C5)
SHUFFLE_EXHAUSTED = "no more new activities for this block"
_TEMPLATE_KEYS = ("kind", "minutes", "skillIds", "stepRange", "notes", "topicCode")


# ---------------------------------------------------------------------------
# the guide lesson for a day (C5)

def template_for_day(curriculum, stage_id: str, lessons: int, n: int) -> tuple[dict | None, int | None]:
    """(template, guide lesson number) for day `n` of an N = `lessons` class. An extra
    day gets guide lesson 7's block kinds and minutes with Review and Introduce
    ["any"], no guide activities and no topic (guide lesson None)."""
    guide_n = session_plan.guide_lesson_for_day(curriculum, stage_id, lessons, n)
    templates = session_plan._templates_by_n(curriculum, stage_id)
    if guide_n is not None:
        return templates.get(guide_n), guide_n
    source = templates.get(EXTRA_DAY_GUIDE_LESSON)
    if source is None:
        return None, None
    blocks = []
    for block in dict_items(source.get("blocks")):
        kind = block.get("kind")
        extra = {"kind": kind, "minutes": block.get("minutes")}
        if kind in ("review", "introduce"):
            extra["skillIds"] = [ids.ANY_SKILL]
        elif kind != "topic":
            for key in ("skillIds", "stepRange"):
                if key in block:
                    extra[key] = copy.deepcopy(block[key])
        blocks.append(extra)
    return {"n": n, "minutes": source.get("minutes"), "blocks": blocks, "stageId": stage_id}, None


def is_any(block: dict) -> bool:
    return (block.get("skillIds") or []) == [ids.ANY_SKILL]


def skill_choices(curriculum, stage_id: str) -> list[str]:
    """The stage's skills in library order, for an "any" block's pick (D3)."""
    return [skill["id"] for skill in curriculum.skills_of(stage_id) if isinstance(skill.get("id"), str)]


# ---------------------------------------------------------------------------
# candidates (D2)

def block_candidates(curriculum, template_block: dict, pool, age_tag: str | None,
                     skill_ids: list[str] | None = None) -> list[str]:
    """D2's full list for a block: the guide's own activities, then the activities of
    the block's skills in catalog order, deduped, then pool- and age-filtered. For an
    "any" block `skill_ids` is the pick; without one the list is empty."""
    if is_any(template_block):
        chosen = [s for s in skill_ids or [] if s != ids.ANY_SKILL]
        if not chosen:
            return []
        guide_ids: list[str] = []
    else:
        chosen = [s for s in template_block.get("skillIds") or [] if isinstance(s, str)]
        guide_ids = [a for a in template_block.get("activityIds") or [] if isinstance(a, str)]
    combined = ACT.dedupe(guide_ids + ACT.skill_activity_ids(curriculum, chosen))
    return ACT.dedupe(ACT.filter_ids(curriculum, combined, pool, age_tag))


def _topic(curriculum, code):
    topic = curriculum.topic(code) if isinstance(code, str) else None
    if not topic:
        return None
    return {"code": code, "name": topic.get("name") or "", "summary": topic.get("summary") or ""}


def _plan_block(curriculum, template_block: dict, stage_id: str, skill_ids: list[str],
                activity_ids: list[str], pool, age_tag: str | None, flag_hidden: bool) -> dict:
    block: dict[str, Any] = {}
    for key in _TEMPLATE_KEYS:
        if key in template_block and template_block[key] is not None:
            block[key] = copy.deepcopy(template_block[key])
    block["skillIds"] = list(skill_ids)
    if block.get("topicCode"):
        topic = _topic(curriculum, block["topicCode"])
        if topic:
            block["topic"] = topic
    if is_any(template_block) and skill_ids == [ids.ANY_SKILL]:
        block["skillChoices"] = skill_choices(curriculum, stage_id)
    block["activityIds"] = list(activity_ids)
    if flag_hidden:
        shown = set(ACT.filter_ids(curriculum, activity_ids, pool, age_tag))
        hidden = [a for a in activity_ids if a not in shown]
        if hidden:
            block["hidden"] = hidden
    return block


def shown_activities(candidates: list[str], done: set[str]) -> list[str]:
    """D10: the one activity a fresh block shows — the first candidate not in the
    class's done set, else the first candidate; nothing when there are none."""
    for activity_id in candidates:
        if activity_id not in done:
            return [activity_id]
    return list(candidates[:1])


def fresh_blocks(curriculum, template: dict, stage_id: str, pool, age_tag: str | None,
                 done: set[str]) -> list[dict]:
    """D1, D2, D10: the guide's blocks, each showing one of its candidates."""
    blocks = []
    for template_block in dict_items(template.get("blocks")):
        skill_ids = [s for s in template_block.get("skillIds") or [] if isinstance(s, str)]
        candidates = block_candidates(curriculum, template_block, pool, age_tag)
        blocks.append(_plan_block(curriculum, template_block, stage_id, skill_ids,
                                  shown_activities(candidates, done), pool, age_tag, False))
    return blocks


# ---------------------------------------------------------------------------
# the plan (D1, D8)

def _check_day(class_, n) -> list:
    lessons = class_.get("lessons") or 0
    if not isinstance(n, int) or isinstance(n, bool) or n < 1 or n > lessons:
        return [problem("day-range", "class %s" % class_.get("id"),
                        "Day %r is not one of this class's %d lessons." % (n, lessons))]
    return []


def plan_day(curriculum, class_, pool, n: int) -> tuple[Plan | None, list]:
    """The plan for day `n` (see the module docstring for where its blocks come from)."""
    problems = _check_day(class_, n)
    if problems:
        return None, problems
    stage_id = class_.get("stageId")
    template, guide_n = template_for_day(curriculum, stage_id, class_["lessons"], n)
    if template is None:
        return None, [problem("day-template", "class %s" % class_.get("id"),
                              "Stage %s has no lesson template for day %d." % (stage_id, n))]
    age_tag = ACT.age_tag(class_.get("ageGroup"))
    entry = CL.log_entry(class_, n)
    draft = CL.draft_for(class_, n)
    if draft is not None or entry is not None:
        source_blocks = {b.get("kind"): b for b in dict_items((draft or entry).get("blocks"))}
        blocks = []
        for template_block in dict_items(template.get("blocks")):
            kind = template_block.get("kind")
            saved = source_blocks.get(kind) or {}
            skill_ids = saved.get("skillIds") if draft is not None and isinstance(saved.get("skillIds"), list) \
                else [s for s in template_block.get("skillIds") or [] if isinstance(s, str)]
            activity_ids = [a for a in saved.get("activityIds") or [] if isinstance(a, str)]
            blocks.append(_plan_block(curriculum, template_block, stage_id, skill_ids, activity_ids,
                                      pool, age_tag, True))
    else:
        blocks = fresh_blocks(curriculum, template, stage_id, pool, age_tag, CL.done_set(class_))
    return {
        "classId": class_.get("id"),
        "n": n,
        "date": CL.lesson_date(class_, n),
        "guideLesson": guide_n,
        "saved": entry is not None,
        "draft": draft is not None,
        "blocks": blocks,
    }, []


def plan_json(plan: Plan) -> str:
    """The plan's canonical JSON (D9)."""
    return canonical.dumps(plan)


# ---------------------------------------------------------------------------
# the draft (D6)

def _draft_from_plan(plan: Plan) -> dict:
    return {
        "n": plan["n"],
        "blocks": [{"kind": b["kind"], "skillIds": list(b.get("skillIds") or []),
                    "activityIds": list(b.get("activityIds") or [])} for b in plan["blocks"]],
        "shuffleCounts": {},
    }


def ensure_draft(curriculum, class_, pool, n: int) -> tuple[Any, dict | None, list]:
    """The class with a draft for day `n` (created from the day's plan when there is
    none: another day's draft is dropped, D6) and that draft."""
    draft = CL.draft_for(class_, n)
    if draft is not None:
        return class_, draft, []
    plan, problems = plan_day(curriculum, class_, pool, n)
    if plan is None:
        return class_, None, problems
    draft = _draft_from_plan(plan)
    return CL.with_draft(class_, draft), draft, []


def _draft_block(draft: dict, kind: str) -> dict | None:
    for block in dict_items(draft.get("blocks")):
        if block.get("kind") == kind:
            return block
    return None


def _replace_block(class_, draft: dict, kind: str, new_block: dict, shuffle_count: int | None = None):
    updated = copy.deepcopy(draft)
    updated["blocks"] = [new_block if b.get("kind") == kind else b for b in updated["blocks"]]
    if shuffle_count is not None:
        updated.setdefault("shuffleCounts", {})[kind] = shuffle_count
    return CL.with_draft(class_, updated)


def _template_block(curriculum, class_, n: int, kind: str) -> dict | None:
    template, _ = template_for_day(curriculum, class_.get("stageId"), class_["lessons"], n)
    for block in dict_items((template or {}).get("blocks")):
        if block.get("kind") == kind:
            return block
    return None


def _edit_setup(curriculum, class_, pool, n: int, kind: str):
    """Common checks for shuffle and edits: a valid day, a block of that kind, a draft."""
    problems = _check_day(class_, n)
    if problems:
        return None, None, None, problems
    where = "class %s day %d" % (class_.get("id"), n)
    template_block = _template_block(curriculum, class_, n, kind)
    if template_block is None or kind == "topic":
        return None, None, None, [problem("block-kind", where, "Day %d has no editable %r block." % (n, kind))]
    class_, draft, problems = ensure_draft(curriculum, class_, pool, n)
    if problems:
        return None, None, None, problems
    return class_, draft, template_block, []


# ---------------------------------------------------------------------------
# shuffle (D4, D5)

def cycle_draw(never_done: list[str], shown: list[str], seed: int, slots: int) -> list[str]:
    """D4: the next `slots` never-done candidates along their seeded order, read as a
    cycle from just after the last of `shown` in it (from the start when none is); the
    ones `shown` holds come only after every other, so repeated shuffles walk through
    every never-done candidate before one comes back (DECISIONS_LOG 2026-09-13)."""
    order = sorted(never_done, key=lambda a: (canonical.hash_parts(seed, a), a))
    anchors = [order.index(a) for a in shown if a in order]
    start = anchors[-1] + 1 if anchors else 0
    walk = order[start:] + order[:start]
    return ([a for a in walk if a not in shown] + [a for a in walk if a in shown])[:slots]


def shuffle(curriculum, class_, pool, n: int, kind: str) -> tuple[Any, dict | None, list]:
    """Replace the block's activities with as many never-done candidates, the next ones
    along a seeded cycle (seed = hash of class id, day, kind; `cycle_draw`). Never done:
    in no saved day but this one, so a saved day shuffles too (DECISIONS_LOG 2026-09-13
    "A day saves itself"). Returns (class with the draft updated, {"kind",
    "activityIds", "shuffleCount", "message"?}, problems). The message: fewer
    never-done candidates than the block shows, or none but those it shows. A block
    with nothing in it is refused."""
    where = "class %s day %d" % (class_.get("id"), n)
    class_, draft, template_block, problems = _edit_setup(curriculum, class_, pool, n, kind)
    if problems:
        return class_, None, problems
    block = _draft_block(draft, kind) or {"kind": kind, "skillIds": [], "activityIds": []}
    slots = len(block.get("activityIds") or [])
    if slots == 0:
        return class_, None, [problem("shuffle-empty", where, "The %s block has no activities to shuffle%s."
                                      % (kind, "; pick a skill first" if is_any(template_block) else ""))]
    age_tag = ACT.age_tag(class_.get("ageGroup"))
    candidates = block_candidates(curriculum, template_block, pool, age_tag, block.get("skillIds"))
    done = CL.done_set(class_, n)
    never_done = [a for a in candidates if a not in done]
    count = int((draft.get("shuffleCounts") or {}).get(kind, 0)) + 1
    shown = [a for a in block.get("activityIds") or [] if isinstance(a, str)]
    drawn = cycle_draw(never_done, shown, canonical.hash_parts(str(class_.get("id")), n, kind), slots)
    result = {"kind": kind, "activityIds": drawn, "shuffleCount": count}
    if len(never_done) < slots or set(drawn) == set(shown):
        result["message"] = SHUFFLE_EXHAUSTED
    new_block = dict(block, activityIds=drawn)
    return _replace_block(class_, draft, kind, new_block, count), result, []


# ---------------------------------------------------------------------------
# edits (D3, D6)

def pick_skill(curriculum, class_, pool, n: int, kind: str, skill_id: str) -> tuple[Any, list]:
    """Resolve an "any" block to one of the stage's skills; the block then shows one
    of that skill's activities, the first never done (D3, D10)."""
    class_, draft, template_block, problems = _edit_setup(curriculum, class_, pool, n, kind)
    if problems:
        return class_, problems
    where = "class %s day %d" % (class_.get("id"), n)
    if not is_any(template_block):
        return class_, [problem("pick-not-any", where, "The %s block's skills are set by the guide." % kind)]
    if skill_id not in skill_choices(curriculum, class_.get("stageId")):
        return class_, [problem("pick-skill", where, "%r is not a Stage %s skill." % (skill_id, class_.get("stageId")))]
    age_tag = ACT.age_tag(class_.get("ageGroup"))
    block = _draft_block(draft, kind) or {"kind": kind}
    candidates = block_candidates(curriculum, template_block, pool, age_tag, [skill_id])
    new_block = dict(block, skillIds=[skill_id], activityIds=shown_activities(candidates, CL.done_set(class_, n)))
    return _replace_block(class_, draft, kind, new_block), []


def remove_activity(curriculum, class_, pool, n: int, kind: str, activity_id: str) -> tuple[Any, list]:
    class_, draft, _, problems = _edit_setup(curriculum, class_, pool, n, kind)
    if problems:
        return class_, problems
    block = _draft_block(draft, kind) or {"kind": kind, "skillIds": [], "activityIds": []}
    if activity_id not in (block.get("activityIds") or []):
        return class_, [problem("edit-missing", "class %s day %d" % (class_.get("id"), n),
                                "%r is not in the %s block." % (activity_id, kind))]
    new_block = dict(block, activityIds=[a for a in block["activityIds"] if a != activity_id])
    return _replace_block(class_, draft, kind, new_block), []


def move_activity(curriculum, class_, pool, n: int, kind: str, from_index: int, to_index: int) -> tuple[Any, list]:
    class_, draft, _, problems = _edit_setup(curriculum, class_, pool, n, kind)
    if problems:
        return class_, problems
    block = _draft_block(draft, kind) or {"kind": kind, "skillIds": [], "activityIds": []}
    items = list(block.get("activityIds") or [])
    if not (0 <= from_index < len(items) and 0 <= to_index < len(items)):
        return class_, [problem("edit-index", "class %s day %d" % (class_.get("id"), n),
                                "The %s block has %d activities; positions %d -> %d are out of range."
                                % (kind, len(items), from_index, to_index))]
    items.insert(to_index, items.pop(from_index))
    return _replace_block(class_, draft, kind, dict(block, activityIds=items)), []


def add_activity(curriculum, class_, pool, n: int, kind: str, activity_id: str) -> tuple[Any, list]:
    """Append an activity from the finder; it must be in the stage's library and not
    already in the block (D6)."""
    class_, draft, _, problems = _edit_setup(curriculum, class_, pool, n, kind)
    if problems:
        return class_, problems
    where = "class %s day %d" % (class_.get("id"), n)
    if activity_id not in ACT.library(curriculum, class_.get("stageId")):
        return class_, [problem("edit-library", where, "%r is not a Stage %s activity." % (activity_id, class_.get("stageId")))]
    block = _draft_block(draft, kind) or {"kind": kind, "skillIds": [], "activityIds": []}
    if activity_id in (block.get("activityIds") or []):
        return class_, [problem("edit-duplicate", where, "%r is already in the %s block." % (activity_id, kind))]
    return _replace_block(class_, draft, kind, dict(block, activityIds=list(block.get("activityIds") or []) + [activity_id])), []


# ---------------------------------------------------------------------------
# save (D7)

def save_day(curriculum, class_, pool, n: int) -> tuple[Any, dict | None, list]:
    """Write day `n`'s log entry {n, date, blocks: [{kind, activityIds}]} from the
    day's plan (draft, saved entry or fresh), dated by the schedule; clear the day's
    draft. Returns (class, entry, problems)."""
    plan, problems = plan_day(curriculum, class_, pool, n)
    if plan is None:
        return class_, None, problems
    entry = {"n": n, "date": plan["date"],
             "blocks": [{"kind": b["kind"], "activityIds": list(b["activityIds"])} for b in plan["blocks"]]}
    updated = CL.with_log_entry(class_, entry)
    if CL.draft_for(updated, n) is not None:
        updated = CL.with_draft(updated, None)
    return updated, entry, []


def save_through(curriculum, class_, pool, iso_date: str) -> tuple[Any, list[int], list]:
    """D11: save every day dated on or before `iso_date` that has no log entry, oldest
    first, each as `save_day` would (its draft when it has one, else its fresh plan with
    the days before it done), so the app needs no Save (DECISIONS_LOG 2026-09-13 "A day
    saves itself"). Returns (class, the days saved, problems); a day the Core cannot plan
    is left unsaved with its problems. The Core takes the date and never reads the clock."""
    saved, found = [], []
    for index, date in enumerate(CL.lesson_dates(class_)):
        n = index + 1
        if date > iso_date or CL.log_entry(class_, n) is not None:
            continue
        class_, entry, problems = save_day(curriculum, class_, pool, n)
        if entry is None:
            found.extend(problems)
        else:
            saved.append(n)
    return class_, saved, found
