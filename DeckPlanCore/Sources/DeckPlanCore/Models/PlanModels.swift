//
//  PlanModels.swift
//  DeckPlanCore
//
//  What the Core hands the screens — the day plan (docs/REDESIGN.md §3; D1–D9),
//  a shuffle's result (D4), the finder's pages, an activity's detail and the
//  browse list (§4; F1–F6). Their JSON is `tools/core/day_plan.py`'s and
//  `finder.py`'s exactly: optional keys are left out when the Python leaves
//  them out, nullable ones written as null, so `Canonical.dumps` of a plan built
//  here equals the Python's fixture byte for byte (D9).
//

import Foundation

// MARK: - The day plan (D1–D3, D8)

/// A topic block's topic: `{ code, name, summary }`.
public struct PlanTopic: JSONModel {
    public var code: String
    public var name: String
    public var summary: String

    public init(code: String, name: String, summary: String) {
        self.code = code
        self.name = name
        self.summary = summary
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "PlanTopic")
        code = try reader.string("code")
        name = try reader.string("name")
        summary = try reader.string("summary")
    }

    public var json: JSONValue {
        var out = JSONBuilder()
        out.set("code", code)
        out.set("name", name)
        out.set("summary", summary)
        return out.json
    }
}

/// One block of a day (docs/REDESIGN.md §2 "Block"): the guide's `kind`,
/// `minutes`, `skillIds`, `stepRange`, `notes` and `topicCode` as the template has
/// them, the topic's name and prompt, the stage's `skillChoices` while an "any"
/// block waits for its pick (D3), the activities shown, and `hidden` — saved or
/// drafted ids the pool now hides (D8).
public struct PlanBlock: JSONModel {
    public var kind: String
    public var minutes: Int?
    public var skillIds: [String]
    public var stepRange: [Int]?
    public var notes: [String]?
    public var topicCode: String?
    public var topic: PlanTopic?
    public var skillChoices: [String]?
    public var activityIds: [String]
    public var hidden: [String]?

    public init(kind: String, minutes: Int? = nil, skillIds: [String] = [], stepRange: [Int]? = nil,
                notes: [String]? = nil, topicCode: String? = nil, topic: PlanTopic? = nil,
                skillChoices: [String]? = nil, activityIds: [String] = [], hidden: [String]? = nil) {
        self.kind = kind
        self.minutes = minutes
        self.skillIds = skillIds
        self.stepRange = stepRange
        self.notes = notes
        self.topicCode = topicCode
        self.topic = topic
        self.skillChoices = skillChoices
        self.activityIds = activityIds
        self.hidden = hidden
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "PlanBlock")
        kind = try reader.string("kind")
        minutes = try reader.optionalInt("minutes")
        skillIds = try reader.strings("skillIds")
        stepRange = try reader.optionalInts("stepRange")
        notes = try reader.optionalStrings("notes")
        topicCode = try reader.optionalString("topicCode")
        topic = try reader.optionalModel("topic")
        skillChoices = try reader.optionalStrings("skillChoices")
        activityIds = try reader.strings("activityIds")
        hidden = try reader.optionalStrings("hidden")
    }

    public var json: JSONValue {
        var out = JSONBuilder()
        out.set("kind", kind)
        out.set("minutes", minutes)
        out.set("skillIds", skillIds)
        out.set("stepRange", stepRange)
        out.set("notes", notes)
        out.set("topicCode", topicCode)
        out.set("topic", topic)
        out.set("skillChoices", skillChoices)
        out.set("activityIds", activityIds)
        out.set("hidden", hidden)
        return out.json
    }

    /// Whether this block still waits for the instructor's pick (D3).
    public var awaitsPick: Bool {
        skillIds == [Ids.anySkill]
    }
}

/// A class's day k as the Today screen shows it (`day_plan.plan_day`): where
/// its blocks came from is `saved` (a log entry exists) and `draft` (the class's
/// draft is for this day and is the working copy shown).
public struct DayPlan: JSONModel {
    public var classId: String
    public var n: Int
    /// The schedule's date for day n; null only for a class whose schedule yields none.
    public var date: String?
    /// The guide lesson the day follows; null for an extra day of an N > 8 class (C5).
    public var guideLesson: Int?
    public var saved: Bool
    public var draft: Bool
    public var blocks: [PlanBlock]

    public init(classId: String, n: Int, date: String?, guideLesson: Int?, saved: Bool, draft: Bool,
                blocks: [PlanBlock]) {
        self.classId = classId
        self.n = n
        self.date = date
        self.guideLesson = guideLesson
        self.saved = saved
        self.draft = draft
        self.blocks = blocks
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "DayPlan")
        classId = try reader.string("classId")
        n = try reader.int("n")
        date = try reader.nullableString("date")
        guideLesson = try reader.nullableInt("guideLesson")
        saved = try reader.bool("saved")
        draft = try reader.bool("draft")
        blocks = try reader.models("blocks")
    }

    public var json: JSONValue {
        var out = JSONBuilder()
        out.set("classId", classId)
        out.set("n", n)
        out.setAllowingNull("date", date)
        out.setAllowingNull("guideLesson", guideLesson)
        out.set("saved", saved)
        out.set("draft", draft)
        out.set("blocks", blocks)
        return out.json
    }

    public func block(_ kind: String) -> PlanBlock? {
        blocks.first { $0.kind == kind }
    }
}

// MARK: - Shuffle (D4, D5)

/// What one shuffle drew: `{ kind, activityIds, shuffleCount, message? }` — the
/// message is `DayPlans.shuffleExhausted` when fewer never-done candidates than
/// slots existed.
public struct ShuffleResult: JSONModel {
    public var kind: String
    public var activityIds: [String]
    public var shuffleCount: Int
    public var message: String?

    public init(kind: String, activityIds: [String], shuffleCount: Int, message: String? = nil) {
        self.kind = kind
        self.activityIds = activityIds
        self.shuffleCount = shuffleCount
        self.message = message
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "ShuffleResult")
        kind = try reader.string("kind")
        activityIds = try reader.strings("activityIds")
        shuffleCount = try reader.int("shuffleCount")
        message = try reader.optionalString("message")
    }

    public var json: JSONValue {
        var out = JSONBuilder()
        out.set("kind", kind)
        out.set("activityIds", activityIds)
        out.set("shuffleCount", shuffleCount)
        out.set("message", message)
        return out.json
    }
}

// MARK: - The finder (F1–F6)

/// One finder result: the inputs and page `page` of the seeded list (F1).
/// Nullable inputs are written as null, as the Python does.
public struct FinderPage: JSONModel {
    public var stageId: String
    public var skillId: String?
    public var step: Int?
    public var ageTag: String?
    public var page: Int
    public var pageSize: Int
    public var total: Int
    public var activityIds: [String]
    /// True when `page` is past the last page and the list started over (F1).
    public var wrapped: Bool

    public init(stageId: String, skillId: String?, step: Int?, ageTag: String?, page: Int, pageSize: Int,
                total: Int, activityIds: [String], wrapped: Bool) {
        self.stageId = stageId
        self.skillId = skillId
        self.step = step
        self.ageTag = ageTag
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.activityIds = activityIds
        self.wrapped = wrapped
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "FinderPage")
        stageId = try reader.string("stageId")
        skillId = try reader.nullableString("skillId")
        step = try reader.nullableInt("step")
        ageTag = try reader.nullableString("ageTag")
        page = try reader.int("page")
        pageSize = try reader.int("pageSize")
        total = try reader.int("total")
        activityIds = try reader.strings("activityIds")
        wrapped = try reader.bool("wrapped")
    }

    public var json: JSONValue {
        var out = JSONBuilder()
        out.set("stageId", stageId)
        out.setAllowingNull("skillId", skillId)
        out.setAllowingNull("step", step)
        out.setAllowingNull("ageTag", ageTag)
        out.set("page", page)
        out.set("pageSize", pageSize)
        out.set("total", total)
        out.set("activityIds", activityIds)
        out.set("wrapped", wrapped)
        return out.json
    }
}

/// One group of the browse list — and of the library before the filter
/// (`activities.library_groups`): the Greeting group has no `skillId`.
public struct BrowseGroup: JSONModel {
    public var skillId: String?
    public var name: String
    public var activityIds: [String]

    public init(skillId: String?, name: String, activityIds: [String]) {
        self.skillId = skillId
        self.name = name
        self.activityIds = activityIds
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "BrowseGroup")
        skillId = try reader.nullableString("skillId")
        name = try reader.string("name")
        activityIds = try reader.strings("activityIds")
    }

    public var json: JSONValue {
        var out = JSONBuilder()
        out.setAllowingNull("skillId", skillId)
        out.set("name", name)
        out.set("activityIds", activityIds)
        return out.json
    }
}

/// The browse list (F6): the stage's pool-filtered library grouped by skill,
/// Greeting first.
public struct BrowseResult: JSONModel {
    public var stageId: String
    public var ageTag: String?
    public var groups: [BrowseGroup]

    public init(stageId: String, ageTag: String?, groups: [BrowseGroup]) {
        self.stageId = stageId
        self.ageTag = ageTag
        self.groups = groups
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "BrowseResult")
        stageId = try reader.string("stageId")
        ageTag = try reader.nullableString("ageTag")
        groups = try reader.models("groups")
    }

    public var json: JSONValue {
        var out = JSONBuilder()
        out.set("stageId", stageId)
        out.setAllowingNull("ageTag", ageTag)
        out.set("groups", groups)
        return out.json
    }
}

/// A search (F7): browse narrowed to the activities named like `text`, only the
/// groups that match; `{ stageId, ageTag, text, groups }`.
public struct SearchResult: JSONModel {
    public var stageId: String
    public var ageTag: String?
    public var text: String
    public var groups: [BrowseGroup]

    public init(stageId: String, ageTag: String?, text: String, groups: [BrowseGroup]) {
        self.stageId = stageId
        self.ageTag = ageTag
        self.text = text
        self.groups = groups
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "SearchResult")
        stageId = try reader.string("stageId")
        ageTag = try reader.nullableString("ageTag")
        text = try reader.string("text")
        groups = try reader.models("groups")
    }

    public var json: JSONValue {
        var out = JSONBuilder()
        out.set("stageId", stageId)
        out.setAllowingNull("ageTag", ageTag)
        out.set("text", text)
        out.set("groups", groups)
        return out.json
    }
}

/// What the finder shows for one activity (F5): `equipment` is one phrase per
/// requirement group ("float belt or life jacket"), `videos` the titles of the
/// skill's videos.
public struct ActivityDetail: JSONModel {
    public var id: String
    public var name: String
    public var description: String
    public var equipment: [String]
    public var equipmentOptional: [String]
    public var ages: [String]
    public var submerges: Bool
    public var videos: [String]

    public init(id: String, name: String, description: String, equipment: [String], equipmentOptional: [String],
                ages: [String], submerges: Bool, videos: [String]) {
        self.id = id
        self.name = name
        self.description = description
        self.equipment = equipment
        self.equipmentOptional = equipmentOptional
        self.ages = ages
        self.submerges = submerges
        self.videos = videos
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "ActivityDetail")
        id = try reader.string("id")
        name = try reader.string("name")
        description = try reader.string("description")
        equipment = try reader.strings("equipment")
        equipmentOptional = try reader.strings("equipmentOptional")
        ages = try reader.strings("ages")
        submerges = try reader.bool("submerges")
        videos = try reader.strings("videos")
    }

    public var json: JSONValue {
        var out = JSONBuilder()
        out.set("id", id)
        out.set("name", name)
        out.set("description", description)
        out.set("equipment", equipment)
        out.set("equipmentOptional", equipmentOptional)
        out.set("ages", ages)
        out.set("submerges", submerges)
        out.set("videos", videos)
        return out.json
    }
}
