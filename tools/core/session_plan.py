"""The N-lesson mapping: which guide lesson a class's day k follows when N ≠ 8.

REDESIGN.md §2 (Guide lesson) keeps this one rule from v1's session plan
(`docs/v1/SESSION_PLAN_FORMAT.md` §3; TEST_CASES C5). Everything else v1 had here
(import, CSV, defaults, resolve) is gone with the session plan.
"""

from __future__ import annotations

from . import ids
from .curriculum import dict_items


def _templates_by_n(curriculum, stage_id):
    stage = curriculum.stage(stage_id) or {}
    return {template.get("n"): template for template in dict_items(stage.get("lessonTemplates"))}


def _blocks_by_kind(template):
    return {block.get("kind"): block for block in dict_items((template or {}).get("blocks"))}


def _introduced_skills(block):
    """The skills a guide lesson's Introduce block introduces; None when the block is
    "any" (or missing), so the lesson introduces nothing in particular."""
    skill_ids = (block or {}).get("skillIds") or []
    if not skill_ids or skill_ids == [ids.ANY_SKILL]:
        return None
    return [skill_id for skill_id in skill_ids if skill_id != ids.ANY_SKILL]


def guide_lesson_mapping(curriculum, stage_id, n):
    """Days 1..`n` -> their guide lesson (1-8), or None for an extra day (C5).

    N >= 8: every guide lesson is kept; `n - 8` extra days are inserted just before
    the last. N < 8: guide lessons are dropped one at a time, latest first within each
    step, never guide lesson 8, each drop re-checked against the days still kept:
    (a) a guide lesson whose Introduce is only "any"; (b) else one whose introduced
    skills are every one of them introduced by another still-kept lesson; (c) else
    the latest remaining guide lesson before the last. Read from the stage's own
    lesson templates, never a hard-coded table.
    """
    if n >= 8:
        return list(range(1, 8)) + [None] * (n - 8) + [8]

    templates = _templates_by_n(curriculum, stage_id)
    introduced = {}
    for guide_n in range(1, 8):
        introduced[guide_n] = _introduced_skills(_blocks_by_kind(templates.get(guide_n)).get("introduce"))

    kept = set(range(1, 8))
    target = max(0, n - 1)
    while len(kept) > target:
        any_only = sorted((g for g in kept if introduced[g] is None), reverse=True)
        if any_only:
            kept.discard(any_only[0])
            continue
        dropped = None
        for g in sorted(kept, reverse=True):
            skills = introduced[g]
            if not skills:
                continue
            others = [introduced[g2] for g2 in kept if g2 != g]
            if all(any(other and skill in other for other in others) for skill in skills):
                dropped = g
                break
        if dropped is not None:
            kept.discard(dropped)
            continue
        kept.discard(max(kept))
    return sorted(kept) + [8]


def guide_lesson_for_day(curriculum, stage_id, lessons, day):
    """Day `day` of an N = `lessons` class -> its guide lesson number, or None for an
    extra day. Raises ValueError when `day` is outside 1..lessons."""
    if not isinstance(day, int) or day < 1 or day > lessons:
        raise ValueError("day %r is not within 1..%d" % (day, lessons))
    return guide_lesson_mapping(curriculum, stage_id, lessons)[day - 1]
