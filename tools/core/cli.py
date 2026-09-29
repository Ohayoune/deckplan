"""Command line: python3 -m tools.core <command> ...

  curriculum validate [--dir curriculum] [--local PATH] [--errors-only]
  curriculum assemble [--work curriculum/_work] [--out curriculum] [--videos PATH]
                      [--equipment PATH] [--safety PATH] [--version V]
  curriculum check-work <file> [--equipment PATH]
  curriculum review <stage> [--work curriculum/_work] [--out curriculum/review]
  class new --stage S --weekdays mon,wed --first-date YYYY-MM-DD --out FILE
            [--lessons N] [--age-group G] [--name NAME] [--id ID] [--curriculum PATH]
  plan    --class FILE --day N [--pool FILE] [--curriculum PATH] [--json OUT]
  shuffle --class FILE --day N --block KIND [--pool FILE] [--curriculum PATH] [--write]
  pick    --class FILE --day N --block KIND --skill SLUG [--pool FILE] [--curriculum PATH] [--write]
  save    --class FILE --day N [--pool FILE] [--curriculum PATH]
  find    --stage S [--skill SLUG] [--step N] [--age P|S|A] [--page K] [--pool FILE]
          [--curriculum PATH] [--json OUT]
  browse  --stage S [--age P|S|A] [--pool FILE] [--curriculum PATH] [--json OUT]

Files are the app's store documents: a class file is `{"format": "classes/1", "items":
[class]}` (its first item is the class), a pool file `{"format": "pool/1", "items":
[profile]}`; without `--pool` every toggle is on (`activities.default_pool`).
`--curriculum` defaults to curriculum/ (with its local.json) and may name a compact
sample file. `--skill` is a skill slug without its stage prefix ("front-glide") or the
full id. `--json OUT` writes `canonical.dumps` of exactly the value printed; `--write`
saves the class file back with its draft (`save` always writes it).

Exit status: 0 success; 1 problems (nothing written); 2 usage error.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path

from . import activities as ACT
from . import assemble as A
from . import canonical
from . import classes as CL
from . import curriculum as C
from . import day_plan
from . import finder
from . import ids
from . import review as R

ROOT = A.ROOT
DEFAULT_CURRICULUM = ROOT / "curriculum"
DEFAULT_WORK = DEFAULT_CURRICULUM / "_work"
DEFAULT_REVIEW = DEFAULT_CURRICULUM / "review"
CLASSES_FORMAT = "classes/1"
POOL_FORMAT = "pool/1"
BLOCK_LABELS = {"welcome": "Welcome", "warmUp": "Warm-up", "review": "Review", "introduce": "Introduce",
                "topic": "Topic", "wrapUp": "Wrap-up"}


def format_problem(item):
    return "%s: %s: %s [%s]" % (item.severity, item.where, item.message, item.code)


def _report(problems, out, errors_only=False):
    for item in problems:
        if item.severity == C.ERROR or not errors_only:
            print(format_problem(item), file=out)


def _counts(problems):
    e, w = len(C.errors(problems)), len(C.warnings(problems))
    return "%d error%s, %d warning%s" % (e, "" if e == 1 else "s", w, "" if w == 1 else "s")


# ---------------------------------------------------------------------------
# curriculum (kept from v1)

def cmd_validate(args, out):
    curriculum, problems = C.check(args.dir, args.local)
    for line in C.format_summary(C.summary(curriculum)):
        print(line, file=out)
    _report(problems, out, args.errors_only)
    print("Validation: %s." % _counts(problems), file=out)
    if C.errors(problems):
        print("The curriculum has errors, so it can't be planned on until they are fixed.", file=out)
        return 1
    return 0


def cmd_assemble(args, out):
    result = A.assemble(args.work, args.out, equipment_path=args.equipment, safety_path=args.safety,
                        videos_path=args.videos, version=args.version)
    _report(result.problems, out)
    for note in result.notes:
        print("note: %s" % note, file=out)
    if not result.ok:
        print("Assembly found %s; nothing was written. Fix the errors and assemble again." % _counts(result.problems),
              file=out)
        return 1
    print("Assembled stages %s (skipped: %s); wrote %d files under %s: %s."
          % (", ".join(result.stages), ", ".join(result.skipped) or "none", len(result.written), args.out,
             ", ".join(result.written)), file=out)
    return 0


def cmd_check_work(args, out):
    catalog_problems = []
    catalog = A.load_catalog(args.equipment, catalog_problems)
    work, problems = A.check_work_file(args.file, catalog)
    problems = catalog_problems + problems
    _report(problems, out)
    print("%s: %s." % (Path(args.file).name, _counts(problems)), file=out)
    return 1 if C.errors(problems) or work is None else 0


def cmd_review(args, out):
    path, problems = R.write_review(args.stage, args.work, args.out)
    if path is None:
        _report(problems, out)
        print("No review written: the work file for Stage %s could not be read." % args.stage, file=out)
        return 1
    print("Wrote %s (check-work: %s)." % (path, _counts(problems)), file=out)
    return 0


# ---------------------------------------------------------------------------
# files

def write_text_atomic(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".%s." % path.name, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def write_canonical(path, value):
    write_text_atomic(path, canonical.dumps(value) + "\n")


def load_store_file(path, expected_format, out):
    """One store document; (items, ok)."""
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as exc:
        print("error: %s: %s" % (path, exc), file=out)
        return None, False
    if not isinstance(data, dict) or data.get("format") != expected_format or not isinstance(data.get("items"), list):
        print("error: %s is not a %s document ({\"format\": \"%s\", \"items\": [...]})."
              % (path, expected_format, expected_format), file=out)
        return None, False
    return data["items"], True


def load_curriculum(args, out):
    path = Path(args.curriculum)
    if path.is_dir():
        curriculum, problems = C.check(path)
    else:
        curriculum = C.load(path)
        problems = C.validate(curriculum)
    if C.errors(problems) or not curriculum.stages:
        _report(problems, out, errors_only=True)
        print("The curriculum at %s has errors; nothing planned." % path, file=out)
        return None
    return curriculum


def load_pool(args, curriculum, out):
    if not getattr(args, "pool", None):
        return ACT.default_pool(curriculum), True
    items, ok = load_store_file(args.pool, POOL_FORMAT, out)
    if not ok:
        return None, False
    if not items or not isinstance(items[0], dict):
        print("error: %s has no pool profile." % args.pool, file=out)
        return None, False
    return ACT.normalize_pool(items[0], curriculum), True


def load_class(args, curriculum, out):
    items, ok = load_store_file(args.class_file, CLASSES_FORMAT, out)
    if not ok:
        return None, None, False
    if not items:
        print("error: %s has no class." % args.class_file, file=out)
        return None, None, False
    class_ = items[0]
    problems = CL.validate_class(class_, curriculum)
    if problems:
        _report(problems, out)
        return None, None, False
    return class_, items, True


def write_class(args, class_, items, out):
    document = {"format": CLASSES_FORMAT, "items": [class_] + list(items[1:])}
    write_canonical(args.class_file, document)
    print("Wrote %s." % args.class_file, file=out)


def resolve_skill(curriculum, stage_id, text):
    """A slug ("front-glide") or a full skill id -> the skill id, or None."""
    if text is None:
        return None, []
    candidate = text if ids.parse_skill_id(text) else ids.skill_id(stage_id, ids.slug(text))
    skill = curriculum.skill(candidate)
    if skill is None or skill.get("stageId") != stage_id:
        names = ", ".join(s["id"].split(".", 1)[1] for s in curriculum.skills_of(stage_id) if isinstance(s.get("id"), str))
        return None, [C.problem("finder-skill", "skill", "%r is not a Stage %s skill; they are: %s." % (text, stage_id, names))]
    return candidate, []


# ---------------------------------------------------------------------------
# rendering

def _name(curriculum, activity_id):
    activity = curriculum.activity(activity_id) or {}
    return activity.get("name") or activity_id


def _skill_name(curriculum, skill_id):
    skill = curriculum.skill(skill_id) or {}
    return skill.get("name") or skill_id


def print_plan(curriculum, plan, out):
    state = "saved" if plan["saved"] else ("draft" if plan["draft"] else "new")
    guide = "guide lesson %s" % plan["guideLesson"] if plan["guideLesson"] else "extra day"
    print("Day %d · %s · %s · %s" % (plan["n"], plan["date"], guide, state), file=out)
    for block in plan["blocks"]:
        skills = block.get("skillIds") or []
        label = BLOCK_LABELS.get(block["kind"], block["kind"])
        if block.get("topic"):
            head = "%s %s" % (block["topic"]["code"], block["topic"]["name"])
        elif skills == [ids.ANY_SKILL]:
            head = "pick a skill: %s" % ", ".join(_skill_name(curriculum, s) for s in block.get("skillChoices") or [])
        else:
            head = ", ".join(_skill_name(curriculum, s) for s in skills)
        line = "%s · %s min" % (label, block.get("minutes"))
        print(line + (" · " + head if head else ""), file=out)
        hidden = set(block.get("hidden") or [])
        for activity_id in block.get("activityIds") or []:
            flag = "  (hidden by the pool)" if activity_id in hidden else ""
            print("  - %s%s" % (_name(curriculum, activity_id), flag), file=out)


def print_find(curriculum, result, out):
    parts = ["Stage %s" % result["stageId"]]
    if result.get("skillId"):
        parts.append(_skill_name(curriculum, result["skillId"]))
    if result.get("step") is not None:
        parts.append("step %d" % result["step"])
    if result.get("ageTag"):
        parts.append(ACT.AGE_WORDS.get(result["ageTag"], result["ageTag"]))
    print("%s · page %d of %d activities%s" % (" · ".join(parts), result["page"], result["total"],
                                                " (wrapped)" if result["wrapped"] else ""), file=out)
    for activity_id in result["activityIds"]:
        item = finder.detail(curriculum, activity_id, result.get("skillId")) or {}
        extras = []
        if item.get("equipment"):
            extras.append("needs " + "; ".join(item["equipment"]))
        if item.get("equipmentOptional"):
            extras.append("optional " + ", ".join(item["equipmentOptional"]))
        if item.get("ages"):
            extras.append("/".join(item["ages"]))
        if item.get("submerges"):
            extras.append("submerges")
        if item.get("videos"):
            extras.append("video: " + "; ".join(item["videos"]))
        print("- %s%s" % (item.get("name", activity_id), (" — " + " · ".join(extras)) if extras else ""), file=out)
        if item.get("description"):
            print("    %s" % item["description"], file=out)


def print_browse(curriculum, result, out):
    print("Stage %s library" % result["stageId"], file=out)
    for group in result["groups"]:
        print("%s (%d)" % (group["name"], len(group["activityIds"])), file=out)
        for activity_id in group["activityIds"]:
            print("  - %s" % _name(curriculum, activity_id), file=out)


# ---------------------------------------------------------------------------
# commands

def _maybe_json(args, value):
    if getattr(args, "json", None):
        write_canonical(args.json, value)


def cmd_class_new(args, out):
    curriculum = load_curriculum(args, out)
    if curriculum is None:
        return 1
    weekdays = [w.strip().lower() for w in args.weekdays.split(",") if w.strip()]
    class_, problems = CL.new_class(curriculum, args.stage, weekdays, args.first_date, name=args.name,
                                    age_group=args.age_group, lessons=args.lessons, class_id=args.id)
    if problems:
        _report(problems, out)
        return 1
    write_canonical(args.out, {"format": CLASSES_FORMAT, "items": [class_]})
    print("Wrote %s: %s, %d lessons from %s." % (args.out, class_["name"], class_["lessons"], args.first_date), file=out)
    return 0


def _setup(args, out):
    curriculum = load_curriculum(args, out)
    if curriculum is None:
        return None
    pool, ok = load_pool(args, curriculum, out)
    if not ok:
        return None
    class_, items, ok = load_class(args, curriculum, out)
    if not ok:
        return None
    return curriculum, pool, class_, items


def cmd_plan(args, out):
    setup = _setup(args, out)
    if setup is None:
        return 1
    curriculum, pool, class_, _ = setup
    plan, problems = day_plan.plan_day(curriculum, class_, pool, args.day)
    if plan is None:
        _report(problems, out)
        return 1
    print_plan(curriculum, plan, out)
    _maybe_json(args, plan)
    return 0


def cmd_shuffle(args, out):
    setup = _setup(args, out)
    if setup is None:
        return 1
    curriculum, pool, class_, items = setup
    updated, result, problems = day_plan.shuffle(curriculum, class_, pool, args.day, args.block)
    if result is None:
        _report(problems, out)
        return 1
    print("%s · shuffle %d" % (BLOCK_LABELS.get(args.block, args.block), result["shuffleCount"]), file=out)
    for activity_id in result["activityIds"]:
        print("  - %s" % _name(curriculum, activity_id), file=out)
    if result.get("message"):
        print(result["message"], file=out)
    if args.write:
        write_class(args, updated, items, out)
    return 0


def cmd_pick(args, out):
    setup = _setup(args, out)
    if setup is None:
        return 1
    curriculum, pool, class_, items = setup
    skill_id, problems = resolve_skill(curriculum, class_["stageId"], args.skill)
    if problems:
        _report(problems, out)
        return 1
    updated, problems = day_plan.pick_skill(curriculum, class_, pool, args.day, args.block, skill_id)
    if problems:
        _report(problems, out)
        return 1
    plan, _ = day_plan.plan_day(curriculum, updated, pool, args.day)
    print_plan(curriculum, plan, out)
    if args.write:
        write_class(args, updated, items, out)
    return 0


def cmd_save(args, out):
    setup = _setup(args, out)
    if setup is None:
        return 1
    curriculum, pool, class_, items = setup
    updated, entry, problems = day_plan.save_day(curriculum, class_, pool, args.day)
    if entry is None:
        _report(problems, out)
        return 1
    write_class(args, updated, items, out)
    following = CL.next_day(updated)
    print("Day %d saved (%s). %s" % (entry["n"], entry["date"],
                                     "Next: day %d." % following if following else "The class is complete."), file=out)
    return 0


def cmd_find(args, out):
    curriculum = load_curriculum(args, out)
    if curriculum is None:
        return 1
    pool, ok = load_pool(args, curriculum, out)
    if not ok:
        return 1
    skill_id, problems = resolve_skill(curriculum, args.stage, args.skill)
    if problems:
        _report(problems, out)
        return 1
    result, problems = finder.find(curriculum, args.stage, pool, skill_id, args.step, args.age, args.page)
    if result is None:
        _report(problems, out)
        return 1
    print_find(curriculum, result, out)
    _maybe_json(args, result)
    return 0


def print_search(curriculum, result, out):
    if not result["groups"]:
        print("Stage %s: nothing named like %r." % (result["stageId"], result["text"]), file=out)
        return
    print("Stage %s: %r" % (result["stageId"], result["text"]), file=out)
    for group in result["groups"]:
        print("%s (%d)" % (group["name"], len(group["activityIds"])), file=out)
        for activity_id in group["activityIds"]:
            print("  - %s" % _name(curriculum, activity_id), file=out)


def cmd_search(args, out):
    curriculum = load_curriculum(args, out)
    if curriculum is None:
        return 1
    pool, ok = load_pool(args, curriculum, out)
    if not ok:
        return 1
    result, problems = finder.search(curriculum, args.stage, pool, args.text, args.age)
    if result is None:
        _report(problems, out)
        return 1
    print_search(curriculum, result, out)
    _maybe_json(args, result)
    return 0


def cmd_today(args, out):
    """Today by date (C7): the lessons dated `--date`, the next lesson and the missed
    days over every class in the file."""
    curriculum = load_curriculum(args, out)
    if curriculum is None:
        return 1
    items, ok = load_store_file(args.class_file, CLASSES_FORMAT, out)
    if not ok:
        return 1
    problems = [p for class_ in items for p in CL.validate_class(class_, curriculum)]
    if problems:
        _report(problems, out)
        return 1
    by_id = {c.get("id"): c for c in items}

    def label(item):
        class_ = by_id.get(item["classId"]) or {}
        return "%s · day %d of %d" % (class_.get("name"), item["n"], class_.get("lessons") or 0)

    lessons = CL.today(items, args.date)
    for item in lessons:
        print("Today %s: %s" % (args.date, label(item)), file=out)
    following = CL.next_lesson(items, args.date)
    if not lessons:
        if following is None:
            print("Nothing on %s and no lesson after it." % args.date, file=out)
        else:
            print("Nothing on %s. Next: %s on %s." % (args.date, label(following), following["date"]), file=out)
    missed = CL.missed(items, args.date)
    for item in missed:
        print("Not saved: %s on %s." % (label(item), item["date"]), file=out)
    _maybe_json(args, {"date": args.date, "today": lessons, "next": following, "missed": missed})
    return 0


def cmd_browse(args, out):
    curriculum = load_curriculum(args, out)
    if curriculum is None:
        return 1
    pool, ok = load_pool(args, curriculum, out)
    if not ok:
        return 1
    result, problems = finder.browse(curriculum, args.stage, pool, args.age)
    if result is None:
        _report(problems, out)
        return 1
    print_browse(curriculum, result, out)
    _maybe_json(args, result)
    return 0


# ---------------------------------------------------------------------------
# parser

def _common(parser, class_file=True, pool=True, json_out=False):
    parser.add_argument("--curriculum", default=str(DEFAULT_CURRICULUM),
                        help="curriculum directory or a compact sample file (default: curriculum/)")
    if class_file:
        parser.add_argument("--class", dest="class_file", required=True, help="a classes/1 file (its first item)")
        parser.add_argument("--day", type=int, required=True, help="lesson day n")
    if pool:
        parser.add_argument("--pool", help="a pool/1 file (default: everything on)")
    if json_out:
        parser.add_argument("--json", help="write the value shown as canonical JSON to this file")


def build_parser():
    parser = argparse.ArgumentParser(prog="python3 -m tools.core",
                                     description="DeckPlan v2: Python reference core.")
    commands = parser.add_subparsers(dest="command", required=True)
    group = commands.add_parser("curriculum", help="validate, assemble, check or review the curriculum data")
    actions = group.add_subparsers(dest="action", required=True)

    validate = actions.add_parser("validate", help="load and validate a curriculum directory or sample file")
    validate.add_argument("--dir", "--curriculum", dest="dir", default=str(DEFAULT_CURRICULUM),
                          help="curriculum directory or a single-file sample (default: curriculum/)")
    validate.add_argument("--local", help="local.json to merge (default: <dir>/local.json)")
    validate.add_argument("--errors-only", action="store_true", help="print errors but not warnings")
    validate.set_defaults(handler=cmd_validate)

    assemble = actions.add_parser("assemble", help="work files -> curriculum files")
    assemble.add_argument("--work", default=str(DEFAULT_WORK), help="work file directory (default: curriculum/_work)")
    assemble.add_argument("--out", default=str(DEFAULT_CURRICULUM), help="output directory (default: curriculum/)")
    assemble.add_argument("--videos", default=str(A.DEFAULT_VIDEOS), help="the Yapp's video list")
    assemble.add_argument("--equipment", default=str(A.DEFAULT_EQUIPMENT), help="the seed equipment catalog")
    assemble.add_argument("--safety", default=None, help="the safety rules (default: safety.json in --work)")
    assemble.add_argument("--version", default=A.DEFAULT_VERSION, help="version.json's version")
    assemble.set_defaults(handler=cmd_assemble)

    check_work = actions.add_parser("check-work", help="check one work file on its own")
    check_work.add_argument("file", help="curriculum/_work/stage-<S>.json")
    check_work.add_argument("--equipment", default=str(A.DEFAULT_EQUIPMENT), help="the seed equipment catalog")
    check_work.set_defaults(handler=cmd_check_work)

    review = actions.add_parser("review", help="write curriculum/review/stage-<S>.md for the owner's sign-off")
    review.add_argument("stage", type=str.upper, choices=list(ids.STAGE_IDS), help="stage: A, B or 1–6")
    review.add_argument("--work", default=str(DEFAULT_WORK), help="work file directory (default: curriculum/_work)")
    review.add_argument("--out", default=str(DEFAULT_REVIEW), help="output directory (default: curriculum/review)")
    review.set_defaults(handler=cmd_review)

    class_group = commands.add_parser("class", help="create a class file")
    class_actions = class_group.add_subparsers(dest="action", required=True)
    new = class_actions.add_parser("new", help="a new class with REDESIGN §5's defaults")
    new.add_argument("--stage", required=True, type=str.upper, choices=list(ids.STAGE_IDS))
    new.add_argument("--weekdays", required=True, help="comma-separated mon..sun")
    new.add_argument("--first-date", required=True, help="YYYY-MM-DD")
    new.add_argument("--out", required=True, help="the classes/1 file to write")
    new.add_argument("--lessons", type=int, default=CL.DEFAULT_LESSONS)
    new.add_argument("--age-group", choices=list(ids.AGE_GROUPS))
    new.add_argument("--name")
    new.add_argument("--id", help="the class id (default: a UUID)")
    _common(new, class_file=False, pool=False)
    new.set_defaults(handler=cmd_class_new)

    plan = commands.add_parser("plan", help="one day's plan")
    _common(plan, json_out=True)
    plan.set_defaults(handler=cmd_plan)

    shuffle = commands.add_parser("shuffle", help="shuffle one block of a day, saved or not")
    _common(shuffle)
    shuffle.add_argument("--block", required=True, choices=[k for k in ids.BLOCK_KINDS if k != "topic"])
    shuffle.add_argument("--write", action="store_true", help="save the class file with the draft")
    shuffle.set_defaults(handler=cmd_shuffle)

    pick = commands.add_parser("pick", help="pick the skill of an \"any\" block")
    _common(pick)
    pick.add_argument("--block", required=True, choices=["review", "introduce"])
    pick.add_argument("--skill", required=True, help="skill slug or id")
    pick.add_argument("--write", action="store_true", help="save the class file with the draft")
    pick.set_defaults(handler=cmd_pick)

    save = commands.add_parser("save", help="save a day to the class's log")
    _common(save)
    save.set_defaults(handler=cmd_save)

    find = commands.add_parser("find", help="three activities for a stage, skill and step")
    find.add_argument("--stage", required=True, type=str.upper, choices=list(ids.STAGE_IDS))
    find.add_argument("--skill", help="skill slug or id")
    find.add_argument("--step", type=int, help="step number within the skill")
    find.add_argument("--age", choices=list(ids.AGE_TAGS), help="age tag; default: all ages")
    find.add_argument("--page", type=int, default=1, help="page number (three per page; default 1)")
    _common(find, class_file=False, json_out=True)
    find.set_defaults(handler=cmd_find)

    browse = commands.add_parser("browse", help="a stage's library, grouped by skill")
    browse.add_argument("--stage", required=True, type=str.upper, choices=list(ids.STAGE_IDS))
    browse.add_argument("--age", choices=list(ids.AGE_TAGS), help="age tag; default: all ages")
    _common(browse, class_file=False, json_out=True)
    browse.set_defaults(handler=cmd_browse)

    search = commands.add_parser("search", help="a stage's library narrowed to activities named like a text")
    search.add_argument("--stage", required=True, type=str.upper, choices=list(ids.STAGE_IDS))
    search.add_argument("--text", required=True, help="part of an activity name, case- and accent-insensitive")
    search.add_argument("--age", choices=list(ids.AGE_TAGS), help="age tag; default: all ages")
    _common(search, class_file=False, json_out=True)
    search.set_defaults(handler=cmd_search)

    today = commands.add_parser("today", help="the lessons dated a day, the next lesson and the missed days")
    today.add_argument("--class", dest="class_file", required=True, help="a classes/1 file (every item)")
    today.add_argument("--date", required=True, help="the calendar day, YYYY-MM-DD (the Core never reads the clock)")
    _common(today, class_file=False, pool=False, json_out=True)
    today.set_defaults(handler=cmd_today)
    return parser


def main(argv=None, out=None):
    out = out or sys.stdout
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exit_:
        return exit_.code if isinstance(exit_.code, int) else 2
    try:
        return args.handler(args, out)
    except OSError as exc:
        print("error: %s" % exc, file=out)
        return 1
