"""Curriculum: load and validate (CURRICULUM_FORMAT.md §3, §5; TEST_CASES A1–A14).

`load(path)` reads a curriculum directory (curriculum/: version.json, stages/<S>.json,
activities.json, equipment.json, safety.json, videos.json, local.json) or a single-file
compact sample (examples/curriculum.stage1.sample.json) into a `Curriculum` of plain
JSON-shaped dicts. Loading never raises: a missing or corrupt file becomes a problem in
`Curriculum.load_problems` and the rest still loads (A10).

`validate(curriculum)` returns a list of `Problem(code, severity, where, message)` —
the load problems first, then every check of CURRICULUM_FORMAT.md §5. It never raises
on bad data. A curriculum with any error must not be planned on (`can_plan`).
"""

import json
from collections import namedtuple
from pathlib import Path

from . import ids

ERROR = "error"
WARNING = "warning"

CURRICULUM_FORMAT_ID = "curriculum/1"
LOCAL_FORMAT = "local/1"
PLACEHOLDER = "TODO-M1"
UNREADABLE = "UNREADABLE"
SINGLE_INHALATION_ID = "single-inhalation"

STEP_FLAGS = ("headfirst", "reachBottom", "nearWall", "submerges")
ACTIVITY_FLAGS = ("headfirst", "reachBottom", "flotationOption", "submerges")
MEASURE_KINDS = ("distance", "time", "count")
MEASURE_UNITS = {"distance": ("ft", "yd"), "time": ("s", "min")}
TOPICS_PER_STAGE = 8
TEMPLATES_PER_STAGE = 8
MIN_SKILLS_PER_STAGE = 8

STAGE_FILES = {stage: "stages/%s.json" % stage for stage in ids.STAGE_IDS}


class Problem(namedtuple("Problem", "code severity where message")):
    """One validation finding. `message` is a plain sentence."""

    __slots__ = ()

    def __str__(self):
        return "%s [%s] %s: %s" % (self.severity, self.code, self.where, self.message)

    def to_dict(self):
        return {"code": self.code, "severity": self.severity, "where": self.where,
                "message": self.message}


def problem(code, where, message, severity=ERROR):
    return Problem(code, severity, where, message)


def errors(problems):
    return [p for p in problems if p.severity == ERROR]


def warnings(problems):
    return [p for p in problems if p.severity == WARNING]


def can_plan(problems):
    """The planner refuses to run on a curriculum with any error (SPEC §6.1, A10)."""
    return not errors(problems)


# ---------------------------------------------------------------------------
# small type helpers (the validator never assumes a shape)

def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def is_str_list(value):
    return isinstance(value, list) and all(isinstance(item, str) for item in value)


def dict_items(value):
    """The dict entries of a list, or [] when it is not a list."""
    return [item for item in value if isinstance(item, dict)] if isinstance(value, list) else []


def text(value):
    return value if isinstance(value, str) else ""


# ---------------------------------------------------------------------------
# the curriculum

class Curriculum:
    """What `load` returns. Attributes are plain JSON-shaped values:

    version     str or None (version.json's version, or a compact sample's top-level one)
    stages      [Stage dict] in stage order (A, B, 1–6), only the stages that loaded
    activities  [Activity dict], activities.json's entries then local.json's
    equipment   [Equipment dict], equipment.json's entries then local.json's (catalog order)
    safety      [SafetyRule dict]
    videos      [Video dict]
    local       local.json's object, or None (no local.json, or a compact sample)
    source      the path loaded; kind "dir" or "sample"
    load_problems  problems found while reading files

    The loader gives each Skill its `stageId` and `stepIds`, each Step its `skillId`,
    each Topic and LessonTemplate its `stageId` (CURRICULUM_FORMAT.md §3).
    """

    def __init__(self, source="", kind="dir"):
        self.source = str(source)
        self.kind = kind
        self.version = None
        self.stages = []
        self.activities = []
        self.equipment = []
        self.safety = []
        self.videos = []
        self.local = None
        self.load_problems = []
        self.reindex()

    def reindex(self):
        self._stages = {}
        self._skills = {}
        self._steps = {}
        self._topics = {}
        for stage in self.stages:
            if not isinstance(stage, dict):
                continue
            self._stages.setdefault(stage.get("id"), stage)
            for skill in dict_items(stage.get("skills")):
                if isinstance(skill.get("id"), str):
                    self._skills.setdefault(skill["id"], skill)
                for step in dict_items(skill.get("steps")):
                    if isinstance(step.get("id"), str):
                        self._steps.setdefault(step["id"], step)
            for topic in dict_items(stage.get("topics")):
                if isinstance(topic.get("code"), str):
                    self._topics.setdefault(topic["code"], topic)
        self._activities = {}
        for activity in dict_items(self.activities):
            if isinstance(activity.get("id"), str):
                self._activities.setdefault(activity["id"], activity)
        self._equipment = {}
        for entry in dict_items(self.equipment):
            if isinstance(entry.get("id"), str):
                self._equipment.setdefault(entry["id"], entry)
        self._videos = {}
        for video in dict_items(self.videos):
            if isinstance(video.get("id"), str):
                self._videos.setdefault(video["id"], video)

    # lookups
    def stage(self, stage_id):
        return self._stages.get(stage_id)

    def skill(self, skill_id):
        return self._skills.get(skill_id)

    def step(self, step_id):
        return self._steps.get(step_id)

    def topic(self, code):
        return self._topics.get(code)

    def activity(self, activity_id):
        return self._activities.get(activity_id)

    def equipment_entry(self, equipment_id):
        return self._equipment.get(equipment_id)

    def video(self, video_id):
        return self._videos.get(video_id)

    @property
    def loaded_stage_ids(self):
        return [stage["id"] for stage in self.stages
                if isinstance(stage, dict) and stage.get("id") in ids.STAGE_INDEX]

    def is_loaded(self, stage_id):
        return stage_id in self._stages

    def skills_of(self, stage_id):
        stage = self.stage(stage_id)
        return dict_items(stage.get("skills")) if stage else []


# ---------------------------------------------------------------------------
# loading

def load(path, local_path=None):
    """Load a curriculum directory or a single-file compact sample. Never raises."""
    path = Path(path)
    try:
        if path.is_file():
            return _load_sample(path)
        return _load_dir(path, local_path)
    except Exception as exc:  # a loader bug must still give a readable result (A10)
        curriculum = Curriculum(path, "dir")
        curriculum.load_problems.append(problem(
            "file-unreadable", str(path),
            "The curriculum could not be read (%s: %s)." % (type(exc).__name__, exc)))
        return curriculum


def read_json(path, problems, where, required=True):
    """Read one JSON file. A missing or corrupt file adds a problem and returns None."""
    path = Path(path)
    if not path.exists():
        if required:
            problems.append(problem("file-missing", where, "%s is missing." % where))
        return None
    try:
        raw = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        problems.append(problem("file-unreadable", where,
                                "%s could not be read (%s)." % (where, exc)))
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        problems.append(problem(
            "file-unreadable", where,
            "%s is not valid JSON (line %d, column %d: %s)." % (where, exc.lineno, exc.colno, exc.msg)))
        return None


def _load_dir(root, local_path=None):
    curriculum = Curriculum(root, "dir")
    found = curriculum.load_problems
    if not root.is_dir():
        found.append(problem("file-missing", str(root),
                             "The curriculum directory %s does not exist." % root))
        return curriculum

    version = read_json(root / "version.json", found, "version.json")
    if isinstance(version, dict):
        curriculum.version = version.get("version")
        if version.get("format") != CURRICULUM_FORMAT_ID:
            found.append(problem("version-invalid", "version.json",
                                 "version.json has format %r; it should be %r."
                                 % (version.get("format"), CURRICULUM_FORMAT_ID)))
        if not isinstance(version.get("version"), str) or not version.get("version"):
            found.append(problem("version-invalid", "version.json",
                                 "version.json has no version string."))
    elif version is not None:
        found.append(problem("version-invalid", "version.json", "version.json is not a JSON object."))

    for stage_id in ids.STAGE_IDS:
        where = STAGE_FILES[stage_id]
        if not (root / where).exists():
            found.append(problem("stage-not-loaded", where,
                                 "Stage %s is not loaded: %s is missing." % (stage_id, where), WARNING))
            continue
        data = read_json(root / where, found, where)
        if data is None:
            continue
        if not isinstance(data, dict):
            found.append(problem("stage-file-invalid", where,
                                 "%s is not a JSON object, so Stage %s is not loaded." % (where, stage_id)))
            continue
        if data.get("id") != stage_id:
            found.append(problem("stage-file-invalid", where,
                                 "%s has id %r, not %r, so Stage %s is not loaded."
                                 % (where, data.get("id"), stage_id, stage_id)))
            continue
        curriculum.stages.append(data)
    stages_dir = root / "stages"
    if stages_dir.is_dir():
        for extra in sorted(stages_dir.glob("*.json")):
            if extra.stem not in ids.STAGE_INDEX:
                found.append(problem("stage-file-invalid", "stages/%s" % extra.name,
                                     "stages/%s is not a stage file (stages are A, B and 1–6) and was ignored."
                                     % extra.name, WARNING))

    for name, attribute, required in (("activities.json", "activities", True),
                                      ("equipment.json", "equipment", True),
                                      ("safety.json", "safety", True),
                                      ("videos.json", "videos", False)):
        data = read_json(root / name, found, name, required)
        if data is None:
            if not required:
                found.append(problem("file-missing", name,
                                     "%s is missing, so no skill has a video." % name, WARNING))
            continue
        if not isinstance(data, list):
            found.append(problem("file-unreadable", name, "%s is not a JSON list." % name))
            continue
        setattr(curriculum, attribute, data)

    local_file = Path(local_path) if local_path else root / "local.json"
    local = read_json(local_file, found, "local.json", required=False)
    if local is None and not local_file.exists():
        found.append(problem("local-missing", "local.json",
                             "local.json is missing, so there are no local additions.", WARNING))
    curriculum.local = local
    if isinstance(local, dict):
        # merged after the YMCA entries: the catalog lists local items last (PLANNER.md §7.1)
        curriculum.activities = list(curriculum.activities) + dict_items(local.get("activities"))
        curriculum.equipment = list(curriculum.equipment) + dict_items(local.get("equipment"))

    if not curriculum.stages:
        found.append(problem("no-stages", "stages/", "No stage loaded: stages/ holds no readable stage file."))
    _enrich(curriculum)
    return curriculum


def _load_sample(path):
    """The compact single-stage form (CURRICULUM_FORMAT.md §3, last paragraphs): `stage`
    holds the Stage's own fields and the top level its skills, greetingActivityIds,
    topics, lessonTemplates (and trackerRows once M1 fills them) beside activities,
    equipment and safety; `version` stands in for version.json's. Read with no local
    additions (PLANNER.md §13)."""
    curriculum = Curriculum(path, "sample")
    found = curriculum.load_problems
    where = path.name
    data = read_json(path, found, where)
    if data is None:
        return curriculum
    if not isinstance(data, dict) or not isinstance(data.get("stage"), dict):
        found.append(problem("sample-invalid", where,
                             "%s is not a compact curriculum sample: it has no stage object." % where))
        return curriculum
    stage = dict(data["stage"])
    for key in ("skills", "greetingActivityIds", "topics", "lessonTemplates", "trackerRows"):
        if key in data and key not in stage:
            stage[key] = data[key]
    stage_id = stage.get("id")
    if stage_id not in ids.STAGE_INDEX:
        found.append(problem("stage-file-invalid", where,
                             "%s has stage id %r, which is not a stage (A, B, 1–6)." % (where, stage_id)))
    else:
        curriculum.stages.append(stage)
    curriculum.version = data.get("version")
    for key in ("activities", "equipment", "safety", "videos"):
        value = data.get(key, [])
        if not isinstance(value, list):
            found.append(problem("sample-invalid", where, "%s's %s is not a list." % (where, key)))
            value = []
        setattr(curriculum, key, value)
    # derived fields the sample leaves out: an activity's skillIds and source
    listed_by = {}
    for skill in dict_items(stage.get("skills")):
        for activity_id in skill.get("activityIds") or []:
            if isinstance(activity_id, str) and isinstance(skill.get("id"), str):
                listed_by.setdefault(activity_id, []).append(skill["id"])
    for activity in dict_items(curriculum.activities):
        activity.setdefault("source", "ymca")
        if "skillIds" not in activity and isinstance(activity.get("id"), str):
            activity["skillIds"] = listed_by.get(activity["id"], [])
    for skill in dict_items(stage.get("skills")):
        skill.setdefault("videoIds", [])
    _enrich(curriculum)
    return curriculum


def _enrich(curriculum):
    """Derived fields (CURRICULUM_FORMAT.md §3) and the defaults of optional lists."""
    for stage in curriculum.stages:
        stage_id = stage.get("id")
        for skill in dict_items(stage.get("skills")):
            skill["stageId"] = stage_id
            steps = dict_items(skill.get("steps"))
            skill["stepIds"] = [step["id"] for step in steps if isinstance(step.get("id"), str)]
            for step in steps:
                step["skillId"] = skill.get("id")
        for topic in dict_items(stage.get("topics")):
            topic["stageId"] = stage_id
        for template in dict_items(stage.get("lessonTemplates")):
            template["stageId"] = stage_id
    for activity in dict_items(curriculum.activities):
        activity.setdefault("equipmentOptional", [])
        activity.setdefault("tags", [])
    curriculum.reindex()


# ---------------------------------------------------------------------------
# counts (A1)

def summary(curriculum):
    stages = {}
    for stage in curriculum.stages:
        skills = dict_items(stage.get("skills"))
        stages[stage.get("id")] = {
            "name": text(stage.get("name")),
            "skills": len(skills),
            "steps": sum(len(dict_items(skill.get("steps"))) for skill in skills),
            "activityLinks": sum(len(skill.get("activityIds") or []) for skill in skills
                                 if isinstance(skill.get("activityIds"), list)),
            "greeting": len(stage.get("greetingActivityIds") or [])
            if isinstance(stage.get("greetingActivityIds"), list) else 0,
            "topics": len(dict_items(stage.get("topics"))),
            "templates": len(dict_items(stage.get("lessonTemplates"))),
            "trackerRows": len(dict_items(stage.get("trackerRows"))),
        }
    activities = dict_items(curriculum.activities)
    equipment = dict_items(curriculum.equipment)
    return {
        "version": curriculum.version,
        "loaded": curriculum.loaded_stage_ids,
        "notLoaded": [s for s in ids.STAGE_IDS if s not in curriculum.loaded_stage_ids],
        "stages": stages,
        "activities": {"ymca": sum(1 for a in activities if a.get("source") != "local"),
                       "local": sum(1 for a in activities if a.get("source") == "local")},
        "equipment": {"items": sum(1 for e in equipment if e.get("kind") == "item" and e.get("source") != "local"),
                      "groups": sum(1 for e in equipment if e.get("kind") == "group"),
                      "local": sum(1 for e in equipment if e.get("source") == "local")},
        "videos": len(dict_items(curriculum.videos)),
        "safety": len(dict_items(curriculum.safety)),
    }


def format_summary(counts):
    lines = []
    loaded = counts["loaded"]
    line = "Loaded stages: %s." % (", ".join(loaded) if loaded else "none")
    if counts["notLoaded"]:
        line += " Not loaded: %s." % ", ".join(counts["notLoaded"])
    lines.append(line)
    for stage_id in loaded:
        c = counts["stages"][stage_id]
        lines.append("Stage %s %s: %d skills, %d steps, %d activity links, %d greeting activities, "
                     "%d topics, %d lesson templates, %d tracker rows."
                     % (stage_id, c["name"], c["skills"], c["steps"], c["activityLinks"], c["greeting"],
                        c["topics"], c["templates"], c["trackerRows"]))
    groups = counts["equipment"]["groups"]
    lines.append("Activities: %d (local %d). Equipment: %d items, %d group%s (local %d). "
                 "Videos: %d. Safety rules: %d."
                 % (counts["activities"]["ymca"], counts["activities"]["local"],
                    counts["equipment"]["items"], groups, "" if groups == 1 else "s", counts["equipment"]["local"],
                    counts["videos"], counts["safety"]))
    return lines


# ---------------------------------------------------------------------------
# continuum links (D17, D25; A4, A11)

def prerequisite_of(curriculum, step_id):
    """The skills that list `step_id` in their prerequisite column."""
    return [skill["id"] for stage in curriculum.stages for skill in dict_items(stage.get("skills"))
            if isinstance(skill.get("prerequisiteStepIds"), list) and step_id in skill["prerequisiteStepIds"]]


def advanced_of(curriculum, step_id):
    """The skills that list `step_id` in their advanced column."""
    return [skill["id"] for stage in curriculum.stages for skill in dict_items(stage.get("skills"))
            if isinstance(skill.get("advancedStepIds"), list) and step_id in skill["advancedStepIds"]]


def prerequisites_satisfied(curriculum, skill_id, achieved_step_ids):
    """Whether the placement prefill may treat the skill's prerequisite column as met: the
    column is empty, or its last step — the earlier stage's benchmark — is achieved."""
    skill = curriculum.skill(skill_id)
    if not skill:
        return False
    column = [s for s in skill.get("prerequisiteStepIds") or [] if isinstance(s, str)]
    return not column or column[-1] in set(achieved_step_ids)


# ---------------------------------------------------------------------------
# validation (CURRICULUM_FORMAT.md §5; TEST_CASES A2–A14)

def validate(curriculum):
    """Every check of CURRICULUM_FORMAT.md §5. Returns the load problems followed by the
    validation problems; never raises on bad data."""
    checker = _Checker(curriculum)
    checker.guarded("equipment catalog", "equipment.json", _check_equipment)
    checker.guarded("safety rules", "safety.json", _check_safety)
    for stage in curriculum.stages:
        checker.guarded("stage", "stage %s" % stage.get("id"), _check_stage, stage)
    checker.guarded("activities", "activities.json", _check_activities)
    checker.guarded("videos", "videos.json", _check_videos)
    checker.guarded("local additions", "local.json", _check_local)
    checker.guarded("ids", "curriculum", _check_cross_ids)
    checker.guarded("placeholders", "curriculum", _check_placeholders)
    return list(curriculum.load_problems) + checker.problems


def check(path, local_path=None):
    """load + validate: (curriculum, problems)."""
    curriculum = load(path, local_path)
    return curriculum, validate(curriculum)


def _show(value, limit=70):
    try:
        shown = json.dumps(value, ensure_ascii=False)
    except (TypeError, ValueError):
        shown = repr(value)
    return shown if len(shown) <= limit else shown[:limit - 1] + "…"


class _Checker:
    def __init__(self, curriculum):
        self.cur = curriculum
        self.problems = []
        local = curriculum.local if isinstance(curriculum.local, dict) else {}
        self.local_objects = {id(entry) for key in ("activities", "equipment")
                              for entry in dict_items(local.get(key))}
        self.catalog = {}
        for entry in dict_items(curriculum.equipment):
            if isinstance(entry.get("id"), str):
                self.catalog.setdefault(entry["id"], entry)

    def add(self, code, where, message, severity=ERROR):
        self.problems.append(problem(code, where, message, severity))

    def guarded(self, label, where, function, *args):
        try:
            function(self, *args)
        except Exception as exc:  # validate() never raises on bad data
            self.add("check-failed", where,
                     "The %s check stopped early on malformed data (%s: %s); fix the problems "
                     "reported here and validate again." % (label, type(exc).__name__, exc))

    def origin(self, entry):
        return "local" if id(entry) in self.local_objects else "ymca"

    def unloaded(self, file_name):
        return any(p.where == file_name and p.code in ("file-missing", "file-unreadable")
                   for p in self.cur.load_problems)

    # shared field checks -------------------------------------------------
    def depths(self, value, where):
        if not isinstance(value, list) or not value:
            self.add("depths", where, "depths must be a non-empty list of shallow, medium and deep "
                                      "(leave it out for any zone); it is %s." % _show(value))
            return
        bad = [zone for zone in value if zone not in ids.ZONES]
        if bad:
            self.add("depths", where, "depths has %s, which is not a zone (shallow, medium, deep)." % _show(bad))
        elif len(set(value)) != len(value):
            self.add("depths", where, "depths lists a zone twice: %s." % _show(value))

    def flags(self, entry, names, where):
        for name in names:
            if name in entry and not isinstance(entry[name], bool):
                self.add("flag-type", where, "%s must be true or false; it is %s." % (name, _show(entry[name])))

    def headfirst(self, entry, where):
        if entry.get("headfirst") is True and entry.get("depths") != ["deep"]:
            self.add("headfirst-depths", where, "A headfirst entry has depths [\"deep\"]; this one has %s."
                     % _show(entry.get("depths")))

    def equipment_id(self, equipment_id, where, field):
        if self.unloaded("equipment.json"):
            return
        if equipment_id not in self.catalog:
            self.add("equipment-unknown", where, "%s names %r, which is not in the equipment catalog "
                                                 "(equipment.json or local.json)." % (field, equipment_id))

    def requirement_groups(self, value, where, field="equipment"):
        if not isinstance(value, list):
            self.add("equipment-shape", where, "%s must be a list of requirement groups ([] = no equipment); "
                                               "it is %s." % (field, _show(value)))
            return
        for group in value:
            if not is_str_list(group) or not group:
                self.add("equipment-shape", where, "%s has %s; each requirement group is a non-empty list of "
                                                   "equipment ids." % (field, _show(group)))
                continue
            for equipment_id in group:
                self.equipment_id(equipment_id, where, field)

    def optional_equipment(self, value, where):
        if not is_str_list(value):
            self.add("equipment-shape", where, "equipmentOptional must be a list of equipment ids; it is %s."
                     % _show(value))
            return
        for equipment_id in value:
            self.equipment_id(equipment_id, where, "equipmentOptional")

    def measure(self, value, where):
        if not isinstance(value, dict):
            self.add("measure", where, "measure must be an object; it is %s." % _show(value))
            return
        kind, amount, unit = value.get("kind"), value.get("value"), value.get("unit")
        if kind not in MEASURE_KINDS:
            self.add("measure", where, "measure kind %r is not distance, time or count." % (kind,))
        if not is_number(amount) or amount <= 0:
            self.add("measure", where, "measure value %s is not a positive number." % _show(amount))
        if kind in MEASURE_UNITS and unit not in MEASURE_UNITS[kind]:
            self.add("measure", where, "a %s measure's unit is %s; it is %s."
                     % (kind, " or ".join(MEASURE_UNITS[kind]), _show(unit)))
        if kind == "count" and "unit" in value and not isinstance(unit, str):
            self.add("measure", where, "a count measure's unit, when given, is a word.")
        if "preschoolValue" in value:
            preschool = value["preschoolValue"]
            if not is_number(preschool) or preschool <= 0:
                self.add("preschool-value", where, "preschoolValue %s is not a positive number." % _show(preschool))
            elif is_number(amount) and preschool >= amount:
                self.add("preschool-value", where, "preschoolValue %s is not less than the value %s; the "
                                                   "preschool variant is the shorter one." % (preschool, amount),
                         WARNING)


# equipment catalog (A13) ---------------------------------------------------

def _check_equipment(c):
    if c.unloaded("equipment.json"):
        return
    seen = {}
    for index, entry in enumerate(c.cur.equipment):
        if not isinstance(entry, dict):
            c.add("equipment-catalog", "equipment entry %d" % (index + 1), "An equipment entry is not an object.")
            continue
        equipment_id = entry.get("id")
        origin = c.origin(entry)
        where = ("local.json / equipment %s" if origin == "local" else "equipment %s") % (equipment_id,)
        if not ids.is_slug(equipment_id):
            c.add("equipment-catalog", where, "Equipment id %r is not a lower-case slug." % (equipment_id,))
        elif (equipment_id, origin) in seen:
            c.add("id-duplicate", where, "Equipment id %r appears twice in %s."
                  % (equipment_id, "local.json" if origin == "local" else "equipment.json"))
        seen[(equipment_id, origin)] = True
        if origin == "ymca" and entry.get("source") != "ymca":
            c.add("equipment-catalog", where, "equipment.json holds the toolkit's items only (source \"ymca\"); "
                                              "your own items go in local.json.")
        if not isinstance(entry.get("name"), str) or not entry.get("name").strip():
            c.add("equipment-catalog", where, "Equipment %r has no name." % (equipment_id,))
        if not is_str_list(entry.get("aliases", [])):
            c.add("equipment-catalog", where, "aliases must be a list of words.")
        kind = entry.get("kind")
        if kind == "group":
            members = entry.get("anyOf")
            if not is_str_list(members) or not members:
                c.add("equipment-catalog", where, "The group %r has no anyOf list of items." % (equipment_id,))
                continue
            for member in members:
                target = c.catalog.get(member)
                if target is None:
                    c.add("equipment-catalog", where, "The group %r lists %r, which is not in the catalog."
                          % (equipment_id, member))
                elif target.get("kind") != "item":
                    c.add("equipment-catalog", where, "The group %r lists %r, which is not an item; a group's "
                                                      "anyOf names items only." % (equipment_id, member))
        elif kind == "item":
            if entry.get("anyOf"):
                c.add("equipment-catalog", where, "The item %r has anyOf; anyOf is on groups only." % (equipment_id,))
        else:
            c.add("equipment-catalog", where, "Equipment %r has kind %r; it must be \"item\" or \"group\"."
                  % (equipment_id, kind))


# safety rules (A14) --------------------------------------------------------

def _check_safety(c):
    if c.unloaded("safety.json") or (c.cur.kind == "sample" and not c.cur.safety):
        if c.cur.kind == "sample" and not c.cur.safety:
            c.add("safety", "safety", "The sample has no safety rules; it needs single-inhalation.")
        return
    seen = set()
    for index, rule in enumerate(c.cur.safety):
        where = "safety rule %d" % (index + 1)
        if not isinstance(rule, dict):
            c.add("safety", where, "A safety rule is not an object { id, text, tags[] }.")
            continue
        rule_id = rule.get("id")
        if isinstance(rule_id, str) and rule_id:
            where = "safety %s" % rule_id
            if rule_id in seen:
                c.add("id-duplicate", where, "Safety rule id %r appears twice." % rule_id)
            seen.add(rule_id)
        else:
            c.add("safety", where, "A safety rule has no id.")
        if not isinstance(rule.get("text"), str) or not rule.get("text").strip():
            c.add("safety", where, "The safety rule %r has no text." % (rule_id,))
        if not is_str_list(rule.get("tags")):
            c.add("safety", where, "The safety rule %r needs tags, a list of words ([] for none)." % (rule_id,))
    single = [rule for rule in dict_items(c.cur.safety) if rule.get("id") == SINGLE_INHALATION_ID]
    if not single:
        c.add("safety", "safety", "There is no single-inhalation rule; the plan prints it whenever a placed "
                                  "activity or step submerges.")
        return
    if single[0].get("tags") != ["submerges"]:
        c.add("safety", "safety %s" % SINGLE_INHALATION_ID,
              "The single-inhalation rule's tags must be [\"submerges\"]; they are %s." % _show(single[0].get("tags")))


# stages (A2–A8) --------------------------------------------------------------

def _check_stage(c, stage):
    stage_id = stage.get("id")
    where = "stage %s" % stage_id
    if not isinstance(stage.get("name"), str) or not stage.get("name").strip():
        c.add("stage-shape", where, "Stage %s has no name." % stage_id)
    if not isinstance(stage.get("group"), str) or not stage.get("group").strip():
        c.add("stage-shape", where, "Stage %s has no group." % stage_id)
    age_groups = stage.get("ageGroups")
    if not is_str_list(age_groups) or not age_groups or any(g not in ids.AGE_GROUPS for g in age_groups):
        c.add("stage-shape", where, "Stage %s's ageGroups must be a non-empty list of %s; it is %s."
              % (stage_id, ", ".join(ids.AGE_GROUPS), _show(age_groups)))
    lesson_minutes = stage.get("lessonMinutes")
    if not is_int(lesson_minutes) or lesson_minutes <= 0:
        c.add("stage-shape", where, "Stage %s's lessonMinutes must be a positive whole number." % stage_id)
        lesson_minutes = None
    if not is_str_list(stage.get("milestones", [])):
        c.add("stage-shape", where, "Stage %s's milestones must be a list of sentences." % stage_id)

    raw_skills = stage.get("skills")
    if not isinstance(raw_skills, list):
        c.add("stage-shape", where, "Stage %s has no skills list." % stage_id)
        raw_skills = []
    skills = dict_items(raw_skills)
    if len(skills) != len(raw_skills):
        c.add("stage-shape", where, "Stage %s's skills list holds something that is not a skill object." % stage_id)
    if len(skills) < MIN_SKILLS_PER_STAGE:
        c.add("skill-count", where, "Stage %s has %d skills; every stage has at least %d."
              % (stage_id, len(skills), MIN_SKILLS_PER_STAGE))
    seen_skills = set()
    step_names = {}
    orders = []
    for index, skill in enumerate(skills):
        c.guarded("skill", "%s / skill #%d" % (where, index + 1), _check_skill, stage, skill, index,
                  seen_skills, step_names)
        orders.append(skill.get("order"))
    if orders and not (all(is_int(o) for o in orders) and all(a < b for a, b in zip(orders, orders[1:]))):
        c.add("skill-shape", where, "Stage %s's skill orders are %s; they rise in library order."
              % (stage_id, _show(orders)))
    for skill in skills:
        c.guarded("links", "%s / skill %s" % (where, skill.get("id")), _check_links, stage, skill)

    for key in ("warmUpSkill", "wrapUpSkill"):
        value = stage.get(key)
        skill = c.cur.skill(value) if isinstance(value, str) else None
        if not skill or skill.get("stageId") != stage_id:
            c.add("warm-up-wrap-up", where, "Stage %s's %s %s is not a skill of Stage %s."
                  % (stage_id, key, _show(value), stage_id))

    greeting = stage.get("greetingActivityIds")
    if not is_str_list(greeting):
        c.add("stage-shape", where, "Stage %s's greetingActivityIds must be a list of activity ids." % stage_id)
    elif not c.unloaded("activities.json"):
        for activity_id in greeting:
            if not c.cur.activity(activity_id):
                c.add("activity-missing", where, "Stage %s's Greeting lists %r, which is not an activity."
                      % (stage_id, activity_id))

    c.guarded("topics", "%s / topics" % where, _check_topics, stage)
    c.guarded("lesson templates", "%s / lesson templates" % where, _check_templates, stage, lesson_minutes)
    c.guarded("tracker rows", "%s / tracker rows" % where, _check_tracker_rows, stage)


def _check_skill(c, stage, skill, index, seen_skills, step_names):
    stage_id = stage.get("id")
    skill_id = skill.get("id")
    where = "stage %s / skill %s" % (stage_id, skill_id if isinstance(skill_id, str) else "#%d" % (index + 1))
    parsed = ids.parse_skill_id(skill_id)
    skill_slug = None
    if not parsed or parsed[0] != stage_id:
        c.add("skill-shape", where, "Skill id %r does not follow <stage>.<skill-slug> for Stage %s."
              % (skill_id, stage_id))
    else:
        skill_slug = parsed[1]
        if skill_id in seen_skills:
            c.add("id-duplicate", where, "Skill id %r appears twice in Stage %s." % (skill_id, stage_id))
        seen_skills.add(skill_id)
    if not isinstance(skill.get("name"), str) or not skill.get("name").strip():
        c.add("skill-shape", where, "Skill %s has no name." % (skill_id,))
    if not isinstance(skill.get("isBenchmarkSequence"), bool):
        c.add("skill-shape", where, "Skill %s's isBenchmarkSequence must be true or false." % (skill_id,))

    raw_steps = skill.get("steps")
    if not isinstance(raw_steps, list):
        c.add("steps", where, "Skill %s has no steps list ([] when the stage has no progression for it)."
              % (skill_id,))
        raw_steps = []
    steps = dict_items(raw_steps)
    numbers = [step.get("n") for step in steps]
    if len(steps) != len(raw_steps) or numbers != list(range(1, len(steps) + 1)):
        c.add("steps", where, "Skill %s's steps are numbered %s; they run 1, 2, 3… in order."
              % (skill_id, _show(numbers)))
    for position, step in enumerate(steps):
        step_id = step.get("id")
        step_where = "stage %s / step %s" % (stage_id, step_id if isinstance(step_id, str) else
                                             "%s #%d" % (skill_id, position + 1))
        n = step.get("n")
        if skill_slug and is_int(n) and step_id != ids.step_id(stage_id, skill_slug, n):
            c.add("steps", step_where, "Step id %r should be %r (<stage>.<skill-slug>.<n>)."
                  % (step_id, ids.step_id(stage_id, skill_slug, n)))
        name = step.get("name")
        if not isinstance(name, str) or not name.strip():
            c.add("steps", step_where, "Step %s has no name." % (step_id,))
        else:
            key = (skill_id, ids.normalize_text(name).casefold())  # a stage may repeat one: Stage 6's Flip turn
            if key in step_names:
                c.add("step-name-duplicate", step_where, "Step name %r is used by both %s and %s; step names are "
                                                         "unique within a skill." % (name, step_names[key], step_id))
            else:
                step_names[key] = step_id
        if not isinstance(step.get("description"), str) or not step.get("description").strip():
            c.add("steps", step_where, "Step %s has no description." % (step_id,))
        if "measure" in step:
            c.measure(step["measure"], step_where)
            measure = step["measure"]
            if isinstance(measure, dict) and "preschoolValue" in measure and position != len(steps) - 1:
                c.add("preschool-value", step_where, "Step %s has a preschoolValue, but only a benchmark step "
                                                     "carries the Progress Tracker's preschool variant." % (step_id,))
        if "depths" in step:
            c.depths(step["depths"], step_where)
        c.flags(step, STEP_FLAGS, step_where)
        c.headfirst(step, step_where)
        if "equipment" in step:
            c.requirement_groups(step["equipment"], step_where)

    benchmark = skill.get("benchmarkStepId")
    if steps:
        last = steps[-1].get("id")
        if benchmark != last:
            c.add("benchmark", where, "Skill %s's benchmarkStepId is %s; it must be its last step, %s."
                  % (skill_id, _show(benchmark), _show(last)))
    elif benchmark is not None:
        c.add("benchmark", where, "Skill %s has no steps in Stage %s, so its benchmarkStepId must be null."
              % (skill_id, stage_id))

    for field in ("prerequisiteStepIds", "advancedStepIds"):
        if not is_str_list(skill.get(field)):
            c.add("skill-shape", where, "Skill %s's %s must be a list of step ids ([] for none)." % (skill_id, field))
    activity_ids = skill.get("activityIds")
    if not is_str_list(activity_ids):
        c.add("skill-shape", where, "Skill %s's activityIds must be a list of activity ids." % (skill_id,))
    elif not c.unloaded("activities.json"):
        for activity_id in activity_ids:
            if not c.cur.activity(activity_id):
                c.add("activity-missing", where, "Skill %s lists activity %r, which is not an activity."
                      % (skill_id, activity_id))
        if len(set(activity_ids)) != len(activity_ids):
            c.add("skill-shape", where, "Skill %s lists an activity twice." % (skill_id,), WARNING)
    video_ids = skill.get("videoIds", [])
    if not is_str_list(video_ids):
        c.add("skill-shape", where, "Skill %s's videoIds must be a list of video ids." % (skill_id,))
    elif c.cur.kind == "dir" and not c.unloaded("videos.json"):
        for video_id in video_ids:
            if not c.cur.video(video_id):
                c.add("video-link", where, "Skill %s lists video %r, which is not in videos.json." % (skill_id, video_id))


def _stages_between(first, second):
    low, high = sorted((ids.STAGE_INDEX[first], ids.STAGE_INDEX[second]))
    return [ids.STAGE_IDS[i] for i in range(low + 1, high)]


def _check_links(c, stage, skill):
    """A4: prerequisite ids point into the nearest earlier stage with the skill's steps,
    advanced ids into the nearest later one; into a stage that isn't loaded: a warning."""
    stage_id = stage.get("id")
    here = ids.STAGE_INDEX.get(stage_id)
    parsed = ids.parse_skill_id(skill.get("id"))
    if here is None or not parsed:
        return
    skill_slug = parsed[1]
    where = "stage %s / skill %s" % (stage_id, skill.get("id"))
    for field, label, direction in (("prerequisiteStepIds", "Prerequisite steps", -1),
                                    ("advancedStepIds", "Advanced steps", 1)):
        values = skill.get(field)
        if not is_str_list(values) or not values:
            continue
        if direction < 0 and stage_id == ids.STAGE_IDS[0]:
            c.add("link-unresolved", where, "Stage A is the first stage, so %s has no prerequisite steps; it lists %s."
                  % (skill["id"], _show(values)))
            continue
        if direction > 0 and stage_id == ids.STAGE_IDS[-1]:
            c.add("link-unresolved", where, "Stage 6 is the last stage, so %s has no advanced steps; it lists %s."
                  % (skill["id"], _show(values)))
            continue
        stages_named = []
        not_loaded = {}
        for value in values:
            ref = ids.parse_step_id(value)
            if not ref:
                c.add("link-unresolved", where, "%s of %s include %r, which is not a step id." % (label, skill["id"], value))
                continue
            ref_stage, ref_slug, _n = ref
            there = ids.STAGE_INDEX[ref_stage]
            if (direction < 0 and there >= here) or (direction > 0 and there <= here):
                c.add("link-unresolved", where, "%s of %s include %s, which is not in an %s stage."
                      % (label, skill["id"], value, "earlier" if direction < 0 else "later"))
                continue
            if ref_stage not in stages_named:
                stages_named.append(ref_stage)
            if not c.cur.is_loaded(ref_stage):
                not_loaded.setdefault(ref_stage, []).append(value)
                continue
            if not c.cur.step(value):
                c.add("link-unresolved", where, "%s of %s include %s, which is not a step of Stage %s."
                      % (label, skill["id"], value, ref_stage))
                continue
            if ref_slug == skill_slug:
                for middle in _stages_between(stage_id, ref_stage):
                    nearer = c.cur.skill(ids.skill_id(middle, skill_slug))
                    if nearer and dict_items(nearer.get("steps")):
                        c.add("link-unresolved", where, "%s of %s point into Stage %s, but Stage %s is nearer and has "
                                                        "%s steps; links go to the nearest stage that has them."
                              % (label, skill["id"], ref_stage, middle, nearer["id"]))
                        break
        if len(stages_named) > 1:
            c.add("link-unresolved", where, "%s of %s come from Stages %s; a column lists one stage's steps."
                  % (label, skill["id"], ", ".join(stages_named)))
        for ref_stage, values_there in not_loaded.items():
            c.add("link-not-loaded", where, "%s of %s point into Stage %s, which isn't loaded: %s (printed "
                                            "without names, e.g. \"%s\")."
                  % (label, skill["id"], ref_stage, ", ".join(values_there), ids.step_label(values_there[0])),
                  WARNING)


def _check_topics(c, stage):
    stage_id = stage.get("id")
    where = "stage %s / topics" % stage_id
    topics = stage.get("topics")
    if not isinstance(topics, list):
        c.add("topics", where, "Stage %s has no topics list." % stage_id)
        return
    items = dict_items(topics)
    numbers = sorted(t.get("n") for t in items if is_int(t.get("n")))
    if len(items) != len(topics) or numbers != list(range(1, TOPICS_PER_STAGE + 1)):
        c.add("topics", where, "Stage %s has topics %s; it needs exactly topics 1–8."
              % (stage_id, _show([t.get("n") for t in items])))
    for topic in items:
        n = topic.get("n")
        topic_where = "stage %s / topic %s" % (stage_id, topic.get("code"))
        if is_int(n) and topic.get("code") != ids.topic_code(stage_id, n):
            c.add("topics", topic_where, "Topic %s's code is %s; it must be %s."
                  % (n, _show(topic.get("code")), ids.topic_code(stage_id, n)))
        if not isinstance(topic.get("name"), str) or not topic.get("name").strip():
            c.add("topics", topic_where, "Topic %s has no name." % _show(topic.get("code")))
        if not isinstance(topic.get("summary", ""), str):
            c.add("topics", topic_where, "Topic %s's summary must be a sentence." % _show(topic.get("code")))
        for field in ("prompts", "notes"):
            if not is_str_list(topic.get(field)):
                c.add("topics", topic_where, "Topic %s's %s must be a list of sentences ([] for none)."
                      % (_show(topic.get("code")), field))


def _check_templates(c, stage, lesson_minutes):
    stage_id = stage.get("id")
    where = "stage %s / lesson templates" % stage_id
    templates = stage.get("lessonTemplates")
    if not isinstance(templates, list):
        c.add("templates", where, "Stage %s has no lessonTemplates list." % stage_id)
        return
    items = dict_items(templates)
    numbers = sorted(t.get("n") for t in items if is_int(t.get("n")))
    if len(items) != len(templates) or numbers != list(range(1, TEMPLATES_PER_STAGE + 1)):
        c.add("templates", where, "Stage %s has lesson templates %s; it needs exactly lesson templates 1–8."
              % (stage_id, _show([t.get("n") for t in items])))
    skills = dict_items(stage.get("skills"))
    greeting = set(stage.get("greetingActivityIds") or []) if is_str_list(stage.get("greetingActivityIds")) else set()
    stage_activities = set()
    for skill in skills:
        if is_str_list(skill.get("activityIds")):
            stage_activities.update(skill["activityIds"])
    for template in items:
        n = template.get("n")
        template_where = "stage %s / lesson template %s" % (stage_id, n)
        minutes = template.get("minutes")
        if not is_int(minutes) or minutes <= 0:
            c.add("template-minutes", template_where, "Stage %s lesson template %s has no minutes." % (stage_id, n))
            minutes = None
        elif lesson_minutes and minutes != lesson_minutes:
            c.add("template-minutes", template_where, "Stage %s lesson template %s is %d minutes; the stage's "
                                                      "lessons are %d." % (stage_id, n, minutes, lesson_minutes))
        blocks = template.get("blocks")
        if not isinstance(blocks, list):
            shown = blocks if isinstance(blocks, str) else type(blocks).__name__
            c.add("template-placeholder", template_where,
                  "Stage %s lesson template %s has no blocks yet (%s); it must be transcribed before the stage "
                  "can be planned." % (stage_id, n, _show(shown)))
            continue
        total, complete = 0, True
        for position, block in enumerate(blocks):
            if not isinstance(block, dict):
                c.add("template-block", template_where, "Block %d is not an object." % (position + 1))
                complete = False
                continue
            _check_block(c, stage, template_where, position, block, greeting, stage_activities)
            if is_int(block.get("minutes")):
                total += block["minutes"]
            else:
                complete = False
        if complete and minutes is not None and total != minutes:
            c.add("template-minutes", template_where,
                  "Stage %s lesson template %s's blocks add up to %d minutes, not %d (a printed range counts as "
                  "its upper value)." % (stage_id, n, total, minutes))


def _check_block(c, stage, template_where, position, block, greeting, stage_activities):
    stage_id = stage.get("id")
    kind = block.get("kind")
    where = "%s / block %d (%s)" % (template_where, position + 1, kind)
    if kind not in ids.BLOCK_KINDS:
        c.add("template-block", where, "Block kind %r is not one of %s." % (kind, ", ".join(ids.BLOCK_KINDS)))
    minutes = block.get("minutes")
    if not is_int(minutes) or minutes < 0:
        c.add("template-block", where, "Block minutes must be a whole number of 0 or more; they are %s."
              % _show(minutes))
    skill_ids = block.get("skillIds") or []
    if not is_str_list(skill_ids):
        c.add("template-block", where, "skillIds must be a list of skill ids.")
        skill_ids = []
    named, has_any = [], False
    for value in skill_ids:
        if value == ids.ANY_SKILL:
            has_any = True
            if kind not in ("review", "introduce"):
                c.add("template-block", where, "\"any\" fills Review and Introduce slots only; this is a %s block."
                      % kind)
            continue
        skill = c.cur.skill(value)
        if not skill or skill.get("stageId") != stage_id:
            c.add("template-block", where, "The block names skill %r, which is not in Stage %s." % (value, stage_id))
        else:
            named.append(skill)
    step_range = block.get("stepRange")
    if step_range is not None:
        if not (isinstance(step_range, list) and len(step_range) == 2 and all(is_int(v) for v in step_range)
                and 1 <= step_range[0] <= step_range[1]):
            c.add("step-range", where, "stepRange must be [first, last] with 1 ≤ first ≤ last; it is %s."
                  % _show(step_range))
        else:
            counts = [(skill["id"], len(dict_items(skill.get("steps")))) for skill in named]
            counts = [item for item in counts if item[1]]
            if not counts:
                c.add("step-range", where, "The block has a stepRange but no skill with steps.")
            else:
                for skill_id, count in counts:
                    if step_range[0] > count:
                        c.add("step-range", where, "stepRange %s starts past %s's last step (%d)."
                              % (_show(step_range), skill_id, count))
                longest = max(count for _id, count in counts)
                if step_range[1] > longest:
                    c.add("step-range", where, "stepRange %s ends past the last step of every skill in the block "
                                               "(the longest has %d)." % (_show(step_range), longest))
    activity_ids = block.get("activityIds") or []
    if not is_str_list(activity_ids):
        c.add("template-block", where, "activityIds must be a list of activity ids.")
    elif not c.unloaded("activities.json"):
        if named or has_any:
            allowed = set(greeting)
            if has_any:
                allowed |= stage_activities
            for skill in named:
                allowed.update(skill.get("activityIds") or [])
            belongs = "the block's skills or the Greeting"
        elif kind == "warmUp":
            allowed, belongs = None, ""
        elif kind == "wrapUp":
            allowed, belongs = greeting | stage_activities, "the stage's skills or the Greeting"
        else:
            allowed, belongs = greeting, "the Greeting"
        for activity_id in activity_ids:
            if not c.cur.activity(activity_id):
                c.add("activity-missing", where, "The block lists activity %r, which is not an activity." % activity_id)
            elif allowed is not None and activity_id not in allowed:
                c.add("template-activity", where, "The block lists %r, which belongs to none of %s."
                      % (activity_id, belongs))
    topic_code = block.get("topicCode")
    if kind == "topic":
        if not isinstance(topic_code, str):
            c.add("template-block", where, "A topic block names its topic (topicCode).")
        elif not c.cur.topic(topic_code) or c.cur.topic(topic_code).get("stageId") != stage_id:
            c.add("template-block", where, "The block names topic %r, which is not one of Stage %s's topics."
                  % (topic_code, stage_id))
    elif topic_code is not None:
        c.add("template-block", where, "Only a topic block has a topicCode.", WARNING)
    if "notes" in block and not is_str_list(block["notes"]):
        c.add("template-block", where, "notes must be a list of sentences.")
    if "depths" in block:
        c.depths(block["depths"], where)
    if "equipment" in block:
        c.requirement_groups(block["equipment"], where)


def _check_tracker_rows(c, stage):
    """A7: rows name only benchmark steps; a one-step row's text is its step's name; "any"
    rows name two or more steps; every skill with steps is in a row."""
    stage_id = stage.get("id")
    where = "stage %s / tracker rows" % stage_id
    rows = stage.get("trackerRows")
    if not isinstance(rows, list) or not rows:
        c.add("tracker-rows-missing", where,
              "Stage %s has no trackerRows yet: the Progress Tracker's rows must be transcribed before the reports "
              "and the next-stage line can work." % stage_id)
        return
    benchmarks = {}
    for skill in dict_items(stage.get("skills")):
        if isinstance(skill.get("benchmarkStepId"), str):
            benchmarks[skill["benchmarkStepId"]] = skill
    covered, texts = {}, {}
    for index, row in enumerate(rows):
        row_where = "stage %s / tracker row %d" % (stage_id, index + 1)
        if not isinstance(row, dict):
            c.add("tracker-row", row_where, "A tracker row is not an object { text, stepIds, rule }.")
            continue
        row_text = row.get("text")
        if not isinstance(row_text, str) or not row_text.strip():
            c.add("tracker-row", row_where, "Tracker row %d has no text." % (index + 1))
        else:
            key = ids.normalize_text(row_text)
            if key in texts:
                c.add("tracker-row", row_where, "Tracker row %d repeats row %d's text %r." % (index + 1, texts[key], row_text))
            texts.setdefault(key, index + 1)
        step_ids = row.get("stepIds")
        if not is_str_list(step_ids) or not step_ids:
            c.add("tracker-row", row_where, "Tracker row %d names no benchmark steps." % (index + 1))
            continue
        for step_id in step_ids:
            if step_id in benchmarks:
                if step_id in covered:
                    c.add("tracker-row", row_where, "%s is in tracker rows %d and %d." % (step_id, covered[step_id], index + 1),
                          WARNING)
                covered.setdefault(step_id, index + 1)
            elif c.cur.step(step_id) and c.cur.step(step_id).get("skillId", "").startswith(stage_id + "."):
                c.add("tracker-row", row_where, "Tracker row %d names %s, which is not its skill's benchmark (last step)."
                      % (index + 1, step_id))
            else:
                c.add("tracker-row", row_where, "Tracker row %d names %s, which is not a step of Stage %s."
                      % (index + 1, step_id, stage_id))
        rule = row.get("rule")
        if rule not in ("all", "any"):
            c.add("tracker-row", row_where, "Tracker row %d's rule is %s; it must be \"all\" or \"any\"." % (index + 1, _show(rule)))
        elif rule == "any" and len(step_ids) < 2:
            c.add("tracker-row", row_where, "Tracker row %d has rule \"any\" over one step; \"any\" needs two or more."
                  % (index + 1))
        if rule == "all" and len(step_ids) == 1 and isinstance(row_text, str):
            step = c.cur.step(step_ids[0])
            if step and isinstance(step.get("name"), str) and \
                    ids.normalize_text(step["name"]) != ids.normalize_text(row_text):
                c.add("tracker-row", row_where, "Tracker row %d's text %r differs from its benchmark step's name %r; "
                                                "a one-step row's text is the step's name." % (index + 1, row_text, step["name"]))
    for step_id, skill in benchmarks.items():
        if step_id not in covered:
            c.add("tracker-coverage", where, "Stage %s's %s has steps, but no tracker row names its benchmark %s."
                  % (stage_id, skill.get("id"), step_id))


# activities (A5, A13) ----------------------------------------------------------

def _check_activities(c):
    if c.unloaded("activities.json"):
        return
    listed = {}
    greeting_ids = set()
    for stage in c.cur.stages:
        for skill in dict_items(stage.get("skills")):
            for activity_id in skill.get("activityIds") or []:
                if isinstance(activity_id, str):
                    listed.setdefault(activity_id, set()).add(skill.get("id"))
        if is_str_list(stage.get("greetingActivityIds")):
            greeting_ids.update(stage["greetingActivityIds"])
    seen = set()
    for index, activity in enumerate(c.cur.activities):
        if not isinstance(activity, dict):
            c.add("activity-shape", "activity %d" % (index + 1), "An activity is not an object.")
            continue
        activity_id = activity.get("id")
        origin = c.origin(activity)
        where = ("local.json / activity %s" if origin == "local" else "activity %s") % (activity_id,)
        if not ids.is_slug(activity_id):
            c.add("activity-shape", where, "Activity id %r is not a lower-case slug." % (activity_id,))
        elif (activity_id, origin) in seen:
            c.add("id-duplicate", where, "Activity id %r appears twice in %s."
                  % (activity_id, "local.json" if origin == "local" else "activities.json"))
        seen.add((activity_id, origin))
        if origin == "ymca" and activity.get("source") != "ymca":
            c.add("activity-shape", where, "activities.json holds the toolkit's activities only (source \"ymca\"); "
                                           "your own activities go in local.json.")
        if not isinstance(activity.get("name"), str) or not activity.get("name").strip():
            c.add("activity-shape", where, "Activity %r has no name." % (activity_id,))
        if not isinstance(activity.get("description"), str) or not activity.get("description").strip():
            c.add("activity-shape", where, "Activity %r has no description." % (activity_id,))
        ages = activity.get("ages")
        if not is_str_list(ages) or any(a not in ids.AGE_TAGS for a in ages) or len(set(ages)) != len(ages):
            c.add("activity-shape", where, "Activity %r's ages must be a list of P, S and A ([] = every age); "
                                           "they are %s." % (activity_id, _show(ages)))
        if "equipment" not in activity:
            c.add("equipment-shape", where, "Activity %r has no equipment list ([] = no equipment)." % (activity_id,))
        else:
            c.requirement_groups(activity["equipment"], where)
        c.optional_equipment(activity.get("equipmentOptional", []), where)
        if "depths" in activity:
            c.depths(activity["depths"], where)
        c.flags(activity, ACTIVITY_FLAGS, where)
        if "nearWall" in activity:
            c.add("flag-type", where, "nearWall is for steps only; activity %r has it." % (activity_id,))
        c.headfirst(activity, where)
        if not isinstance(activity.get("submerges"), bool):
            c.add("flag-type", where, "Activity %r needs submerges, true or false." % (activity_id,))
        if not is_str_list(activity.get("tags", [])):
            c.add("activity-shape", where, "Activity %r's tags must be a list of words." % (activity_id,))
        skill_ids = activity.get("skillIds", [])
        if not is_str_list(skill_ids):
            c.add("activity-shape", where, "Activity %r's skillIds must be a list of skill ids." % (activity_id,))
            continue
        declared, unloaded_stages = set(), set()
        for skill_id in skill_ids:
            parsed = ids.parse_skill_id(skill_id)
            if not parsed:
                c.add("activity-shape", where, "Activity %r names %r, which is not a skill id." % (activity_id, skill_id))
            elif not c.cur.is_loaded(parsed[0]):
                unloaded_stages.add(parsed[0])
            elif not c.cur.skill(skill_id):
                c.add("activity-shape", where, "Activity %r names skill %s, which is not in Stage %s."
                      % (activity_id, skill_id, parsed[0]))
            else:
                declared.add(skill_id)
        if unloaded_stages and origin == "local":
            c.add("activity-shape", where, "Local activity %r names skills of Stage %s, which isn't loaded."
                  % (activity_id, ", ".join(sorted(unloaded_stages, key=ids.stage_sort_key))), WARNING)
        if origin != "ymca":
            continue
        listing = listed.get(activity_id, set())
        if listing != declared:
            c.add("activity-skills", where, "Activity %r's skillIds %s differ from the loaded skills that list it %s."
                  % (activity_id, _show(sorted(declared)), _show(sorted(listing))), WARNING)
        if not listing and activity_id not in greeting_ids and not unloaded_stages:
            c.add("orphan-activity", where, "No loaded skill or Greeting lists activity %r." % (activity_id,), WARNING)


# videos (A12) ------------------------------------------------------------------

def _check_videos(c):
    if c.unloaded("videos.json"):
        return
    seen = set()
    for index, video in enumerate(c.cur.videos):
        where = "video %d" % (index + 1)
        if not isinstance(video, dict):
            c.add("video", where, "A video entry is not an object.")
            continue
        video_id = video.get("id")
        number = ids.parse_video_id(video_id)
        where = "video %s" % (video_id,)
        if not number:
            c.add("video", where, "Video id %r is not vimeo:<number>." % (video_id,))
        elif video_id in seen:
            c.add("id-duplicate", where, "Video id %r appears twice." % video_id)
        seen.add(video_id)
        url_number = ids.vimeo_id_from_url(video.get("url"))
        if not url_number:
            c.add("video", where, "Video %s's url %s is not a Vimeo url." % (video_id, _show(video.get("url"))))
        elif number and url_number != number:
            c.add("video", where, "Video %s's url is Vimeo video %s, not %s." % (video_id, url_number, number))
        if not isinstance(video.get("title"), str) or not video.get("title").strip():
            c.add("video", where, "Video %s has no title." % (video_id,))
        stage_ids = video.get("stageIds", [])
        skill_ids = video.get("skillIds", [])
        if not is_str_list(stage_ids) or not is_str_list(skill_ids):
            c.add("video-link", where, "Video %s's stageIds and skillIds must be lists of ids." % (video_id,))
            continue
        not_loaded = set()
        for stage_id in stage_ids:
            if not ids.is_stage_id(stage_id):
                c.add("video-link", where, "Video %s names stage %r, which is not a stage." % (video_id, stage_id))
            elif not c.cur.is_loaded(stage_id):
                not_loaded.add(stage_id)
        for skill_id in skill_ids:
            parsed = ids.parse_skill_id(skill_id)
            if not parsed:
                c.add("video-link", where, "Video %s names %r, which is not a skill id." % (video_id, skill_id))
            elif not c.cur.is_loaded(parsed[0]):
                not_loaded.add(parsed[0])
            elif not c.cur.skill(skill_id):
                c.add("video-link", where, "Video %s names skill %s, which is not in Stage %s."
                      % (video_id, skill_id, parsed[0]))
            elif parsed[0] not in stage_ids:
                c.add("video-link", where, "Video %s names skill %s but not its stage %s." % (video_id, skill_id, parsed[0]),
                      WARNING)
        if not_loaded:
            c.add("video-link", where, "Video %s links Stage %s, which isn't loaded."
                  % (video_id, ", ".join(sorted(not_loaded, key=ids.stage_sort_key))), WARNING)


# local additions (A9, A13) -------------------------------------------------------

def _ymca_ids(c):
    found = set(ids.STAGE_IDS)
    for key in ("activities", "equipment"):
        for entry in dict_items(getattr(c.cur, key)):
            if c.origin(entry) == "ymca" and isinstance(entry.get("id"), str):
                found.add(entry["id"])
    for key in ("safety", "videos"):
        found.update(entry["id"] for entry in dict_items(getattr(c.cur, key)) if isinstance(entry.get("id"), str))
    for stage in c.cur.stages:
        for skill in dict_items(stage.get("skills")):
            if isinstance(skill.get("id"), str):
                found.add(skill["id"])
            found.update(step["id"] for step in dict_items(skill.get("steps")) if isinstance(step.get("id"), str))
        found.update(t["code"] for t in dict_items(stage.get("topics")) if isinstance(t.get("code"), str))
    return found


def _check_local(c):
    if c.cur.kind != "dir" or c.cur.local is None:
        return
    local = c.cur.local
    if not isinstance(local, dict):
        c.add("local-format", "local.json", "local.json is not a JSON object { format, activities, equipment }.")
        return
    if local.get("format") != LOCAL_FORMAT:
        c.add("local-format", "local.json", "local.json has format %s; it must be \"local/1\"." % _show(local.get("format")))
    extra = sorted(key for key in local if key not in ("format", "activities", "equipment"))
    if extra:
        c.add("local-format", "local.json", "local.json may hold only format, activities and equipment; it also has %s."
              % ", ".join(extra))
    ymca = _ymca_ids(c)
    for key, noun in (("activities", "activity"), ("equipment", "equipment")):
        entries = local.get(key)
        if key not in local:
            c.add("local-format", "local.json", "local.json has no %s list ([] when empty)." % key)
            continue
        if not isinstance(entries, list):
            c.add("local-format", "local.json", "local.json's %s is not a list." % key)
            continue
        for index, entry in enumerate(entries):
            if not isinstance(entry, dict):
                c.add("local-entry", "local.json", "local.json's %s entry %d is not an object." % (key, index + 1))
                continue
            entry_id = entry.get("id")
            where = "local.json / %s %s" % (noun, entry_id)
            if entry.get("source") != "local":
                c.add("local-entry", where, "local.json %s %r has source %s; every local entry has source \"local\"."
                      % (noun, entry_id, _show(entry.get("source"))))
            if key == "equipment" and entry.get("kind") != "item":
                c.add("local-entry", where, "local.json equipment %r is a %s; local equipment entries are items "
                                            "(kind \"item\")." % (entry_id, _show(entry.get("kind"))))
            if entry_id in ymca:
                c.add("local-collision", where, "local.json %s %r uses a YMCA id; local ids never reuse a YMCA id."
                      % (noun, entry_id))


def _check_cross_ids(c):
    """A9: ids are unique across the files. Activity, equipment and safety ids share one
    slug namespace; a clash between two YMCA files is an error here (local clashes are
    reported as local-collision)."""
    owners = {}
    for label, entries in (("activity", c.cur.activities), ("equipment item", c.cur.equipment),
                           ("safety rule", c.cur.safety)):
        for entry in dict_items(entries):
            if c.origin(entry) != "ymca" or not isinstance(entry.get("id"), str):
                continue
            owners.setdefault(entry["id"], [])
            if label not in owners[entry["id"]]:
                owners[entry["id"]].append(label)
    for entry_id, labels in owners.items():
        if len(labels) > 1:
            c.add("id-duplicate", "curriculum", "Id %r is both a %s; ids are unique across the curriculum files."
                  % (entry_id, " and a ".join(labels)))


# placeholders -----------------------------------------------------------------------

def _walk_strings(value, path):
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, dict):
        for key in value:
            yield from _walk_strings(value[key], "%s.%s" % (path, key) if path else key)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from _walk_strings(item, "%s[%d]" % (path, index))


def _check_placeholders(c):
    groups = [("stage %s" % stage.get("id"), stage) for stage in c.cur.stages]
    groups.append(("activities", {str(a.get("id")): a for a in dict_items(c.cur.activities)}))
    for where, value in groups:
        todo, unreadable = [], []
        for path, string in _walk_strings(value, ""):
            if path.endswith(".blocks") and string == PLACEHOLDER:
                continue  # reported as template-placeholder
            if string.startswith(PLACEHOLDER):
                todo.append(path)
            if UNREADABLE in string:
                unreadable.append(path)
        if todo:
            c.add("placeholder-text", where, "%s still has %d %s field%s (%s%s)."
                  % (where.capitalize(), len(todo), PLACEHOLDER, "" if len(todo) == 1 else "s",
                     ", ".join(todo[:3]), ", …" if len(todo) > 3 else ""), WARNING)
        if unreadable:
            c.add("placeholder-text", where, "%s has %d field%s marked UNREADABLE (%s%s); read them from the PDF."
                  % (where.capitalize(), len(unreadable), "" if len(unreadable) == 1 else "s",
                     ", ".join(unreadable[:3]), ", …" if len(unreadable) > 3 else ""), WARNING)
