"""Work files -> the curriculum files (CURRICULUM_FORMAT.md §3), and check-work.

Each stage's transcriber writes curriculum/_work/stage-<S>.json (format
"curriculum-work/1"). `check_work` validates one work file on its own; `assemble` reads
every work file and writes curriculum/stages/<S>.json, activities.json, equipment.json,
videos.json, version.json and safety.json. Output is deterministic: stages A, B, 1–6,
library order, 2-space JSON with sorted keys. Nothing is written when any error is found.
The safety rules are read from safety.json beside the work files: the owner's copy holds the
libraries' own sentences, so it lives in the gitignored curriculum/_work/.
"""

import json
import os
import re
import tempfile
from pathlib import Path

from . import curriculum as C
from . import ids
from .curriculum import ERROR, WARNING, dict_items, is_int, is_str_list, problem

WORK_FORMAT = "curriculum-work/1"
PACKAGE_DIR = Path(__file__).resolve().parent
ROOT = PACKAGE_DIR.parents[1]
DATA_DIR = PACKAGE_DIR / "data"
DEFAULT_EQUIPMENT = DATA_DIR / "equipment.json"
SAFETY_FILE = "safety.json"  # the safety rules, read from the work folder
DEFAULT_VIDEOS = ROOT / "reference" / "ymca-v6" / "videos.json"
DEFAULT_VERSION = "2026.09"
VERSION_SOURCE = "YMCA Swim Lessons V6 Instructor Toolkit (Yapp YSLSWIM)"
VIDEO_PAGES = ("YSL Videos", "SAW Videos")
GREETING = "greeting"
TAG_RE = re.compile(r"^[a-z][a-z0-9-]*$")
PRESCHOOL_NOTE_RE = re.compile(r"\s*\([^()]*\bpreschool\)\s*$")


def row_text(row):
    """A tracker row's text without the printed preschool note ("Front glide on your own, farther, 10 feet (5 ft.
    preschool)" -> "Front glide on your own, farther, 10 feet"): the variant lives in the benchmark step's
    measure.preschoolValue, and the note itself only feeds the A8 check."""
    return PRESCHOOL_NOTE_RE.sub("", row.get("text", "")).strip()


def work_file_name(stage_id):
    return "stage-%s.json" % stage_id


def dumps(value):
    """The curriculum files' format: 2-space JSON, keys sorted, UTF-8, trailing newline."""
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def write_text_atomic(path, content):
    """Write via a temporary file and os.replace, so a failed write never leaves a torn file."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=".%s." % path.name, dir=str(path.parent))
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            stream.write(content)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def _show(value, limit=70):
    shown = json.dumps(value, ensure_ascii=False)
    return shown if len(shown) <= limit else shown[:limit - 1] + "…"


def load_catalog(path=DEFAULT_EQUIPMENT, problems=None):
    """The seed equipment catalog as a list, or [] with a problem when it can't be read."""
    found = [] if problems is None else problems
    data = C.read_json(path, found, Path(path).name)
    if not isinstance(data, list):
        if data is not None:
            found.append(problem("file-unreadable", Path(path).name, "%s is not a JSON list." % Path(path).name))
        return []
    return data


# ---------------------------------------------------------------------------
# check-work

class _WorkChecker(C._Checker):
    """The validator's field checks (depths, flags, measure, equipment ids) run over the
    seed catalog, with every `where` prefixed by the work file's name."""

    def __init__(self, catalog_entries, name):
        seed = C.Curriculum(name, "work")
        seed.equipment = list(catalog_entries)
        seed.reindex()
        C._Checker.__init__(self, seed)
        self.name = name

    def add(self, code, where, message, severity=ERROR):
        full = "%s / %s" % (self.name, where) if where else self.name
        self.problems.append(problem(code, full, message, severity))


def check_work_file(path, catalog=None):
    """Read and check one work file: (work or None, problems)."""
    path = Path(path)
    found = []
    work = C.read_json(path, found, path.name)
    if work is None:
        return None, found
    if catalog is None:
        catalog = load_catalog(DEFAULT_EQUIPMENT, found)
    return work, found + check_work(work, catalog, path.name)


def activity_entries(work):
    """(owner, index, activity) for the work file's activities in library order: the
    Greeting first, then each skill's page. owner is "greeting" or the skill slug."""
    found = []
    greeting = work.get("greeting") if isinstance(work.get("greeting"), dict) else {}
    for index, activity in enumerate(dict_items(greeting.get("activities"))):
        found.append((GREETING, index, activity))
    for skill in dict_items(work.get("skills")):
        for index, activity in enumerate(dict_items(skill.get("activities"))):
            found.append((skill.get("slug"), index, activity))
    return found


def name_candidates(work, block_slugs, kind):
    """The stage's activities a printed name may mean, in preference order: the block's
    skills' pages (block order), the Greeting (first for a Welcome block), then the
    stage's other skills. Returns [(owner, index, activity)]."""
    entries = activity_entries(work)
    ordered = []
    tiers = [list(block_slugs)]
    tiers.insert(0 if kind == "welcome" else 1, [GREETING])
    for tier in tiers:
        for owner in tier:
            ordered.extend(entry for entry in entries if entry[0] == owner)
    ordered.extend(entry for entry in entries if entry[0] not in block_slugs and entry[0] != GREETING)
    return ordered


def match_name(name, candidates):
    key = ids.slug(name)
    return [entry for entry in candidates if ids.slug(entry[2].get("name")) == key]


def _upper_minutes(printed):
    numbers = [int(n) for n in re.findall(r"[0-9]+", printed)]
    return max(numbers) if numbers else None


def check_work(work, catalog, name="work file"):
    """Every check-work rule on one work file on its own. Returns problems."""
    c = _WorkChecker(catalog, name)
    try:
        _check_work(c, work)
    except Exception as exc:  # never raise on bad data
        c.add("check-failed", "", "The check stopped early on malformed data (%s: %s); fix the problems "
                                  "reported here and check again." % (type(exc).__name__, exc))
    return c.problems


def _check_work(c, work):
    if not isinstance(work, dict):
        c.add("work-shape", "", "The work file is not a JSON object.")
        return
    if work.get("format") != WORK_FORMAT:
        c.add("work-shape", "format", "format is %s; it must be %r." % (_show(work.get("format")), WORK_FORMAT))
    stage = work.get("stage") if isinstance(work.get("stage"), dict) else None
    if stage is None:
        c.add("work-shape", "stage", "The work file has no stage object.")
        stage = {}
    stage_id = stage.get("id")
    if not ids.is_stage_id(stage_id):
        c.add("work-shape", "stage", "stage.id %s is not a stage (A, B, 1–6)." % _show(stage_id))
        stage_id = None
    for key in ("name", "group"):
        if not isinstance(stage.get(key), str) or not stage.get(key).strip():
            c.add("work-shape", "stage", "stage.%s is missing." % key)
    age_groups = stage.get("ageGroups")
    if not is_str_list(age_groups) or not age_groups or any(g not in ids.AGE_GROUPS for g in age_groups):
        c.add("work-shape", "stage", "stage.ageGroups must be a non-empty list of %s." % ", ".join(ids.AGE_GROUPS))
    lesson_minutes = stage.get("lessonMinutes")
    if not is_int(lesson_minutes) or lesson_minutes <= 0:
        c.add("work-shape", "stage", "stage.lessonMinutes must be a positive whole number.")
        lesson_minutes = None
    milestones = stage.get("milestones")
    if not is_str_list(milestones):
        c.add("work-shape", "stage", "stage.milestones must be a list of the library's milestones.")
    elif len(milestones) != 3:
        c.add("work-shape", "stage", "stage.milestones has %d entries; the library prints three." % len(milestones),
              WARNING)

    skills = work.get("skills")
    if not isinstance(skills, list) or not skills:
        c.add("work-shape", "skills", "The work file has no skills list.")
        skills = []
    by_slug = {}
    for index, skill in enumerate(skills):
        if not isinstance(skill, dict):
            c.add("work-shape", "skills[%d]" % index, "A skill is not an object.")
            continue
        slug = skill.get("slug")
        if isinstance(slug, str) and slug not in by_slug:
            by_slug[slug] = skill
        elif isinstance(slug, str):
            c.add("id-duplicate", "skill %s" % slug, "Skill slug %r appears twice." % slug)
    for key in ("warmUpSkill", "wrapUpSkill"):
        if stage.get(key) not in by_slug:
            c.add("warm-up-wrap-up", "stage", "stage.%s %s is not the slug of a skill in this file."
                  % (key, _show(stage.get(key))))

    for index, skill in enumerate(dict_items(skills)):
        _check_work_skill(c, stage_id, skill, index)
    greeting = work.get("greeting")
    if not isinstance(greeting, dict):
        c.add("work-shape", "greeting", "The work file has no greeting object { activities, pages }.")
    else:
        if not isinstance(greeting.get("activities"), list):
            c.add("work-shape", "greeting", "greeting.activities must be a list.")
        for activity in dict_items(greeting.get("activities")):
            _check_work_activity(c, "greeting / activity %s" % activity.get("name"), activity)
        if not isinstance(greeting.get("pages"), list):
            c.add("work-shape", "greeting", "greeting.pages is missing.", WARNING)
    _check_work_tracker(c, work, by_slug)
    _check_work_topics(c, work, stage_id)
    _check_work_templates(c, work, stage, stage_id, lesson_minutes, by_slug)
    sources = work.get("sources")
    if not isinstance(sources, dict) or not sources.get("library") or not sources.get("guide"):
        c.add("work-shape", "sources", "sources should name the library and guide files.", WARNING)
    uncertain = work.get("uncertain", [])
    if not isinstance(uncertain, list):
        c.add("work-shape", "uncertain", "uncertain must be a list of { where, issue, page }.")
    else:
        for entry in uncertain:
            if not isinstance(entry, dict):
                c.add("work-shape", "uncertain", "An uncertain entry is not an object.")
                continue
            c.add("uncertain", "uncertain", "%s: %s (page %s)." % (entry.get("where"), entry.get("issue"),
                                                                    entry.get("page")), WARNING)
    unreadable = [path for path, value in C._walk_strings(work, "") if C.UNREADABLE in value
                  and not path.startswith("uncertain")]
    if unreadable:
        c.add("placeholder-text", "", "%d field%s marked UNREADABLE (%s%s)."
              % (len(unreadable), "" if len(unreadable) == 1 else "s", ", ".join(unreadable[:3]),
                 ", …" if len(unreadable) > 3 else ""), WARNING)


def _check_work_link(c, where, stage_id, field, refs):
    if not isinstance(refs, list):
        c.add("work-shape", where, "%s must be a list ([] when the page says there is none)." % field)
        return
    if stage_id is None:
        return
    here = ids.STAGE_INDEX[stage_id]
    for ref in refs:
        if not isinstance(ref, dict):
            c.add("link", where, "A %s entry is not an object { stage, skill, n, name }." % field)
            continue
        ref_stage = ref.get("stage")
        if not ids.is_stage_id(ref_stage):
            c.add("link", where, "%s entry %s names stage %s, which is not a stage." % (field, _show(ref), _show(ref_stage)))
            continue
        there = ids.STAGE_INDEX[ref_stage]
        if field == "prerequisite" and there >= here:
            c.add("link", where, "prerequisite entry %s is not in an earlier stage." % _show(ref))
        if field == "advanced" and there <= here:
            c.add("link", where, "advanced entry %s is not in a later stage." % _show(ref))
        has_id = ids.is_slug(ref.get("skill")) and is_int(ref.get("n")) and ref.get("n") >= 1
        if not has_id and not (isinstance(ref.get("name"), str) and ref.get("name").strip()):
            c.add("link", where, "%s entry %s needs skill and n (or at least the step's name)." % (field, _show(ref)))


def _check_work_skill(c, stage_id, skill, index):
    slug = skill.get("slug")
    where = "skill %s" % (slug if isinstance(slug, str) else "#%d" % (index + 1))
    name = skill.get("name")
    if not isinstance(name, str) or not name.strip():
        c.add("work-shape", where, "The skill has no name.")
    if not ids.is_slug(slug) or slug != ids.slug(name):
        c.add("slug-rule", where, "Skill slug %s does not follow the slug rule for %s (expected %r)."
              % (_show(slug), _show(name), ids.slug(name)))
    if skill.get("order") != index + 1:
        c.add("work-shape", where, "order is %s; skills are listed in library order, so it should be %d."
              % (_show(skill.get("order")), index + 1))
    if not isinstance(skill.get("isBenchmarkSequence"), bool):
        c.add("work-shape", where, "isBenchmarkSequence must be true or false.")
    _check_work_link(c, where, stage_id, "prerequisite", skill.get("prerequisite"))
    _check_work_link(c, where, stage_id, "advanced", skill.get("advanced"))
    if stage_id == ids.STAGE_IDS[0] and skill.get("prerequisite"):
        c.add("link", where, "Stage A has no prerequisite steps.")
    if stage_id == ids.STAGE_IDS[-1] and skill.get("advanced"):
        c.add("link", where, "Stage 6 has no advanced steps.")
    steps = skill.get("steps")
    if not isinstance(steps, list):
        c.add("steps", where, "steps must be a list ([] when the stage has no progression for the skill).")
        steps = []
    numbers = [step.get("n") if isinstance(step, dict) else None for step in steps]
    if numbers != list(range(1, len(steps) + 1)):
        c.add("steps", where, "Steps are numbered %s; they run 1, 2, 3… as printed." % _show(numbers))
    names = {}
    for position, step in enumerate(dict_items(steps)):
        step_where = "%s / step %s" % (where, step.get("n"))
        for key in ("name", "description"):
            if not isinstance(step.get(key), str) or not step.get(key).strip():
                c.add("steps", step_where, "The step has no %s." % key)
        if isinstance(step.get("name"), str):
            key = ids.normalize_text(step["name"]).casefold()
            if key in names:
                c.add("step-name-duplicate", step_where, "Step name %r repeats step %s." % (step["name"], names[key]))
            names.setdefault(key, step.get("n"))
        if "measure" in step:
            c.measure(step["measure"], step_where)
            if isinstance(step["measure"], dict) and "preschoolValue" in step["measure"] and position != len(steps) - 1:
                c.add("preschool-value", step_where, "Only the benchmark (last) step carries a preschoolValue.")
        if "depths" in step:
            c.depths(step["depths"], step_where)
        c.flags(step, C.STEP_FLAGS, step_where)
        c.headfirst(step, step_where)
        if "equipment" in step:
            c.requirement_groups(step["equipment"], step_where)
    activities = skill.get("activities")
    if not isinstance(activities, list):
        c.add("work-shape", where, "activities must be a list.")
        activities = []
    seen = set()
    for activity in activities:
        if not isinstance(activity, dict):
            c.add("work-shape", where, "An activity is not an object.")
            continue
        _check_work_activity(c, "%s / activity %s" % (where, activity.get("name")), activity)
        key = (ids.slug(activity.get("name")), ids.description_key(activity.get("description")),
               activity.get("headfirst") is True)
        if key in seen:
            c.add("work-shape", where, "Activity %r is listed twice with the same description." % activity.get("name"),
                  WARNING)
        seen.add(key)
    pages = skill.get("pages")
    if not isinstance(pages, dict) or not is_int(pages.get("progression")) or not is_int(pages.get("activities")):
        c.add("work-shape", where, "pages should give the progression and activities page numbers.", WARNING)


def _check_work_activity(c, where, activity):
    for key in ("name", "description"):
        if not isinstance(activity.get(key), str) or not activity.get(key).strip():
            c.add("activity-shape", where, "The activity has no %s." % key)
    ages = activity.get("ages")
    if not is_str_list(ages) or any(a not in ids.AGE_TAGS for a in ages) or len(set(ages)) != len(ages):
        c.add("activity-shape", where, "ages must be a list of P, S and A as printed ([] when untagged); it is %s."
              % _show(ages))
    if "equipment" in activity:
        c.requirement_groups(activity["equipment"], where)
    if "equipmentOptional" in activity:
        c.optional_equipment(activity["equipmentOptional"], where)
    if "depths" in activity:
        c.depths(activity["depths"], where)
    c.flags(activity, C.ACTIVITY_FLAGS, where)
    if "nearWall" in activity:
        c.add("flag-type", where, "nearWall is for steps only.")
    c.headfirst(activity, where)
    tags = activity.get("tags", [])
    if not is_str_list(tags):
        c.add("activity-shape", where, "tags must be a list of short lower-case words.")
    elif any(not TAG_RE.match(tag) for tag in tags):
        c.add("activity-shape", where, "tags %s should be short lower-case words." % _show(tags), WARNING)
    if "idSuffix" in activity and not ids.is_slug(activity.get("idSuffix")):
        c.add("activity-shape", where, "idSuffix %s is not a lower-case slug." % _show(activity.get("idSuffix")))
    if "variant" in activity and not ids.slug(activity.get("variant")):
        c.add("activity-shape", where, "variant %s must be a word saying what differs, such as \"dive\" or \"back\"."
              % _show(activity.get("variant")))
    if not is_int(activity.get("page")):
        c.add("activity-shape", where, "page (the activities page number) is missing.", WARNING)


def _check_work_tracker(c, work, by_slug):
    rows = work.get("trackerRows")
    if not isinstance(rows, list) or not rows:
        c.add("tracker-rows-missing", "trackerRows", "trackerRows is missing: list the Progress Tracker's rows in order.")
        return
    covered = set()
    for index, row in enumerate(rows):
        where = "trackerRows[%d]" % index
        if not isinstance(row, dict):
            c.add("tracker-row", where, "A tracker row is not an object.")
            continue
        row_text = row.get("text")
        if not isinstance(row_text, str) or not row_text.strip():
            c.add("tracker-row", where, "The row has no text.")
        refs = row.get("steps")
        if not isinstance(refs, list) or not refs:
            c.add("tracker-row", where, "The row names no benchmark steps.")
            continue
        named = []
        for ref in refs:
            skill = by_slug.get(ref.get("skill")) if isinstance(ref, dict) else None
            if skill is None:
                c.add("tracker-row", where, "The row names %s, which is not a skill in this file." % _show(ref))
                continue
            steps = dict_items(skill.get("steps"))
            if not steps:
                c.add("tracker-row", where, "The row names %s, which has no steps in this stage." % skill.get("slug"))
            elif ref.get("n") != len(steps):
                c.add("tracker-row", where, "The row names %s step %s, which is not its last (benchmark) step %d."
                      % (skill.get("slug"), _show(ref.get("n")), len(steps)))
            else:
                named.append(steps[-1])
                covered.add(skill.get("slug"))
        rule = row.get("rule")
        if rule not in ("all", "any"):
            c.add("tracker-row", where, "rule is %s; it must be \"all\" or \"any\"." % _show(rule))
        elif rule == "any" and len(refs) < 2:
            c.add("tracker-row", where, "rule \"any\" needs two or more steps.")
        if rule == "all" and len(refs) == 1 and len(named) == 1 and isinstance(row_text, str):
            if ids.normalize_text(named[0].get("name")) != ids.normalize_text(row_text):
                c.add("tracker-row", where, "The row's text %r differs from its benchmark step's name %r; a one-step "
                                            "row's text is the step's name." % (row_text, named[0].get("name")))
        preschool = row.get("preschool")
        if preschool is not None and not isinstance(preschool, str):
            c.add("tracker-row", where, "preschool must be the preschool variant as printed, or null.")
        for step in named:
            measure = step.get("measure") if isinstance(step.get("measure"), dict) else {}
            if preschool and "preschoolValue" not in measure:
                c.add("preschool-value", where, "The row prints a preschool variant (%s), but step %r has no "
                                                "measure.preschoolValue." % (preschool, step.get("name")))
            if not preschool and "preschoolValue" in measure:
                c.add("preschool-value", where, "Step %r has a preschoolValue, but its row prints no preschool variant."
                      % step.get("name"))
    for slug, skill in by_slug.items():
        if dict_items(skill.get("steps")) and slug not in covered:
            c.add("tracker-coverage", "skill %s" % slug, "Skill %s has steps, but no tracker row names its benchmark."
                  % slug)


def _check_work_topics(c, work, stage_id):
    topics = work.get("topics")
    if not isinstance(topics, list):
        c.add("topics", "topics", "The work file has no topics list.")
        return
    numbers = [t.get("n") if isinstance(t, dict) else None for t in topics]
    if sorted(n for n in numbers if is_int(n)) != list(range(1, 9)) or len(topics) != 8:
        c.add("topics", "topics", "Topics are %s; the stage has topics 1–8." % _show(numbers))
    for topic in dict_items(topics):
        where = "topic %s" % topic.get("code")
        if stage_id and is_int(topic.get("n")) and topic.get("code") != ids.topic_code(stage_id, topic["n"]):
            c.add("topics", where, "code %s should be %r." % (_show(topic.get("code")), ids.topic_code(stage_id, topic["n"])))
        if not isinstance(topic.get("name"), str) or not topic.get("name").strip():
            c.add("topics", where, "The topic has no name.")
        if not isinstance(topic.get("summary", ""), str):
            c.add("topics", where, "summary must be one line of text.")
        for key in ("prompts", "notes"):
            if not is_str_list(topic.get(key)):
                c.add("topics", where, "%s must be a list of strings ([] for none)." % key)
        if not is_int(topic.get("page")):
            c.add("topics", where, "page is missing.", WARNING)


def _check_work_templates(c, work, stage, stage_id, lesson_minutes, by_slug):
    templates = work.get("lessonTemplates")
    if not isinstance(templates, list):
        c.add("templates", "lessonTemplates", "The work file has no lessonTemplates list.")
        return
    numbers = [t.get("n") if isinstance(t, dict) else None for t in templates]
    if sorted(n for n in numbers if is_int(n)) != list(range(1, 9)) or len(templates) != 8:
        c.add("templates", "lessonTemplates", "Lesson templates are %s; the guide has lessons 1–8." % _show(numbers))
    topic_codes = {t.get("code") for t in dict_items(work.get("topics"))}
    for template in dict_items(templates):
        n = template.get("n")
        where = "lesson %s" % n
        total_expected = template.get("minutesTotal")
        if not is_int(total_expected) or total_expected <= 0:
            c.add("template-minutes", where, "minutesTotal is missing.")
            total_expected = None
        elif lesson_minutes and total_expected != lesson_minutes:
            c.add("template-minutes", where, "minutesTotal is %d; the stage's lessons are %d."
                  % (total_expected, lesson_minutes))
        if not isinstance(template.get("pages"), list):
            c.add("templates", where, "pages (the guide pages of this lesson) is missing.", WARNING)
        blocks = template.get("blocks")
        if not isinstance(blocks, list) or not blocks:
            c.add("template-placeholder", where, "The lesson has no blocks.")
            continue
        total, complete = 0, True
        for position, block in enumerate(blocks):
            if not isinstance(block, dict):
                c.add("template-block", where, "Block %d is not an object." % (position + 1))
                complete = False
                continue
            if not is_int(block.get("minutes")):
                complete = False
            else:
                total += block["minutes"]
            _check_work_block(c, work, stage, "%s / block %d (%s)" % (where, position + 1, block.get("kind")),
                              n, block, by_slug, topic_codes)
        if complete and total_expected is not None and total != total_expected:
            c.add("template-minutes", where, "Block minutes add up to %d, not minutesTotal %d (a printed range is "
                                             "recorded at its upper value)." % (total, total_expected))


def _check_work_block(c, work, stage, where, lesson_n, block, by_slug, topic_codes):
    kind = block.get("kind")
    if kind not in ids.BLOCK_KINDS:
        c.add("template-block", where, "kind %s is not one of %s." % (_show(kind), ", ".join(ids.BLOCK_KINDS)))
    minutes = block.get("minutes")
    if not is_int(minutes) or minutes < 0:
        c.add("template-block", where, "minutes must be a whole number of 0 or more.")
    printed = block.get("minutesPrinted")
    if printed is not None:
        upper = _upper_minutes(printed) if isinstance(printed, str) else None
        if upper is None:
            c.add("template-block", where, "minutesPrinted %s holds no number." % _show(printed))
        elif is_int(minutes) and upper != minutes:
            c.add("template-minutes", where, "minutesPrinted %r's upper value is %d, but minutes is %s."
                  % (printed, upper, minutes))
    skills = block.get("skills", [])
    if not isinstance(skills, list):
        c.add("template-block", where, "skills must be a list.")
        skills = []
    slugs = []
    for ref in skills:
        slug = ref.get("slug") if isinstance(ref, dict) else None
        if slug == ids.ANY_SKILL:
            if kind not in ("review", "introduce"):
                c.add("template-block", where, "\"any\" fills Review and Introduce slots only.")
            continue
        skill = by_slug.get(slug)
        if skill is None:
            c.add("template-block", where, "The block names skill %s, which is not in this file." % _show(ref))
            continue
        slugs.append(slug)
        step_range = ref.get("steps")
        if step_range is None:
            continue
        count = len(dict_items(skill.get("steps")))
        if not (isinstance(step_range, list) and len(step_range) == 2 and all(is_int(v) for v in step_range)
                and 1 <= step_range[0] <= step_range[1]):
            c.add("step-range", where, "%s steps %s must be [first, last] with 1 ≤ first ≤ last." % (slug, _show(step_range)))
        elif not count:
            c.add("step-range", where, "%s has no steps in this stage, so its step range %s is not recorded."
                  % (slug, _show(step_range)), WARNING)
        elif step_range[1] > count:
            c.add("step-range", where, "%s steps %s go past its last step %d." % (slug, _show(step_range), count))
    if kind == "wrapUp" and is_int(lesson_n):
        if lesson_n == 8 and slugs:
            c.add("template-block", where, "Lesson 8's wrap-up is the group game, with no skill.", WARNING)
        if lesson_n < 8 and slugs != [stage.get("wrapUpSkill")]:
            c.add("template-block", where, "The wrap-up of lessons 1–7 is the stage's wrap-up skill %s; this one has %s."
                  % (_show(stage.get("wrapUpSkill")), _show(slugs)), WARNING)
    names = block.get("activities", [])
    if not is_str_list(names):
        c.add("template-block", where, "activities must be a list of activity names as printed.")
        names = []
    candidates = name_candidates(work, slugs, kind)
    elsewhere = []
    for activity_name in names:
        if match_name(activity_name, candidates):
            continue
        if kind == "warmUp" and not slugs:
            elsewhere.append(activity_name)
        else:
            c.add("template-activity", where, "%r is not the name of an activity in this stage's library."
                  % activity_name)
    if elsewhere:
        one = len(elsewhere) == 1
        c.add("template-activity", where, "%s %s not in this stage's library; the assembler looks for %s in the "
                                          "other stages." % (", ".join(repr(n) for n in elsewhere),
                                                             "is" if one else "are", "it" if one else "them"), WARNING)
    topic = block.get("topicCode")
    if kind == "topic" and topic not in topic_codes:
        c.add("template-block", where, "The topic block's topicCode %s is not one of the file's topics." % _show(topic))
    if "notes" in block and not is_str_list(block["notes"]):
        c.add("template-block", where, "notes must be a list of strings.")
    if "depths" in block:
        c.depths(block["depths"], where)
    if "equipment" in block:
        c.requirement_groups(block["equipment"], where)


# ---------------------------------------------------------------------------
# assemble

JUDGMENT_FIELDS = ("ages", "equipment", "equipmentOptional", "depths", "headfirst", "reachBottom",
                   "flotationOption", "submerges", "tags")


class AssembleResult:
    """What `assemble` did: problems (errors stop the write), report notes, the stages
    assembled and skipped, and the files written (paths relative to the output dir)."""

    def __init__(self):
        self.problems = []
        self.notes = []
        self.stages = []
        self.skipped = []
        self.written = []
        self.files = {}

    @property
    def ok(self):
        return not C.errors(self.problems)


class _Variant:
    def __init__(self, activity_id, slug, key, stage_id, owner, entry):
        self.id = activity_id
        self.slug = slug
        self.key = key
        self.stage = stage_id
        self.owner = owner
        self.entry = entry
        self.skill_ids = []
        self.explicit = None
        self.explicit_from = None
        self.dive_split = False
        self.first_of_slug = True


def _judgment(entry):
    """The judgment fields in a comparable form (flags false when absent)."""
    return {
        "ages": sorted(entry.get("ages") or [], key=lambda a: ids.AGE_TAGS.index(a) if a in ids.AGE_TAGS else 9),
        "equipment": sorted(sorted(group) for group in entry.get("equipment") or [] if isinstance(group, list)),
        "equipmentOptional": sorted(entry.get("equipmentOptional") or []),
        "depths": sorted(entry.get("depths") or []),
        "headfirst": entry.get("headfirst") is True,
        "reachBottom": entry.get("reachBottom") is True,
        "flotationOption": entry.get("flotationOption") is True,
        "submerges": entry.get("submerges") is True,
        "tags": sorted(set(entry.get("tags") or [])),
    }


def _zones(depths):
    return [zone for zone in ids.ZONES if zone in depths]


def _owner_label(stage_id, owner, works):
    if owner == GREETING:
        return "Stage %s's Greeting" % stage_id
    for skill in dict_items(works[stage_id].get("skills")):
        if skill.get("slug") == owner:
            return "Stage %s's %s page" % (stage_id, skill.get("name"))
    return "Stage %s's %s page" % (stage_id, owner)


def _final_activity(variant):
    entry = variant.entry
    out = {
        "id": variant.id,
        "name": entry.get("name", "").strip(),
        "description": entry.get("description", "").strip(),
        "ages": [a for a in ids.AGE_TAGS if a in (entry.get("ages") or [])],
        "equipment": entry.get("equipment") or [],
        "equipmentOptional": entry.get("equipmentOptional") or [],
        "submerges": entry.get("submerges") is True,
        "tags": sorted(set(entry.get("tags") or [])),
        "skillIds": list(variant.skill_ids),
        "source": "ymca",
    }
    if entry.get("depths"):
        out["depths"] = _zones(entry["depths"])
    for flag in ("headfirst", "reachBottom", "flotationOption"):
        if entry.get(flag) is True:
            out[flag] = True
    return out


# The order activity ids are assigned in: the order the owner teaches, so the stages taught first
# keep plain ids and a later stage's differing entry takes the suffix (DECISIONS_LOG 2026-09-10).
ID_ORDER = ("1", "2", "3", "4", "5", "6", "A", "B")


def _build_activities(works, reserved, result):
    """Dedupe in ID_ORDER (stages 1–6, then A and B; each library's Greeting, then its skills'
    pages). Same slug + same normalized description = one activity with merged skillIds;
    same slug with another description = a separate activity whose id takes the suffix
    -<first stage of that description>. A Variation that turns a jump into a dive is its own
    activity even where the library prints one description for both (CURRICULUM_FORMAT.md
    §5 step 3), so headfirst is part of the key and such a split takes the suffix -dive. An
    entry's idSuffix or variant ("back", "dive") names the suffix instead, on whichever
    occurrence it appears, so ids are assigned after grouping. Returns (variants in library
    order, placement {(stage, owner, index): activity id})."""
    registry, ordered, occurrences = {}, [], []
    for stage_id, work in sorted(works.items(), key=lambda item: ID_ORDER.index(item[0])):
        for owner, index, entry in activity_entries(work):
            slug = ids.slug(entry.get("name"))
            key = (ids.description_key(entry.get("description")), entry.get("headfirst") is True)
            explicit = entry.get("idSuffix") or entry.get("variant")
            variants = registry.setdefault(slug, [])
            match = next((v for v in variants if v.key == key), None)
            if match is None:
                match = _Variant(None, slug, key, stage_id, owner, entry)
                match.dive_split = key[1] and any(v.key[0] == key[0] for v in variants)
                match.first_of_slug = not variants
                variants.append(match)
                ordered.append(match)
            else:
                first, here = _judgment(match.entry), _judgment(entry)
                differing = [field for field in JUDGMENT_FIELDS if first[field] != here[field]]
                if differing:
                    result.problems.append(problem(
                        "activity-variant", "activity %s" % slug,
                        "%r has the same description on %s and %s but different %s; the first is kept — check both "
                        "pages." % (entry.get("name"), _owner_label(match.stage, match.owner, works),
                                    _owner_label(stage_id, owner, works), ", ".join(differing)), WARNING))
            if explicit:
                if match.explicit is None:
                    match.explicit, match.explicit_from = explicit, (stage_id, owner)
                elif ids.slug(str(explicit)) != ids.slug(str(match.explicit)):
                    result.problems.append(problem(
                        "activity-variant", "activity %s" % slug,
                        "%s marks %r as %r, but %s marks the same entry %r; %r is used."
                        % (_owner_label(match.explicit_from[0], match.explicit_from[1], works), entry.get("name"),
                           match.explicit, _owner_label(stage_id, owner, works), explicit, match.explicit), WARNING))
            if owner != GREETING:
                skill_id = ids.skill_id(stage_id, owner)
                if skill_id not in match.skill_ids:
                    match.skill_ids.append(skill_id)
            occurrences.append(((stage_id, owner, index), match))
    assigned = set()
    for variant in ordered:
        name = variant.entry.get("name")
        if variant.explicit:
            candidate = ids.activity_id(name, variant.explicit)
        elif variant.first_of_slug:
            candidate = variant.slug
        elif variant.dive_split:
            candidate = "%s-dive" % variant.slug
        else:
            candidate = "%s-%s" % (variant.slug, variant.stage.lower())
        stage_suffix = "-%s" % variant.stage.lower()
        fallbacks = [] if candidate.endswith(stage_suffix) else [candidate + stage_suffix]
        fallbacks += ["%s-%s" % (candidate, variant.owner)] + ["%s-%d" % (candidate, k) for k in range(2, 100)]
        activity_id = candidate
        while activity_id in assigned or activity_id in reserved:
            activity_id = fallbacks.pop(0)
        where = _owner_label(variant.stage, variant.owner, works)
        if activity_id != candidate:
            result.problems.append(problem(
                "activity-id", "activity %s" % activity_id,
                "The id %s was taken, so %r on %s is %s." % (candidate, name, where, activity_id), WARNING))
        variant.id = activity_id
        assigned.add(activity_id)
        if not variant.first_of_slug:
            reason = "the dive split of the same description" if variant.dive_split else "its own description"
            result.notes.append("Activity %r on %s is a separate activity (%s): id %s (first: %s)."
                                % (name, where, reason, activity_id, registry[variant.slug][0].id))
    placement = {where: variant.id for where, variant in occurrences}
    merged = sum(1 for v in ordered if len(v.skill_ids) > 1)
    result.notes.append("Activities: %d library entries -> %d activities (%d shared by more than one skill)."
                        % (len(placement), len(ordered), merged))
    return ordered, placement


def _resolve_ref(ref, works, where, field, result):
    """A prerequisite or advanced entry -> a step id, or None when it can't be resolved.
    An entry into a stage with no work file keeps its id; the validator warns about it."""
    if not isinstance(ref, dict):
        return None
    ref_stage, slug, n, name = ref.get("stage"), ref.get("skill"), ref.get("n"), ref.get("name")
    target = works.get(ref_stage)
    if ids.is_slug(slug) and is_int(n):
        step_id = ids.step_id(ref_stage, slug, n)
        if target is None:
            return step_id
        skill = next((s for s in dict_items(target.get("skills")) if s.get("slug") == slug), None)
        steps = dict_items(skill.get("steps")) if skill else []
        if not skill or not 1 <= n <= len(steps):
            result.problems.append(problem("link-unresolved", where, "%s %s is not a step of Stage %s's work file."
                                           % (field, step_id, ref_stage)))
            return None
        if isinstance(name, str) and ids.normalize_text(name) != ids.normalize_text(steps[n - 1].get("name")):
            result.problems.append(problem("link-name", where, "%s %s is named %r here but %r in Stage %s."
                                           % (field, step_id, name, steps[n - 1].get("name"), ref_stage), WARNING))
        return step_id
    if target is None:
        result.problems.append(problem("link-unresolved", where, "%s %s names no skill and n, and Stage %s has no work "
                                                                 "file to find it by name." % (field, _show(ref), ref_stage)))
        return None
    found = [ids.step_id(ref_stage, s.get("slug"), step.get("n"))
             for s in dict_items(target.get("skills")) for step in dict_items(s.get("steps"))
             if ids.normalize_text(step.get("name")) == ids.normalize_text(name)]
    if len(found) != 1:
        result.problems.append(problem("link-unresolved", where, "%s %s matches %d steps of Stage %s by name."
                                       % (field, _show(ref), len(found), ref_stage)))
        return None
    return found[0]


def _resolve_template_activity(name, work, stage_id, slugs, kind, works, placement, where, result):
    candidates = name_candidates(work, slugs, kind)
    matches = match_name(name, candidates)
    if matches:
        chosen = placement[(stage_id, matches[0][0], matches[0][1])]
        own = {placement[(stage_id, owner, index)] for owner, index, _e in matches if owner in slugs}
        if len(own) > 1:
            result.problems.append(problem("template-activity", where, "%r matches %s on the block's skills' pages; "
                                                                       "%s was used." % (name, ", ".join(sorted(own)), chosen),
                                           WARNING))
        return chosen
    if kind == "warmUp" and not slugs:
        for other_id, other in works.items():
            if other_id == stage_id:
                continue
            found = match_name(name, activity_entries(other))
            if found:
                return placement[(other_id, found[0][0], found[0][1])]
    result.problems.append(problem("template-activity", where, "%r is not an activity of Stage %s%s."
                                   % (name, stage_id, " or of any assembled stage" if kind == "warmUp" and not slugs else "")))
    return None


def _final_block(block, work, stage_id, lesson_n, works, placement, result):
    kind = block.get("kind")
    where = "stage %s / lesson template %s / %s" % (stage_id, lesson_n, kind)
    out = {"kind": kind, "minutes": block.get("minutes")}
    skills = {s.get("slug"): s for s in dict_items(work.get("skills"))}
    skill_ids, slugs, ranges = [], [], []
    for ref in dict_items(block.get("skills")):
        slug = ref.get("slug")
        if slug == ids.ANY_SKILL:
            skill_ids.append(ids.ANY_SKILL)
            continue
        skill_ids.append(ids.skill_id(stage_id, slug))
        slugs.append(slug)
        count = len(dict_items(skills.get(slug, {}).get("steps")))
        if isinstance(ref.get("steps"), list) and count:
            ranges.append((slug, ref["steps"], count))
    if skill_ids:
        out["skillIds"] = skill_ids
    if ranges:
        first = min(r[1][0] for r in ranges)
        last = max(r[1][1] for r in ranges)
        out["stepRange"] = [first, last]
        if any(r[1] != [first, min(last, r[2])] for r in ranges):
            result.problems.append(problem(
                "step-range-merged", where,
                "The block's skills have different step ranges (%s); a block has one stepRange, recorded as [%d, %d]."
                % (", ".join("%s %s" % (r[0], r[1]) for r in ranges), first, last), WARNING))
    activity_ids = []
    for name in block.get("activities") or []:
        activity_id = _resolve_template_activity(name, work, stage_id, slugs, kind, works, placement, where, result)
        if activity_id and activity_id not in activity_ids:
            activity_ids.append(activity_id)
    if activity_ids:
        out["activityIds"] = activity_ids
    if block.get("topicCode") is not None:
        out["topicCode"] = block["topicCode"]
    if block.get("notes"):
        out["notes"] = list(block["notes"])
    if block.get("depths"):
        out["depths"] = _zones(block["depths"])
    if block.get("equipment"):
        out["equipment"] = block["equipment"]
    return out


def _final_step(stage_id, slug, step):
    out = {"id": ids.step_id(stage_id, slug, step["n"]), "n": step["n"],
           "name": PRESCHOOL_NOTE_RE.sub("", step.get("name", "")).strip(),
           "description": step.get("description", "").strip()}
    if isinstance(step.get("measure"), dict):
        out["measure"] = dict(step["measure"])
    if step.get("depths"):
        out["depths"] = _zones(step["depths"])
    for flag in C.STEP_FLAGS:
        if step.get(flag) is True:
            out[flag] = True
    if step.get("equipment"):
        out["equipment"] = step["equipment"]
    return out


def _build_stage(stage_id, work, works, placement, result):
    info = work["stage"]
    skills = []
    for skill in dict_items(work.get("skills")):
        slug = skill["slug"]
        where = "stage %s / skill %s" % (stage_id, ids.skill_id(stage_id, slug))
        steps = [_final_step(stage_id, slug, step) for step in dict_items(skill.get("steps"))]
        links = {}
        for field, key in (("prerequisite", "prerequisiteStepIds"), ("advanced", "advancedStepIds")):
            resolved = [_resolve_ref(ref, works, where, field, result) for ref in skill.get(field) or []]
            links[key] = [r for r in resolved if r]
        activity_ids = []
        for index, _entry in enumerate(dict_items(skill.get("activities"))):
            activity_id = placement[(stage_id, slug, index)]
            if activity_id not in activity_ids:
                activity_ids.append(activity_id)
        skills.append({
            "id": ids.skill_id(stage_id, slug), "name": skill.get("name", "").strip(), "order": skill.get("order"),
            "isBenchmarkSequence": skill.get("isBenchmarkSequence") is True,
            "prerequisiteStepIds": links["prerequisiteStepIds"], "steps": steps,
            "benchmarkStepId": steps[-1]["id"] if steps else None,
            "advancedStepIds": links["advancedStepIds"], "activityIds": activity_ids, "videoIds": [],
        })
    greeting = []
    for index, _entry in enumerate(dict_items((work.get("greeting") or {}).get("activities"))):
        activity_id = placement[(stage_id, GREETING, index)]
        if activity_id not in greeting:
            greeting.append(activity_id)
    rows = [{"text": row_text(row),
             "stepIds": [ids.step_id(stage_id, ref["skill"], ref["n"]) for ref in dict_items(row.get("steps"))],
             "rule": row.get("rule")} for row in dict_items(work.get("trackerRows"))]
    topics = [{"code": t.get("code"), "n": t.get("n"), "name": t.get("name", "").strip(),
               "summary": t.get("summary", ""), "prompts": list(t.get("prompts") or []),
               "notes": list(t.get("notes") or [])}
              for t in sorted(dict_items(work.get("topics")), key=lambda t: t.get("n"))]
    templates = []
    for template in sorted(dict_items(work.get("lessonTemplates")), key=lambda t: t.get("n")):
        blocks = [_final_block(block, work, stage_id, template.get("n"), works, placement, result)
                  for block in dict_items(template.get("blocks"))]
        templates.append({"n": template.get("n"), "minutes": template.get("minutesTotal"), "blocks": blocks})
    return {
        "id": stage_id, "name": info.get("name"), "group": info.get("group"), "ageGroups": list(info.get("ageGroups")),
        "lessonMinutes": info.get("lessonMinutes"),
        "warmUpSkill": ids.skill_id(stage_id, info.get("warmUpSkill")),
        "wrapUpSkill": ids.skill_id(stage_id, info.get("wrapUpSkill")),
        "milestones": list(info.get("milestones") or []), "greetingActivityIds": greeting,
        "trackerRows": rows, "skills": skills, "topics": topics, "lessonTemplates": templates,
    }


# videos ------------------------------------------------------------------------

def parse_video_title(title):
    """'Wall Grab & Monkey Crawl (Stages A & B)' -> (['A', 'B'], ['Wall Grab', 'Monkey Crawl']);
    'Water Exit demo video' -> (['1', '2', '3'], ['Water Exit']);
    'Submerge demo video' -> (['1'], ['Submerge', 'Open Eyes Under water'])."""
    rest = re.sub(r"-HD$", "", (title or "").strip())
    stages = []
    match = re.search(r"\(\s*Stages?\s+([^)]*)\)", rest)
    if match:
        rest = (rest[:match.start()] + rest[match.end():]).strip()
        for token in re.split(r"\s*(?:&|,|\band\b)\s*", match.group(1)):
            token = token.strip()
            span = re.match(r"^([AB1-6])\s*[-–]\s*([AB1-6])$", token)
            if span:
                low, high = ids.STAGE_INDEX[span.group(1)], ids.STAGE_INDEX[span.group(2)]
                stages.extend(ids.STAGE_IDS[low:high + 1])
            elif token in ids.STAGE_INDEX:
                stages.append(token)
    level = re.search(r"\bL([1-6])\b", rest)
    if level:
        stages.append(level.group(1))
        rest = (rest[:level.start()] + rest[level.end():]).strip()
    names = [part.strip() for part in re.split(r"\s+(?:&|and)\s+", rest) if part.strip()]
    unique = []
    for stage in stages:
        if stage not in unique:
            unique.append(stage)
    return sorted(unique, key=ids.stage_sort_key), names


def _match_video_skills(stages, names, works):
    found = []
    for stage_id in stages:
        work = works.get(stage_id)
        if not work:
            continue
        skills = dict_items(work.get("skills"))
        for name in names:
            key = ids.slug(name)
            exact = [s for s in skills if s.get("slug") == key]
            prefixed = [s for s in skills if isinstance(s.get("slug"), str) and s["slug"].startswith(key + "-")]
            chosen = exact or [s for s in prefixed if dict_items(s.get("steps"))] or prefixed
            for skill in chosen:
                skill_id = ids.skill_id(stage_id, skill["slug"])
                if skill_id not in found:
                    found.append(skill_id)
    return found


def _build_videos(videos_path, works, result):
    source = C.read_json(videos_path, result.problems, Path(videos_path).name, required=False)
    if source is None:
        result.problems.append(problem("videos-missing", str(videos_path),
                                       "The video list %s is missing, so videos.json is empty." % videos_path, WARNING))
        return []
    entries = source.get("videos") if isinstance(source, dict) else source
    videos, seen, skipped, unmatched = [], {}, 0, []
    for entry in dict_items(entries):
        if entry.get("page") not in VIDEO_PAGES:
            skipped += 1
            continue
        title = entry.get("title", "")
        number = ids.vimeo_id_from_url(entry.get("url")) or str(entry.get("videoId", ""))
        video_id = ids.video_id(number)
        if video_id in seen:
            result.notes.append("Video %r (%s) is the same Vimeo video as %r; listed once."
                                % (title, entry.get("page"), seen[video_id]))
            continue
        seen[video_id] = title
        stages, names = parse_video_title(title)
        skill_ids = _match_video_skills(stages, names, works)
        if not skill_ids:
            unmatched.append(title)
        videos.append({"id": video_id, "title": title, "url": entry.get("url"),
                       "stageIds": stages, "skillIds": skill_ids})
    if skipped:
        result.notes.append("Videos: %d %s from other Yapp pages (not %s) left out."
                            % (skipped, "entry" if skipped == 1 else "entries", " or ".join(VIDEO_PAGES)))
    if unmatched:
        result.notes.append("Videos with no skill matched by title: %s." % "; ".join(unmatched))
    return videos


# the whole assembly ----------------------------------------------------------------

def assemble(work_dir, out_dir, equipment_path=DEFAULT_EQUIPMENT, safety_path=None,
             videos_path=DEFAULT_VIDEOS, version=DEFAULT_VERSION, write=True):
    """Read every work file in `work_dir`, build the curriculum files, validate them, and
    (when there is no error and `write` is true) write them under `out_dir`."""
    result = AssembleResult()
    work_dir, out_dir = Path(work_dir), Path(out_dir)
    catalog = load_catalog(equipment_path, result.problems)
    safety_path = Path(safety_path) if safety_path else work_dir / SAFETY_FILE
    safety = C.read_json(safety_path, result.problems, safety_path.name)
    if not isinstance(safety, list):
        if safety is not None:
            result.problems.append(problem("file-unreadable", Path(safety_path).name, "The safety rules are not a list."))
        safety = []
    works = {}
    for stage_id in ids.STAGE_IDS:
        path = work_dir / work_file_name(stage_id)
        if not path.exists():
            result.skipped.append(stage_id)
            result.problems.append(problem("stage-skipped", work_file_name(stage_id),
                                           "Stage %s is skipped: there is no %s." % (stage_id, work_file_name(stage_id)),
                                           WARNING))
            continue
        work, found = check_work_file(path, catalog)
        result.problems.extend(found)
        if work is None or C.errors(found):
            continue
        if work["stage"]["id"] != stage_id:
            result.problems.append(problem("work-shape", path.name, "%s holds Stage %s, not Stage %s."
                                           % (path.name, work["stage"]["id"], stage_id)))
            continue
        works[stage_id] = work
    if not result.ok:
        return result
    if not works:
        result.problems.append(problem("no-stages", str(work_dir), "There are no work files in %s." % work_dir))
        return result
    if (out_dir / "stages").is_dir():
        for stage_id in result.skipped:
            if (out_dir / C.STAGE_FILES[stage_id]).exists():
                result.problems.append(problem(
                    "stale-stage", C.STAGE_FILES[stage_id],
                    "%s is left from an earlier assembly; Stage %s has no work file now, so it was not rewritten and "
                    "may not match the new activities.json." % (C.STAGE_FILES[stage_id], stage_id), WARNING))

    reserved = {e.get("id") for e in dict_items(catalog)} | {r.get("id") for r in dict_items(safety)}
    variants, placement = _build_activities(works, reserved, result)
    stages = {stage_id: _build_stage(stage_id, work, works, placement, result) for stage_id, work in works.items()}
    videos = _build_videos(videos_path, works, result)
    for stage in stages.values():
        for skill in stage["skills"]:
            skill["videoIds"] = [v["id"] for v in videos if skill["id"] in v["skillIds"]]
    activities = [_final_activity(v) for v in variants]
    version_file = {"format": C.CURRICULUM_FORMAT_ID, "version": version, "source": VERSION_SOURCE}

    files = {C.STAGE_FILES[stage_id]: stage for stage_id, stage in stages.items()}
    files.update({"activities.json": activities, "equipment.json": catalog, "videos.json": videos,
                  "version.json": version_file, "safety.json": safety})
    result.files = {path: dumps(value) for path, value in files.items()}
    result.stages = list(stages)

    # validate what would be written, with the owner's local.json when there is one
    built = C.Curriculum(out_dir, "dir")
    built.version, built.stages = version, [json.loads(result.files[C.STAGE_FILES[s]]) for s in stages]
    built.activities, built.equipment = json.loads(result.files["activities.json"]), list(catalog)
    built.safety, built.videos = list(safety), videos
    local = C.read_json(out_dir / "local.json", result.problems, "local.json", required=False)
    if isinstance(local, dict):
        built.local = local
        built.activities += dict_items(local.get("activities"))
        built.equipment += dict_items(local.get("equipment"))
    C._enrich(built)
    result.problems.extend(C.validate(built))
    if not result.ok or not write:
        return result
    for path in sorted(result.files):
        write_text_atomic(out_dir / path, result.files[path])
        result.written.append(path)
    return result
