"""Writes the synthetic mini curriculum used by tests/test_curriculum.py and
tests/test_assemble.py. Everything here is made up ("Skill One", "Skill One, step 1",
"One Drill"); none of it is toolkit text.

It mirrors the real curriculum's structure: eight stages (A, B, 1–6); 30-minute lessons
in A–3 and 40-minute ones in 4–6 with a printed "1–2 mins." Review; Stage 5's Skill Eight
Left has no steps and links Stage 4's and Stage 6's, which takes Stage 4's as
prerequisites; Stage 6 has one tracker row, rule "any", over its two Skill Eight
benchmarks; Stage 4's lessons 1–4 warm up with no skill, on activities from Stages 1–3;
preschool variants, deep-water and headfirst steps, step and block equipment.

Run it from the project root to rewrite _work/ (the stage work files and safety.json),
videos-source.json and local.json and to
assemble the golden output beside them (stages/, activities.json, equipment.json,
videos.json, version.json, safety.json):

    python3 tests/fixtures/curriculum_mini/make_fixture.py
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.core import assemble as A  # noqa: E402
from tools.core import ids  # noqa: E402

ALL_AGES = ["preschool", "schoolAge", "teen", "adult"]
STAGES = {
    "A": ("Stage Alpha", "Synthetic Starters", ["infantToddler"], 30),
    "B": ("Stage Beta", "Synthetic Starters", ["infantToddler"], 30),
    "1": ("Stage One", "Synthetic Basics", ALL_AGES, 30),
    "2": ("Stage Two", "Synthetic Basics", ALL_AGES, 30),
    "3": ("Stage Three", "Synthetic Basics", ALL_AGES, 30),
    "4": ("Stage Four", "Synthetic Strokes", ALL_AGES, 40),
    "5": ("Stage Five", "Synthetic Strokes", ALL_AGES[1:], 40),
    "6": ("Stage Six", "Synthetic Strokes", ALL_AGES[1:], 40),
}
ORDER = list(STAGES)
WORDS = ["One", "Two", "Three", "Four", "Five", "Six", "Seven"]
BASE_STEPS = {"skill-one": 4, "skill-two": 3, "skill-three": 2, "skill-four": 4, "skill-five": 1,
              "skill-six": 3, "skill-seven": 2, "skill-eight-left": 2, "skill-eight-right": 3}


def skill_names(stage):
    names = ["Skill %s" % word for word in WORDS] + ["Skill Eight Left"]
    if stage in ("5", "6"):
        names.append("Skill Eight Right")
    return names


def name_of(slug):
    return next(name for name in skill_names("6") if ids.slug(name) == slug)


def step_count(stage, slug):
    if slug not in [ids.slug(n) for n in skill_names(stage)]:
        return 0
    if stage == "5" and slug == "skill-eight-left":
        return 0
    if stage == "2" and slug == "skill-seven":
        return 4
    return BASE_STEPS[slug]


def step_name(slug, n):
    return "%s, step %d" % (name_of(slug), n)


def nearest(stage, slug, direction):
    index = ORDER.index(stage) + direction
    while 0 <= index < len(ORDER):
        if step_count(ORDER[index], slug):
            return ORDER[index]
        index += direction
    return None


def link_refs(stage, slug, direction):
    other = nearest(stage, slug, direction)
    if other is None:
        return []
    refs = [{"stage": other, "skill": slug, "n": n, "name": step_name(slug, n)}
            for n in range(1, step_count(other, slug) + 1)]
    if (stage, slug, direction) == ("1", "skill-two", -1):
        refs[-1] = {"stage": other, "name": step_name(slug, refs[-1]["n"])}  # resolved by name
    return refs


def make_steps(stage, slug):
    count = step_count(stage, slug)
    steps = []
    for n in range(1, count + 1):
        step = {"n": n, "name": step_name(slug, n),
                "description": "Synthetic description of %s, step %d." % (name_of(slug).lower(), n)}
        if slug == "skill-one" and n == 1:
            step["depths"] = ["shallow"]
        if slug == "skill-one" and n == 3:
            step["submerges"] = True
        if slug == "skill-four" and stage in ("1", "2", "3") and n >= 2:
            step["reachBottom"] = True
        if slug == "skill-four" and stage in ("4", "5", "6"):
            step["depths"], step["headfirst"] = ["deep"], True
        if stage == "2" and slug == "skill-seven":
            step["depths"] = ["medium", "deep"]
            if n <= 3:
                step["equipment"] = [["life-jacket", "float-belt"]]
            else:
                step["nearWall"] = True
        if stage == "3" and slug == "skill-seven" and n == 1:
            step["depths"], step["nearWall"] = ["medium", "deep"], True
        if n == count:
            if (stage, slug) == ("2", "skill-two"):
                step["measure"] = {"kind": "distance", "value": 10, "unit": "ft", "preschoolValue": 5}
            elif (stage, slug) == ("3", "skill-six"):
                step["measure"] = {"kind": "time", "value": 60, "unit": "s", "preschoolValue": 30}
            elif slug == "skill-five":
                step["measure"] = {"kind": "distance", "value": 15, "unit": "yd"}
        steps.append(step)
    return steps


def activity(name, description, page, **fields):
    entry = {"name": name, "description": description, "ages": fields.pop("ages", ["P", "S", "A"]), "page": page}
    entry.update(fields)
    return entry


def hoop_leap(page, variant):
    """A jump whose printed Variation goes in head first: one description, two entries, the
    dive one marked headfirst (and, in Stage 2, variant "dive")."""
    text = "Leap through a floating hoop. Variation: go through it head first."
    dive = activity("Hoop Leap", text, page, equipment=[["hoop"]], depths=["deep"], headfirst=True, submerges=True,
                    tags=["dive"])
    if variant:
        dive["variant"] = variant
    return [activity("Hoop Leap", text, page, equipment=[["hoop"]], submerges=True, tags=["jump"]), dive]


def make_activities(stage, slug, page):
    word = name_of(slug)[len("Skill "):]
    acts = [activity("%s Drill" % word, "Practise %s with a partner, then alone." % name_of(slug).lower(), page,
                     tags=["drill"]),
            activity("%s Relay" % word, "A relay race that repeats %s across the pool." % name_of(slug).lower(), page,
                     ages=["S", "A"], equipment=[["kickboard"]], tags=["game"])]
    special = {
        ("1", "skill-one"): [activity("Bob Game", "Bob up and down five times.", page, submerges=True, tags=["bob"])],
        ("2", "skill-one"): [activity("Dip Game", "Dip the chin, then the nose.", page, submerges=True)],
        ("3", "skill-five"): [activity("Float Game", "Float while holding a flotation device.", page,
                                       equipment=[["flotation-device"]], equipmentOptional=["watering-can"])],
        ("1", "skill-two"): [activity("Twin Game", "Glide toward a toy on the bottom.", page,
                                      equipment=[["small-toys"]], submerges=True)],
        ("1", "skill-eight-left"): [activity("Twin Game", "Glide on the back toward a spot on the ceiling.", page)],
        ("1", "skill-three"): [activity("Circle Game", "Jump through a hoop held on the surface.", page,
                                        equipment=[["hoop"]], submerges=True, tags=["jump"]),
                               activity("Circle Game", "Variation: dive through the hoop instead.", page,
                                        equipment=[["hoop"]], depths=["deep"], headfirst=True, submerges=True,
                                        tags=["dive"], idSuffix="dive"),
                               activity("Shared Game", "Everyone plays together in a circle.", page, tags=["game"])],
        ("1", "skill-four"): [activity("Shared Game", "Everyone plays together in a circle.", page, tags=["game"])],
        ("2", "skill-three"): [activity("Shared Game", "Everyone  plays together in a circle.", page, tags=["game"])],
        ("1", "skill-six"): [activity("Deep Game", "Jump into deep water and swim back to the wall.", page,
                                      equipment=[["hoop"]], equipmentOptional=["pool-noodle"],
                                      depths=["medium", "deep"], submerges=True, tags=["deep", "jump"])] +
                            hoop_leap(page, None),
        ("2", "skill-six"): hoop_leap(page, "dive"),
        ("1", "skill-seven"): [activity("Wade Game", "Walk across where everyone can stand.", page, ages=[],
                                        depths=["shallow"], flotationOption=True)],
        ("1", "skill-five"): [activity("Toy Hunt", "Fetch toys from the bottom and set them on a kickboard.", page,
                                       ages=["P", "S"], equipment=[["kickboard"], ["small-toys"]], reachBottom=True,
                                       submerges=True)],
        ("2", "skill-two"): [activity("Noodle Race", "Race holding a noodle or a rescue tube.", page,
                                      equipment=[["pool-noodle", "rescue-tube"]])],
    }
    acts += special.get((stage, slug), [])
    if slug == "skill-four":
        if stage in ("1", "2", "3"):
            acts.append(activity("Splash Game", "Jump in and make a splash.", page, submerges=True, tags=["jump"]))
        elif stage in ("4", "5", "6"):
            acts.append(activity("Splash Game", "Dive in and make a splash.", page, depths=["deep"], headfirst=True,
                                 submerges=True, tags=["dive"]))
    return acts


def make_skill(stage, order, name):
    slug = ids.slug(name)
    return {
        "slug": slug, "name": name, "order": order, "isBenchmarkSequence": slug == "skill-four",
        "prerequisite": link_refs(stage, slug, -1), "steps": make_steps(stage, slug),
        "advanced": link_refs(stage, slug, 1),
        "activities": make_activities(stage, slug, 2 * order + 2),
        "pages": {"progression": 2 * order + 1, "activities": 2 * order + 2},
    }


def drill(slug):
    return "%s Drill" % name_of(slug)[len("Skill "):]


def make_template(stage, n, total):
    long_lesson = total == 40
    intro_seven = "skill-eight-right" if stage == "5" else "skill-eight-left"
    blocks = [{"kind": "welcome", "minutes": 5 if n == 1 else 3, "activities": ["Hello Game", "Name Song"],
               "notes": ["Say hello."]}]
    warm_minutes = (5 if long_lesson else 8) if n == 1 else (10 if long_lesson else 5)
    if stage == "4" and n <= 4:
        blocks.append({"kind": "warmUp", "minutes": warm_minutes, "skills": [], "notes": ["Warm up with five bobs."],
                       "activities": ["Bob Game", "Dip Game", "Float Game"]})
    else:
        blocks.append({"kind": "warmUp", "minutes": warm_minutes, "skills": [{"slug": "skill-one", "steps": [1, 4]}],
                       "activities": ["One Drill", "One Relay"]})
    if n == 1:
        blocks.append({"kind": "review", "minutes": 0, "skills": [], "notes": ["No skills to review today."]})
    else:
        review = {"kind": "review", "minutes": 2, "minutesPrinted": "1–2 mins." if long_lesson else "1-2 mins."}
        if n == 2:
            review.update(skills=[{"slug": "skill-two"}], activities=["Two Drill"])
        elif n in (3, 4):
            review.update(skills=[{"slug": "skill-three"}, {"slug": "skill-five"}], activities=["Three Drill", "Five Relay"])
        else:
            review.update(skills=[{"slug": "any"}], notes=["Practise what needs work."])
        blocks.append(review)
    intro = {"kind": "introduce", "minutes": (20 if long_lesson else 7) if n == 1 else (15 if long_lesson else 10)}
    if n == 1:
        intro.update(skills=[{"slug": "skill-two", "steps": [1, 3]}, {"slug": "skill-three", "steps": [1, 2]}],
                     activities=["Two Drill", "Three Relay"] + (["Twin Game"] if stage == "1" else []))
    elif n == 2:
        intro.update(skills=[{"slug": "skill-five"}], activities=["Five Drill"] + (["Toy Hunt"] if stage == "1" else []))
    elif n == 3:
        intro.update(skills=[{"slug": "skill-six", "steps": [1, 3]}], activities=["Six Drill", "Six Relay"])
    elif n == 4:
        intro.update(skills=[{"slug": "skill-seven"}], activities=["Seven Drill"])
    elif n == 7:
        intro.update(skills=[{"slug": intro_seven}], activities=[drill(intro_seven)])
        if stage in ("1", "3"):
            intro.update(equipment=[["life-jacket"]], notes=["Wear life jackets first, then take them off."])
        if stage == "3":
            intro["depths"] = ["medium", "deep"]
    else:
        intro.update(skills=[{"slug": "any"}], notes=["Practise what needs work."])
    blocks.append(intro)
    blocks.append({"kind": "topic", "minutes": 5, "topicCode": ids.topic_code(stage, n)})
    if n < 8:
        blocks.append({"kind": "wrapUp", "minutes": 5, "skills": [{"slug": "skill-four", "steps": [1, 4]}],
                       "activities": ["Four Drill", "Splash Game"] if stage not in ("A", "B") else ["Four Drill"],
                       "notes": ["Celebrate progress."]})
    else:
        blocks.append({"kind": "wrapUp", "minutes": 5, "skills": [],
                       "notes": ["Play a group game with everyone.", "Let the swimmers choose."]})
    return {"n": n, "minutesTotal": total, "pages": [2 * n - 1, 2 * n], "blocks": blocks}


def make_tracker(stage):
    rows = []
    for name in skill_names(stage):
        slug = ids.slug(name)
        count = step_count(stage, slug)
        if not count or (stage == "6" and slug == "skill-eight-right"):
            continue
        if stage == "6" and slug == "skill-eight-left":
            rows.append({"text": "Skill Eight, left or right", "rule": "any", "preschool": None,
                         "steps": [{"skill": "skill-eight-left", "n": 2}, {"skill": "skill-eight-right", "n": 3}]})
            continue
        preschool = {("2", "skill-two"): "5 ft. preschool", ("3", "skill-six"): "30 secs. preschool"}.get((stage, slug))
        rows.append({"text": step_name(slug, count), "steps": [{"skill": slug, "n": count}], "rule": "all",
                     "preschool": preschool})
    return rows


def make_work(stage):
    name, group, ages, minutes = STAGES[stage]
    return {
        "format": A.WORK_FORMAT,
        "stage": {"id": stage, "name": name, "group": group, "ageGroups": ages, "lessonMinutes": minutes,
                  "warmUpSkill": "skill-one", "wrapUpSkill": "skill-four",
                  "milestones": ["Milestone one.", "Milestone two.", "Milestone three."]},
        "skills": [make_skill(stage, order, skill) for order, skill in enumerate(skill_names(stage), 1)],
        "greeting": {"activities": [activity("Hello Game", "Say hello and your name.", 1),
                                    activity("Name Song", "Sing everyone's name.", 2, ages=["P", "S"], tags=["song"])],
                     "pages": [1, 2]},
        "topics": [{"code": ids.topic_code(stage, n), "n": n, "name": "Topic %s" % (WORDS + ["Eight"])[n - 1],
                    "summary": "Synthetic topic summary.", "prompts": ["Ask question %d: expect answer %d." % (n, n)],
                    "notes": ["Bring a prop."] if n == 6 else [], "page": 20 + n} for n in range(1, 9)],
        "lessonTemplates": [make_template(stage, n, minutes) for n in range(1, 9)],
        "trackerRows": make_tracker(stage),
        "sources": {"library": "synthetic-library-%s.pdf" % stage, "guide": "synthetic-guide-%s.pdf" % stage,
                    "trackerPages": "1-2", "overviewPages": "1"},
        "uncertain": [],
    }


VIDEOS = {"source": "synthetic", "videos": [
    {"page": "YSL Videos", "title": "Welcome to the Synthetic Program-HD", "url": "https://vimeo.com/100000000",
     "videoId": "100000000", "provider": "Vimeo"},
    {"page": "YSL Videos", "title": "Skill One (Stages 1 & 2)", "url": "https://vimeo.com/100000001",
     "videoId": "100000001", "provider": "Vimeo"},
    {"page": "YSL Videos", "title": "Skill Two & Skill Three (Stages A & B)", "url": "https://vimeo.com/100000002",
     "videoId": "100000002", "provider": "Vimeo"},
    {"page": "YSL Videos", "title": "Skill Four (Stages 4-6)", "url": "https://vimeo.com/100000003",
     "videoId": "100000003", "provider": "Vimeo"},
    {"page": "YSL Videos", "title": "Skill Eight (Stage 5)", "url": "https://vimeo.com/100000004",
     "videoId": "100000004", "provider": "Vimeo"},
    {"page": "YSL Videos", "title": "Skill Five and Skill Six L3", "url": "https://vimeo.com/100000005",
     "videoId": "100000005", "provider": "Vimeo"},
    {"page": "SAW Videos", "title": "Skill One", "url": "https://vimeo.com/album/1/video/100000001",
     "videoId": "100000001", "provider": "Vimeo"},
    {"page": "YLG Videos", "title": "Lifeguard Synthetic", "url": "https://vimeo.com/100000009/abc123",
     "videoId": 100000009, "provider": "Vimeo"},
]}

LOCAL = {"format": "local/1",
         "activities": [{"id": "local-relay", "name": "Local Relay", "description": "A relay made up at our own pool.",
                         "ages": ["S", "A"], "equipment": [["foam-dice"]], "equipmentOptional": [], "submerges": False,
                         "tags": ["game"], "skillIds": ["1.skill-one"], "source": "local"}],
         "equipment": [{"id": "foam-dice", "name": "Foam dice", "aliases": [], "source": "local", "kind": "item"}]}

SAFETY = [{"id": "single-inhalation", "text": "Made-up rule one: one breath before each time under.",
           "tags": ["submerges"]},
          {"id": "deck-diving", "text": "Made-up rule two: headfirst entries only in deep water.", "tags": ["dive"]}]


def main():
    for stage in ORDER:
        A.write_text_atomic(HERE / "_work" / A.work_file_name(stage), A.dumps(make_work(stage)))
    A.write_text_atomic(HERE / "videos-source.json", A.dumps(VIDEOS))
    A.write_text_atomic(HERE / "local.json", A.dumps(LOCAL))
    A.write_text_atomic(HERE / "_work" / A.SAFETY_FILE, A.dumps(SAFETY))
    result = A.assemble(HERE / "_work", HERE, videos_path=HERE / "videos-source.json")
    for item in result.problems:
        print(item)
    for note in result.notes:
        print("note:", note)
    print("ok" if result.ok else "FAILED", "wrote:", ", ".join(result.written))
    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main())
