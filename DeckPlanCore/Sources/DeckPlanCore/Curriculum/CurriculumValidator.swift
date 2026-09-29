//
//  CurriculumValidator.swift
//  DeckPlanCore
//
//  Every check of docs/CURRICULUM_FORMAT.md §5 (docs/TEST_CASES.md A2–A14). A
//  port of `validate`, `_Checker` and every `_check_*` function in
//  `tools/core/curriculum.py`. Never raises on bad data — each check reads a
//  `JSONValue` the way Python's checks read a dict, with `if`/`guard` standing
//  in for `isinstance`, and reports a `Problem` instead of trusting the shape.
//
//  Message wording is free to differ from the Python (the M4 brief: "messages
//  are plain sentences naming what Python's name"); the codes, severities and
//  the conditions that trigger them are ported exactly, since those are what
//  the app and the tests key off.
//

import Foundation

// MARK: - Summary (docs/TEST_CASES.md A1)

/// One loaded stage's counts, as `CurriculumValidator.summary` reports them.
public struct CurriculumStageSummary: Sendable, Equatable {
    public var name: String
    public var skills: Int
    public var steps: Int
    public var activityLinks: Int
    public var greeting: Int
    public var topics: Int
    public var templates: Int
    public var trackerRows: Int
}

/// Activity counts by source.
public struct CurriculumActivitySummary: Sendable, Equatable {
    public var ymca: Int
    public var local: Int
}

/// Equipment counts by kind and source.
public struct CurriculumEquipmentSummary: Sendable, Equatable {
    public var items: Int
    public var groups: Int
    public var local: Int
}

/// The whole-curriculum counts `CurriculumValidator.summary` reports
/// (docs/TEST_CASES.md A1) — `tools/core/curriculum.py`'s `summary`.
public struct CurriculumSummary: Sendable, Equatable {
    public var version: String?
    /// Loaded stage ids, in stage order.
    public var loaded: [String]
    /// Stage ids that did not load, in stage order.
    public var notLoaded: [String]
    public var stages: [String: CurriculumStageSummary]
    public var activities: CurriculumActivitySummary
    public var equipment: CurriculumEquipmentSummary
    public var videos: Int
    public var safety: Int
}

// MARK: - The validator

/// Validates a `LoadedCurriculum` against every check of
/// docs/CURRICULUM_FORMAT.md §5. Never raises.
public enum CurriculumValidator {

    /// Every check of docs/CURRICULUM_FORMAT.md §5. Returns the load problems
    /// first, then the validation problems.
    public static func validate(_ curriculum: LoadedCurriculum) -> [Problem] {
        let checker = Checker(curriculum)
        checker.guarded("equipment catalog", "equipment.json") { checkEquipment($0) }
        checker.guarded("safety rules", "safety.json") { checkSafety($0) }
        for stage in curriculum.stages {
            checker.guarded("stage", "stage \(displayId(stage["id"]))") { checkStage($0, stage) }
        }
        checker.guarded("activities", "activities.json") { checkActivities($0) }
        checker.guarded("videos", "videos.json") { checkVideos($0) }
        checker.guarded("local additions", "local.json") { checkLocal($0) }
        checker.guarded("ids", "curriculum") { checkCrossIds($0) }
        checker.guarded("placeholders", "curriculum") { checkPlaceholders($0) }
        return curriculum.loadProblems + checker.problems
    }

    /// `load(directory:)` + `validate`.
    public static func check(directory root: URL, localPath: URL? = nil) -> (LoadedCurriculum, [Problem]) {
        let curriculum = CurriculumLoader.load(directory: root, localPath: localPath)
        return (curriculum, validate(curriculum))
    }

    /// `load(sampleFile:)` + `validate`.
    public static func check(sampleFile path: URL) -> (LoadedCurriculum, [Problem]) {
        let curriculum = CurriculumLoader.load(sampleFile: path)
        return (curriculum, validate(curriculum))
    }

    /// `load(sampleFiles:)` + `validate`.
    public static func check(sampleFiles paths: [URL]) -> (LoadedCurriculum, [Problem]) {
        let curriculum = CurriculumLoader.load(sampleFiles: paths)
        return (curriculum, validate(curriculum))
    }

    // MARK: Counts (A1)

    public static func summary(_ curriculum: LoadedCurriculum) -> CurriculumSummary {
        var stages: [String: CurriculumStageSummary] = [:]
        for stage in curriculum.stages {
            let skills = dictItems(stage["skills"])
            let steps = skills.reduce(0) { $0 + dictItems($1["steps"]).count }
            let activityLinks = skills.reduce(0) { total, skill -> Int in
                guard case .array(let items)? = skill["activityIds"] else { return total }
                return total + items.count
            }
            let greeting: Int
            if case .array(let items)? = stage["greetingActivityIds"] { greeting = items.count } else { greeting = 0 }
            stages[displayId(stage["id"])] = CurriculumStageSummary(
                name: text(stage["name"]),
                skills: skills.count,
                steps: steps,
                activityLinks: activityLinks,
                greeting: greeting,
                topics: dictItems(stage["topics"]).count,
                templates: dictItems(stage["lessonTemplates"]).count,
                trackerRows: dictItems(stage["trackerRows"]).count)
        }
        let activities = dictItems(curriculum.activities)
        let equipment = dictItems(curriculum.equipment)
        let loaded = curriculum.loadedStageIds
        return CurriculumSummary(
            version: curriculum.version,
            loaded: loaded,
            notLoaded: Ids.stageIds.filter { !loaded.contains($0) },
            stages: stages,
            activities: CurriculumActivitySummary(
                ymca: activities.filter { $0["source"]?.stringValue != "local" }.count,
                local: activities.filter { $0["source"]?.stringValue == "local" }.count),
            equipment: CurriculumEquipmentSummary(
                items: equipment.filter { $0["kind"]?.stringValue == "item" && $0["source"]?.stringValue != "local" }.count,
                groups: equipment.filter { $0["kind"]?.stringValue == "group" }.count,
                local: equipment.filter { $0["source"]?.stringValue == "local" }.count),
            videos: dictItems(curriculum.videos).count,
            safety: dictItems(curriculum.safety).count)
    }

    public static func formatSummary(_ summary: CurriculumSummary) -> [String] {
        var lines: [String] = []
        var line = "Loaded stages: \(summary.loaded.isEmpty ? "none" : summary.loaded.joined(separator: ", "))."
        if !summary.notLoaded.isEmpty {
            line += " Not loaded: \(summary.notLoaded.joined(separator: ", "))."
        }
        lines.append(line)
        for stageId in summary.loaded {
            guard let s = summary.stages[stageId] else { continue }
            lines.append("Stage \(stageId) \(s.name): \(s.skills) skills, \(s.steps) steps, \(s.activityLinks) activity links, "
                + "\(s.greeting) greeting activities, \(s.topics) topics, \(s.templates) lesson templates, \(s.trackerRows) tracker rows.")
        }
        let groups = summary.equipment.groups
        lines.append("Activities: \(summary.activities.ymca) (local \(summary.activities.local)). "
            + "Equipment: \(summary.equipment.items) items, \(groups) group\(groups == 1 ? "" : "s") (local \(summary.equipment.local)). "
            + "Videos: \(summary.videos). Safety rules: \(summary.safety).")
        return lines
    }
}

// MARK: - The checker

/// Where an equipment or activity catalog entry came from — replaces
/// `tools/core/curriculum.py`'s identity-based `_Checker.origin`; see
/// `LoadedCurriculum`'s doc comment for why.
enum CatalogOrigin: String {
    case ymca
    case local
}

/// Accumulates problems while validating, and the small shared field checks
/// every `_check_*` uses (`tools/core/curriculum.py`'s `_Checker`).
final class Checker {
    let cur: LoadedCurriculum
    private(set) var problems: [Problem] = []
    /// `equipment.json` and `local.json`'s equipment, id -> entry (first wins).
    let catalog: [String: JSONValue]

    static let stepFlags = ["headfirst", "reachBottom", "nearWall", "submerges"]
    static let activityFlags = ["headfirst", "reachBottom", "flotationOption", "submerges"]
    static let measureKinds = ["distance", "time", "count"]
    static let measureUnits: [String: [String]] = ["distance": ["ft", "yd"], "time": ["s", "min"]]
    static let topicsPerStage = 8
    static let templatesPerStage = 8
    static let minSkillsPerStage = 8
    static let placeholder = "TODO-M1"
    static let unreadableMarker = "UNREADABLE"
    static let localFormat = "local/1"
    static let singleInhalationId = "single-inhalation"

    init(_ curriculum: LoadedCurriculum) {
        self.cur = curriculum
        var catalog: [String: JSONValue] = [:]
        for entry in dictItems(curriculum.equipment) {
            if let id = entry["id"]?.stringValue, catalog[id] == nil { catalog[id] = entry }
        }
        self.catalog = catalog
    }

    func add(_ code: String, _ location: String, _ message: String, _ severity: Severity = .error) {
        problems.append(Problem(code: code, severity: severity, where: location, message: message))
    }

    /// Runs `body`; a thrown error becomes a `check-failed` problem rather than
    /// aborting the rest of `validate` (`tools/core/curriculum.py`'s `guarded`).
    /// None of this port's checks are written to throw — they read `JSONValue`
    /// with `if`/`guard`, never force-unwrapping or indexing out of bounds, since
    /// an out-of-bounds Swift array access is a fatal trap that no `catch` can
    /// intercept (unlike Python's catchable `IndexError`). This wrapper is kept
    /// for structural fidelity and as a safety net for a future check that does
    /// throw; the real "never crashes" guarantee comes from every check below
    /// using safe optional-binding throughout.
    func guarded(_ label: String, _ location: String, _ body: (Checker) throws -> Void) {
        do {
            try body(self)
        } catch {
            add("check-failed", `location`,
                "The \(label) check stopped early on malformed data (\(error)); fix the problems reported here and validate again.")
        }
    }

    /// Whether `fileName` failed to load (docs/TEST_CASES.md A10): checks
    /// depending on it skip rather than pile on redundant problems.
    func unloaded(_ fileName: String) -> Bool {
        cur.loadProblems.contains { $0.`where` == fileName && ($0.code == "file-missing" || $0.code == "file-unreadable") }
    }

    /// Whether `cur.activities[index]` came from `local.json` (appended after
    /// the YMCA entries in catalog order — see `LoadedCurriculum.localActivityCount`).
    func originOfActivity(index: Int) -> CatalogOrigin {
        index >= cur.activities.count - cur.localActivityCount ? .local : .ymca
    }

    /// The equipment equivalent of `originOfActivity`.
    func originOfEquipment(index: Int) -> CatalogOrigin {
        index >= cur.equipment.count - cur.localEquipmentCount ? .local : .ymca
    }

    // MARK: Shared field checks

    func depths(_ value: JSONValue?, _ location: String) {
        guard case .array(let items)? = value, !items.isEmpty else {
            add("depths", `location`,
                "depths must be a non-empty list of shallow, medium and deep (leave it out for any zone); it is \(show(value)).")
            return
        }
        let bad = items.filter { !($0.stringValue.map { Ids.zones.contains($0) } ?? false) }
        if !bad.isEmpty {
            add("depths", `location`, "depths has \(show(.array(bad))), which is not a zone (shallow, medium, deep).")
        } else {
            let strings = items.compactMap(\.stringValue)
            if Set(strings).count != items.count {
                add("depths", `location`, "depths lists a zone twice: \(show(value)).")
            }
        }
    }

    func flags(_ entry: JSONValue, _ names: [String], _ location: String) {
        for name in names {
            guard let value = entry[name] else { continue }
            if case .bool = value { continue }
            add("flag-type", `location`, "\(name) must be true or false; it is \(show(value)).")
        }
    }

    func headfirst(_ entry: JSONValue, _ location: String) {
        guard case .bool(true)? = entry["headfirst"] else { return }
        let depthsValue = entry["depths"]
        var isExactlyDeep = false
        if case .array(let items)? = depthsValue, items.count == 1, items[0].stringValue == "deep" {
            isExactlyDeep = true
        }
        if !isExactlyDeep {
            add("headfirst-depths", `location`, "A headfirst entry has depths [\"deep\"]; this one has \(show(depthsValue)).")
        }
    }

    func equipmentId(_ equipmentId: String, _ location: String, _ field: String) {
        if unloaded("equipment.json") { return }
        if catalog[equipmentId] == nil {
            add("equipment-unknown", `location`,
                "\(field) names \"\(equipmentId)\", which is not in the equipment catalog (equipment.json or local.json).")
        }
    }

    func requirementGroups(_ value: JSONValue?, _ location: String, field: String = "equipment") {
        guard case .array(let groups)? = value else {
            add("equipment-shape", `location`,
                "\(field) must be a list of requirement groups ([] = no equipment); it is \(show(value)).")
            return
        }
        for group in groups {
            guard let items = strList(group), !items.isEmpty else {
                add("equipment-shape", `location`,
                    "\(field) has \(show(group)); each requirement group is a non-empty list of equipment ids.")
                continue
            }
            for equipmentIdValue in items {
                equipmentId(equipmentIdValue, `location`, field)
            }
        }
    }

    func optionalEquipment(_ value: JSONValue?, _ location: String) {
        guard let items = strList(value) else {
            add("equipment-shape", `location`, "equipmentOptional must be a list of equipment ids; it is \(show(value)).")
            return
        }
        for equipmentIdValue in items {
            equipmentId(equipmentIdValue, `location`, "equipmentOptional")
        }
    }

    func measure(_ value: JSONValue?, _ location: String) {
        guard case .object = value else {
            add("measure", `location`, "measure must be an object; it is \(show(value)).")
            return
        }
        let kind = value?["kind"]?.stringValue
        let amount = value?["value"]
        if kind == nil || !Checker.measureKinds.contains(kind!) {
            add("measure", `location`, "measure kind \(show(value?["kind"])) is not distance, time or count.")
        }
        if !isNumber(amount) || (amount?.doubleValue ?? 0) <= 0 {
            add("measure", `location`, "measure value \(show(amount)) is not a positive number.")
        }
        if let kind, let allowedUnits = Checker.measureUnits[kind] {
            let unit = value?["unit"]?.stringValue
            if unit == nil || !allowedUnits.contains(unit!) {
                add("measure", `location`,
                    "a \(kind) measure's unit is \(allowedUnits.joined(separator: " or ")); it is \(show(value?["unit"])).")
            }
        }
        if kind == "count", let unitField = value?["unit"] {
            if case .string = unitField {} else {
                add("measure", `location`, "a count measure's unit, when given, is a word.")
            }
        }
        if let preschoolField = value?["preschoolValue"] {
            if !isNumber(preschoolField) || (preschoolField.doubleValue ?? 0) <= 0 {
                add("preschool-value", `location`, "preschoolValue \(show(preschoolField)) is not a positive number.")
            } else if isNumber(amount), let amountNumber = amount?.doubleValue, let preschoolNumber = preschoolField.doubleValue,
                      preschoolNumber >= amountNumber {
                add("preschool-value", `location`,
                    "preschoolValue \(show(preschoolField)) is not less than the value \(show(amount)); the preschool variant is the shorter one.",
                    .warning)
            }
        }
    }
}

// MARK: - Equipment catalog (A13)

func checkEquipment(_ c: Checker) {
    if c.unloaded("equipment.json") { return }
    var seen: Set<String> = []
    for (index, entry) in c.cur.equipment.enumerated() {
        guard case .object = entry else {
            c.add("equipment-catalog", "equipment entry \(index + 1)", "An equipment entry is not an object.")
            continue
        }
        let equipmentId = entry["id"]?.stringValue
        let origin = c.originOfEquipment(index: index)
        let location = origin == .local
            ? "local.json / equipment \(displayId(entry["id"]))"
            : "equipment \(displayId(entry["id"]))"
        let seenKey = "\(equipmentId ?? "")\u{0}\(origin.rawValue)"
        if !Ids.isSlug(equipmentId) {
            c.add("equipment-catalog", location, "Equipment id \(show(entry["id"])) is not a lower-case slug.")
        } else if seen.contains(seenKey) {
            c.add("id-duplicate", location,
                "Equipment id \"\(equipmentId ?? "")\" appears twice in \(origin == .local ? "local.json" : "equipment.json").")
        }
        seen.insert(seenKey)

        if origin == .ymca, entry["source"]?.stringValue != "ymca" {
            c.add("equipment-catalog", location,
                "equipment.json holds the toolkit's items only (source \"ymca\"); your own items go in local.json.")
        }
        if !isNonBlankString(entry["name"]) {
            c.add("equipment-catalog", location, "Equipment \(show(entry["id"])) has no name.")
        }
        if !isStrList(entry["aliases"] ?? .array([])) {
            c.add("equipment-catalog", location, "aliases must be a list of words.")
        }
        let kind = entry["kind"]?.stringValue
        if kind == "group" {
            guard let members = strList(entry["anyOf"]), !members.isEmpty else {
                c.add("equipment-catalog", location, "The group \(show(entry["id"])) has no anyOf list of items.")
                continue
            }
            for member in members {
                guard let target = c.catalog[member] else {
                    c.add("equipment-catalog", location, "The group \(show(entry["id"])) lists \"\(member)\", which is not in the catalog.")
                    continue
                }
                if target["kind"]?.stringValue != "item" {
                    c.add("equipment-catalog", location,
                        "The group \(show(entry["id"])) lists \"\(member)\", which is not an item; a group's anyOf names items only.")
                }
            }
        } else if kind == "item" {
            if isTruthy(entry["anyOf"]) {
                c.add("equipment-catalog", location, "The item \(show(entry["id"])) has anyOf; anyOf is on groups only.")
            }
        } else {
            c.add("equipment-catalog", location,
                "Equipment \(show(entry["id"])) has kind \(show(entry["kind"])); it must be \"item\" or \"group\".")
        }
    }
}

// MARK: - Safety rules (A14)

func checkSafety(_ c: Checker) {
    if c.unloaded("safety.json") || (c.cur.kind == .sample && c.cur.safety.isEmpty) {
        if c.cur.kind == .sample, c.cur.safety.isEmpty {
            c.add("safety", "safety", "The sample has no safety rules; it needs single-inhalation.")
        }
        return
    }
    var seen: Set<String> = []
    for (index, rule) in c.cur.safety.enumerated() {
        var location = "safety rule \(index + 1)"
        guard case .object = rule else {
            c.add("safety", location, "A safety rule is not an object { id, text, tags[] }.")
            continue
        }
        let ruleId = rule["id"]?.stringValue
        if let ruleId, !ruleId.isEmpty {
            location = "safety \(ruleId)"
            if seen.contains(ruleId) {
                c.add("id-duplicate", location, "Safety rule id \"\(ruleId)\" appears twice.")
            }
            seen.insert(ruleId)
        } else {
            c.add("safety", location, "A safety rule has no id.")
        }
        if !isNonBlankString(rule["text"]) {
            c.add("safety", location, "The safety rule \(show(rule["id"])) has no text.")
        }
        if !isStrList(rule["tags"]) {
            c.add("safety", location, "The safety rule \(show(rule["id"])) needs tags, a list of words ([] for none).")
        }
    }
    guard let single = dictItems(c.cur.safety).first(where: { $0["id"]?.stringValue == Checker.singleInhalationId }) else {
        c.add("safety", "safety", "There is no single-inhalation rule; the plan prints it whenever a placed activity or step submerges.")
        return
    }
    var tagsOK = false
    if case .array(let items)? = single["tags"], items.count == 1, items[0].stringValue == "submerges" {
        tagsOK = true
    }
    if !tagsOK {
        c.add("safety", "safety \(Checker.singleInhalationId)",
            "The single-inhalation rule's tags must be [\"submerges\"]; they are \(show(single["tags"])).")
    }
}

// MARK: - Stages (A2–A8)

func checkStage(_ c: Checker, _ stage: JSONValue) {
    let stageIdValue = stage["id"]
    let stageId = displayId(stageIdValue)
    let location = "stage \(stageId)"

    if !isNonBlankString(stage["name"]) {
        c.add("stage-shape", location, "Stage \(stageId) has no name.")
    }
    if !isNonBlankString(stage["group"]) {
        c.add("stage-shape", location, "Stage \(stageId) has no group.")
    }
    let ageGroups = stage["ageGroups"]
    var ageGroupsOK = false
    if let list = strList(ageGroups) {
        ageGroupsOK = !list.isEmpty && list.allSatisfy { Ids.ageGroups.contains($0) }
    }
    if !ageGroupsOK {
        c.add("stage-shape", location,
            "Stage \(stageId)'s ageGroups must be a non-empty list of \(Ids.ageGroups.joined(separator: ", ")); it is \(show(ageGroups)).")
    }

    var lessonMinutes: Int?
    if isInt(stage["lessonMinutes"]), let value = stage["lessonMinutes"]?.intValue, value > 0 {
        lessonMinutes = value
    } else {
        c.add("stage-shape", location, "Stage \(stageId)'s lessonMinutes must be a positive whole number.")
    }

    if !isStrList(stage["milestones"] ?? .array([])) {
        c.add("stage-shape", location, "Stage \(stageId)'s milestones must be a list of sentences.")
    }

    var rawSkills: [JSONValue] = []
    if case .array(let items)? = stage["skills"] {
        rawSkills = items
    } else {
        c.add("stage-shape", location, "Stage \(stageId) has no skills list.")
    }
    let skills = dictItems(rawSkills)
    if skills.count != rawSkills.count {
        c.add("stage-shape", location, "Stage \(stageId)'s skills list holds something that is not a skill object.")
    }
    if skills.count < Checker.minSkillsPerStage {
        c.add("skill-count", location, "Stage \(stageId) has \(skills.count) skills; every stage has at least \(Checker.minSkillsPerStage).")
    }

    var seenSkills = Set<String>()
    var stepNames: [String: String] = [:]
    var orders: [JSONValue?] = []
    for (index, skill) in skills.enumerated() {
        c.guarded("skill", "\(location) / skill #\(index + 1)") { checker in
            checkSkill(checker, stage, skill, index, &seenSkills, &stepNames)
        }
        orders.append(skill["order"])
    }
    if !orders.isEmpty {
        let ints = orders.compactMap { value -> Int? in
            guard let value, isInt(value) else { return nil }
            return value.intValue
        }
        let allInts = ints.count == orders.count
        var monotonic = true
        if allInts, ints.count > 1 {
            for i in 0..<(ints.count - 1) where !(ints[i] < ints[i + 1]) {
                monotonic = false
                break
            }
        }
        if !(allInts && monotonic) {
            c.add("skill-shape", location, "Stage \(stageId)'s skill orders are \(show(orders)); they rise in library order.")
        }
    }
    for skill in skills {
        c.guarded("links", "\(location) / skill \(displayId(skill["id"]))") { checker in
            checkLinks(checker, stage, skill)
        }
    }

    for key in ["warmUpSkill", "wrapUpSkill"] {
        let value = stage[key]?.stringValue
        let skill = value.flatMap { c.cur.skill($0) }
        if skill == nil || skill?["stageId"]?.stringValue != stageIdValue?.stringValue {
            c.add("warm-up-wrap-up", location, "Stage \(stageId)'s \(key) \(show(stage[key])) is not a skill of Stage \(stageId).")
        }
    }

    let greeting = stage["greetingActivityIds"]
    if !isStrList(greeting) {
        c.add("stage-shape", location, "Stage \(stageId)'s greetingActivityIds must be a list of activity ids.")
    } else if !c.unloaded("activities.json") {
        for activityId in strList(greeting) ?? [] where c.cur.activity(activityId) == nil {
            c.add("activity-missing", location, "Stage \(stageId)'s Greeting lists \"\(activityId)\", which is not an activity.")
        }
    }

    c.guarded("topics", "\(location) / topics") { checker in checkTopics(checker, stage) }
    c.guarded("lesson templates", "\(location) / lesson templates") { checker in checkTemplates(checker, stage, lessonMinutes) }
    c.guarded("tracker rows", "\(location) / tracker rows") { checker in checkTrackerRows(checker, stage) }
}

func checkSkill(_ c: Checker, _ stage: JSONValue, _ skill: JSONValue, _ index: Int,
                _ seenSkills: inout Set<String>, _ stepNames: inout [String: String]) {
    let stageId = displayId(stage["id"])
    let skillIdValue = skill["id"]
    let skillIdText = skillIdValue?.stringValue ?? "#\(index + 1)"
    let location = "stage \(stageId) / skill \(skillIdText)"

    let parsed = Ids.parseSkillId(skillIdValue?.stringValue)
    var skillSlug: String?
    if parsed == nil || parsed?.stage != stage["id"]?.stringValue {
        c.add("skill-shape", location, "Skill id \(show(skillIdValue)) does not follow <stage>.<skill-slug> for Stage \(stageId).")
    } else if let parsed {
        skillSlug = parsed.skillSlug
        if let skillId = skillIdValue?.stringValue {
            if seenSkills.contains(skillId) {
                c.add("id-duplicate", location, "Skill id \"\(skillId)\" appears twice in Stage \(stageId).")
            }
            seenSkills.insert(skillId)
        }
    }
    if !isNonBlankString(skill["name"]) {
        c.add("skill-shape", location, "Skill \(displayId(skillIdValue)) has no name.")
    }
    if case .bool? = skill["isBenchmarkSequence"] {} else {
        c.add("skill-shape", location, "Skill \(displayId(skillIdValue))'s isBenchmarkSequence must be true or false.")
    }

    var rawSteps: [JSONValue] = []
    if case .array(let items)? = skill["steps"] {
        rawSteps = items
    } else {
        c.add("steps", location, "Skill \(displayId(skillIdValue)) has no steps list ([] when the stage has no progression for it).")
    }
    let steps = dictItems(rawSteps)
    let expectedNumbers: [JSONValue?] = stride(from: 1, through: steps.count, by: 1).map { JSONValue.int(Int64($0)) }
    let actualNumbers: [JSONValue?] = steps.map { $0["n"] }
    let numbersMatch = actualNumbers.count == expectedNumbers.count && zip(actualNumbers, expectedNumbers).allSatisfy { $0 == $1 }
    if steps.count != rawSteps.count || !numbersMatch {
        c.add("steps", location, "Skill \(displayId(skillIdValue))'s steps are numbered \(show(actualNumbers)); they run 1, 2, 3\u{2026} in order.")
    }

    for (position, step) in steps.enumerated() {
        let stepIdValue = step["id"]
        let stepWhere = "stage \(stageId) / step \(stepIdValue?.stringValue ?? "\(skillIdText) #\(position + 1)")"
        let n = step["n"]
        if let skillSlug, isInt(n), let nValue = n?.intValue {
            let expectedStepId = Ids.stepId(stage["id"]?.stringValue ?? stageId, skillSlug, nValue)
            if stepIdValue?.stringValue != expectedStepId {
                c.add("steps", stepWhere, "Step id \(show(stepIdValue)) should be \"\(expectedStepId)\" (<stage>.<skill-slug>.<n>).")
            }
        }
        if !isNonBlankString(step["name"]) {
            c.add("steps", stepWhere, "Step \(displayId(stepIdValue)) has no name.")
        } else if let nameText = step["name"]?.stringValue {
            let key = "\(skillIdText)\u{0}\(Ids.descriptionKey(nameText))"
            if let earlier = stepNames[key] {
                c.add("step-name-duplicate", stepWhere,
                    "Step name \"\(nameText)\" is used by both \(earlier) and \(displayId(stepIdValue)); step names are unique within a skill.")
            } else {
                stepNames[key] = displayId(stepIdValue)
            }
        }
        if !isNonBlankString(step["description"]) {
            c.add("steps", stepWhere, "Step \(displayId(stepIdValue)) has no description.")
        }
        if let measureField = step["measure"] {
            c.measure(measureField, stepWhere)
            if case .object = measureField, isPresentNonNull(measureField["preschoolValue"]), position != steps.count - 1 {
                c.add("preschool-value", stepWhere,
                    "Step \(displayId(stepIdValue)) has a preschoolValue, but only a benchmark step carries the Progress Tracker's preschool variant.")
            }
        }
        if let depthsField = step["depths"] {
            c.depths(depthsField, stepWhere)
        }
        c.flags(step, Checker.stepFlags, stepWhere)
        c.headfirst(step, stepWhere)
        if let equipmentField = step["equipment"] {
            c.requirementGroups(equipmentField, stepWhere)
        }
    }

    let benchmark = skill["benchmarkStepId"]
    if let last = steps.last {
        let lastId = last["id"]
        if benchmark != lastId {
            c.add("benchmark", location,
                "Skill \(displayId(skillIdValue))'s benchmarkStepId is \(show(benchmark)); it must be its last step, \(show(lastId)).")
        }
    } else if isPresentNonNull(benchmark) {
        c.add("benchmark", location, "Skill \(displayId(skillIdValue)) has no steps in Stage \(stageId), so its benchmarkStepId must be null.")
    }

    for field in ["prerequisiteStepIds", "advancedStepIds"] {
        if !isStrList(skill[field]) {
            c.add("skill-shape", location, "Skill \(displayId(skillIdValue))'s \(field) must be a list of step ids ([] for none).")
        }
    }
    if let activityIds = strList(skill["activityIds"]) {
        if !c.unloaded("activities.json") {
            for activityId in activityIds where c.cur.activity(activityId) == nil {
                c.add("activity-missing", location, "Skill \(displayId(skillIdValue)) lists activity \"\(activityId)\", which is not an activity.")
            }
            if Set(activityIds).count != activityIds.count {
                c.add("skill-shape", location, "Skill \(displayId(skillIdValue)) lists an activity twice.", .warning)
            }
        }
    } else {
        c.add("skill-shape", location, "Skill \(displayId(skillIdValue))'s activityIds must be a list of activity ids.")
    }
    if let videoIds = strList(skill["videoIds"] ?? .array([])) {
        if c.cur.kind == .directory, !c.unloaded("videos.json") {
            for videoId in videoIds where c.cur.video(videoId) == nil {
                c.add("video-link", location, "Skill \(displayId(skillIdValue)) lists video \"\(videoId)\", which is not in videos.json.")
            }
        }
    } else {
        c.add("skill-shape", location, "Skill \(displayId(skillIdValue))'s videoIds must be a list of video ids.")
    }
}

/// The stage ids strictly between `first` and `second` (either order), in stage order.
func stagesBetween(_ first: String, _ second: String) -> [String] {
    guard let a = Ids.stageIndex[first], let b = Ids.stageIndex[second] else { return [] }
    let low = min(a, b), high = max(a, b)
    guard low + 1 < high else { return [] }
    return Array(Ids.stageIds[(low + 1)..<high])
}

/// A4: prerequisite ids point into the nearest earlier stage with the skill's
/// steps, advanced ids into the nearest later one; into a stage that isn't
/// loaded: a warning.
func checkLinks(_ c: Checker, _ stage: JSONValue, _ skill: JSONValue) {
    guard let stageId = stage["id"]?.stringValue, let here = Ids.stageIndex[stageId] else { return }
    guard let parsed = Ids.parseSkillId(skill["id"]?.stringValue) else { return }
    let skillSlug = parsed.skillSlug
    let skillIdText = displayId(skill["id"])
    let location = "stage \(stageId) / skill \(skillIdText)"

    let columns: [(field: String, label: String, direction: Int)] = [
        ("prerequisiteStepIds", "Prerequisite steps", -1),
        ("advancedStepIds", "Advanced steps", 1),
    ]
    for (field, label, direction) in columns {
        guard let values = strList(skill[field]), !values.isEmpty else { continue }
        if direction < 0, stageId == Ids.stageIds.first {
            c.add("link-unresolved", location,
                "Stage A is the first stage, so \(skillIdText) has no prerequisite steps; it lists \(show(values)).")
            continue
        }
        if direction > 0, stageId == Ids.stageIds.last {
            c.add("link-unresolved", location, "Stage 6 is the last stage, so \(skillIdText) has no advanced steps; it lists \(show(values)).")
            continue
        }
        var stagesNamed: [String] = []
        var notLoadedOrder: [String] = []
        var notLoadedValues: [String: [String]] = [:]
        for value in values {
            guard let ref = Ids.parseStepId(value) else {
                c.add("link-unresolved", location, "\(label) of \(skillIdText) include \"\(value)\", which is not a step id.")
                continue
            }
            guard let there = Ids.stageIndex[ref.stage] else { continue }
            if (direction < 0 && there >= here) || (direction > 0 && there <= here) {
                c.add("link-unresolved", location,
                    "\(label) of \(skillIdText) include \(value), which is not in an \(direction < 0 ? "earlier" : "later") stage.")
                continue
            }
            if !stagesNamed.contains(ref.stage) { stagesNamed.append(ref.stage) }
            if !c.cur.isLoaded(ref.stage) {
                if notLoadedValues[ref.stage] == nil { notLoadedOrder.append(ref.stage) }
                notLoadedValues[ref.stage, default: []].append(value)
                continue
            }
            guard c.cur.step(value) != nil else {
                c.add("link-unresolved", location, "\(label) of \(skillIdText) include \(value), which is not a step of Stage \(ref.stage).")
                continue
            }
            if ref.skillSlug == skillSlug {
                for middle in stagesBetween(stageId, ref.stage) {
                    guard let nearer = c.cur.skill(Ids.skillId(middle, skillSlug)), !dictItems(nearer["steps"]).isEmpty else { continue }
                    c.add("link-unresolved", location,
                        "\(label) of \(skillIdText) point into Stage \(ref.stage), but Stage \(middle) is nearer and has "
                        + "\(displayId(nearer["id"])) steps; links go to the nearest stage that has them.")
                    break
                }
            }
        }
        if stagesNamed.count > 1 {
            c.add("link-unresolved", location,
                "\(label) of \(skillIdText) come from Stages \(stagesNamed.joined(separator: ", ")); a column lists one stage's steps.")
        }
        for refStage in notLoadedOrder {
            let valuesThere = notLoadedValues[refStage] ?? []
            c.add("link-not-loaded", location,
                "\(label) of \(skillIdText) point into Stage \(refStage), which isn't loaded: \(valuesThere.joined(separator: ", ")) "
                + "(printed without names, e.g. \"\(Ids.stepLabel(valuesThere.first ?? ""))\").",
                .warning)
        }
    }
}

func checkTopics(_ c: Checker, _ stage: JSONValue) {
    let stageId = displayId(stage["id"])
    let location = "stage \(stageId) / topics"
    guard case .array(let topicsRaw)? = stage["topics"] else {
        c.add("topics", location, "Stage \(stageId) has no topics list.")
        return
    }
    let items = dictItems(topicsRaw)
    let ns = items.map { $0["n"] }
    let intNs = ns.compactMap { value -> Int? in
        guard let value, isInt(value) else { return nil }
        return value.intValue
    }.sorted()
    if items.count != topicsRaw.count || intNs != Array(1...Checker.topicsPerStage) {
        c.add("topics", location, "Stage \(stageId) has topics \(show(ns)); it needs exactly topics 1\u{2013}8.")
    }
    for topic in items {
        let n = topic["n"]
        let code = topic["code"]
        let topicWhere = "stage \(stageId) / topic \(displayId(code))"
        if isInt(n), let nValue = n?.intValue {
            let expectedCode = Ids.topicCode(stageId, nValue)
            if code?.stringValue != expectedCode {
                c.add("topics", topicWhere, "Topic \(nValue)'s code is \(show(code)); it must be \"\(expectedCode)\".")
            }
        }
        if !isNonBlankString(topic["name"]) {
            c.add("topics", topicWhere, "Topic \(show(code)) has no name.")
        }
        if let summaryField = topic["summary"] {
            if case .string = summaryField {} else {
                c.add("topics", topicWhere, "Topic \(show(code))'s summary must be a sentence.")
            }
        }
        for field in ["prompts", "notes"] {
            if !isStrList(topic[field]) {
                c.add("topics", topicWhere, "Topic \(show(code))'s \(field) must be a list of sentences ([] for none).")
            }
        }
    }
}

func checkTemplates(_ c: Checker, _ stage: JSONValue, _ lessonMinutes: Int?) {
    let stageId = displayId(stage["id"])
    let location = "stage \(stageId) / lesson templates"
    guard case .array(let templatesRaw)? = stage["lessonTemplates"] else {
        c.add("templates", location, "Stage \(stageId) has no lessonTemplates list.")
        return
    }
    let items = dictItems(templatesRaw)
    let ns = items.map { $0["n"] }
    let intNs = ns.compactMap { value -> Int? in
        guard let value, isInt(value) else { return nil }
        return value.intValue
    }.sorted()
    if items.count != templatesRaw.count || intNs != Array(1...Checker.templatesPerStage) {
        c.add("templates", location, "Stage \(stageId) has lesson templates \(show(ns)); it needs exactly lesson templates 1\u{2013}8.")
    }

    let skills = dictItems(stage["skills"])
    let greeting: Set<String> = strList(stage["greetingActivityIds"]).map(Set.init) ?? []
    var stageActivities: Set<String> = []
    for skill in skills {
        if let activityIds = strList(skill["activityIds"]) {
            stageActivities.formUnion(activityIds)
        }
    }

    for template in items {
        let n = template["n"]
        let templateWhere = "stage \(stageId) / lesson template \(displayId(n))"
        var minutes: Int?
        if !isInt(template["minutes"]) || (template["minutes"]?.intValue ?? 0) <= 0 {
            c.add("template-minutes", templateWhere, "Stage \(stageId) lesson template \(displayId(n)) has no minutes.")
        } else {
            minutes = template["minutes"]?.intValue
            if let lessonMinutes, let minutes, minutes != lessonMinutes {
                c.add("template-minutes", templateWhere,
                    "Stage \(stageId) lesson template \(displayId(n)) is \(minutes) minutes; the stage's lessons are \(lessonMinutes).")
            }
        }

        guard case .array(let blocksRaw)? = template["blocks"] else {
            let shown: String
            if case .string? = template["blocks"] {
                shown = show(template["blocks"])
            } else {
                shown = describeJSON(template["blocks"] ?? .null)
            }
            c.add("template-placeholder", templateWhere,
                "Stage \(stageId) lesson template \(displayId(n)) has no blocks yet (\(shown)); it must be transcribed before the stage can be planned.")
            continue
        }

        var total = 0
        var complete = true
        for (position, block) in blocksRaw.enumerated() {
            guard case .object = block else {
                c.add("template-block", templateWhere, "Block \(position + 1) is not an object.")
                complete = false
                continue
            }
            checkBlock(c, stage, templateWhere, position, block, greeting, stageActivities)
            if isInt(block["minutes"]), let blockMinutes = block["minutes"]?.intValue {
                total += blockMinutes
            } else {
                complete = false
            }
        }
        if complete, let minutes, total != minutes {
            c.add("template-minutes", templateWhere,
                "Stage \(stageId) lesson template \(displayId(n))'s blocks add up to \(total) minutes, not \(minutes) "
                + "(a printed range counts as its upper value).")
        }
    }
}

func checkBlock(_ c: Checker, _ stage: JSONValue, _ templateWhere: String, _ position: Int, _ block: JSONValue,
                 _ greeting: Set<String>, _ stageActivities: Set<String>) {
    let stageId = displayId(stage["id"])
    let kind = block["kind"]?.stringValue
    let location = "\(templateWhere) / block \(position + 1) (\(kind ?? displayId(block["kind"])))"

    if kind == nil || !Ids.blockKinds.contains(kind!) {
        c.add("template-block", location, "Block kind \(show(block["kind"])) is not one of \(Ids.blockKinds.joined(separator: ", ")).")
    }

    if !isInt(block["minutes"]) || (block["minutes"]?.intValue ?? -1) < 0 {
        c.add("template-block", location, "Block minutes must be a whole number of 0 or more; they are \(show(block["minutes"])).")
    }

    var skillIds: [String] = []
    if let field = block["skillIds"], !field.isNull {
        if let list = strList(field) {
            skillIds = list
        } else {
            c.add("template-block", location, "skillIds must be a list of skill ids.")
        }
    }

    var named: [JSONValue] = []
    var hasAny = false
    for value in skillIds {
        if value == Ids.anySkill {
            hasAny = true
            if kind != "review", kind != "introduce" {
                c.add("template-block", location, "\"any\" fills Review and Introduce slots only; this is a \(kind ?? "?") block.")
            }
            continue
        }
        if let skill = c.cur.skill(value), skill["stageId"]?.stringValue == stage["id"]?.stringValue {
            named.append(skill)
        } else {
            c.add("template-block", location, "The block names skill \"\(value)\", which is not in Stage \(stageId).")
        }
    }

    if let stepRangeField = block["stepRange"], !stepRangeField.isNull {
        var validRange: (first: Int, last: Int)?
        if case .array(let items) = stepRangeField, items.count == 2, items.allSatisfy(isInt),
           let first = items[0].intValue, let last = items[1].intValue, first >= 1, first <= last {
            validRange = (first, last)
        }
        if let validRange {
            var counts: [(id: String, count: Int)] = []
            for skill in named {
                let stepCount = dictItems(skill["steps"]).count
                if stepCount > 0 { counts.append((displayId(skill["id"]), stepCount)) }
            }
            if counts.isEmpty {
                c.add("step-range", location, "The block has a stepRange but no skill with steps.")
            } else {
                for (skillId, count) in counts where validRange.first > count {
                    c.add("step-range", location, "stepRange \(show(stepRangeField)) starts past \(skillId)'s last step (\(count)).")
                }
                let longest = counts.map(\.count).max() ?? 0
                if validRange.last > longest {
                    c.add("step-range", location,
                        "stepRange \(show(stepRangeField)) ends past the last step of every skill in the block (the longest has \(longest)).")
                }
            }
        } else {
            c.add("step-range", location, "stepRange must be [first, last] with 1 \u{2264} first \u{2264} last; it is \(show(stepRangeField)).")
        }
    }

    var activityIds: [String] = []
    var activityIdsFieldOK = true
    if let field = block["activityIds"], !field.isNull {
        if let list = strList(field) {
            activityIds = list
        } else {
            activityIdsFieldOK = false
            c.add("template-block", location, "activityIds must be a list of activity ids.")
        }
    }
    if activityIdsFieldOK, !c.unloaded("activities.json") {
        var allowed: Set<String>?
        var belongs = ""
        if !named.isEmpty || hasAny {
            var set = greeting
            if hasAny { set.formUnion(stageActivities) }
            for skill in named { set.formUnion(strList(skill["activityIds"]) ?? []) }
            allowed = set
            belongs = "the block's skills or the Greeting"
        } else if kind == "warmUp" {
            allowed = nil
        } else if kind == "wrapUp" {
            allowed = greeting.union(stageActivities)
            belongs = "the stage's skills or the Greeting"
        } else {
            allowed = greeting
            belongs = "the Greeting"
        }
        for activityId in activityIds {
            if c.cur.activity(activityId) == nil {
                c.add("activity-missing", location, "The block lists activity \"\(activityId)\", which is not an activity.")
            } else if let allowed, !allowed.contains(activityId) {
                c.add("template-activity", location, "The block lists \"\(activityId)\", which belongs to none of \(belongs).")
            }
        }
    }

    let topicCodeField = block["topicCode"]
    if kind == "topic" {
        if let topicCode = topicCodeField?.stringValue {
            let topic = c.cur.topic(topicCode)
            if topic == nil || topic?["stageId"]?.stringValue != stage["id"]?.stringValue {
                c.add("template-block", location, "The block names topic \"\(topicCode)\", which is not one of Stage \(stageId)'s topics.")
            }
        } else {
            c.add("template-block", location, "A topic block names its topic (topicCode).")
        }
    } else if isPresentNonNull(topicCodeField) {
        c.add("template-block", location, "Only a topic block has a topicCode.", .warning)
    }

    if let notes = block["notes"], !isStrList(notes) {
        c.add("template-block", location, "notes must be a list of sentences.")
    }
    if let depths = block["depths"] {
        c.depths(depths, location)
    }
    if let equipment = block["equipment"] {
        c.requirementGroups(equipment, location)
    }
}

/// A7: rows name only benchmark steps; a one-step row's text is its step's
/// name; "any" rows name two or more steps; every skill with steps is in a row.
func checkTrackerRows(_ c: Checker, _ stage: JSONValue) {
    let stageId = displayId(stage["id"])
    let location = "stage \(stageId) / tracker rows"
    guard case .array(let rows)? = stage["trackerRows"], !rows.isEmpty else {
        c.add("tracker-rows-missing", location,
            "Stage \(stageId) has no trackerRows yet: the Progress Tracker's rows must be transcribed before the reports and the next-stage line can work.")
        return
    }
    var benchmarks: [String: JSONValue] = [:]
    var benchmarkOrder: [String] = []
    for skill in dictItems(stage["skills"]) {
        if let benchmarkStepId = skill["benchmarkStepId"]?.stringValue {
            if benchmarks[benchmarkStepId] == nil { benchmarkOrder.append(benchmarkStepId) }
            benchmarks[benchmarkStepId] = skill
        }
    }
    var covered: [String: Int] = [:]
    var texts: [String: Int] = [:]
    for (index, row) in rows.enumerated() {
        let rowWhere = "stage \(stageId) / tracker row \(index + 1)"
        guard case .object = row else {
            c.add("tracker-row", rowWhere, "A tracker row is not an object { text, stepIds, rule }.")
            continue
        }
        let rowText = row["text"]?.stringValue
        if !isNonBlankString(row["text"]) {
            c.add("tracker-row", rowWhere, "Tracker row \(index + 1) has no text.")
        } else if let rowText {
            let key = Ids.normalizeText(rowText)
            if let earlier = texts[key] {
                c.add("tracker-row", rowWhere, "Tracker row \(index + 1) repeats row \(earlier)'s text \"\(rowText)\".")
            }
            if texts[key] == nil { texts[key] = index + 1 }
        }
        guard let stepIds = strList(row["stepIds"]), !stepIds.isEmpty else {
            c.add("tracker-row", rowWhere, "Tracker row \(index + 1) names no benchmark steps.")
            continue
        }
        for stepId in stepIds {
            if benchmarks[stepId] != nil {
                if let earlier = covered[stepId] {
                    c.add("tracker-row", rowWhere, "\(stepId) is in tracker rows \(earlier) and \(index + 1).", .warning)
                }
                if covered[stepId] == nil { covered[stepId] = index + 1 }
            } else if let step = c.cur.step(stepId), (step["skillId"]?.stringValue ?? "").hasPrefix("\(stageId).") {
                c.add("tracker-row", rowWhere, "Tracker row \(index + 1) names \(stepId), which is not its skill's benchmark (last step).")
            } else {
                c.add("tracker-row", rowWhere, "Tracker row \(index + 1) names \(stepId), which is not a step of Stage \(stageId).")
            }
        }
        let rule = row["rule"]?.stringValue
        if rule != "all", rule != "any" {
            c.add("tracker-row", rowWhere, "Tracker row \(index + 1)'s rule is \(show(row["rule"])); it must be \"all\" or \"any\".")
        } else if rule == "any", stepIds.count < 2 {
            c.add("tracker-row", rowWhere, "Tracker row \(index + 1) has rule \"any\" over one step; \"any\" needs two or more.")
        }
        if rule == "all", stepIds.count == 1, let rowText {
            if let step = c.cur.step(stepIds[0]), let stepName = step["name"]?.stringValue,
               Ids.normalizeText(stepName) != Ids.normalizeText(rowText) {
                c.add("tracker-row", rowWhere,
                    "Tracker row \(index + 1)'s text \"\(rowText)\" differs from its benchmark step's name \"\(stepName)\"; "
                    + "a one-step row's text is the step's name.")
            }
        }
    }
    for stepId in benchmarkOrder where covered[stepId] == nil {
        let skill = benchmarks[stepId]
        c.add("tracker-coverage", location, "Stage \(stageId)'s \(displayId(skill?["id"])) has steps, but no tracker row names its benchmark \(stepId).")
    }
}

// MARK: - Activities (A5, A13)

func checkActivities(_ c: Checker) {
    if c.unloaded("activities.json") { return }
    var listed: [String: Set<String>] = [:]
    var greetingIds: Set<String> = []
    for stage in c.cur.stages {
        for skill in dictItems(stage["skills"]) {
            guard case .array(let activityIdValues)? = skill["activityIds"], let skillId = skill["id"]?.stringValue else { continue }
            for value in activityIdValues {
                if let activityId = value.stringValue {
                    listed[activityId, default: []].insert(skillId)
                }
            }
        }
        if let ids = strList(stage["greetingActivityIds"]) {
            greetingIds.formUnion(ids)
        }
    }
    var seen: Set<String> = []
    for (index, activityValue) in c.cur.activities.enumerated() {
        guard case .object = activityValue else {
            c.add("activity-shape", "activity \(index + 1)", "An activity is not an object.")
            continue
        }
        let activityId = activityValue["id"]?.stringValue
        let origin = c.originOfActivity(index: index)
        let location = origin == .local
            ? "local.json / activity \(displayId(activityValue["id"]))"
            : "activity \(displayId(activityValue["id"]))"

        let seenKey = "\(activityId ?? "")\u{0}\(origin.rawValue)"
        if !Ids.isSlug(activityId) {
            c.add("activity-shape", location, "Activity id \(show(activityValue["id"])) is not a lower-case slug.")
        } else if seen.contains(seenKey) {
            c.add("id-duplicate", location,
                "Activity id \"\(activityId ?? "")\" appears twice in \(origin == .local ? "local.json" : "activities.json").")
        }
        seen.insert(seenKey)

        if origin == .ymca, activityValue["source"]?.stringValue != "ymca" {
            c.add("activity-shape", location,
                "activities.json holds the toolkit's activities only (source \"ymca\"); your own activities go in local.json.")
        }
        if !isNonBlankString(activityValue["name"]) {
            c.add("activity-shape", location, "Activity \(show(activityValue["id"])) has no name.")
        }
        if !isNonBlankString(activityValue["description"]) {
            c.add("activity-shape", location, "Activity \(show(activityValue["id"])) has no description.")
        }
        let ages = activityValue["ages"]
        var agesOK = false
        if let agesList = strList(ages) {
            agesOK = agesList.allSatisfy { Ids.ageTags.contains($0) } && Set(agesList).count == agesList.count
        }
        if !agesOK {
            c.add("activity-shape", location,
                "Activity \(show(activityValue["id"]))'s ages must be a list of P, S and A ([] = every age); they are \(show(ages)).")
        }
        if activityValue["equipment"] == nil {
            c.add("equipment-shape", location, "Activity \(show(activityValue["id"])) has no equipment list ([] = no equipment).")
        } else {
            c.requirementGroups(activityValue["equipment"], location)
        }
        c.optionalEquipment(activityValue["equipmentOptional"] ?? .array([]), location)
        if let depths = activityValue["depths"] {
            c.depths(depths, location)
        }
        c.flags(activityValue, Checker.activityFlags, location)
        if activityValue["nearWall"] != nil {
            c.add("flag-type", location, "nearWall is for steps only; activity \(show(activityValue["id"])) has it.")
        }
        c.headfirst(activityValue, location)
        if case .bool? = activityValue["submerges"] {} else {
            c.add("flag-type", location, "Activity \(show(activityValue["id"])) needs submerges, true or false.")
        }
        if !isStrList(activityValue["tags"] ?? .array([])) {
            c.add("activity-shape", location, "Activity \(show(activityValue["id"]))'s tags must be a list of words.")
        }
        guard let skillIds = strList(activityValue["skillIds"] ?? .array([])) else {
            c.add("activity-shape", location, "Activity \(show(activityValue["id"]))'s skillIds must be a list of skill ids.")
            continue
        }
        var declared: Set<String> = []
        var unloadedStages: Set<String> = []
        for skillId in skillIds {
            guard let parsed = Ids.parseSkillId(skillId) else {
                c.add("activity-shape", location, "Activity \(show(activityValue["id"])) names \"\(skillId)\", which is not a skill id.")
                continue
            }
            if !c.cur.isLoaded(parsed.stage) {
                unloadedStages.insert(parsed.stage)
            } else if c.cur.skill(skillId) == nil {
                c.add("activity-shape", location,
                    "Activity \(show(activityValue["id"])) names skill \(skillId), which is not in Stage \(parsed.stage).")
            } else {
                declared.insert(skillId)
            }
        }
        if !unloadedStages.isEmpty, origin == .local {
            let sorted = unloadedStages.sorted { Ids.stageSortKey($0) < Ids.stageSortKey($1) }
            c.add("activity-shape", location,
                "Local activity \(show(activityValue["id"])) names skills of Stage \(sorted.joined(separator: ", ")), which isn't loaded.",
                .warning)
        }
        if origin != .ymca { continue }
        let listing = listed[activityId ?? "\u{0}"] ?? []
        if listing != declared {
            c.add("activity-skills", location,
                "Activity \(show(activityValue["id"]))'s skillIds \(show(declared.sorted())) differ from the loaded skills that list it \(show(listing.sorted())).",
                .warning)
        }
        if listing.isEmpty, !greetingIds.contains(activityId ?? "\u{0}"), unloadedStages.isEmpty {
            c.add("orphan-activity", location, "No loaded skill or Greeting lists activity \(show(activityValue["id"])).", .warning)
        }
    }
}

// MARK: - Videos (A12)

func checkVideos(_ c: Checker) {
    if c.unloaded("videos.json") { return }
    var seen: Set<String> = []
    for (index, video) in c.cur.videos.enumerated() {
        guard case .object = video else {
            c.add("video", "video \(index + 1)", "A video entry is not an object.")
            continue
        }
        let videoId = video["id"]?.stringValue
        let number = Ids.parseVideoId(videoId)
        let idText = displayId(video["id"])
        let location = "video \(idText)"
        if number == nil {
            c.add("video", location, "Video id \(show(video["id"])) is not vimeo:<number>.")
        } else if let videoId, seen.contains(videoId) {
            c.add("id-duplicate", location, "Video id \"\(videoId)\" appears twice.")
        }
        if let videoId { seen.insert(videoId) }

        let urlNumber = Ids.vimeoId(fromURL: video["url"]?.stringValue)
        if urlNumber == nil {
            c.add("video", location, "Video \(idText)'s url \(show(video["url"])) is not a Vimeo url.")
        } else if let number, let urlNumber, urlNumber != number {
            c.add("video", location, "Video \(idText)'s url is Vimeo video \(urlNumber), not \(number).")
        }
        if !isNonBlankString(video["title"]) {
            c.add("video", location, "Video \(idText) has no title.")
        }
        guard let stageIds = strList(video["stageIds"] ?? .array([])),
              let skillIds = strList(video["skillIds"] ?? .array([])) else {
            c.add("video-link", location, "Video \(idText)'s stageIds and skillIds must be lists of ids.")
            continue
        }
        var notLoaded: Set<String> = []
        for stageId in stageIds {
            if !Ids.isStageId(stageId) {
                c.add("video-link", location, "Video \(idText) names stage \"\(stageId)\", which is not a stage.")
            } else if !c.cur.isLoaded(stageId) {
                notLoaded.insert(stageId)
            }
        }
        for skillId in skillIds {
            guard let parsed = Ids.parseSkillId(skillId) else {
                c.add("video-link", location, "Video \(idText) names \"\(skillId)\", which is not a skill id.")
                continue
            }
            if !c.cur.isLoaded(parsed.stage) {
                notLoaded.insert(parsed.stage)
            } else if c.cur.skill(skillId) == nil {
                c.add("video-link", location, "Video \(idText) names skill \(skillId), which is not in Stage \(parsed.stage).")
            } else if !stageIds.contains(parsed.stage) {
                c.add("video-link", location, "Video \(idText) names skill \(skillId) but not its stage \(parsed.stage).", .warning)
            }
        }
        if !notLoaded.isEmpty {
            let sorted = notLoaded.sorted { Ids.stageSortKey($0) < Ids.stageSortKey($1) }
            c.add("video-link", location, "Video \(idText) links Stage \(sorted.joined(separator: ", ")), which isn't loaded.", .warning)
        }
    }
}

// MARK: - Local additions (A9, A13)

/// Every id already used by a YMCA (non-local) entry, across every file.
func ymcaIds(_ c: Checker) -> Set<String> {
    var found = Set(Ids.stageIds)
    for (index, entry) in indexedDictItems(c.cur.activities) where c.originOfActivity(index: index) == .ymca {
        if let id = entry["id"]?.stringValue { found.insert(id) }
    }
    for (index, entry) in indexedDictItems(c.cur.equipment) where c.originOfEquipment(index: index) == .ymca {
        if let id = entry["id"]?.stringValue { found.insert(id) }
    }
    for entry in dictItems(c.cur.safety) {
        if let id = entry["id"]?.stringValue { found.insert(id) }
    }
    for entry in dictItems(c.cur.videos) {
        if let id = entry["id"]?.stringValue { found.insert(id) }
    }
    for stage in c.cur.stages {
        for skill in dictItems(stage["skills"]) {
            if let id = skill["id"]?.stringValue { found.insert(id) }
            for step in dictItems(skill["steps"]) {
                if let id = step["id"]?.stringValue { found.insert(id) }
            }
        }
        for topic in dictItems(stage["topics"]) {
            if let code = topic["code"]?.stringValue { found.insert(code) }
        }
    }
    return found
}

func checkLocal(_ c: Checker) {
    guard c.cur.kind == .directory, let local = c.cur.local else { return }
    guard case .object(let localFields) = local else {
        c.add("local-format", "local.json", "local.json is not a JSON object { format, activities, equipment }.")
        return
    }
    if localFields["format"]?.stringValue != Checker.localFormat {
        c.add("local-format", "local.json", "local.json has format \(show(localFields["format"])); it must be \"local/1\".")
    }
    let extra = localFields.keys.filter { !["format", "activities", "equipment"].contains($0) }.sorted()
    if !extra.isEmpty {
        c.add("local-format", "local.json", "local.json may hold only format, activities and equipment; it also has \(extra.joined(separator: ", ")).")
    }
    let ymca = ymcaIds(c)
    for (key, noun) in [("activities", "activity"), ("equipment", "equipment")] {
        guard let entriesField = localFields[key] else {
            c.add("local-format", "local.json", "local.json has no \(key) list ([] when empty).")
            continue
        }
        guard case .array(let entries) = entriesField else {
            c.add("local-format", "local.json", "local.json's \(key) is not a list.")
            continue
        }
        for (index, entry) in entries.enumerated() {
            guard case .object = entry else {
                c.add("local-entry", "local.json", "local.json's \(key) entry \(index + 1) is not an object.")
                continue
            }
            let entryId = entry["id"]?.stringValue
            let location = "local.json / \(noun) \(displayId(entry["id"]))"
            if entry["source"]?.stringValue != "local" {
                c.add("local-entry", location,
                    "local.json \(noun) \(show(entry["id"])) has source \(show(entry["source"])); every local entry has source \"local\".")
            }
            if key == "equipment", entry["kind"]?.stringValue != "item" {
                c.add("local-entry", location,
                    "local.json equipment \(show(entry["id"])) is a \(show(entry["kind"])); local equipment entries are items (kind \"item\").")
            }
            if let entryId, ymca.contains(entryId) {
                c.add("local-collision", location, "local.json \(noun) \(show(entry["id"])) uses a YMCA id; local ids never reuse a YMCA id.")
            }
        }
    }
}

/// A9: ids are unique across the files. Activity, equipment and safety ids
/// share one slug namespace; a clash between two YMCA files is an error here
/// (local clashes are reported as local-collision).
func checkCrossIds(_ c: Checker) {
    var owners: [String: [String]] = [:]
    func record(_ label: String, _ id: String) {
        if owners[id] == nil { owners[id] = [] }
        if !(owners[id]?.contains(label) ?? false) { owners[id]?.append(label) }
    }
    for (index, entry) in indexedDictItems(c.cur.activities) where c.originOfActivity(index: index) == .ymca {
        if let id = entry["id"]?.stringValue { record("activity", id) }
    }
    for (index, entry) in indexedDictItems(c.cur.equipment) where c.originOfEquipment(index: index) == .ymca {
        if let id = entry["id"]?.stringValue { record("equipment item", id) }
    }
    for entry in dictItems(c.cur.safety) {
        if let id = entry["id"]?.stringValue { record("safety rule", id) }
    }
    for (id, labels) in owners where labels.count > 1 {
        c.add("id-duplicate", "curriculum", "Id \"\(id)\" is both a \(labels.joined(separator: " and a ")); ids are unique across the curriculum files.")
    }
}

// MARK: - Placeholders

func walkStrings(_ value: JSONValue, _ path: String, _ visit: (String, String) -> Void) {
    switch value {
    case .string(let s):
        visit(path, s)
    case .object(let fields):
        for key in fields.keys {
            walkStrings(fields[key] ?? .null, path.isEmpty ? key : "\(path).\(key)", visit)
        }
    case .array(let items):
        for (index, item) in items.enumerated() {
            walkStrings(item, "\(path)[\(index)]", visit)
        }
    default:
        break
    }
}

func checkPlaceholders(_ c: Checker) {
    var groups: [(location: String, value: JSONValue)] = c.cur.stages.map { stage in
        ("stage \(displayId(stage["id"]))", stage)
    }
    var activitiesById: [String: JSONValue] = [:]
    for activity in dictItems(c.cur.activities) {
        activitiesById[displayId(activity["id"])] = activity
    }
    groups.append(("activities", .object(activitiesById)))

    for (location, value) in groups {
        var todo: [String] = []
        var unreadable: [String] = []
        walkStrings(value, "") { path, string in
            if path.hasSuffix(".blocks"), string == Checker.placeholder { return }
            if string.hasPrefix(Checker.placeholder) { todo.append(path) }
            if string.contains(Checker.unreadableMarker) { unreadable.append(path) }
        }
        let capitalized = location.isEmpty ? location : location.prefix(1).uppercased() + location.dropFirst()
        if !todo.isEmpty {
            c.add("placeholder-text", location,
                "\(capitalized) still has \(todo.count) \(Checker.placeholder) field\(todo.count == 1 ? "" : "s") "
                + "(\(todo.prefix(3).joined(separator: ", "))\(todo.count > 3 ? ", \u{2026}" : "")).",
                .warning)
        }
        if !unreadable.isEmpty {
            c.add("placeholder-text", location,
                "\(capitalized) has \(unreadable.count) field\(unreadable.count == 1 ? "" : "s") marked UNREADABLE "
                + "(\(unreadable.prefix(3).joined(separator: ", "))\(unreadable.count > 3 ? ", \u{2026}" : "")); read them from the PDF.",
                .warning)
        }
    }
}
