//
//  CurriculumLookups.swift
//  DeckPlanCore
//
//  Id lookups over a `LoadedCurriculum`, and the continuum-link helpers
//  (docs/SPEC.md D17, D25). A port of `tools/core/curriculum.py`'s
//  `Curriculum.stage`/`.skill`/`.step`/`.topic`/`.activity`/`.equipment_entry`/
//  `.video`/`.loaded_stage_ids`/`.is_loaded`/`.skills_of`, `reindex`,
//  `prerequisite_of`, `advanced_of` and `prerequisites_satisfied`.
//
//  Every lookup returns the raw `JSONValue` object (or nil) rather than a typed
//  record, for the same reason `LoadedCurriculum` stores raw JSON — see its
//  doc comment. `Curriculum.stage("4")["warmUpSkill"]` in the Python reads
//  naturally in Swift as `loaded.stage("4")?["warmUpSkill"]`, using
//  `JSONValue`'s own subscript and typed accessors (`.stringValue`, `.intValue`…).
//

import Foundation

extension LoadedCurriculum {

    /// This curriculum's data reassembled as one JSON object in the shape
    /// `Models/CurriculumModels.swift`'s typed `Curriculum` decodes. For a
    /// consumer that has confirmed `Problem.canPlan` and wants that model's
    /// ergonomics (`Curriculum(json: loaded.json)`) rather than raw
    /// `JSONValue` lookups — expected to matter starting with the Planner
    /// (M2), not M4. The loader and validator never go through this
    /// themselves; they work in `JSONValue` throughout, for the reasons in
    /// this type's doc comment.
    public var json: JSONValue {
        var fields: [String: JSONValue] = [
            "stages": .array(stages),
            "activities": .array(activities),
            "equipment": .array(equipment),
            "videos": .array(videos),
            "safety": .array(safety),
        ]
        if let version { fields["version"] = .string(version) }
        if let local { fields["local"] = local }
        return .object(fields)
    }

    /// The stage `stageId`, if it loaded. First match wins on a duplicate id,
    /// matching `reindex`'s `setdefault`.
    public func stage(_ stageId: String?) -> JSONValue? {
        guard let stageId else { return nil }
        return stages.first { $0["id"]?.stringValue == stageId }
    }

    /// The skill `skillId`, searched across every loaded stage.
    public func skill(_ skillId: String?) -> JSONValue? {
        guard let skillId else { return nil }
        for stage in stages {
            for skill in dictItems(stage["skills"]) where skill["id"]?.stringValue == skillId {
                return skill
            }
        }
        return nil
    }

    /// The step `stepId`, searched across every loaded stage and skill.
    public func step(_ stepId: String?) -> JSONValue? {
        guard let stepId else { return nil }
        for stage in stages {
            for skill in dictItems(stage["skills"]) {
                for step in dictItems(skill["steps"]) where step["id"]?.stringValue == stepId {
                    return step
                }
            }
        }
        return nil
    }

    /// The topic `code`, searched across every loaded stage.
    public func topic(_ code: String?) -> JSONValue? {
        guard let code else { return nil }
        for stage in stages {
            for topic in dictItems(stage["topics"]) where topic["code"]?.stringValue == code {
                return topic
            }
        }
        return nil
    }

    /// The activity `activityId` (YMCA or local; local additions are merged in
    /// catalog order, so a YMCA entry wins a same-id clash — the loader still
    /// reports that clash via `id-duplicate`/`local-collision`).
    public func activity(_ activityId: String?) -> JSONValue? {
        guard let activityId else { return nil }
        return activities.first { $0["id"]?.stringValue == activityId }
    }

    /// The equipment catalog entry `equipmentId` (`equipment.json` or `local.json`).
    public func equipmentEntry(_ equipmentId: String?) -> JSONValue? {
        guard let equipmentId else { return nil }
        return equipment.first { $0["id"]?.stringValue == equipmentId }
    }

    /// The video `videoId`.
    public func video(_ videoId: String?) -> JSONValue? {
        guard let videoId else { return nil }
        return videos.first { $0["id"]?.stringValue == videoId }
    }

    /// The stage ids that loaded, in stage order (docs/TEST_CASES.md A1).
    public var loadedStageIds: [String] {
        stages.compactMap { stage in
            guard let id = stage["id"]?.stringValue, Ids.stageIndex[id] != nil else { return nil }
            return id
        }
    }

    /// Whether `stageId` loaded.
    public func isLoaded(_ stageId: String) -> Bool {
        stages.contains { $0["id"]?.stringValue == stageId }
    }

    /// `stageId`'s skills (object entries only), or `[]` when the stage did not
    /// load or has no skills list.
    public func skillsOf(_ stageId: String) -> [JSONValue] {
        guard let stage = stage(stageId) else { return [] }
        return dictItems(stage["skills"])
    }
}

// MARK: - Continuum links (docs/SPEC.md D17, D25; docs/TEST_CASES.md A4, A11)

/// Whether the JSON array `value` contains the string `target` as one of its
/// elements. Unlike `isStrList`, this does not require every element to be a
/// string — it mirrors Python's `step_id in skill["prerequisiteStepIds"]`,
/// which only asks whether the field is a list and whether the target is one
/// of its (possibly mixed-type) elements.
private func arrayContainsString(_ value: JSONValue?, _ target: String) -> Bool {
    guard case .array(let items)? = value else { return false }
    return items.contains { $0.stringValue == target }
}

extension LoadedCurriculum {

    /// The skills that list `stepId` in their prerequisite column.
    public func prerequisiteOf(_ stepId: String) -> [String] {
        var found: [String] = []
        for stage in stages {
            for skill in dictItems(stage["skills"]) {
                guard arrayContainsString(skill["prerequisiteStepIds"], stepId),
                      let skillId = skill["id"]?.stringValue else { continue }
                found.append(skillId)
            }
        }
        return found
    }

    /// The skills that list `stepId` in their advanced column.
    public func advancedOf(_ stepId: String) -> [String] {
        var found: [String] = []
        for stage in stages {
            for skill in dictItems(stage["skills"]) {
                guard arrayContainsString(skill["advancedStepIds"], stepId),
                      let skillId = skill["id"]?.stringValue else { continue }
                found.append(skillId)
            }
        }
        return found
    }

    /// Whether the placement prefill may treat `skillId`'s prerequisite column
    /// as met: the column is empty, or its last step — the earlier stage's
    /// benchmark — is achieved.
    public func prerequisitesSatisfied(_ skillId: String, achievedStepIds: Set<String>) -> Bool {
        guard let skill = skill(skillId) else { return false }
        let column: [String]
        if case .array(let items)? = skill["prerequisiteStepIds"] {
            column = items.compactMap(\.stringValue)
        } else {
            column = []
        }
        guard let last = column.last else { return true }
        return achievedStepIds.contains(last)
    }
}
