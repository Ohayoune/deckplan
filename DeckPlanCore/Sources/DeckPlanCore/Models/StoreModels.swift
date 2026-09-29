//
//  StoreModels.swift
//  DeckPlanCore
//
//  What the app stores — docs/REDESIGN.md §2 (Class, Pool profile, lesson log)
//  and §6 (the files): one pool profile, the classes with their logs and drafts,
//  and settings. The JSON shapes are `tools/core/classes.py`'s and
//  `tools/core/activities.py`'s, read strictly (a required field that is missing
//  is reported, never defaulted — docs/TEST_CASES.md S1) and written back byte
//  for byte through `Canonical.dumps`, so a class file the Python CLI wrote is
//  what this package keeps (DECISIONS_LOG 2026-09-12 "Store documents from the CLI").
//
//  Naming: REDESIGN.md's `Class` is ``SwimClass`` in Swift. The JSON keys never change.
//

import Foundation

// MARK: - Pool profile (P1)

/// The pool profile (docs/REDESIGN.md §2; DECISIONS_LOG 2026-09-12 "New pool
/// profile"): `{ depths: {shallow, medium, deep}, diving, totDock,
/// equipment: {<catalog item id>: bool} }`.
///
/// `depths` and `equipment` are maps rather than fixed fields because a key with
/// no entry reads as off (P1): an equipment item added to the catalog later is
/// off until toggled. `Activities.normalizePool` fills a partial profile out.
public struct Pool: JSONModel {
    public var depths: [String: Bool]
    public var diving: Bool
    public var totDock: Bool
    public var equipment: [String: Bool]
    public var extra: [String: JSONValue]

    public init(depths: [String: Bool] = [:], diving: Bool = false, totDock: Bool = false,
                equipment: [String: Bool] = [:], extra: [String: JSONValue] = [:]) {
        self.depths = depths
        self.diving = diving
        self.totDock = totDock
        self.equipment = equipment
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "Pool")
        guard let depths = try reader.optionalBoolMap("depths") else {
            throw JSONModelError.missingField(type: "Pool", field: "depths")
        }
        self.depths = depths
        diving = try reader.bool("diving")
        totDock = try reader.bool("totDock")
        guard let equipment = try reader.optionalBoolMap("equipment") else {
            throw JSONModelError.missingField(type: "Pool", field: "equipment")
        }
        self.equipment = equipment
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("depths", depths)
        out.set("diving", diving)
        out.set("totDock", totDock)
        out.set("equipment", equipment)
        return out.json
    }
}

// MARK: - Classes (C1)

/// A class's schedule: `{ weekdays: ["mon", ...], firstDate: "YYYY-MM-DD" }`
/// (docs/REDESIGN.md §2). The dates come from `Schedule.lessonDates` (C4).
public struct ClassSchedule: JSONModel {
    public var weekdays: [String]
    public var firstDate: String
    public var extra: [String: JSONValue]

    public init(weekdays: [String], firstDate: String, extra: [String: JSONValue] = [:]) {
        self.weekdays = weekdays
        self.firstDate = firstDate
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "ClassSchedule")
        weekdays = try reader.strings("weekdays")
        firstDate = try reader.string("firstDate")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("weekdays", weekdays)
        out.set("firstDate", firstDate)
        return out.json
    }
}

/// One block of a saved day: `{ kind, activityIds }` (docs/REDESIGN.md §3.5).
public struct LogBlock: JSONModel {
    public var kind: String
    public var activityIds: [String]
    public var extra: [String: JSONValue]

    public init(kind: String, activityIds: [String], extra: [String: JSONValue] = [:]) {
        self.kind = kind
        self.activityIds = activityIds
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "LogBlock")
        kind = try reader.string("kind")
        activityIds = try reader.strings("activityIds")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("kind", kind)
        out.set("activityIds", activityIds)
        return out.json
    }
}

/// A saved day: `{ n, date, blocks: [{ kind, activityIds }] }` (docs/REDESIGN.md
/// §3.5; D7). `date` is the schedule's date for day n, written as a key even when
/// there is none.
public struct LogEntry: JSONModel {
    public var n: Int
    public var date: String?
    public var blocks: [LogBlock]
    public var extra: [String: JSONValue]

    public init(n: Int, date: String?, blocks: [LogBlock], extra: [String: JSONValue] = [:]) {
        self.n = n
        self.date = date
        self.blocks = blocks
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "LogEntry")
        n = try reader.int("n")
        date = try reader.nullableString("date")
        blocks = try reader.models("blocks")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("n", n)
        out.setAllowingNull("date", date)
        out.set("blocks", blocks)
        return out.json
    }
}

/// One block of the working copy: `{ kind, skillIds, activityIds }` — `skillIds`
/// carries an "any" block's pick (D3, D6).
public struct DraftBlock: JSONModel {
    public var kind: String
    public var skillIds: [String]
    public var activityIds: [String]
    public var extra: [String: JSONValue]

    public init(kind: String, skillIds: [String], activityIds: [String], extra: [String: JSONValue] = [:]) {
        self.kind = kind
        self.skillIds = skillIds
        self.activityIds = activityIds
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "DraftBlock")
        kind = try reader.string("kind")
        skillIds = try reader.strings("skillIds")
        activityIds = try reader.strings("activityIds")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("kind", kind)
        out.set("skillIds", skillIds)
        out.set("activityIds", activityIds)
        return out.json
    }
}

/// The class's single draft — the unsaved edits, picks and shuffle counts of one
/// day: `{ n, blocks: [DraftBlock], shuffleCounts: {<kind>: int} }` (D6;
/// DECISIONS_LOG 2026-09-12 "Unsaved edits live in one draft per class").
public struct Draft: JSONModel {
    public var n: Int
    public var blocks: [DraftBlock]
    public var shuffleCounts: [String: Int]
    public var extra: [String: JSONValue]

    public init(n: Int, blocks: [DraftBlock], shuffleCounts: [String: Int] = [:],
                extra: [String: JSONValue] = [:]) {
        self.n = n
        self.blocks = blocks
        self.shuffleCounts = shuffleCounts
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "Draft")
        n = try reader.int("n")
        blocks = try reader.models("blocks")
        if let raw = reader.claim("shuffleCounts") {
            guard case .object(let entries) = raw else {
                throw JSONModelError.wrongType(type: "Draft", field: "shuffleCounts",
                                               expected: "an object", found: describeJSON(raw))
            }
            shuffleCounts = try entries.mapValues { entry in
                guard let count = entry.intValue else {
                    throw JSONModelError.wrongType(type: "Draft", field: "shuffleCounts",
                                                   expected: "an object of integers", found: describeJSON(entry))
                }
                return count
            }
        } else {
            shuffleCounts = [:]
        }
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("n", n)
        out.set("blocks", blocks)
        out.set("shuffleCounts", .object(shuffleCounts.mapValues { .int(Int64($0)) }))
        return out.json
    }
}

/// One class (docs/REDESIGN.md §2, `Class`; `tools/core/classes.py`):
/// `{ id, name, stageId, ageGroup, lessons, order, schedule, log, draft }`.
/// `draft` is always written, as `null` when there is none, matching the Python.
public struct SwimClass: JSONModel {
    public var id: String
    public var name: String
    public var stageId: String
    /// One of the stage's `ageGroups`; drives the P/S/A age tag (P5).
    public var ageGroup: String
    /// N, the number of lessons (8 by default).
    public var lessons: Int
    /// The class's place among the day's classes; the list sorts by order, then name (C2).
    public var order: Int
    public var schedule: ClassSchedule
    /// Saved days, one entry per n, sorted by n (D7).
    public var log: [LogEntry]
    public var draft: Draft?
    public var extra: [String: JSONValue]

    public init(id: String, name: String, stageId: String, ageGroup: String, lessons: Int = 8,
                order: Int = 1, schedule: ClassSchedule, log: [LogEntry] = [], draft: Draft? = nil,
                extra: [String: JSONValue] = [:]) {
        self.id = id
        self.name = name
        self.stageId = stageId
        self.ageGroup = ageGroup
        self.lessons = lessons
        self.order = order
        self.schedule = schedule
        self.log = log
        self.draft = draft
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "SwimClass")
        id = try reader.string("id")
        name = try reader.string("name")
        stageId = try reader.string("stageId")
        ageGroup = try reader.string("ageGroup")
        lessons = try reader.int("lessons")
        order = try reader.int("order")
        schedule = try reader.model("schedule")
        log = try reader.models("log")
        if let raw = reader.claimIncludingNull("draft"), !raw.isNull {
            draft = try Draft(json: raw)
        } else {
            draft = nil
        }
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("id", id)
        out.set("name", name)
        out.set("stageId", stageId)
        out.set("ageGroup", ageGroup)
        out.set("lessons", lessons)
        out.set("order", order)
        out.set("schedule", schedule)
        out.set("log", log)
        out.set("draft", draft.map(\.json) ?? .null)
        return out.json
    }
}

// MARK: - Settings

/// `settings.json` (`settings/1`; docs/REDESIGN.md §6). Three display toggles
/// (DECISIONS_LOG 2026-09-12, "Welcome and Topic blocks are off by default";
/// 2026-09-13, "Introduce before Review"): a file without them reads as all
/// off and is written back without them,
/// so the record still keeps exactly what it holds until a toggle is set.
/// `finderStageId` (V5, "The plan is the product") remembers the finder's
/// last stage the same way: absent until the finder is used. Any other field
/// is kept as it was read and written back unchanged.
public struct Settings: JSONModel {
    /// Draw the Welcome block on a day's screen. Display only: the plan and
    /// the saved entry keep the block either way.
    public var showWelcome: Bool {
        get { welcomeFlag ?? false }
        set { welcomeFlag = newValue }
    }
    /// Draw the Topic (Y value) block on a day's screen. Display only.
    public var showTopic: Bool {
        get { topicFlag ?? false }
        set { topicFlag = newValue }
    }
    /// Draw Review before Introduce, as the Lesson Guide prints them; off,
    /// Introduce comes first. Display only.
    public var reviewFirst: Bool {
        get { reviewFirstFlag ?? false }
        set { reviewFirstFlag = newValue }
    }
    /// The stage the finder last showed (F7's remembered stage); nil until set.
    public var finderStageId: String?
    public var extra: [String: JSONValue]
    /// nil when the file never held the key.
    private var welcomeFlag: Bool?
    private var topicFlag: Bool?
    private var reviewFirstFlag: Bool?

    public init(showWelcome: Bool? = nil, showTopic: Bool? = nil, reviewFirst: Bool? = nil,
                finderStageId: String? = nil, extra: [String: JSONValue] = [:]) {
        welcomeFlag = showWelcome
        topicFlag = showTopic
        reviewFirstFlag = reviewFirst
        self.finderStageId = finderStageId
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "Settings")
        welcomeFlag = try reader.optionalBool("showWelcome")
        topicFlag = try reader.optionalBool("showTopic")
        reviewFirstFlag = try reader.optionalBool("reviewFirst")
        finderStageId = try reader.optionalString("finderStageId")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        if let welcomeFlag { out.set("showWelcome", .bool(welcomeFlag)) }
        if let topicFlag { out.set("showTopic", .bool(topicFlag)) }
        if let reviewFirstFlag { out.set("reviewFirst", .bool(reviewFirstFlag)) }
        if let finderStageId { out.set("finderStageId", .string(finderStageId)) }
        return out.json
    }
}
