"""Activities: the one pool filter, the age filter and the library order.

REDESIGN.md §2 (Activity, Pool profile), §3.2 (the filter is the same everywhere);
TEST_CASES.md P1–P5. Every function here is pure and works on the plain JSON
shapes the curriculum loader returns and the Store keeps.

Pool profile (pool/1 item; DECISIONS_LOG 2026-09-12 "New pool profile" and, V5,
"The pool profile lists pool equipment, not props" with the owner's answers):

    { "depths": {"shallow": bool, "medium": bool, "deep": bool},
      "diving": bool, "totDock": bool,
      "equipment": {"<profile item id>": bool, ...} }

`equipment` has one key per **profile item** (P6): the five catalog items that are
the only option of a required group in the most activities of the loaded library,
a `group` requirement (flotation-device) counting toward each of its `anyOf[]`
members, ties by catalog order. Every other catalog item is a **prop**, brought for
one activity: never in the profile, always on for the filter. A missing profile
key reads as off; a prop's key is ignored on read and dropped by `normalize_pool`
(P1). A `group` entry is on when any of its `anyOf[]` items is on. The profile is
computed from the data, so the functions below take the curriculum, not just its
catalog.

The filter (P2–P3, in this order): an activity is hidden when any group in its
`equipment[]` has no item on; when it has `depths` and none of them is on; when
it is `headfirst` and deep or diving is off. `equipmentOptional` never hides.
The age filter (P5) is separate: a class's `ageGroup` gives a tag P/S/A (none
for infantToddler); an activity with `ages` that lack the tag is hidden;
`ages: []` passes everywhere. `pool_filter` applies both and is the only
function the plan, shuffle, finder and browse go through (P4).
"""

from __future__ import annotations

from typing import Any, Iterable

from . import ids

Activity = dict[str, Any]
Pool = dict[str, Any]
Catalog = list[dict[str, Any]]

PROFILE_SIZE = 5  # the number of profile items (the owner's answers, 2026-09-12)
AGE_TAG_BY_GROUP = {"preschool": "P", "schoolAge": "S", "teen": "A", "adult": "A", "infantToddler": None}
AGE_WORDS = {"P": "preschool", "S": "school age", "A": "teen & adult"}
GREETING_GROUP = "greeting"


# ---------------------------------------------------------------------------
# age

def age_tag(age_group: str | None) -> str | None:
    """preschool -> "P", schoolAge -> "S", teen/adult -> "A"; infantToddler (or an
    unrecognized value) -> None, which passes every activity's age filter (P5)."""
    return AGE_TAG_BY_GROUP.get(age_group or "")


# ---------------------------------------------------------------------------
# catalog

def catalog_index(catalog: Catalog | None) -> dict[str, dict[str, Any]]:
    return {entry["id"]: entry for entry in catalog or []
            if isinstance(entry, dict) and isinstance(entry.get("id"), str)}


def catalog_items(catalog: Catalog | None) -> list[str]:
    """Every catalog *item* id in catalog order (groups left out)."""
    return [entry["id"] for entry in catalog or []
            if isinstance(entry, dict) and entry.get("kind") == "item" and isinstance(entry.get("id"), str)]


def catalog_order(catalog: Catalog | None) -> dict[str, int]:
    return {entry_id: position for position, entry_id in enumerate(catalog_index(catalog))}


def equipment_name(catalog: Catalog | None, equipment_id: str) -> str:
    """The catalog name, lower-cased ("life jacket"); the id when unknown."""
    entry = catalog_index(catalog).get(equipment_id)
    name = entry.get("name") if entry and isinstance(entry.get("name"), str) else equipment_id
    return name.lower()


def requirement_phrases(activity: Activity, catalog: Catalog | None) -> list[str]:
    """One phrase per requirement group, items in catalog order joined with "or":
    [["life-jacket", "float-belt"]] -> ["float belt or life jacket"] (F5)."""
    order = catalog_order(catalog)
    phrases = []
    for group in activity.get("equipment") or []:
        items = sorted((item for item in group if isinstance(item, str)),
                       key=lambda item: (order.get(item, len(order)), item))
        if items:
            phrases.append(" or ".join(equipment_name(catalog, item) for item in items))
    return phrases


def optional_names(activity: Activity, catalog: Catalog | None) -> list[str]:
    order = catalog_order(catalog)
    items = sorted((item for item in activity.get("equipmentOptional") or [] if isinstance(item, str)),
                   key=lambda item: (order.get(item, len(order)), item))
    return [equipment_name(catalog, item) for item in items]


# ---------------------------------------------------------------------------
# profile items and props (P6)

def requirement_counts(activities: Iterable[Activity], catalog: Catalog | None) -> dict[str, int]:
    """Catalog item id -> the number of activities in which it is the only option of a
    required group; a `group` entry as the only option counts toward each of its
    `anyOf[]` items. An activity counts an item once however many groups name it;
    ids that are not in the catalog do not count."""
    index = catalog_index(catalog)
    counts: dict[str, int] = {}
    for activity in activities:
        if not isinstance(activity, dict):
            continue
        counted: set[str] = set()
        for group in activity.get("equipment") or []:
            options = [item for item in group if isinstance(item, str)] if isinstance(group, list) else []
            if len(options) != 1:
                continue
            entry = index.get(options[0])
            if entry is None:
                continue
            if entry.get("kind") == "group":
                counted.update(item for item in entry.get("anyOf") or []
                               if isinstance(item, str) and index.get(item, {}).get("kind") == "item")
            elif entry.get("kind") == "item":
                counted.add(options[0])
        for item in counted:
            counts[item] = counts.get(item, 0) + 1
    return counts


def profile_items(curriculum) -> list[str]:
    """The profile's equipment (P6): the `PROFILE_SIZE` catalog items with the highest
    `requirement_counts` over the loaded library, ties by catalog order, listed in
    catalog order. Every other catalog item is a prop."""
    catalog = curriculum.equipment
    items = catalog_items(catalog)
    counts = requirement_counts(curriculum.activities, catalog)
    ranked = sorted(range(len(items)), key=lambda position: (-counts.get(items[position], 0), position))
    chosen = set(ranked[:PROFILE_SIZE])
    return [item for position, item in enumerate(items) if position in chosen]


def is_prop(curriculum, equipment_id: str, profile: Iterable[str] | None = None) -> bool:
    """A catalog item that is not profile equipment."""
    entry = catalog_index(curriculum.equipment).get(equipment_id)
    if entry is None or entry.get("kind") != "item":
        return False
    return equipment_id not in (set(profile) if profile is not None else set(profile_items(curriculum)))


# ---------------------------------------------------------------------------
# pool profile

def default_pool(curriculum) -> Pool:
    """A new profile: every depth, diving, the tot-dock and every profile item on (P1)."""
    return {
        "depths": {zone: True for zone in ids.ZONES},
        "diving": True,
        "totDock": True,
        "equipment": {item: True for item in profile_items(curriculum)},
    }


def normalize_pool(pool: Pool | None, curriculum) -> Pool:
    """The full profile shape from a possibly partial one: a missing key is off, a
    key that is not a profile item (a prop, a group, an unknown id) is dropped,
    values are bools (P1)."""
    pool = pool or {}
    depths = pool.get("depths") or {}
    equipment = pool.get("equipment") or {}
    return {
        "depths": {zone: bool(depths.get(zone, False)) for zone in ids.ZONES},
        "diving": bool(pool.get("diving", False)),
        "totDock": bool(pool.get("totDock", False)),
        "equipment": {item: bool(equipment.get(item, False)) for item in profile_items(curriculum)},
    }


def depth_on(pool: Pool | None, zone: str) -> bool:
    return bool(((pool or {}).get("depths") or {}).get(zone, False))


def is_on(pool: Pool | None, equipment_id: str, curriculum, profile: Iterable[str] | None = None) -> bool:
    """A profile item's toggle (a missing key is off); a prop is always on; a group is
    on when any of its anyOf[] items is; an unknown id is off. `profile` is
    `profile_items(curriculum)`, passed by callers that filter many activities."""
    profile_set = set(profile) if profile is not None else set(profile_items(curriculum))
    entry = catalog_index(curriculum.equipment).get(equipment_id)
    state = (pool or {}).get("equipment") or {}
    if entry is None:
        return False
    if entry.get("kind") == "group":
        return any(is_on(pool, item, curriculum, profile_set) for item in entry.get("anyOf") or []
                   if isinstance(item, str))
    if equipment_id not in profile_set:
        return True
    return bool(state.get(equipment_id))


def group_satisfied(pool: Pool | None, group: Iterable[str], curriculum,
                    profile: Iterable[str] | None = None) -> bool:
    """One requirement group is satisfied when any of its ids is on. An empty group
    requires nothing."""
    group = list(group or [])
    return not group or any(is_on(pool, item, curriculum, profile) for item in group)


# ---------------------------------------------------------------------------
# the filter

def hidden_reason(activity: Activity, pool: Pool | None, curriculum, age_tag: str | None = None,
                  profile: Iterable[str] | None = None) -> dict[str, Any] | None:
    """The first reason the pool (or the age tag) hides `activity`, or None when it
    shows: {"kind": "equipment", "missing": [group, ...]} · {"kind": "depth",
    "depths": [...]} · {"kind": "diving"} · {"kind": "age", "ages": [...]}. A prop
    never hides (P6)."""
    profile = list(profile) if profile is not None else profile_items(curriculum)
    missing = [list(group) for group in activity.get("equipment") or []
               if not group_satisfied(pool, group, curriculum, profile)]
    if missing:
        return {"kind": "equipment", "missing": missing}
    depths = activity.get("depths") or []
    if depths and not any(depth_on(pool, zone) for zone in depths):
        return {"kind": "depth", "depths": list(depths)}
    if activity.get("headfirst") and not (depth_on(pool, "deep") and bool((pool or {}).get("diving"))):
        return {"kind": "diving"}
    ages = activity.get("ages") or []
    if ages and age_tag is not None and age_tag not in ages:
        return {"kind": "age", "ages": list(ages)}
    return None


def passes(activity: Activity, pool: Pool | None, curriculum, age_tag: str | None = None,
           profile: Iterable[str] | None = None) -> bool:
    return hidden_reason(activity, pool, curriculum, age_tag, profile) is None


def pool_filter(activities: Iterable[Activity], pool: Pool | None, curriculum,
                age_tag: str | None = None) -> list[Activity]:
    """The one filter (P4): the activities that show, in the order given."""
    profile = profile_items(curriculum)
    return [activity for activity in activities if passes(activity, pool, curriculum, age_tag, profile)]


def filter_ids(curriculum, activity_ids: Iterable[str], pool: Pool | None,
               age_tag: str | None = None) -> list[str]:
    """`pool_filter` over ids resolved through the curriculum; an id that is not an
    activity is dropped. Order preserved, duplicates kept (callers dedupe)."""
    activities = [curriculum.activity(activity_id) for activity_id in activity_ids]
    shown = pool_filter((a for a in activities if a is not None), pool, curriculum, age_tag)
    return [activity["id"] for activity in shown]


# ---------------------------------------------------------------------------
# library order

def catalog_position(curriculum) -> dict[str, int]:
    """Activity id -> its position in activities.json (the "catalog number")."""
    return {activity["id"]: position for position, activity in enumerate(curriculum.activities)
            if isinstance(activity, dict) and isinstance(activity.get("id"), str)}


def dedupe(items: Iterable[str]) -> list[str]:
    """First occurrence wins, order kept."""
    seen: set[str] = set()
    result = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result


def skill_activity_ids(curriculum, skill_ids: Iterable[str]) -> list[str]:
    """The activities of several skills, in catalog order, deduped (D2's second part)."""
    position = catalog_position(curriculum)
    collected = []
    for skill_id in skill_ids:
        skill = curriculum.skill(skill_id)
        if skill:
            collected.extend(a for a in skill.get("activityIds") or [] if isinstance(a, str))
    return dedupe(sorted(collected, key=lambda a: (position.get(a, len(position)), a)))


def library_groups(curriculum, stage_id: str) -> list[dict[str, Any]]:
    """The stage's library grouped: a Greeting group first (`greetingActivityIds`),
    then one group per skill in library order, each group's activities in catalog
    order (F6's grouping before the filter). Group: {"skillId": id or None,
    "name", "activityIds"}."""
    stage = curriculum.stage(stage_id)
    if not stage:
        return []
    position = catalog_position(curriculum)

    def ordered(activity_ids):
        return dedupe(sorted((a for a in activity_ids or [] if isinstance(a, str)),
                             key=lambda a: (position.get(a, len(position)), a)))

    groups = [{"skillId": None, "name": "Greeting", "activityIds": ordered(stage.get("greetingActivityIds"))}]
    for skill in curriculum.skills_of(stage_id):
        groups.append({"skillId": skill.get("id"), "name": skill.get("name") or skill.get("id"),
                       "activityIds": ordered(skill.get("activityIds"))})
    return groups


def library(curriculum, stage_id: str) -> list[str]:
    """Every activity id of a stage: Greeting first, then skill by skill, deduped."""
    return dedupe(a for group in library_groups(curriculum, stage_id) for a in group["activityIds"])
