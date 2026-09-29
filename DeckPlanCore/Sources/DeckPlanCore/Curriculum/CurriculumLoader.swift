//
//  CurriculumLoader.swift
//  DeckPlanCore
//
//  Load a curriculum directory or a single-file compact sample
//  (docs/CURRICULUM_FORMAT.md §3). A port of `load`, `read_json`, `_load_dir`,
//  `_load_sample` and `_enrich` in `tools/core/curriculum.py`.
//
//  Loading never throws: a missing or corrupt file becomes a `Problem` in
//  `LoadedCurriculum.loadProblems` and the rest still loads (docs/TEST_CASES.md A10).
//

import Foundation

/// Where a `LoadedCurriculum` came from: a `curriculum/`-shaped directory, or a
/// single-file compact sample (`examples/curriculum.stage1.sample.json`).
public enum CurriculumSourceKind: String, Sendable, Equatable {
    case directory = "dir"
    case sample
}

/// What `CurriculumLoader.load` returns: the raw, enriched curriculum data plus
/// whatever went wrong reading it. A port of `tools/core/curriculum.py`'s
/// `Curriculum` class — the load state (`source`, `kind`, `load_problems`) the
/// M4 brief asks to keep apart from the app's typed `Curriculum` record
/// (`Models/CurriculumModels.swift`) lives here, alongside the data itself.
///
/// **Why this holds `JSONValue`, not typed `Stage`/`Skill`/… records.** The
/// validator must keep checking a record even when *one* of its fields has the
/// wrong shape — `tests/fixtures/curriculum_mini`'s A10 case sets a stage's
/// `"skills"` to the string `"not a list"` and still expects every *other*
/// check on that stage to run and report its own problems, not to abort the
/// whole stage. `Stage.init(json:)` in `Models/CurriculumModels.swift` cannot
/// give that: it throws `JSONModelError` the moment one present field has the
/// wrong type, which would fail the *entire* record's decode over a single bad
/// key — exactly backwards from what CURRICULUM_FORMAT.md §5 and A10 need. So
/// this loader, like `tools/core/curriculum.py`, works on plain JSON-shaped
/// values end to end: a stage, a skill, a step is a `JSONValue` object, read
/// field by field with the same tolerance Python's `dict.get(...)` has. The
/// typed records stay available for code that only runs after
/// `Problem.canPlan` is true (the Planner and later milestones), where the
/// shape is already known good. This is a deliberate difference from the
/// M4 brief's original sketch (`Curriculum/Curriculum.swift`, "the loaded
/// curriculum + lookups", extending the typed `Curriculum`); see the M4
/// worker-2 report for the proposed `docs/DECISIONS_LOG.md` sentence.
public struct LoadedCurriculum: Sendable, Equatable {
    /// The path loaded, as given to `load`.
    public var source: String
    public var kind: CurriculumSourceKind
    /// `version.json`'s version, or a compact sample's top-level one.
    public var version: String?
    /// In stage order (A, B, 1–6), only the stages that loaded. Each a JSON object.
    public var stages: [JSONValue]
    /// `activities.json`'s entries, then `local.json`'s.
    public var activities: [JSONValue]
    /// `equipment.json`'s entries, then `local.json`'s (catalog order).
    public var equipment: [JSONValue]
    public var safety: [JSONValue]
    public var videos: [JSONValue]
    /// `local.json`'s object, or nil (no local.json, or a compact sample).
    public var local: JSONValue?
    /// How many of the trailing entries of `activities` / `equipment` came from
    /// `local.json` (replaces `tools/core/curriculum.py`'s identity-based
    /// `_Checker.origin`, which Swift's value-typed `JSONValue` has no
    /// equivalent for: `local.json`'s entries are appended after the YMCA
    /// ones in catalog order, so "is this entry local" is "is its index past
    /// the YMCA ones", counted here).
    public var localActivityCount: Int
    public var localEquipmentCount: Int
    /// Problems found while reading files.
    public var loadProblems: [Problem]

    public init(source: String = "", kind: CurriculumSourceKind = .directory) {
        self.source = source
        self.kind = kind
        self.version = nil
        self.stages = []
        self.activities = []
        self.equipment = []
        self.safety = []
        self.videos = []
        self.local = nil
        self.localActivityCount = 0
        self.localEquipmentCount = 0
        self.loadProblems = []
    }
}

/// Loads a curriculum directory or a single-file compact sample into a
/// `LoadedCurriculum`. Never throws.
public enum CurriculumLoader {

    /// `version.json`'s expected `format`.
    static let curriculumFormatId = "curriculum/1"

    /// `stages/<S>.json` for each stage id.
    static let stageFiles: [String: String] =
        Dictionary(uniqueKeysWithValues: Ids.stageIds.map { ($0, "stages/\($0).json") })

    // MARK: - Directory

    /// Load `curriculum/`'s files: `version.json`, `stages/<S>.json`,
    /// `activities.json`, `equipment.json`, `safety.json`, `videos.json` and
    /// `local.json` (or `localPath`, when given, instead of `<root>/local.json`
    /// — used by tests). Never throws (docs/TEST_CASES.md A10).
    public static func load(directory root: URL, localPath: URL? = nil) -> LoadedCurriculum {
        var curriculum = LoadedCurriculum(source: root.path, kind: .directory)
        var found: [Problem] = []

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            found.append(Problem(code: "file-missing", where: root.path,
                message: "The curriculum directory \(root.path) does not exist."))
            curriculum.loadProblems = found
            return curriculum
        }

        if let version = readJSON(at: root.appendingPathComponent("version.json"), into: &found, where: "version.json") {
            if case .object = version {
                curriculum.version = version["version"]?.stringValue
                let format = version["format"]?.stringValue
                if format != curriculumFormatId {
                    found.append(Problem(code: "version-invalid", where: "version.json",
                        message: "version.json has format \(show(version["format"])); it should be \"\(curriculumFormatId)\"."))
                }
                let versionString = version["version"]?.stringValue
                if versionString == nil || versionString!.isEmpty {
                    found.append(Problem(code: "version-invalid", where: "version.json",
                        message: "version.json has no version string."))
                }
            } else {
                found.append(Problem(code: "version-invalid", where: "version.json",
                    message: "version.json is not a JSON object."))
            }
        }

        for stageId in Ids.stageIds {
            let relative = stageFiles[stageId] ?? "stages/\(stageId).json"
            let fileURL = root.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                found.append(Problem(code: "stage-not-loaded", severity: .warning, where: relative,
                    message: "Stage \(stageId) is not loaded: \(relative) is missing."))
                continue
            }
            guard let data = readJSON(at: fileURL, into: &found, where: relative) else { continue }
            guard case .object = data else {
                found.append(Problem(code: "stage-file-invalid", where: relative,
                    message: "\(relative) is not a JSON object, so Stage \(stageId) is not loaded."))
                continue
            }
            guard let dataId = data["id"]?.stringValue, dataId == stageId else {
                found.append(Problem(code: "stage-file-invalid", where: relative,
                    message: "\(relative) has id \(show(data["id"])), not \"\(stageId)\", so Stage \(stageId) is not loaded."))
                continue
            }
            curriculum.stages.append(data)
        }

        let stagesDir = root.appendingPathComponent("stages")
        var stagesDirIsDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: stagesDir.path, isDirectory: &stagesDirIsDirectory),
           stagesDirIsDirectory.boolValue {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: stagesDir.path)) ?? [])
                .filter { $0.hasSuffix(".json") }
                .sorted()
            for name in names {
                let stem = String(name.dropLast(".json".count))
                if Ids.stageIndex[stem] == nil {
                    found.append(Problem(code: "stage-file-invalid", severity: .warning, where: "stages/\(name)",
                        message: "stages/\(name) is not a stage file (stages are A, B and 1\u{2013}6) and was ignored."))
                }
            }
        }

        let catalogFiles: [(name: String, required: Bool)] = [
            ("activities.json", true), ("equipment.json", true), ("safety.json", true), ("videos.json", false),
        ]
        for (name, required) in catalogFiles {
            guard let data = readJSON(at: root.appendingPathComponent(name), into: &found, where: name, required: required) else {
                if !required {
                    found.append(Problem(code: "file-missing", severity: .warning, where: name,
                        message: "\(name) is missing, so no skill has a video."))
                }
                continue
            }
            guard case .array(let list) = data else {
                found.append(Problem(code: "file-unreadable", where: name, message: "\(name) is not a JSON list."))
                continue
            }
            switch name {
            case "activities.json": curriculum.activities = list
            case "equipment.json": curriculum.equipment = list
            case "safety.json": curriculum.safety = list
            case "videos.json": curriculum.videos = list
            default: break
            }
        }

        let localFile = localPath ?? root.appendingPathComponent("local.json")
        let local = readJSON(at: localFile, into: &found, where: "local.json", required: false)
        if local == nil, !FileManager.default.fileExists(atPath: localFile.path) {
            found.append(Problem(code: "local-missing", severity: .warning, where: "local.json",
                message: "local.json is missing, so there are no local additions."))
        }
        curriculum.local = local
        if case .object = local {
            let localActivities = dictItems(local?["activities"])
            let localEquipment = dictItems(local?["equipment"])
            curriculum.activities.append(contentsOf: localActivities)
            curriculum.equipment.append(contentsOf: localEquipment)
            curriculum.localActivityCount = localActivities.count
            curriculum.localEquipmentCount = localEquipment.count
        }

        if curriculum.stages.isEmpty {
            found.append(Problem(code: "no-stages", where: "stages/",
                message: "No stage loaded: stages/ holds no readable stage file."))
        }
        curriculum.loadProblems = found
        return enrich(curriculum)
    }

    // MARK: - Compact sample

    /// The compact single-stage form (docs/CURRICULUM_FORMAT.md §3, last
    /// paragraphs): `stage` holds the Stage's own fields and the top level its
    /// skills, `greetingActivityIds`, topics, `lessonTemplates` (and
    /// `trackerRows`) beside `activities`, `equipment` and `safety`; `version`
    /// stands in for `version.json`'s. Read with no local additions
    /// (docs/PLANNER.md §13).
    public static func load(sampleFile path: URL) -> LoadedCurriculum {
        var curriculum = LoadedCurriculum(source: path.path, kind: .sample)
        var found: [Problem] = []
        let whereText = path.lastPathComponent

        guard let data = readJSON(at: path, into: &found, where: whereText) else {
            curriculum.loadProblems = found
            return curriculum
        }
        guard case .object(let stageValue)? = data["stage"] else {
            found.append(Problem(code: "sample-invalid", where: whereText,
                message: "\(whereText) is not a compact curriculum sample: it has no stage object."))
            curriculum.loadProblems = found
            return curriculum
        }

        var stageFields = stageValue
        for key in ["skills", "greetingActivityIds", "topics", "lessonTemplates", "trackerRows"] {
            if let value = data[key], stageFields[key] == nil {
                stageFields[key] = value
            }
        }

        // A derived field the sample leaves out: each skill defaults videoIds to [].
        if case .array(let rawSkills)? = stageFields["skills"] {
            stageFields["skills"] = .array(rawSkills.map { skillValue -> JSONValue in
                guard case .object(var skillFields) = skillValue else { return skillValue }
                if skillFields["videoIds"] == nil { skillFields["videoIds"] = .array([]) }
                return .object(skillFields)
            })
        }

        let stageId = stageFields["id"]?.stringValue
        if let stageId, Ids.stageIndex[stageId] != nil {
            curriculum.stages = [.object(stageFields)]
        } else {
            found.append(Problem(code: "stage-file-invalid", where: whereText,
                message: "\(whereText) has stage id \(show(stageFields["id"])), which is not a stage (A, B, 1\u{2013}6)."))
        }
        curriculum.version = data["version"]?.stringValue

        for key in ["activities", "equipment", "safety", "videos"] {
            var list: [JSONValue] = []
            if let value = data[key] {
                if case .array(let items) = value {
                    list = items
                } else {
                    found.append(Problem(code: "sample-invalid", where: whereText,
                        message: "\(whereText)'s \(key) is not a list."))
                }
            }
            switch key {
            case "activities": curriculum.activities = list
            case "equipment": curriculum.equipment = list
            case "safety": curriculum.safety = list
            case "videos": curriculum.videos = list
            default: break
            }
        }

        // A derived field the sample leaves out: an activity's skillIds (from the
        // skills that list it) and source ("ymca" for every entry).
        var listedBy: [String: [String]] = [:]
        for skill in dictItems(stageFields["skills"]) {
            guard let skillId = skill["id"]?.stringValue, case .array(let activityIds)? = skill["activityIds"] else { continue }
            for activityIdValue in activityIds {
                if let activityId = activityIdValue.stringValue {
                    listedBy[activityId, default: []].append(skillId)
                }
            }
        }
        curriculum.activities = curriculum.activities.map { activityValue -> JSONValue in
            guard case .object(var fields) = activityValue else { return activityValue }
            if fields["source"] == nil { fields["source"] = .string("ymca") }
            if fields["skillIds"] == nil, let activityId = fields["id"]?.stringValue {
                fields["skillIds"] = .array((listedBy[activityId] ?? []).map { .string($0) })
            }
            return .object(fields)
        }

        curriculum.loadProblems = found
        return enrich(curriculum)
    }

    /// Several compact samples read as one curriculum: the demo build carries
    /// the made-up Stages 1, 2 and 4 (DECISIONS_LOG 2026-09-28). Stages come in
    /// stage order; activities, equipment, safety rules and videos come once
    /// each by id, in the order first met. An activity two samples share keeps
    /// its first entry and gains the other sample's skills in its `skillIds`;
    /// shared entries that differ otherwise are reported. The first stage's
    /// version stands for the whole.
    public static func load(sampleFiles paths: [URL]) -> LoadedCurriculum {
        let parts = paths.map { (load(sampleFile: $0), $0.lastPathComponent) }
            .enumerated()
            .sorted { left, right in
                let l = Ids.stageSortKey(left.element.0.loadedStageIds.first ?? "")
                let r = Ids.stageSortKey(right.element.0.loadedStageIds.first ?? "")
                return l != r ? l < r : left.offset < right.offset
            }
            .map(\.element)
        var merged = LoadedCurriculum(source: paths.map(\.path).joined(separator: ", "), kind: .sample)
        merged.version = parts.first?.0.version
        for (part, whereText) in parts {
            merged.loadProblems += part.loadProblems
            for stage in part.stages {
                let stageId = stage["id"]?.stringValue ?? ""
                if merged.loadedStageIds.contains(stageId) {
                    merged.loadProblems.append(Problem(code: "sample-invalid", where: whereText,
                        message: "\(whereText) holds Stage \(stageId), which another sample already holds."))
                } else {
                    merged.stages.append(stage)
                }
            }
            merged.activities = mergeById(merged.activities, part.activities, from: whereText,
                                          unionSkillIds: true, into: &merged.loadProblems)
            merged.equipment = mergeById(merged.equipment, part.equipment, from: whereText, into: &merged.loadProblems)
            merged.safety = mergeById(merged.safety, part.safety, from: whereText, into: &merged.loadProblems)
            merged.videos = mergeById(merged.videos, part.videos, from: whereText, into: &merged.loadProblems)
        }
        return merged
    }

    /// `more` appended to `list`, less the entries whose id `list` already has.
    /// Only ids across the two lists are folded: a repeat inside one sample is
    /// left for the validator's A9 check.
    private static func mergeById(_ list: [JSONValue], _ more: [JSONValue], from whereText: String,
                                  unionSkillIds: Bool = false, into problems: inout [Problem]) -> [JSONValue] {
        var result = list
        var position: [String: Int] = [:]
        for (index, entry) in list.enumerated() {
            if let id = entry["id"]?.stringValue, position[id] == nil { position[id] = index }
        }
        for entry in more {
            guard let id = entry["id"]?.stringValue, let index = position[id] else {
                result.append(entry)
                continue
            }
            guard case .object(var have) = result[index], case .object(var other) = entry else { continue }
            let haveSkills = strList(have["skillIds"]) ?? []
            let otherSkills = strList(other["skillIds"]) ?? []
            if unionSkillIds {
                have["skillIds"] = nil
                other["skillIds"] = nil
            }
            if have != other {
                problems.append(Problem(code: "sample-invalid", where: whereText,
                    message: "\(whereText)'s \(id) differs from the entry of the same id in another sample."))
            }
            if unionSkillIds, case .object(var fields) = result[index] {
                fields["skillIds"] = .array((haveSkills + otherSkills.filter { !haveSkills.contains($0) }).map { .string($0) })
                result[index] = .object(fields)
            }
        }
        return result
    }

    // MARK: - Reading one file

    /// Read one JSON file. A missing or corrupt file adds a `Problem` and
    /// returns nil. `tools/core/curriculum.py`'s `read_json`.
    static func readJSON(at url: URL, into problems: inout [Problem], where whereText: String,
                          required: Bool = true) -> JSONValue? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            if required {
                problems.append(Problem(code: "file-missing", where: whereText, message: "\(whereText) is missing."))
            }
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            problems.append(Problem(code: "file-unreadable", where: whereText,
                message: "\(whereText) could not be read (\(error))."))
            return nil
        }
        do {
            return try JSONValue.parse(data)
        } catch {
            problems.append(Problem(code: "file-unreadable", where: whereText,
                message: "\(whereText) is not valid JSON (\(error))."))
            return nil
        }
    }

    // MARK: - Derived fields (`_enrich`)

    /// Derived fields (docs/CURRICULUM_FORMAT.md §3) and the defaults of
    /// optional lists: each Skill gets `stageId` and `stepIds`, each Step
    /// `skillId`, each Topic and LessonTemplate `stageId`; each Activity
    /// defaults `equipmentOptional` and `tags` to `[]` when absent.
    /// `tools/core/curriculum.py`'s `_enrich`.
    static func enrich(_ curriculum: LoadedCurriculum) -> LoadedCurriculum {
        var result = curriculum
        result.stages = curriculum.stages.map(enrichStage)
        result.activities = curriculum.activities.map(enrichActivityDefaults)
        return result
    }

    private static func enrichStage(_ stage: JSONValue) -> JSONValue {
        guard case .object(var fields) = stage else { return stage }
        let stageId = fields["id"]

        if case .array(let rawSkills)? = fields["skills"] {
            fields["skills"] = .array(rawSkills.map { skillValue -> JSONValue in
                guard case .object(var skillFields) = skillValue else { return skillValue }
                if let stageId { skillFields["stageId"] = stageId }
                let skillId = skillFields["id"]
                var stepIds: [JSONValue] = []
                if case .array(let rawSteps)? = skillFields["steps"] {
                    var enrichedSteps: [JSONValue] = []
                    enrichedSteps.reserveCapacity(rawSteps.count)
                    for stepValue in rawSteps {
                        guard case .object(var stepFields) = stepValue else {
                            enrichedSteps.append(stepValue)
                            continue
                        }
                        if case .string(let idText)? = stepFields["id"] { stepIds.append(.string(idText)) }
                        if let skillId { stepFields["skillId"] = skillId }
                        enrichedSteps.append(.object(stepFields))
                    }
                    skillFields["steps"] = .array(enrichedSteps)
                }
                skillFields["stepIds"] = .array(stepIds)
                return .object(skillFields)
            })
        }

        if case .array(let rawTopics)? = fields["topics"] {
            fields["topics"] = .array(rawTopics.map { topicValue -> JSONValue in
                guard case .object(var topicFields) = topicValue else { return topicValue }
                if let stageId { topicFields["stageId"] = stageId }
                return .object(topicFields)
            })
        }

        if case .array(let rawTemplates)? = fields["lessonTemplates"] {
            fields["lessonTemplates"] = .array(rawTemplates.map { templateValue -> JSONValue in
                guard case .object(var templateFields) = templateValue else { return templateValue }
                if let stageId { templateFields["stageId"] = stageId }
                return .object(templateFields)
            })
        }

        return .object(fields)
    }

    private static func enrichActivityDefaults(_ activity: JSONValue) -> JSONValue {
        guard case .object(var fields) = activity else { return activity }
        if fields["equipmentOptional"] == nil { fields["equipmentOptional"] = .array([]) }
        if fields["tags"] == nil { fields["tags"] = .array([]) }
        return .object(fields)
    }
}
