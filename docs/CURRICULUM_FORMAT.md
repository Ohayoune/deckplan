# Curriculum data — the YMCA V6 program as JSON

> **2026-09-12.** Still the data contract under `docs/REDESIGN.md`. References here to `SPEC.md`, `PLANNER.md`, `SESSION_PLAN_FORMAT.md`, `PROGRESS_TRACKING.md` and the v1 test ids (A1–A14 aside, which stay in force) point to the archived copies in `docs/v1/`; the planner behaviour they describe (deep-water clearance, safety rules, scoring) is gone.

What the app knows about swimming comes from one place: the YMCA Swim Lessons V6 Instructor Toolkit, which is what the "YMCA Swim Lessons Instructor V6" Yapp (Yapp id `YSLSWIM`) distributes. This document says what is in the toolkit, how it is structured, how the app encodes it, and how to transcribe and validate it (milestone M1).

## 1. Sources

Everything below was pulled from the Yapp's public preview and the toolkit PDFs it links to, and is saved under `reference/ymca-v6/` (PDFs, extracted text, and `yapp-app-inventory.json` with the app's full document and video list). © 2016 YMCA of the USA — see §6.

The Yapp has five tabs: **Welcome**, **Toolkit** (35 PDFs), **YSL Videos** (25 skill videos on Vimeo), **SAW Videos** (11 Safety Around Water videos), **More** (YLG videos, pilot photos, trainer news feed, instructor chat). The Toolkit documents, by role:

| Document | Role | Used for |
|---|---|---|
| Skill & Topic Library, one per stage (A, B, 1–6; ~25 pages each) | The exercise library | Skills, steps, activities, topics |
| Lesson Guides, one per stage (16 pages: 8 lessons × 2) | The day-by-day lesson plans; the owner's branch teaches from them | Lesson templates, block minutes, suggested activities; with the Stage Overview, the default session plan |
| Stage Overview (16 pages) | One-page-per-stage summary of the 8 lessons | Default session plan, with the Lesson Guides (SESSION_PLAN_FORMAT.md §3) |
| Progress Tracker (16 pages) | Class sheet: swimmers × benchmark skills, 8-lesson attendance, topics, next stage; the owner's working sheet | Each stage's tracker rows (`trackerRows`, §3); the Progress Tracker report |
| Mid-Session Report (16 pages) | Per-swimmer report after lesson ⌈N/2⌉ (lesson 4 of 8); handed in | The Mid-Session Report, printed on the toolkit's own page (§6) |
| Certificates of Achievement | Per swimmer at the end of the session, with "My next stage should be"; handed in | The Certificate, printed on the toolkit's own page (§6) |
| Session Planner (2 pages) | Blank 8-lesson grid: Lesson / Skills / Activities / Topic | The session plan's shape |
| Skill Continuums (Infant & Toddler / Preschool; School-Age / Teen & Adult) | Benchmarks per stage per age band | Age variants (D4) |
| Program Overview | Stages, groups, pathways, benchmark sequences | Stage metadata |
| Safety & Character Topics | All topics with discussion text | Topic prompts |
| Home Activities | Per-skill practice at home | Suggestions in the parent summary, never on the handed-in forms (PROGRESS_TRACKING.md §7) |
| Welcome Letters, Toolkit Introduction | Family communication | Not encoded |
| Aquatic Conditioning, Endurance Sports & Games (library, lesson guides, tracker) | Add-on modules | Later; same format (PDFs in `reference/ymca-v6/modules/`) |
| Complete Toolkit for app (459 pages) | All of the above in one PDF, same pages | Reading on a phone or iPad; transcribe from the per-document PDFs |

## 2. How the source is structured

**Skill & Topic Library (per stage).** Page 1 "Teaching this stage" (three milestones, the stage's `milestones`), then one skill after another. Each skill has:

- a **progression page** with three columns: **PREREQUISITE** (the previous stage's steps for this skill, or "No prerequisite for this stage"), **STAGE PROGRESSION** (numbered steps 1–4 with a name and a one-to-three-sentence description; the last one is the stage benchmark), and **ADVANCED** (the next stage's first steps, "See 2 / Moving Along");
- an **activities page**: 10–15 named activities with a short description and age tags P (Preschool), S (School Age), A (Teen & Adult); untagged activities suit everyone.

The Greeting "skill" holds setting-expectations items (Tugboat Hello, Thunder Handshake, Castle Hello), relationship games (Snowflake Welcome, Iceberg Wave…) and water-adjustment songs. It has no steps, so it is not a skill in the JSON: its entries are the stage's `greetingActivityIds` (§3). The last section, **Safety & Character Topics**, has eight topics `<stage>.1`–`<stage>.8`, each a heading and discussion prompts with expected answers.

**Lesson Guide (per stage).** The day-by-day guide: eight lessons, 30 minutes each in A–3 and 40 in 4–6. The owner's branch teaches from these guides as printed, with the Stage Overview as the one-page summary, so the two together are the app's default session plan (SPEC D6, SESSION_PLAN_FORMAT.md §3); a branch copy is needed only if the branch changes a lesson (inputs/README q1). Each lesson is two pages with six timed blocks:

| Block | A–3, lesson 1 | A–3, lessons 2–8 | 4–6, lesson 1 | 4–6, lessons 2–8 |
|---|---|---|---|---|
| Welcome (Greeting) | 5 | 1–2 | 5 | 1–2 |
| Warm-up | 8 | 3 | 5 | 3 |
| Review skills | 0 | 5 | 0 | 10 |
| Introduce & Sequence (A–3) / Introduce & Practice (4–6) | 7 | 10 | 20 | 15 |
| Topic `<stage>.<n>` | 5 | 5 | 5 | 5 |
| Wrap-up | 5 | 5 | 5 | 5 |

(Lesson 1 of Stages 5–6 differs: it opens with a Review of the previous stage's resting stroke, so the table's Review 0 and Introduce 20 do not hold there (both print Review 10 and Introduce 10), and Stage 6 prints its Welcome as a range of one to two minutes with an 8-minute Warm-up. Transcribe each lesson's printed minutes — do not assume the table; a printed range is transcribed as its upper value, §5 step 5.) The owner's branch runs every lesson at 30 minutes, every stage: transcribe the Stage 4–6 guides at their printed 40 minutes anyway and let the planner scale them (SPEC D22, PLANNER.md §4, test C9). Each block names its skills with the steps to work through and three activities from the stage’s Skill & Topic Library. The wrap-up of guide lessons 1–7 is the stage's wrap-up skill — the benchmark sequence in Stages 1–3 (Jump and return on your own; Jump, swim, turn, swim, grab in Stage 3), Dive in 4–6, Water entry in A–B; lesson 8’s wrap-up is a group game the swimmers pick, with no skill, no groups and no marks. Some later blocks are a review slot the instructor fills — no skill and no activities, only an instruction to work on what needs improvement — the slots this app fills from marks (`"any"` in the session plan). They are in guide lessons 5–8 of Stage 1, 7–8 of Stage 2 and 6–8 of the other stages; the guide lessons whose Introduce is only "any" are 5, 6 (and 8) in Stage 1, 7 (and 8) in Stage 2, and 6, 7 (and 8) in the other stages. A few blocks set the water or the equipment: life jackets for Swim, float, swim in 1.7, 2.6 and 3.5, and deep water in 3.5 (§5 step 5). Stage 4's lessons 1–4 warm up with a Submerge block although the Stage 4 library has no Submerge skill (§4.3, §5 step 5). Lesson 8, the last, stays the last lesson in a session of any length N: a shorter session drops guide lessons by SESSION_PLAN_FORMAT.md §3's rule, the "any"-only lessons first, and a longer one adds extra lessons on guide lesson 7's template (PLANNER.md §4).

**Progress Tracker (per stage).** Columns: swimmer names, six per sheet; rows: the stage's benchmark skills with their benchmark text — one row per benchmark, except that Stage 5 has no elementary backstroke row and Stage 6 prints one resting-stroke row for its two resting strokes (`trackerRows`, §3); each cell has the two marks "taught, but yet to be achieved" and "achieved"; an attendance grid 1–8 (the form prints 8; the app's grid has N boxes); the eight topics as checkboxes; "Next stage should be" with the current and next stage and "Other". It is the owner's working sheet. The Mid-Session Report and the Certificate of Achievement are the per-swimmer forms the owner hands in: the tracker's rows as checkboxes, "My next stage should be" (current or next stage), "I'm awesome at / I can improve on", and on the Certificate the stage's eight topic names (PROGRESS_TRACKING.md §6).

## 3. Encoding

One JSON file per stage plus shared files. All ids are lowercase, stable, and never reused; marks reference step ids forever.

```
curriculum/version.json          { "format": "curriculum/1", "version": "2026.09", "source": "YMCA Swim Lessons V6 Instructor Toolkit (Yapp YSLSWIM)" }
curriculum/stages/1.json         one Stage with its skills, steps, topics, lessonTemplates
curriculum/activities.json       every activity once (activities recur across stages)
curriculum/videos.json           the Yapp's videos with stage and skill links
curriculum/safety.json           the libraries' safety rules the plan prints, each { id, text, tags[] } (PLANNER.md §8)
curriculum/equipment.json        the equipment catalog: items (one toggle each) and groups (SPEC D28)
curriculum/local.json            your additions, local/1 (tracked in git; bundled read-only into your build): activities and equipment items
```

Id conventions: stage `A|B|1..6`; skill `<stage>.<skill-slug>` (`1.front-glide`); step `<stage>.<skill-slug>.<n>` (`1.front-glide.3`); activity `<slug>` (`meteor-torpedo`), and a second entry with the same name gets a suffix saying what differs (`koala-launch`, §5 step 3); equipment `<slug>` (`pool-noodle`); topic `<stage>.<n>`; video `vimeo:<id>`. The loader assembles `Curriculum { version, stages[], activities[], equipment[], safety[], videos[] }` (SPEC §7) from these files and `local.json`. In the files a skill's steps nest in it (`steps[]`); the loader gives each Step its `skillId` and each Skill its `stepIds[]`.

```json
{
  "id": "1", "name": "Getting Comfortable", "group": "Swim Basics",
  "ageGroups": ["preschool", "schoolAge", "teen", "adult"],
  "lessonMinutes": 30,
  "warmUpSkill": "1.submerge", "wrapUpSkill": "1.jump-and-return",
  "milestones": ["Feeling at home in the water with a helper close by", "…"],
  "greetingActivityIds": ["tugboat-hello", "thunder-handshake", "castle-hello", "snowflake-welcome", "sunflower-name-circle", "iceberg-wave", "heron-roll-call", "…"],
  "trackerRows": [
    { "text": "Submerge on your own, farther, near the wall", "stepIds": ["1.submerge.4"], "rule": "all" },
    { "text": "Front glide on your own, farther, 5 feet", "stepIds": ["1.front-glide.4"], "rule": "all" },
    "…"
  ],
  "skills": [
    {
      "id": "1.front-glide", "name": "Front Glide", "order": 2, "isBenchmarkSequence": false,
      "prerequisiteStepIds": ["B.front-tow.2"],
      "steps": [
        { "id": "1.front-glide.1", "n": 1, "name": "Front glide with hands-on help",
          "description": "Front glide with hands-on help. A helper stays within reach.",
          "depths": ["shallow"] },
        { "id": "1.front-glide.2", "n": 2, "name": "Front glide with a helper close by, near the wall",
          "description": "Front glide with a helper close by, near the wall. Rest between tries.",
          "depths": ["shallow"] },
        { "id": "1.front-glide.3", "n": 3, "name": "Front glide, assisted, to wall, one arm's length, feet on bottom",
          "description": "…", "depths": ["shallow"] },
        { "id": "1.front-glide.4", "n": 4, "name": "Front glide on your own, farther, 5 feet",
          "description": "Front glide on your own, farther, 5 feet. Cheer each try.",
          "measure": { "kind": "distance", "value": 5, "unit": "ft" }, "depths": ["shallow"] }
      ],
      "benchmarkStepId": "1.front-glide.4",
      "advancedStepIds": ["2.front-glide.1", "2.front-glide.2", "2.front-glide.3", "2.front-glide.4"],
      "activityIds": ["manatee-glide", "lighthouse-express", "thunder-launch", "castle-torpedo", "dragon-launch",
                      "meteor-torpedo", "penguin-slide", "comet-rocket-ride", "pinwheel-slide",
                      "puffin-rocket-ride", "rocket-glide", "jellybean-express"],
      "videoIds": ["vimeo:172429568"]
    }
  ],
  "topics": [
    { "code": "1.5", "n": 5, "name": "Being Kind",
      "summary": "Share one idea about staying warm and try it during the lesson.",
      "prompts": ["Who watches you when you are near water?", "What should you do before getting in?"],
      "notes": [] }
  ],
  "lessonTemplates": [
    { "n": 5, "minutes": 30, "blocks": [
      { "kind": "welcome",   "minutes": 3,  "notes": ["Say each swimmer’s name.", "Check in with quieter swimmers.", "Show today’s skills before trying them.", "Demonstrate once, slowly.", "Start in the shallowest spot."], "activityIds": ["snowflake-welcome", "tugboat-hello", "iceberg-wave"] },
      { "kind": "warmUp",    "minutes": 5,  "skillIds": ["1.submerge"], "stepRange": [1, 4], "activityIds": ["otter-bubbles", "snowflake-hide-and-seek", "rainbow-treasure-hunt"] },
      { "kind": "review",    "minutes": 2,  "skillIds": ["1.front-float", "1.back-glide"] },
      { "kind": "introduce", "minutes": 10, "skillIds": ["any"], "notes": ["Recap what the group practised."] },
      { "kind": "topic",     "minutes": 5,  "topicCode": "1.5" },
      { "kind": "wrapUp",    "minutes": 5,  "skillIds": ["1.jump-and-return"], "stepRange": [1, 4], "activityIds": ["canoe-climb", "rainbow-leap", "moonbeam-hop"], "notes": ["Reflect on and celebrate today's progress."] }
    ] }
  ]
}
```

Stage fields beyond the skills: `milestones[]` — the three milestones from the library’s teaching page for the stage, verbatim; `greetingActivityIds[]` — the library's Greeting entries in page order (the Welcome block picks from them, PLANNER.md §5.1); `trackerRows[]` — the Progress Tracker's rows in its order, each `{ text, stepIds[], rule: "all" | "any" }`: the row's text (§4.2), the benchmark steps it stands for, and whether all or any of them must be achieved. Every row but one is `rule` "all" over one benchmark, whose step name is its text; Stage 6's resting-stroke row stands for both its resting strokes: `{ "text": "<the row as the Tracker prints it>", "stepIds": ["6.elementary-backstroke.3", "6.resting-stroke-sidestroke.3"], "rule": "any" }`. The next-stage recommendation and the reports read these rows, not skills (PROGRESS_TRACKING.md §5–§6; A7). A topic's `notes[]` holds the props and set-up it asks for (a mannequin, a toy phone, first-aid role-play supplies), never catalog equipment; `[]` when it asks for none.

A skill with no stage progression in its stage has no steps (`steps: []`, `benchmarkStepId: null`) and no tracker row: Stage 5's Elementary Backstroke, whose page has a Prerequisite column (Stage 4's steps) and an Advanced column (Stage 6's) but, under Stage Progression, only a note that it is not a key skill for the stage. Its links still go in `prerequisiteStepIds` and `advancedStepIds`, and the links around it pass it by: Stage 6's elementary backstroke takes Stage 4's steps as prerequisites (§5 step 2). Stage 5's guide lesson 1 reviews it at Stage 4's 15 yd. (SESSION_PLAN_FORMAT.md §3).

Lesson-template blocks carry two more fields where a guide sets them for one lesson (§5 step 5):

- `depths` — the water the guide sets for this block's steps in this lesson. It replaces those steps' own `depths` for this lesson only: Stage 3 guide lesson 5 runs Swim, float, swim in deep water, `["medium", "deep"]`.
- `equipment` — safety equipment the guide prescribes, in the activity shape: life jackets for Swim, float, swim in 1.7, 2.6 and 3.5, `[["life-jacket"]]`. It never filters: with the item switched off the instruction stays and the plan warns (SPEC D28, test G7). Life jackets worn in the block give its swimmers deep-water clearance while `life-jacket` is on for the lesson; switched off, they give none (SPEC D23, PLANNER.md §8).

A block with no skill has no `skillIds`: Welcome, Topic, the warm-up of Stage 4 guide lessons 1–4, and the group-game wrap-up of every guide lesson 8. Below: Stage 3 guide lesson 5's Introduce, Stage 4 guide lesson 2's warm-up (3 minutes in lessons 2–4, 5 in lesson 1) and a guide lesson 8's wrap-up.

```json
{ "kind": "introduce", "minutes": 10, "skillIds": ["3.swim-float-swim"],
  "depths": ["medium", "deep"], "equipment": [["life-jacket"]],
  "notes": ["Everyone keeps a life jacket on for this block.",
            "Take the life jackets off for the last try.", "…"],
  "activityIds": ["otter-journey", "beaver-trip", "tugboat-swim"] }
{ "kind": "warmUp", "minutes": 3, "notes": ["Submerge: do 5–10 bobs."],
  "activityIds": ["thunder-game", "rainbow-treasure-hunt", "lantern-countdown"] }
{ "kind": "wrapUp", "minutes": 5,
  "notes": ["Mention one safety habit.",
            "Ask what they want to try next time."] }
```

Activities (`activities.json`):

```json
[
  { "id": "comet-rocket-ride", "name": "Comet Rocket Ride", "ages": ["P", "S", "A"],
    "equipment": [["pool-noodle", "rescue-tube", "rope"]], "submerges": true,
    "description": "…each swimmer holds a rope, a rescue tube or a pool noodle. …",
    "skillIds": ["1.front-glide", "2.front-glide"], "source": "ymca" },
  { "id": "toy-rescue-swim", "name": "Toy Rescue Swim", "ages": ["S"],
    "equipment": [["kickboard"], ["small-toys"]], "submerges": false,
    "description": "…balance a toy on a kickboard and glide on your back…",
    "skillIds": ["1.back-glide", "2.back-glide"], "source": "ymca" },
  { "id": "moonbeam-hop", "name": "Moonbeam Hop", "ages": ["P", "S", "A"],
    "equipment": [], "depths": ["shallow"], "flotationOption": true, "submerges": false,
    "description": "Have students stand in shallow water. …",
    "skillIds": ["1.jump-and-return", "2.jump-and-return"], "source": "ymca" },
  { "id": "volcano-ladder", "name": "Volcano Ladder", "ages": ["P", "S", "A"],
    "equipment": [["hoop"]], "equipmentOptional": ["pool-noodle"], "depths": ["medium", "deep"],
    "submerges": true, "tags": ["jump", "deep"],
    "description": "Swimmers take turns going through a hoop held out in deep water. …",
    "skillIds": ["1.water-exit", "1.jump-and-return"], "source": "ymca" }
]
```

The fields that are judgment rather than text (§5 step 3):

- `equipment` — requirement groups, all required; each group is an array of catalog ids, any one of which satisfies it. `[["pool-noodle", "rescue-tube", "rope"]]` is a noodle, a rescue tube or a rope; `[["kickboard"], ["small-toys"]]` is a kickboard and a toy; `[]` is no equipment. The planner places an activity only when every group has an item switched on for the lesson (SPEC D28).
- `equipmentOptional` — ids the description makes optional ("the wall or a kickboard", "if needed") or names only in a Variation. Never filters; listed on the plan as "(optional)".
- `depths` — the zones the activity can run in, a subset of `shallow`, `medium`, `deep`; missing = any zone. `headfirst: true` — a dive: needs the deep zone and diving on. `reachBottom: true` — the swimmer touches or fetches from the bottom; the plan notes it, zones unchanged. `flotationOption: true` — may run outside its zones when swimmers use flotation, only with a flotation item on, and the plan says so. The flags are omitted when false.
- `submerges` — the swimmer holds their breath and submerges, face or head under, as the description says (steps carry it too, below). A placed activity or step with `submerges: true`, or a skill-less warm-up, prints the single-inhalation rule once, in the plan's `safety[]`: `safety.json`'s `single-inhalation`, tagged `submerges`, whose text is exactly the libraries' sentence (below; PLANNER.md §8, test G1). `tags` match every other rule — the rest of `safety.json` and the pool profile's `rules[]` (`{ id?, text, tags[] }`, the id optional there): such a rule prints in the notes of each block whose activity shares one of its tags (`jump`, `dive`, `deep`, `noodle`…).

Safety rules (`safety.json`):

```json
[
  { "id": "single-inhalation", "tags": ["submerges"],
    "text": "One breath at a time: swimmers take a single normal breath before each time they go under, never several deep breaths in a row." }
]
```

The test sample `examples/curriculum.stage1.sample.json` is a compact single-stage form of these files: a top-level `version` ("sample-2026.09") stands in for `version.json`'s and a top-level `safety` for `safety.json`; its skills carry `videoTitles` in place of `videoIds`; its activities leave out `skillIds`, which are derived from `skills[].activityIds` and `greetingActivityIds`, and `source`, which is `"ymca"` for every entry.

Steps carry `depths`, `headfirst`, `reachBottom`, `submerges` and `equipment` the same way, from their own descriptions, and one flag of their own: `nearWall: true` — the step is done at or within arm's reach of the wall, as its description says (Stage 2 Tread water 4, Stage 3 Tread water 1). A step's `equipment` is what the step itself needs, as requirement groups: Stage 2 Tread water steps 1–3 are done wearing a life jacket or float belt. When a group has no item on for the lesson, the step is listed under "can't practise today" with the reason (PLANNER.md §8).

```json
{ "id": "1.submerge.3", "n": 3, "name": "Submerge on your own",
  "description": "Submerge entire head underwater. …", "submerges": true }
{ "id": "2.tread-water.1", "n": 1, "name": "Tread water with hands-on help, using a life jacket, 10 seconds",
  "description": "In a flotation device — a life jacket or a float belt — float upright in deep water. …",
  "depths": ["medium", "deep"], "equipment": [["life-jacket", "float-belt"]] }
{ "id": "2.tread-water.4", "n": 4, "name": "Tread water on your own, farther, near the wall, 10 seconds",
  "description": "In deep water and within arm's reach of wall, …", "depths": ["medium", "deep"], "nearWall": true }
{ "id": "4.dive.1", "n": 1, "name": "Dive on your own",
  "description": "Sit at the edge of the deep end, arms stretched over the head. …", "depths": ["deep"], "headfirst": true }
```

The toolkit teaches its deep-water steps in deep water, with its own supports. So a step of the swimmer's own stage that is tagged overhead or headfirst is placed in the medium or deep zone without deep-water clearance, under the condition the step gives: at the wall or within arm's reach of it where the step has `nearWall`, wearing the device its `equipment` names, otherwise within arm's reach of an adult — the toolkit's words (Lesson Guide A, p. 8), printed "within arm's reach of an adult (the instructor)". The plan prints the condition on the block, and a headfirst step still needs the deep zone and diving on (SPEC D23, PLANNER.md §8; owner to confirm, `docs/DECISIONS_LOG.md`). Set `nearWall: true` where the description puts the swimmer at or within arm's reach of the wall, keep that wording verbatim in the description, and put a device the step is done in into `equipment`.

Measured steps use `measure` with `preschoolValue` where the Progress Tracker prints a preschool variant (`"Front glide on your own, farther, 10 feet (5 ft. preschool)"` → `{ "kind": "distance", "value": 10, "unit": "ft", "preschoolValue": 5 }`).

**Equipment catalog** (`equipment.json`, SPEC D28). One entry per thing the activity descriptions ask for — about 30 — each `Equipment { id, name, aliases[], source, kind, anyOf[] }`:

```json
[
  { "id": "pool-noodle", "name": "Pool noodle", "aliases": ["noodle", "noodles", "pool noodles"], "source": "ymca", "kind": "item" },
  { "id": "small-toys", "name": "Small toys", "aliases": ["toy", "toys", "sinking toys", "floating toys", "other objects"], "source": "ymca", "kind": "item" },
  { "id": "barbell", "name": "Barbell", "aliases": ["barbells", "short barbell"], "source": "ymca", "kind": "item" },
  { "id": "flotation-device", "name": "Flotation device", "aliases": ["flotation devices"], "source": "ymca", "kind": "group",
    "anyOf": ["kickboard", "pool-noodle", "barbell", "float-belt", "life-jacket", "pull-buoy"] }
]
```

- An `item` gets one on/off toggle in the pool profile (`Pool.equipment`) and can be switched for one lesson (`Lesson.poolOverrides.equipment`). A `group` has no toggle; it is satisfied when any item in its `anyOf[]` is on. `anyOf[]` is on groups only.
- Initial ids — items: pool-noodle, kickboard, hoop, rescue-tube, small-toys, ball, rope, pull-buoy, fins, float-belt, hand-paddles, dive-rings, barbell, life-jacket, small-tube, mat, bucket, straws, stopwatch, pole, pennies, goggles, sunglasses, newspaper, balloon, watering-can, t-shirt, and whistle (added at Stage 1's sign-off, 2026-09-11, for Submarine Peekaboo' Variation); group: flotation-device. `small-toys` covers the text's toys, sinking toys, floating toys and "other objects" to retrieve; dive rings and balls stay separate items. Rescue tube, dive rings, barbell and floating mat only ever appear as alternatives. `equipment.json` keeps its entries in this order and adds new ones at the end: the file's order is the catalog order that labels and because lines follow (PLANNER.md §7.1–§7.2).
- `name` is the item as the plan prints it, lower-cased and never pluralised (PLANNER.md §7.1): singular ("Pool noodle", "Kickboard"), plural only for a thing used in numbers ("Small toys", "Straws", "Pennies"). A because line puts "a " or "an " before a name that doesn't end in "s": "needs a pool noodle", "needs straws".
- `aliases[]` are the toolkit's own words for the item (plurals, "Hula-Hoop", "flippers"), for M1's mapping and Library search. The owner's words are not aliases: they live in the pool profile's `equipmentNames` (SPEC §7), never in the catalog. The owner's marshmallow stick is assumed to be the barbell and shown as "Barbell (marshmallow stick)" until the owner confirms (inputs/README).
- Not equipment, so no entry and no toggle: the wall, steps, ladder, deck, lane lines (`Pool.lanes`), lifelines, drains, ceiling targets, lifeguard gear. Topic props (a mannequin, a toy phone, first-aid role-play supplies) go in the topic's notes, not the catalog.
- An item you own that the toolkit never names is a local entry in `local.json`'s `equipment[]` with `source: "local"`; its id never collides with a YMCA id (A13).

**Local additions** (`curriculum/local.json`). Yours, not the toolkit's: the one file in `curriculum/` that is tracked in git, edited as a file, and bundled read-only into your build with the rest of `curriculum/` (SPEC §8).

```json
{ "format": "local/1",
  "activities": [ { "id": "…", "name": "…", "ages": ["P", "S", "A"], "equipment": [], "submerges": false,
                    "description": "…", "skillIds": ["1.front-glide"], "source": "local" } ],
  "equipment":  [ { "id": "…", "name": "…", "aliases": [], "source": "local", "kind": "item" } ] }
```

- `activities` — activities with every field of an `activities.json` entry and `source: "local"`; shown with a "local" tag, never mixed into the YMCA files.
- `equipment` — items only (`kind: "item"`, `source: "local"`), each with a toggle in the pool profile; the catalog lists them after `equipment.json`'s entries (PLANNER.md §7.1).
- Nothing else. Pool rules live in the pool profile's `rules[]` (Settings), not here. Local ids never collide with YMCA ids (A9, A13).
- A backup or a handoff can name a local id the installed build lacks (a new phone, an older build, a substitute's copy of the app); Restore and handoff import list those ids instead of failing silently (SPEC §6.7).

## 4. Reference tables (transcribed)

Every stage's benchmarks, its skills, Stage 1's steps, the topics and the video titles are the
toolkit's own content, so the transcribed tables are not here. They live with the owner's copy,
in the gitignored `curriculum/_work/REFERENCE_TABLES.md` (DECISIONS_LOG 2026-09-15). What they
are for: checking a transcription against the printed tables, and the A7/A8 tests, which read
`curriculum/_work/benchmarks.json` and skip when it is absent.

## 5. Transcription procedure and validation (M1)

The extracted text in `reference/ymca-v6/text/` is a starting point, not a source of truth: the PDFs' three-column progression pages interleave in extraction, and the activity age tags (P/S/A) detach from their activity names. Procedure:

1. Skills and steps: from each library's progression pages, reading the PDF, not the text dump. Step names must match the Lesson Guide wording exactly (the guides list steps by name); a benchmark step's name must match its Progress Tracker row, and the stage's `trackerRows` copy the tracker's rows in order (§3). A skill whose Stage Progression column has no steps (Stage 5's elementary backstroke) gets `steps: []` and `benchmarkStepId: null`.
2. Prerequisite and advanced links: from the same pages ("See 2 / Moving Along" → the referenced stage's steps by name). A column can reach past a stage that has no steps for the skill: Stage 6's elementary backstroke lists Stage 4's steps as prerequisites.
3. Activities: one entry per library entry; description verbatim; age tags from the PDF layout. An activity that recurs with the same description (Canoe Climb on the Water Exit and Jump and Return pages) is one entry listing every skill. The same name with a different description is a separate activity with its own id: Meteor Torpedo on Front Glide (a sinking object) is `meteor-torpedo`, on Back Glide (a spot on the ceiling) `koala-launch`; Canoe Climb in Stages 4–6, where students dive instead of jump, is `lobster-dive`. A Variation that turns a jump into a dive (Otter Home Base) is split off the same way. Then, from the description, your judgment:
   - `equipment`: one requirement group per thing the activity needs, holding every alternative the text names (a description naming a rope, a rescue tube or a pool noodle → `[["pool-noodle", "rescue-tube", "rope"]]`; one naming dive rings or other sinking objects → `[["dive-rings", "small-toys"]]`); one that just says a flotation device → the `flotation-device` group. What the text makes optional or names only in a Variation goes in `equipmentOptional`. Something the text asks for that fits no catalog entry gets a new `ymca` item in `equipment.json` (§3).
   - `depths`, `headfirst`, `reachBottom`, `flotationOption`: the depth tags below. Steps get the same tags from their own descriptions, `nearWall: true` where the description puts them at or within arm's reach of the wall, and `equipment` for a device the step is done in, as the step names it: a step done in a life jacket or a float belt → `[["life-jacket", "float-belt"]]`, the items named rather than the whole `flotation-device` group (§3).
   - `submerges` (activities and steps: the swimmer holds their breath with face or head under, §3), `tags`.
4. Topics: names from the Progress Tracker; prompts from the library's own Safety & Character Topics pages (the instructor wording, which the Lesson Guide's topic blocks repeat), each "Discuss …" question joined to its expected answer with a newline, and a demonstration the page asks for (1.6's reaching and throwing assists) as a prompt of its own; the props and set-up a topic asks for in its `notes` (§3). The toolkit's separate Safety & Character Topics PDF phrases the same topics as questions for families, with a few extra items (Stage 1: 1.1, 1.3, 1.4); it is not encoded (settled at Stage 1's sign-off, 2026-09-11).
5. Lesson templates: from each Lesson Guide, per lesson: block minutes as printed, skills, step ranges, the three activities, notes. A printed range of minutes (one to two) is transcribed as its upper value (2), so a template's minutes sum exactly to the stage's lesson minutes (A2). A review slot the instructor fills is `skillIds: ["any"]` with the guide's note and no activities (template 5's Introduce in §3). Where the guide sets the water or the safety equipment for a block, record it on the block (§3): `depths` (3.5’s deep-water note → `["medium", "deep"]`, for that block's steps in that lesson only) and `equipment` in the activity shape (life jackets for Swim, float, swim in 1.7, 2.6 and 3.5 → `[["life-jacket"]]`). Block equipment never filters: if an item is off, the plan keeps the instruction and warns, and the block gives no deep-water clearance (SPEC D28, tests G2, G7). Two blocks that elsewhere name a skill have none:
   - **Stage 4 guide lessons 1–4's warm-up** — "Submerge, do 5–10 bobs", a skill the Stage 4 library does not have. Transcribe it with no `skillIds`, the guide's instruction as its note and its three listed activities (Thunder Game, Rainbow Treasure Hunt, Lantern Countdown: existing `activities.json` entries from the earlier stages' libraries). Stage 4's `warmUpSkill` is `4.endurance`, the warm-up of guide lessons 4.5–4.8. The planner gives a skill-less warm-up one activity from the block's list, the single-inhalation line, no groups and no marks (PLANNER.md §5.2).
   - **Guide lesson 8's wrap-up**, in every stage — the group game: no `skillIds`, no `activityIds`, the guide's text as its notes. The session plan's last row says `"group-game"` (SESSION_PLAN_FORMAT.md §2) and the planner picks the game (PLANNER.md §5.7).
6. Videos: `reference/ymca-v6/videos.json`, add `stageIds` and `skillIds` by title.
7. Run the validator (`tools/core/curriculum.py --validate`; standard library only, pypdf is for the transcription tooling), fix, repeat.

**Depth tags** (step 3, SPEC D28). The toolkit never measures depth. Its sample pool rules allow deck diving only in water deeper than nine feet, and every Dive step starts from the edge of the deep end; deep water means water over the swimmer's head, and shallow water is defined on the swimmer: no higher than the armpits. So the toolkit tells medium from deep only for dives. Tag each activity and step, per library entry:

| Tag | The description says | Encode |
|---|---|---|
| standing | shallow water, where students can stand or touch the bottom, walking, chest-deep, waist- to chest-deep, zero-depth | `"depths": ["shallow"]` |
| overhead | deep water, the deep end, over the head; every Tread water step; *Jump, turn, grab, in deep water*; *Jump, swim, turn, swim, grab*; Lesson 3.5's *Swim, float, swim* (on the block, step 5) | `"depths": ["medium", "deep"]` |
| headfirst | every Dive step and dive activity; the dive variation of Otter Home Base | `"depths": ["deep"], "headfirst": true` |
| any | no depth words, "comfortable depth", waist-deep to over the head | no `depths` |

Three flags, set alongside the tag: `reachBottom: true` when the swimmer must touch or fetch from the bottom (Lantern Countdown, Lighthouse Bubbles, the "push off bottom" steps of Jump and return on your own); `flotationOption: true` when the entry may run outside its zones with flotation (Moonbeam Hop: too deep to touch → flotation devices); and, on a step only, `nearWall: true` when it is done at or within arm's reach of the wall (Stage 2 Tread water 4 and Stage 3 Tread water 1: "In deep water and within arm's reach of wall"). A word in a name is not a tag: Lantern Countdown fetches from the bottom, it is not a headfirst entry. The zone labels "shallow (4 ft)", "medium (6–8 ft)" and "deep (9+ ft)" are the owner's pool, not the toolkit's; two owner questions stay open (inputs/README q5): the toolkit's "more than nine feet" against the 9+ ft zone, and a 4-ft shallow zone for preschoolers (for them, standing keeps the toolkit's definition, water no higher than the armpits). Tags say where an entry runs, not who may do it there: deep-water clearance is the planner's rule, and a swimmer's own-stage deep-water steps run under the step's own condition (§3; SPEC D23, PLANNER.md §8).

A semi-automatic first pass is fine (an agent reading the PDFs page by page into JSON), but every stage must be read against the PDF once by you before it is trusted — you will be teaching from it. Order (inputs/README q3): Stages 1–3 are transcribed, validated and signed off first, then 4–6, then A–B.

Validation checks (each is a test in TEST_CASES.md group A):

- every stage has 8 topics `n = 1..8`, 8 lesson templates `n = 1..8`, ≥ 8 skills; each lesson template's minutes sum exactly to the stage's lesson minutes (a printed range is its upper value, step 5)
- every skill with a stage progression has ≥ 1 step with `n` contiguous from 1 and `benchmarkStepId` its last step, and a skill without one has no steps and `benchmarkStepId` null; step ids follow the convention; step names unique within a skill (Stage 6 repeats Flip turn and Open turn across strokes)
- every prerequisite id resolves to a step in the nearest earlier stage that has the skill's steps (or the list is empty), every advanced id to a step in the nearest later such stage; a reference into a stage that isn't loaded is a warning, not an error (M1's first run has only Stages 1–3), and the renderer prints such a step without its name ("2 / Front glide / 1")
- every `activityIds` and `greetingActivityIds` entry exists; every activity has `ages ⊆ {P,S,A}` and a description; `depths` on an activity, step or template block, when present, is a non-empty subset of {shallow, medium, deep}, and `headfirst: true` comes with `depths` [deep]; `headfirst`, `reachBottom`, `flotationOption`, `submerges` and `nearWall`, when present, are booleans, `nearWall` on steps only; every lesson template activity exists and belongs to a scheduled skill or Greeting — a warm-up with no skill (Stage 4 guide lessons 1–4) may list any existing activity
- `warmUpSkill` and `wrapUpSkill` exist in the stage; `stepRange` within the skill's steps
- the stage's `trackerRows` equal the Progress Tracker's rows, text and order (a table in the test fixtures), and name only benchmark steps; a one-step row's text is its step's name; Stage 6's resting-stroke row is `rule` "any" over the elementary backstroke and sidestroke benchmarks
- the continuum's age variants appear as `preschoolValue` on exactly the steps the Progress Tracker prints with "(… preschool)"
- ids are unique across all files; `local.json` has format `local/1`, `source: "local"` on every entry and only items in its `equipment`; no id in it collides with a YMCA id
- every equipment id in an activity's `equipment` and `equipmentOptional`, a step's `equipment` and a template block's `equipment` exists in the catalog; a group's `anyOf` lists only items; no `local.json` equipment id collides with a YMCA id (A13)
- `safety.json` entries are `{ id, text, tags[] }` with unique ids, and `single-inhalation` is there with `tags` ["submerges"] and exactly the libraries' sentence (§3, A14)

## 6. Copyright and distribution

The toolkit is "Copyright © 2016 by YMCA of the USA. All rights reserved." You have it as a certified instructor through the Yapp. Encoding it for your own teaching is personal use. Never commit `curriculum/` or `reference/` (`.gitignore` excludes them; `curriculum/local.json`, which is yours, is the one tracked file there); the repository is local and private, never pushed, because `examples/` holds short excerpts as test fixtures (README). Do not bundle the content into a build you give to others, and if this app ever goes beyond you, get a license from Y-USA (Exchange, yexchange.org) or replace the content. The same holds for the toolkit's form PDFs the app prints on — Mid-Session Report, Certificates, Progress Tracker: they are copied into your build only (`<App>/Resources/forms/*.pdf`, gitignored like `curriculum/`; the `<form>.layout.json` files beside them hold only field names and coordinates and are committed), and the app draws the toolkit's own page and overlays the filled fields, so it never redraws the Y logo, the skill illustrations or the Cachet typeface. Your own additions in `local.json` are yours.
