"""Owner sign-off aid (M1 done-when): curriculum/review/stage-<S>.md from a stage's work
file — per skill its steps (name, description, measure, depth tags) and activities (ages,
equipment, depths), then the Greeting, the topics and the eight lesson templates, each with
its source pages, and a checklist line per section for the owner to tick against the PDF.

The page quotes the toolkit, so it is written under curriculum/ (gitignored, SPEC D20).
"""

from pathlib import Path

from . import curriculum as C
from . import ids
from .assemble import DEFAULT_EQUIPMENT, check_work_file, load_catalog, work_file_name, write_text_atomic
from .curriculum import dict_items


def equipment_names(catalog):
    return {e["id"]: e.get("name", e["id"]).lower() for e in dict_items(catalog) if isinstance(e.get("id"), str)}


def equipment_label(groups, names):
    """[["pool-noodle", "rescue-tube"], ["kickboard"]] -> 'pool noodle or rescue tube + kickboard'."""
    if not groups:
        return "none"
    labels = []
    for group in groups:
        words = [names.get(item, item) for item in group] if isinstance(group, list) else [str(group)]
        labels.append(words[0] if len(words) == 1 else "%s or %s" % (", ".join(words[:-1]), words[-1]))
    return " + ".join(labels)


def _cell(value):
    return str(value).replace("|", "\\|").replace("\n", " ")


def _pages(value):
    if isinstance(value, list):
        return ", ".join(str(p) for p in value)
    return str(value) if value is not None else "?"


def _measure(measure):
    if not isinstance(measure, dict):
        return ""
    unit = measure.get("unit") or ""
    shown = ("%s %s" % (measure.get("value"), unit)).strip()
    if "preschoolValue" in measure:
        shown += " (preschool %s %s)" % (measure["preschoolValue"], unit)
    return "%s %s" % (measure.get("kind", ""), shown.strip())


def _tags(entry, flags):
    parts = []
    if entry.get("depths"):
        parts.append("depths: %s" % ", ".join(entry["depths"]))
    else:
        parts.append("depths: any")
    labels = {"headfirst": "headfirst", "reachBottom": "reaches bottom", "nearWall": "near wall",
              "flotationOption": "flotation option", "submerges": "submerges"}
    parts.extend(labels[f] for f in flags if entry.get(f) is True)
    return " · ".join(parts)


def _ref(ref):
    if not isinstance(ref, dict):
        return str(ref)
    head = "%s / %s / %s" % (ref.get("stage"), ref.get("skill"), ref.get("n"))
    return "%s “%s”" % (head, ref["name"]) if ref.get("name") else head


def _activity_lines(activity, names):
    ages = " ".join(activity.get("ages") or []) or "untagged"
    bits = ["ages %s" % ages, "equipment: %s" % equipment_label(activity.get("equipment") or [], names)]
    if activity.get("equipmentOptional"):
        bits.append("optional: %s" % ", ".join(names.get(i, i) for i in activity["equipmentOptional"]))
    bits.append(_tags(activity, C.ACTIVITY_FLAGS))
    if activity.get("tags"):
        bits.append("tags: %s" % ", ".join(activity["tags"]))
    if activity.get("idSuffix"):
        bits.append("idSuffix: %s" % activity["idSuffix"])
    if activity.get("variant"):
        bits.append("variant: %s" % activity["variant"])
    bits.append("p. %s" % activity.get("page", "?"))
    return ["- **%s** · %s" % (activity.get("name"), " · ".join(bits)),
            "  %s" % activity.get("description", "")]


def render_review(work, catalog, problems, file_name):
    names = equipment_names(catalog)
    stage = work.get("stage") or {}
    stage_id = stage.get("id")
    sources = work.get("sources") or {}
    lines = ["# Stage %s · %s — transcription review" % (stage_id, stage.get("name")), "",
             "Read each section against the PDF and tick its box when it matches word for word, equipment and "
             "depth tags included (BUILD_PLAN M1). Work file: `%s`." % file_name, "",
             "Sources: library %s; guide %s; Progress Tracker pages %s; Stage Overview pages %s."
             % (sources.get("library", "?"), sources.get("guide", "?"), sources.get("trackerPages", "?"),
                sources.get("overviewPages", "?")), ""]
    found_errors, found_warnings = C.errors(problems), C.warnings(problems)
    lines.append("check-work: %d error%s, %d warning%s." % (len(found_errors), "" if len(found_errors) == 1 else "s",
                                                         len(found_warnings), "" if len(found_warnings) == 1 else "s"))
    for item in found_errors + found_warnings:
        lines.append("- %s: %s: %s" % (item.severity, item.where, item.message))
    lines += ["", "## Stage", "",
              "- Group: %s · age groups: %s · lessons: %s min" % (stage.get("group"), ", ".join(stage.get("ageGroups") or []),
                                                                  stage.get("lessonMinutes")),
              "- Warm-up skill: %s · wrap-up skill: %s" % (stage.get("warmUpSkill"), stage.get("wrapUpSkill")),
              "- Milestones:"]
    lines += ["  %d. %s" % (i + 1, m) for i, m in enumerate(stage.get("milestones") or [])]
    lines += ["- [ ] Stage details and milestones checked", "",
              "## Progress Tracker rows (pages %s)" % sources.get("trackerPages", "?"), ""]
    for index, row in enumerate(dict_items(work.get("trackerRows"))):
        refs = ", ".join("%s %s" % (r.get("skill"), r.get("n")) for r in dict_items(row.get("steps")))
        extra = " · preschool: %s" % row["preschool"] if row.get("preschool") else ""
        lines.append("%d. %s → %s (%s)%s" % (index + 1, row.get("text"), refs, row.get("rule"), extra))
    lines += ["- [ ] Tracker rows checked, text and order", "", "## Skills", ""]
    for skill in dict_items(work.get("skills")):
        pages = skill.get("pages") or {}
        lines += ["### %s. %s (`%s`) — progression p. %s, activities p. %s"
                  % (skill.get("order"), skill.get("name"), ids.skill_id(stage_id, skill.get("slug")),
                     pages.get("progression", "?"), pages.get("activities", "?")), ""]
        if skill.get("isBenchmarkSequence"):
            lines.append("Benchmark sequence.")
        lines.append("Prerequisite: %s" % ("; ".join(_ref(r) for r in skill.get("prerequisite") or []) or "none"))
        steps = dict_items(skill.get("steps"))
        if steps:
            lines.append("Steps:")
            for step in steps:
                lines.append("%s. **%s** — %s" % (step.get("n"), step.get("name"), step.get("description")))
                detail = [d for d in (_measure(step.get("measure")), _tags(step, C.STEP_FLAGS)) if d]
                if step.get("equipment"):
                    detail.append("equipment: %s" % equipment_label(step["equipment"], names))
                lines.append("   %s" % " · ".join(detail))
        else:
            lines.append("Steps: none in this stage (no stage progression).")
        lines.append("Advanced: %s" % ("; ".join(_ref(r) for r in skill.get("advanced") or []) or "none"))
        activities = dict_items(skill.get("activities"))
        lines.append("Activities (%d):" % len(activities))
        for activity in activities:
            lines += _activity_lines(activity, names)
        lines += ["- [ ] %s: steps (names, descriptions, measures, depth tags) and activities (ages, equipment, "
                  "depths) checked against pp. %s–%s" % (skill.get("name"), pages.get("progression", "?"),
                                                         pages.get("activities", "?")), ""]
    greeting = work.get("greeting") or {}
    lines += ["## Greeting (pp. %s)" % _pages(greeting.get("pages")), ""]
    for activity in dict_items(greeting.get("activities")):
        lines += _activity_lines(activity, names)
    lines += ["- [ ] Greeting activities checked", "", "## Topics", ""]
    for topic in dict_items(work.get("topics")):
        lines += ["### %s %s (p. %s)" % (topic.get("code"), topic.get("name"), topic.get("page", "?")),
                  "Summary: %s" % topic.get("summary", "")]
        lines += ["- %s" % prompt for prompt in topic.get("prompts") or []]
        if topic.get("notes"):
            lines.append("Notes: %s" % " · ".join(topic["notes"]))
        lines.append("")
    lines += ["- [ ] Topics checked", "", "## Lesson templates", ""]
    for template in dict_items(work.get("lessonTemplates")):
        lines += ["### Lesson %s — %s min (guide pp. %s)" % (template.get("n"), template.get("minutesTotal"),
                                                            _pages(template.get("pages"))), "",
                  "| # | Block | Min | Skills | Activities | Topic | Notes |", "|---|---|---|---|---|---|---|"]
        for index, block in enumerate(dict_items(template.get("blocks"))):
            minutes = block.get("minutes")
            if block.get("minutesPrinted"):
                minutes = "%s (printed %s)" % (minutes, block["minutesPrinted"])
            skills = ", ".join("%s%s" % (s.get("slug"), " %s–%s" % tuple(s["steps"]) if isinstance(s.get("steps"), list)
                                         and len(s["steps"]) == 2 else "") for s in dict_items(block.get("skills")))
            notes = list(block.get("notes") or [])
            if block.get("depths"):
                notes.append("water: %s" % ", ".join(block["depths"]))
            if block.get("equipment"):
                notes.append("equipment: %s" % equipment_label(block["equipment"], names))
            lines.append("| %d | %s | %s | %s | %s | %s | %s |" % (
                index + 1, block.get("kind"), _cell(minutes), _cell(skills),
                _cell(", ".join(block.get("activities") or [])), _cell(block.get("topicCode") or ""),
                _cell(" · ".join(notes))))
        lines += ["", "- [ ] Lesson %s checked" % template.get("n"), ""]
    uncertain = dict_items(work.get("uncertain"))
    lines += ["## Uncertain (%d)" % len(uncertain), ""]
    lines += ["- %s: %s (p. %s)" % (u.get("where"), u.get("issue"), u.get("page", "?")) for u in uncertain]
    return "\n".join(lines).rstrip() + "\n"


def write_review(stage_id, work_dir, out_dir, catalog_path=DEFAULT_EQUIPMENT):
    """Write <out_dir>/stage-<S>.md. Returns (path or None, problems)."""
    stage_id = str(stage_id).upper()
    if stage_id not in ids.STAGE_INDEX:
        return None, [C.problem("work-shape", str(stage_id), "%r is not a stage (A, B, 1–6)." % stage_id)]
    path = Path(work_dir) / work_file_name(stage_id)
    problems = []
    catalog = load_catalog(catalog_path, problems)
    work, found = check_work_file(path, catalog)
    problems += found
    if not isinstance(work, dict):
        return None, problems
    target = Path(out_dir) / ("stage-%s.md" % stage_id)
    write_text_atomic(target, render_review(work, catalog, found, path.name))
    return target, problems
