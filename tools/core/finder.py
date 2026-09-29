"""The activity finder, browse and search (REDESIGN.md §4; TEST_CASES F1–F7).

Pure functions over the curriculum and a pool profile. The finder's list is the
pool-filtered candidates in a seeded order (seed = hash of the inputs, the age tag
included), paged three at a time and wrapping after the last (F1). With a step,
the activities the guide pairs with the lessons whose `stepRange` covers it come
first in guide order, the rest of the skill's activities after them, seeded (F3).
Search (F7; DECISIONS_LOG 2026-09-12 "The plan is the product") is browse narrowed
to the activities whose name contains a text, case- and diacritic-insensitive.
"""

from __future__ import annotations

import unicodedata
from typing import Any

from . import activities as ACT
from . import canonical
from .curriculum import dict_items, problem

PAGE_SIZE = 3
_NULL = "-"


def _check_inputs(curriculum, stage_id, skill_id, step) -> list:
    if curriculum.stage(stage_id) is None:
        return [problem("finder-stage", "finder", "Stage %r is not in the curriculum." % (stage_id,))]
    if skill_id is not None:
        skill = curriculum.skill(skill_id)
        if skill is None or skill.get("stageId") != stage_id:
            return [problem("finder-skill", "finder", "%r is not a Stage %s skill." % (skill_id, stage_id))]
        if step is not None:
            steps = len(skill.get("stepIds") or [])
            if not isinstance(step, int) or isinstance(step, bool) or step < 1 or step > steps:
                return [problem("finder-step", "finder", "%s has steps 1..%d, not %r." % (skill_id, steps, step))]
    elif step is not None:
        return [problem("finder-step", "finder", "A step needs a skill.")]
    return []


def seed(stage_id: str, skill_id: str | None, step: int | None, age_tag: str | None) -> int:
    return canonical.hash_parts("finder", str(stage_id), skill_id or _NULL,
                                step if step is not None else _NULL, age_tag or _NULL)


def guide_paired(curriculum, stage_id: str, skill_id: str, step: int) -> list[str]:
    """The activities of every guide lesson block for `skill_id` whose stepRange covers
    `step`, in guide order (lesson n, then block order), deduped (F3's first part). A
    block that pairs two skills lists both skills' activities; only those the skill
    itself lists count as paired with it."""
    stage = curriculum.stage(stage_id) or {}
    own = set(a for a in (curriculum.skill(skill_id) or {}).get("activityIds") or [] if isinstance(a, str))
    found: list[str] = []
    for template in sorted(dict_items(stage.get("lessonTemplates")), key=lambda t: t.get("n") or 0):
        for block in dict_items(template.get("blocks")):
            if skill_id not in (block.get("skillIds") or []):
                continue
            step_range = block.get("stepRange") or []
            if len(step_range) == 2 and step_range[0] <= step <= step_range[1]:
                found.extend(a for a in block.get("activityIds") or [] if isinstance(a, str) and a in own)
    return ACT.dedupe(found)


def candidates(curriculum, stage_id: str, pool, skill_id: str | None = None, step: int | None = None,
               age_tag: str | None = None) -> tuple[list[str], list]:
    """The finder's full ordered list for these inputs (F1–F4)."""
    problems = _check_inputs(curriculum, stage_id, skill_id, step)
    if problems:
        return [], problems
    if skill_id is None:
        base = ACT.library(curriculum, stage_id)
    else:
        base = ACT.dedupe(a for a in (curriculum.skill(skill_id) or {}).get("activityIds") or [] if isinstance(a, str))
    shown = ACT.filter_ids(curriculum, base, pool, age_tag)
    the_seed = seed(stage_id, skill_id, step, age_tag)
    seeded = sorted(shown, key=lambda a: (canonical.hash_parts(the_seed, a), a))
    if step is None:
        return seeded, []
    paired = [a for a in guide_paired(curriculum, stage_id, skill_id, step) if a in set(shown)]
    rest = [a for a in seeded if a not in set(paired)]
    return paired + rest, []


def page(ordered: list[str], page_number: int, page_size: int = PAGE_SIZE) -> dict[str, Any]:
    """Page `page_number` (1-based) of three. The pages are fixed slices of the list;
    after the last (possibly short) page comes page 1 again, flagged `wrapped` (F1)."""
    total = len(ordered)
    if total == 0 or page_number < 1:
        return {"page": max(page_number, 1), "pageSize": page_size, "total": total, "activityIds": [], "wrapped": False}
    page_count = -(-total // page_size)
    index = (page_number - 1) % page_count
    start = index * page_size
    return {"page": page_number, "pageSize": page_size, "total": total,
            "activityIds": list(ordered[start:start + page_size]), "wrapped": page_number - 1 >= page_count}


def find(curriculum, stage_id: str, pool, skill_id: str | None = None, step: int | None = None,
         age_tag: str | None = None, page_number: int = 1) -> tuple[dict[str, Any] | None, list]:
    """One finder result: the inputs and page `page_number` of the ordered list."""
    ordered, problems = candidates(curriculum, stage_id, pool, skill_id, step, age_tag)
    if problems:
        return None, problems
    result = {"stageId": stage_id, "skillId": skill_id, "step": step, "ageTag": age_tag}
    result.update(page(ordered, page_number))
    return result, []


def detail(curriculum, activity_id: str, skill_id: str | None = None) -> dict[str, Any] | None:
    """What the finder shows for one activity (F5): name, description, required and
    optional equipment, ages, submerges, and the titles of the videos of `skill_id`
    (or, without one, of every skill that lists the activity)."""
    activity = curriculum.activity(activity_id)
    if activity is None:
        return None
    skill_ids = [skill_id] if skill_id else [s for s in activity.get("skillIds") or [] if isinstance(s, str)]
    titles = []
    for video in dict_items(curriculum.videos):
        if any(s in (video.get("skillIds") or []) for s in skill_ids) and isinstance(video.get("title"), str):
            titles.append(video["title"])
    return {
        "id": activity_id,
        "name": activity.get("name") or activity_id,
        "description": activity.get("description") or "",
        "equipment": ACT.requirement_phrases(activity, curriculum.equipment),
        "equipmentOptional": ACT.optional_names(activity, curriculum.equipment),
        "ages": list(activity.get("ages") or []),
        "submerges": bool(activity.get("submerges")),
        "videos": ACT.dedupe(titles),
    }


def browse(curriculum, stage_id: str, pool, age_tag: str | None = None) -> tuple[dict[str, Any] | None, list]:
    """The stage's pool-filtered library grouped by skill, Greeting first (F6). A skill
    with every activity hidden is an empty group."""
    if curriculum.stage(stage_id) is None:
        return None, [problem("finder-stage", "browse", "Stage %r is not in the curriculum." % (stage_id,))]
    groups = []
    for group in ACT.library_groups(curriculum, stage_id):
        groups.append({"skillId": group["skillId"], "name": group["name"],
                       "activityIds": ACT.filter_ids(curriculum, group["activityIds"], pool, age_tag)})
    return {"stageId": stage_id, "ageTag": age_tag, "groups": groups}, []


# ---------------------------------------------------------------------------
# search (F7)

def fold(text: str) -> str:
    """Case- and diacritic-insensitive form: NFKD, combining marks dropped, casefolded.
    The Swift port folds with Foundation; the fixtures' names are ASCII."""
    decomposed = unicodedata.normalize("NFKD", text or "")
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch)).casefold()


def search(curriculum, stage_id: str, pool, text: str, age_tag: str | None = None) -> tuple[dict[str, Any] | None, list]:
    """The stage's pool- and age-filtered library whose activity names contain `text`,
    grouped as browse (F6) with the groups that match nothing left out; an empty or
    blank text matches nothing (F7)."""
    if curriculum.stage(stage_id) is None:
        return None, [problem("finder-stage", "search", "Stage %r is not in the curriculum." % (stage_id,))]
    needle = fold((text or "").strip())
    groups = []
    if needle:
        for group in ACT.library_groups(curriculum, stage_id):
            shown = ACT.filter_ids(curriculum, group["activityIds"], pool, age_tag)
            matching = [a for a in shown
                        if needle in fold((curriculum.activity(a) or {}).get("name") or a)]
            if matching:
                groups.append({"skillId": group["skillId"], "name": group["name"], "activityIds": matching})
    return {"stageId": stage_id, "ageTag": age_tag, "text": text or "", "groups": groups}, []
