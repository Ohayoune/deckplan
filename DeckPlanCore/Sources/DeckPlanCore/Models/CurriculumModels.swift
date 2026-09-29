//
//  CurriculumModels.swift
//  DeckPlanCore
//
//  The curriculum half of docs/SPEC.md §7, in the shapes
//  docs/CURRICULUM_FORMAT.md §3 encodes.
//
//  These records are read **leniently**: every field is optional and a missing
//  one is never an error. The curriculum is transcribed data whose faults are
//  the validator's to report, code by code, as Problems (docs/CURRICULUM_FORMAT.md
//  §5, docs/TEST_CASES.md A2–A14) — the loader "never throws on bad data", so a
//  decoder that threw on a missing name would take that job away from it. A field
//  that is present with the wrong kind of value does throw `JSONModelError`.
//
//  Every record keeps the keys it does not know (`extra`) and every explicitly
//  null one, so `init(json:)` -> `json` is lossless: the sample curricula carry
//  `videoTitles` on a skill, which is not a §7 field, and it survives the trip.
//

import Foundation

// MARK: - Step

/// How much of a step counts as done: 10 ft., 15 secs., 5 bobs
/// (docs/SPEC.md §7, Step.measure).
public struct Measure: JSONModel {
    /// "time", "distance" or "count".
    public var kind: String?
    public var value: Double?
    public var unit: String?
    /// The preschool variant of `value`, where the toolkit prints one.
    public var preschoolValue: Double?
    public var extra: [String: JSONValue]

    public init(kind: String? = nil, value: Double? = nil, unit: String? = nil,
                preschoolValue: Double? = nil, extra: [String: JSONValue] = [:]) {
        self.kind = kind
        self.value = value
        self.unit = unit
        self.preschoolValue = preschoolValue
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "Measure")
        kind = try reader.optionalString("kind")
        value = try reader.optionalDouble("value")
        unit = try reader.optionalString("unit")
        preschoolValue = try reader.optionalDouble("preschoolValue")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("kind", kind)
        out.set("value", value)
        out.set("unit", unit)
        out.set("preschoolValue", preschoolValue)
        return out.json
    }
}

/// One progression of a skill (docs/SPEC.md §7, Step).
///
/// `skillId` is derived by the loader, not written in the stage file
/// (docs/CURRICULUM_FORMAT.md §3: "the loader gives each Step its `skillId`").
public struct Step: JSONModel {
    public var id: String?
    public var skillId: String?
    public var n: Int?
    public var name: String?
    public var description: String?
    public var measure: Measure?
    /// A subset of "shallow", "medium", "deep"; absent means any zone.
    public var depths: [String]?
    public var headfirst: Bool?
    public var reachBottom: Bool?
    /// Done at or within arm's reach of the wall (docs/SPEC.md §7, Step.nearWall).
    public var nearWall: Bool?
    public var submerges: Bool?
    /// Requirement groups the step itself needs, worn or held (docs/SPEC.md D28).
    public var equipment: [[String]]?
    public var extra: [String: JSONValue]

    public init(id: String? = nil, skillId: String? = nil, n: Int? = nil, name: String? = nil,
                description: String? = nil, measure: Measure? = nil, depths: [String]? = nil,
                headfirst: Bool? = nil, reachBottom: Bool? = nil, nearWall: Bool? = nil,
                submerges: Bool? = nil, equipment: [[String]]? = nil,
                extra: [String: JSONValue] = [:]) {
        self.id = id
        self.skillId = skillId
        self.n = n
        self.name = name
        self.description = description
        self.measure = measure
        self.depths = depths
        self.headfirst = headfirst
        self.reachBottom = reachBottom
        self.nearWall = nearWall
        self.submerges = submerges
        self.equipment = equipment
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "Step")
        id = try reader.optionalString("id")
        skillId = try reader.optionalString("skillId")
        n = try reader.optionalInt("n")
        name = try reader.optionalString("name")
        description = try reader.optionalString("description")
        measure = try reader.optionalModel("measure")
        depths = try reader.optionalStrings("depths")
        headfirst = try reader.optionalBool("headfirst")
        reachBottom = try reader.optionalBool("reachBottom")
        nearWall = try reader.optionalBool("nearWall")
        submerges = try reader.optionalBool("submerges")
        equipment = try reader.optionalStringGroups("equipment")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("id", id)
        out.set("skillId", skillId)
        out.set("n", n)
        out.set("name", name)
        out.set("description", description)
        out.set("measure", measure)
        out.set("depths", depths)
        out.set("headfirst", headfirst)
        out.set("reachBottom", reachBottom)
        out.set("nearWall", nearWall)
        out.set("submerges", submerges)
        out.set("equipment", equipment)
        return out.json
    }
}

// MARK: - Skill

/// One skill of one stage, with its progression (docs/SPEC.md §7, Skill).
///
/// `stageId` and `stepIds` are the loader's derivations; the stage file nests the
/// steps in `steps` (docs/CURRICULUM_FORMAT.md §3). `benchmarkStepId` is null —
/// present as a key, with no value — for a skill the stage lists for review with
/// no progression of its own (docs/TEST_CASES.md A3), and a null read here is
/// written back as a null.
public struct Skill: JSONModel {
    public var id: String?
    public var stageId: String?
    public var name: String?
    public var order: Int?
    public var isBenchmarkSequence: Bool?
    /// The steps as the stage file nests them.
    public var steps: [Step]?
    /// The step ids, derived by the loader from `steps`.
    public var stepIds: [String]?
    public var benchmarkStepId: String?
    /// Steps of the nearest earlier stage that has this skill (docs/SPEC.md D25).
    public var prerequisiteStepIds: [String]?
    /// Steps of the nearest later stage that has this skill (docs/SPEC.md D25).
    public var advancedStepIds: [String]?
    public var activityIds: [String]?
    public var videoIds: [String]?
    public var extra: [String: JSONValue]

    public init(id: String? = nil, stageId: String? = nil, name: String? = nil, order: Int? = nil,
                isBenchmarkSequence: Bool? = nil, steps: [Step]? = nil, stepIds: [String]? = nil,
                benchmarkStepId: String? = nil, prerequisiteStepIds: [String]? = nil,
                advancedStepIds: [String]? = nil, activityIds: [String]? = nil,
                videoIds: [String]? = nil, extra: [String: JSONValue] = [:]) {
        self.id = id
        self.stageId = stageId
        self.name = name
        self.order = order
        self.isBenchmarkSequence = isBenchmarkSequence
        self.steps = steps
        self.stepIds = stepIds
        self.benchmarkStepId = benchmarkStepId
        self.prerequisiteStepIds = prerequisiteStepIds
        self.advancedStepIds = advancedStepIds
        self.activityIds = activityIds
        self.videoIds = videoIds
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "Skill")
        id = try reader.optionalString("id")
        stageId = try reader.optionalString("stageId")
        name = try reader.optionalString("name")
        order = try reader.optionalInt("order")
        isBenchmarkSequence = try reader.optionalBool("isBenchmarkSequence")
        steps = try reader.optionalModels("steps")
        stepIds = try reader.optionalStrings("stepIds")
        benchmarkStepId = try reader.optionalString("benchmarkStepId")
        prerequisiteStepIds = try reader.optionalStrings("prerequisiteStepIds")
        advancedStepIds = try reader.optionalStrings("advancedStepIds")
        activityIds = try reader.optionalStrings("activityIds")
        videoIds = try reader.optionalStrings("videoIds")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("id", id)
        out.set("stageId", stageId)
        out.set("name", name)
        out.set("order", order)
        out.set("isBenchmarkSequence", isBenchmarkSequence)
        out.set("steps", steps)
        out.set("stepIds", stepIds)
        out.set("benchmarkStepId", benchmarkStepId)
        out.set("prerequisiteStepIds", prerequisiteStepIds)
        out.set("advancedStepIds", advancedStepIds)
        out.set("activityIds", activityIds)
        out.set("videoIds", videoIds)
        return out.json
    }
}

// MARK: - Stage

/// A row of the Progress Tracker: the text it prints and the benchmark steps that
/// satisfy it (docs/SPEC.md §7, Stage.trackerRows; docs/PROGRESS_TRACKING.md).
public struct TrackerRow: JSONModel {
    /// The row as the tracker prints it.
    public var text: String?
    /// Benchmark step ids only.
    public var stepIds: [String]?
    /// "all" — every step achieved — or "any": Stage 6's resting-stroke row.
    public var rule: String?
    public var extra: [String: JSONValue]

    public init(text: String? = nil, stepIds: [String]? = nil, rule: String? = nil,
                extra: [String: JSONValue] = [:]) {
        self.text = text
        self.stepIds = stepIds
        self.rule = rule
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "TrackerRow")
        text = try reader.optionalString("text")
        stepIds = try reader.optionalStrings("stepIds")
        rule = try reader.optionalString("rule")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("text", text)
        out.set("stepIds", stepIds)
        out.set("rule", rule)
        return out.json
    }
}

/// A lesson topic and its prompts (docs/SPEC.md §7, Topic).
public struct Topic: JSONModel {
    /// `<stage>.<n>`, "1.5".
    public var code: String?
    public var stageId: String?
    public var n: Int?
    public var name: String?
    public var summary: String?
    public var prompts: [String]?
    /// Props and set-up the topic asks for; not catalog equipment.
    public var notes: [String]?
    public var extra: [String: JSONValue]

    public init(code: String? = nil, stageId: String? = nil, n: Int? = nil, name: String? = nil,
                summary: String? = nil, prompts: [String]? = nil, notes: [String]? = nil,
                extra: [String: JSONValue] = [:]) {
        self.code = code
        self.stageId = stageId
        self.n = n
        self.name = name
        self.summary = summary
        self.prompts = prompts
        self.notes = notes
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "Topic")
        code = try reader.optionalString("code")
        stageId = try reader.optionalString("stageId")
        n = try reader.optionalInt("n")
        name = try reader.optionalString("name")
        summary = try reader.optionalString("summary")
        prompts = try reader.optionalStrings("prompts")
        notes = try reader.optionalStrings("notes")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("code", code)
        out.set("stageId", stageId)
        out.set("n", n)
        out.set("name", name)
        out.set("summary", summary)
        out.set("prompts", prompts)
        out.set("notes", notes)
        return out.json
    }
}

/// One block of a guide lesson as the toolkit prints it (docs/SPEC.md §7, Block).
///
/// No `skillIds` (or an empty one) is a block without a skill: Welcome, Topic,
/// lesson 8's group-game wrap-up, Stage 4's guide lessons 1–4 warm-up.
public struct Block: JSONModel {
    /// "welcome", "warmUp", "review", "introduce", "topic" or "wrapUp".
    public var kind: String?
    /// As printed; a printed range ("1–2 mins.") is its upper value.
    public var minutes: Int?
    public var skillIds: [String]?
    /// The guide's step range for this block, `[first, last]`.
    public var stepRange: [Int]?
    public var activityIds: [String]?
    public var topicCode: String?
    public var notes: [String]?
    /// The water the guide sets for this block's steps in this lesson.
    public var depths: [String]?
    /// Safety equipment the guide prescribes (life jackets in 1.7, 2.6, 3.5); never filters.
    public var equipment: [[String]]?
    public var extra: [String: JSONValue]

    public init(kind: String? = nil, minutes: Int? = nil, skillIds: [String]? = nil,
                stepRange: [Int]? = nil, activityIds: [String]? = nil, topicCode: String? = nil,
                notes: [String]? = nil, depths: [String]? = nil, equipment: [[String]]? = nil,
                extra: [String: JSONValue] = [:]) {
        self.kind = kind
        self.minutes = minutes
        self.skillIds = skillIds
        self.stepRange = stepRange
        self.activityIds = activityIds
        self.topicCode = topicCode
        self.notes = notes
        self.depths = depths
        self.equipment = equipment
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "Block")
        kind = try reader.optionalString("kind")
        minutes = try reader.optionalInt("minutes")
        skillIds = try reader.optionalStrings("skillIds")
        stepRange = try reader.optionalInts("stepRange")
        activityIds = try reader.optionalStrings("activityIds")
        topicCode = try reader.optionalString("topicCode")
        notes = try reader.optionalStrings("notes")
        depths = try reader.optionalStrings("depths")
        equipment = try reader.optionalStringGroups("equipment")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("kind", kind)
        out.set("minutes", minutes)
        out.set("skillIds", skillIds)
        out.set("stepRange", stepRange)
        out.set("activityIds", activityIds)
        out.set("topicCode", topicCode)
        out.set("notes", notes)
        out.set("depths", depths)
        out.set("equipment", equipment)
        return out.json
    }
}

/// One of a stage's eight guide lessons (docs/SPEC.md §7, LessonTemplate).
public struct LessonTemplate: JSONModel {
    /// 1–8.
    public var n: Int?
    public var stageId: String?
    /// The blocks' minutes sum to this.
    public var minutes: Int?
    public var blocks: [Block]?
    public var extra: [String: JSONValue]

    public init(n: Int? = nil, stageId: String? = nil, minutes: Int? = nil,
                blocks: [Block]? = nil, extra: [String: JSONValue] = [:]) {
        self.n = n
        self.stageId = stageId
        self.minutes = minutes
        self.blocks = blocks
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "LessonTemplate")
        n = try reader.optionalInt("n")
        stageId = try reader.optionalString("stageId")
        minutes = try reader.optionalInt("minutes")
        blocks = try reader.optionalModels("blocks")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("n", n)
        out.set("stageId", stageId)
        out.set("minutes", minutes)
        out.set("blocks", blocks)
        return out.json
    }
}

/// One stage of the YMCA V6 program: A, B or 1–6 (docs/SPEC.md §7, Stage).
public struct Stage: JSONModel {
    public var id: String?
    public var name: String?
    /// "Swim Starters", "Swim Basics" or "Swim Strokes".
    public var group: String?
    public var ageGroups: [String]?
    public var lessonMinutes: Int?
    public var warmUpSkill: String?
    public var wrapUpSkill: String?
    /// The library's "Teaching this stage" lines.
    public var milestones: [String]?
    /// The stage's Greeting activities in page order; Greeting has no steps, so it
    /// is not a Skill.
    public var greetingActivityIds: [String]?
    public var skills: [Skill]?
    public var topics: [Topic]?
    /// The Progress Tracker's rows in its order.
    public var trackerRows: [TrackerRow]?
    public var lessonTemplates: [LessonTemplate]?
    public var extra: [String: JSONValue]

    public init(id: String? = nil, name: String? = nil, group: String? = nil,
                ageGroups: [String]? = nil, lessonMinutes: Int? = nil, warmUpSkill: String? = nil,
                wrapUpSkill: String? = nil, milestones: [String]? = nil,
                greetingActivityIds: [String]? = nil, skills: [Skill]? = nil,
                topics: [Topic]? = nil, trackerRows: [TrackerRow]? = nil,
                lessonTemplates: [LessonTemplate]? = nil, extra: [String: JSONValue] = [:]) {
        self.id = id
        self.name = name
        self.group = group
        self.ageGroups = ageGroups
        self.lessonMinutes = lessonMinutes
        self.warmUpSkill = warmUpSkill
        self.wrapUpSkill = wrapUpSkill
        self.milestones = milestones
        self.greetingActivityIds = greetingActivityIds
        self.skills = skills
        self.topics = topics
        self.trackerRows = trackerRows
        self.lessonTemplates = lessonTemplates
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "Stage")
        id = try reader.optionalString("id")
        name = try reader.optionalString("name")
        group = try reader.optionalString("group")
        ageGroups = try reader.optionalStrings("ageGroups")
        lessonMinutes = try reader.optionalInt("lessonMinutes")
        warmUpSkill = try reader.optionalString("warmUpSkill")
        wrapUpSkill = try reader.optionalString("wrapUpSkill")
        milestones = try reader.optionalStrings("milestones")
        greetingActivityIds = try reader.optionalStrings("greetingActivityIds")
        skills = try reader.optionalModels("skills")
        topics = try reader.optionalModels("topics")
        trackerRows = try reader.optionalModels("trackerRows")
        lessonTemplates = try reader.optionalModels("lessonTemplates")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("id", id)
        out.set("name", name)
        out.set("group", group)
        out.set("ageGroups", ageGroups)
        out.set("lessonMinutes", lessonMinutes)
        out.set("warmUpSkill", warmUpSkill)
        out.set("wrapUpSkill", wrapUpSkill)
        out.set("milestones", milestones)
        out.set("greetingActivityIds", greetingActivityIds)
        out.set("skills", skills)
        out.set("topics", topics)
        out.set("trackerRows", trackerRows)
        out.set("lessonTemplates", lessonTemplates)
        return out.json
    }
}

// MARK: - Catalogs

/// One activity from the toolkit's libraries, or one of the owner's own
/// (docs/SPEC.md §7, Activity).
public struct Activity: JSONModel {
    public var id: String?
    public var name: String?
    public var description: String?
    /// "P", "S", "A" — preschool, school age, adult.
    public var ages: [String]?
    /// Requirement groups, all required; any one id satisfies a group; `[]` = none.
    public var equipment: [[String]]?
    /// Listed on the plan as "(optional)"; never filters.
    public var equipmentOptional: [String]?
    /// A subset of "shallow", "medium", "deep"; absent means any zone.
    public var depths: [String]?
    public var headfirst: Bool?
    /// Touches or fetches from the bottom; noted on the plan, zones unchanged.
    public var reachBottom: Bool?
    /// May run outside its zones with flotation (docs/SPEC.md D28).
    public var flotationOption: Bool?
    public var submerges: Bool?
    public var tags: [String]?
    public var skillIds: [String]?
    /// "ymca" or "local".
    public var source: String?
    public var extra: [String: JSONValue]

    public init(id: String? = nil, name: String? = nil, description: String? = nil,
                ages: [String]? = nil, equipment: [[String]]? = nil,
                equipmentOptional: [String]? = nil, depths: [String]? = nil,
                headfirst: Bool? = nil, reachBottom: Bool? = nil, flotationOption: Bool? = nil,
                submerges: Bool? = nil, tags: [String]? = nil, skillIds: [String]? = nil,
                source: String? = nil, extra: [String: JSONValue] = [:]) {
        self.id = id
        self.name = name
        self.description = description
        self.ages = ages
        self.equipment = equipment
        self.equipmentOptional = equipmentOptional
        self.depths = depths
        self.headfirst = headfirst
        self.reachBottom = reachBottom
        self.flotationOption = flotationOption
        self.submerges = submerges
        self.tags = tags
        self.skillIds = skillIds
        self.source = source
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "Activity")
        id = try reader.optionalString("id")
        name = try reader.optionalString("name")
        description = try reader.optionalString("description")
        ages = try reader.optionalStrings("ages")
        equipment = try reader.optionalStringGroups("equipment")
        equipmentOptional = try reader.optionalStrings("equipmentOptional")
        depths = try reader.optionalStrings("depths")
        headfirst = try reader.optionalBool("headfirst")
        reachBottom = try reader.optionalBool("reachBottom")
        flotationOption = try reader.optionalBool("flotationOption")
        submerges = try reader.optionalBool("submerges")
        tags = try reader.optionalStrings("tags")
        skillIds = try reader.optionalStrings("skillIds")
        source = try reader.optionalString("source")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("id", id)
        out.set("name", name)
        out.set("description", description)
        out.set("ages", ages)
        out.set("equipment", equipment)
        out.set("equipmentOptional", equipmentOptional)
        out.set("depths", depths)
        out.set("headfirst", headfirst)
        out.set("reachBottom", reachBottom)
        out.set("flotationOption", flotationOption)
        out.set("submerges", submerges)
        out.set("tags", tags)
        out.set("skillIds", skillIds)
        out.set("source", source)
        return out.json
    }
}

/// One entry of the equipment catalog (docs/SPEC.md §7, Equipment; D28).
///
/// An "item" has one toggle; a "group" has none and is satisfied when any id in
/// `anyOf` is on — `flotation-device` is the only one.
public struct Equipment: JSONModel {
    public var id: String?
    public var name: String?
    public var aliases: [String]?
    /// "ymca" or "local".
    public var source: String?
    /// "item" or "group".
    public var kind: String?
    public var anyOf: [String]?
    public var extra: [String: JSONValue]

    public init(id: String? = nil, name: String? = nil, aliases: [String]? = nil,
                source: String? = nil, kind: String? = nil, anyOf: [String]? = nil,
                extra: [String: JSONValue] = [:]) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.source = source
        self.kind = kind
        self.anyOf = anyOf
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "Equipment")
        id = try reader.optionalString("id")
        name = try reader.optionalString("name")
        aliases = try reader.optionalStrings("aliases")
        source = try reader.optionalString("source")
        kind = try reader.optionalString("kind")
        anyOf = try reader.optionalStrings("anyOf")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("id", id)
        out.set("name", name)
        out.set("aliases", aliases)
        out.set("source", source)
        out.set("kind", kind)
        out.set("anyOf", anyOf)
        return out.json
    }
}

/// One of the Yapp's videos with its stage and skill links (docs/SPEC.md §7, Video).
public struct Video: JSONModel {
    /// `vimeo:<id>`.
    public var id: String?
    public var title: String?
    public var url: String?
    public var stageIds: [String]?
    public var skillIds: [String]?
    public var extra: [String: JSONValue]

    public init(id: String? = nil, title: String? = nil, url: String? = nil,
                stageIds: [String]? = nil, skillIds: [String]? = nil,
                extra: [String: JSONValue] = [:]) {
        self.id = id
        self.title = title
        self.url = url
        self.stageIds = stageIds
        self.skillIds = skillIds
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "Video")
        id = try reader.optionalString("id")
        title = try reader.optionalString("title")
        url = try reader.optionalString("url")
        stageIds = try reader.optionalStrings("stageIds")
        skillIds = try reader.optionalStrings("skillIds")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("id", id)
        out.set("title", title)
        out.set("url", url)
        out.set("stageIds", stageIds)
        out.set("skillIds", skillIds)
        return out.json
    }
}

/// A safety line the plan prints (docs/SPEC.md §7, SafetyRule; docs/PLANNER.md §8).
///
/// `curriculum/safety.json`'s entries have an id; the owner's house rules, which
/// live in `Pool.rules`, need none.
public struct SafetyRule: JSONModel {
    public var id: String?
    public var text: String?
    /// "jump", "dive", "deep", "submerges", "noodle" … — a rule prints in the
    /// notes of each block whose activity shares one of its tags.
    public var tags: [String]?
    public var extra: [String: JSONValue]

    public init(id: String? = nil, text: String? = nil, tags: [String]? = nil,
                extra: [String: JSONValue] = [:]) {
        self.id = id
        self.text = text
        self.tags = tags
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "SafetyRule")
        id = try reader.optionalString("id")
        text = try reader.optionalString("text")
        tags = try reader.optionalStrings("tags")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("id", id)
        out.set("text", text)
        out.set("tags", tags)
        return out.json
    }
}

// MARK: - The whole curriculum

/// `curriculum/local.json` — the owner's own activities and equipment, the one
/// tracked file in `curriculum/` (docs/SPEC.md §6.12, docs/CURRICULUM_FORMAT.md §3).
///
/// `localHash` (docs/CANONICAL_JSON.md) is the SHA-256 of this object's canonical
/// JSON, so it has to round-trip byte for byte; a compact curriculum sample has no
/// local additions and hashes the empty `local/1` object instead.
public struct LocalAdditions: JSONModel {
    public var format: String?
    public var activities: [Activity]?
    public var equipment: [Equipment]?
    public var extra: [String: JSONValue]

    /// The empty `local/1` object a compact sample stands in with
    /// (`tools/core/fixtures.py`'s `EMPTY_LOCAL`; manifest D9).
    public static let empty = LocalAdditions(format: "local/1", activities: [], equipment: [])

    public init(format: String? = nil, activities: [Activity]? = nil,
                equipment: [Equipment]? = nil, extra: [String: JSONValue] = [:]) {
        self.format = format
        self.activities = activities
        self.equipment = equipment
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "LocalAdditions")
        format = try reader.optionalString("format")
        activities = try reader.optionalModels("activities")
        equipment = try reader.optionalModels("equipment")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("format", format)
        out.set("activities", activities)
        out.set("equipment", equipment)
        return out.json
    }
}

/// The assembled curriculum (docs/SPEC.md §7, Curriculum).
///
/// This is the *data* the loader produces from `curriculum/`'s files or from a
/// compact single-stage sample — `version.json`'s version, the stages that loaded,
/// and the shared catalogs, with `local.json` merged in after the YMCA entries
/// (docs/CURRICULUM_FORMAT.md §3). Where the curriculum came from, what went wrong
/// reading it, and the id lookups belong to the loader in `Curriculum/`, which
/// extends this type rather than declaring a second one.
public struct Curriculum: JSONModel {
    /// `version.json`'s version, or a compact sample's top-level one.
    public var version: String?
    /// In stage order (A, B, 1–6), only the stages that loaded.
    public var stages: [Stage]?
    /// `activities.json`'s entries, then `local.json`'s.
    public var activities: [Activity]?
    /// `equipment.json`'s entries, then `local.json`'s (catalog order).
    public var equipment: [Equipment]?
    public var videos: [Video]?
    public var safety: [SafetyRule]?
    /// `local.json`'s object; nil for a compact sample, which is read with no
    /// local additions (docs/PLANNER.md §13).
    public var local: LocalAdditions?
    public var extra: [String: JSONValue]

    public init(version: String? = nil, stages: [Stage]? = nil, activities: [Activity]? = nil,
                equipment: [Equipment]? = nil, videos: [Video]? = nil,
                safety: [SafetyRule]? = nil, local: LocalAdditions? = nil,
                extra: [String: JSONValue] = [:]) {
        self.version = version
        self.stages = stages
        self.activities = activities
        self.equipment = equipment
        self.videos = videos
        self.safety = safety
        self.local = local
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "Curriculum")
        version = try reader.optionalString("version")
        stages = try reader.optionalModels("stages")
        activities = try reader.optionalModels("activities")
        equipment = try reader.optionalModels("equipment")
        videos = try reader.optionalModels("videos")
        safety = try reader.optionalModels("safety")
        local = try reader.optionalModel("local")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("version", version)
        out.set("stages", stages)
        out.set("activities", activities)
        out.set("equipment", equipment)
        out.set("videos", videos)
        out.set("safety", safety)
        out.set("local", local)
        return out.json
    }
}
