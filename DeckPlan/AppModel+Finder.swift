//
//  AppModel+Finder.swift
//  DeckPlan
//
//  The activity finder and browse (docs/REDESIGN.md §4) over
//  `DeckPlanCore.Finder`, plus the name lookups every screen uses. Pure reads:
//  the pool profile is always applied; the age tag only when a class is given.
//

import Foundation
import DeckPlanCore

extension AppModel {
    // MARK: Finder

    /// Page `pageNumber` of one skill's seeded list (REDESIGN §4; F1). The app
    /// never narrows by step (DECISIONS_LOG 2026-09-12, "Finder is stage →
    /// skill → activities"); the Core keeps `step` for the CLI. nil when the
    /// Core refused the inputs.
    func find(stageId: String, skillId: String, ageTag: String?, pageNumber: Int) -> FinderPage? {
        guard let curriculum = planningCurriculum else { return nil }
        return Finder.find(curriculum, stageId: stageId, pool: pool, skillId: skillId, step: nil,
                           ageTag: ageTag, pageNumber: pageNumber).0
    }

    /// The skill the finder opens on: `preferred` when it is one of the
    /// stage's skills (a day's block), else the stage's first.
    func finderSkill(stageId: String, preferred: String? = nil) -> String {
        let ids = skillChoices(of: stageId).map(\.id)
        if let preferred, ids.contains(preferred) { return preferred }
        return ids.first ?? ""
    }

    /// The detail view's facts (REDESIGN §4): equipment phrases, ages,
    /// submerges and the video titles of the skill.
    func activityDetail(_ activityId: String, skillId: String? = nil) -> ActivityDetail? {
        guard let curriculum = planningCurriculum else { return nil }
        return Finder.detail(curriculum, activityId: activityId, skillId: skillId)
    }

    /// The stage's pool-filtered library grouped by skill, Greeting first (F6).
    func browse(stageId: String, ageTag: String?) -> BrowseResult? {
        guard let curriculum = planningCurriculum else { return nil }
        return Finder.browse(curriculum, stageId: stageId, pool: pool, ageTag: ageTag).0
    }

    /// The stage's library narrowed to the activities named like `text`,
    /// grouped by skill (F7); no groups for a blank text.
    func search(stageId: String, text: String, ageTag: String?) -> SearchResult? {
        guard let curriculum = planningCurriculum else { return nil }
        return Finder.search(curriculum, stageId: stageId, pool: pool, text: text, ageTag: ageTag).0
    }

    /// The stage the finder opens on: the stage of today's class, else the one
    /// remembered in Settings, else the first loaded (DECISIONS_LOG
    /// 2026-09-12, "The plan is the product").
    func initialFinderStage(on date: String) -> String {
        let ids = stageChoices.map(\.id)
        if let today = todayLessons(on: date).first, let swimClass = swimClass(today.classId),
           ids.contains(swimClass.stageId) {
            return swimClass.stageId
        }
        if let remembered = settings.finderStageId, ids.contains(remembered) { return remembered }
        return ids.first ?? "1"
    }

    /// Remembers the finder's stage in Settings (an optional key, as V4's toggles).
    func rememberFinderStage(_ stageId: String) async {
        guard settings.finderStageId != stageId else { return }
        var updated = settings
        updated.finderStageId = stageId
        await commit(settings: updated)
    }

    /// The first sentence of an activity's description, for a block's card.
    func activityFirstSentence(_ activityId: String) -> String {
        Display.firstSentence(planningCurriculum?.activity(activityId)?["description"]?.stringValue ?? "")
    }

    /// The stage a skill belongs to.
    func stageId(ofSkill skillId: String) -> String? {
        planningCurriculum?.skill(skillId)?["stageId"]?.stringValue
    }

    /// The profile's equipment (P6), in catalog order, with their names.
    var profileEquipment: [(id: String, name: String)] {
        guard let curriculum = planningCurriculum else { return [] }
        return Activities.profileItems(curriculum).map { ($0, Activities.equipmentName(curriculum.equipment, $0)) }
    }

    // MARK: Names

    func stageName(_ stageId: String) -> String {
        planningCurriculum?.stage(stageId)?["name"]?.stringValue ?? "Stage \(stageId)"
    }

    /// "Stage 1 · Getting Comfortable".
    func stageTitle(_ stageId: String) -> String {
        "Stage \(stageId) · \(stageName(stageId))"
    }

    func skillName(_ skillId: String) -> String {
        planningCurriculum?.skill(skillId)?["name"]?.stringValue ?? skillId
    }

    func activityName(_ activityId: String) -> String {
        let name = planningCurriculum?.activity(activityId)?["name"]?.stringValue ?? ""
        return name.isEmpty ? activityId : name
    }

    /// The stage's skills in curriculum order, as (id, name).
    func skillChoices(of stageId: String) -> [(id: String, name: String)] {
        guard let curriculum = planningCurriculum else { return [] }
        return curriculum.skillsOf(stageId).compactMap { skill in
            guard let id = skill["id"]?.stringValue else { return nil }
            return (id, skill["name"]?.stringValue ?? id)
        }
    }

    /// The class's age tag (P/S/A), nil for infant-toddler groups (P5).
    func ageTag(_ swimClass: SwimClass) -> String? {
        Activities.ageTag(swimClass.ageGroup)
    }
}
