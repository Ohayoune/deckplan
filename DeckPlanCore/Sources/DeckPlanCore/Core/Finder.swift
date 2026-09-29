//
//  Finder.swift
//  DeckPlanCore
//
//  The activity finder, browse and search — a port of `tools/core/finder.py`
//  (docs/REDESIGN.md §4; docs/TEST_CASES.md F1–F7). Pure functions over the
//  curriculum and a pool profile. The finder's list is the pool-filtered
//  candidates in a seeded order (seed = hash of the inputs, the age tag
//  included), paged three at a time and wrapping after the last (F1). With a
//  step, the activities the guide pairs with the lessons whose `stepRange`
//  covers it come first in guide order, the rest of the skill's activities after
//  them, seeded (F3). Search (F7) is browse narrowed to the activities whose name
//  contains a text, case- and diacritic-insensitive.
//

import Foundation

public enum Finder {

    public static let pageSize = 3
    static let nullPart = "-"

    static func checkInputs(_ curriculum: LoadedCurriculum, stageId: String, skillId: String?,
                            step: Int?) -> [Problem] {
        guard curriculum.stage(stageId) != nil else {
            return [Problem(code: "finder-stage", where: "finder",
                            message: "Stage '\(stageId)' is not in the curriculum.")]
        }
        if let skillId {
            guard let skill = curriculum.skill(skillId), skill["stageId"]?.stringValue == stageId else {
                return [Problem(code: "finder-skill", where: "finder",
                                message: "'\(skillId)' is not a Stage \(stageId) skill.")]
            }
            if let step {
                let steps = stringItems(skill["stepIds"]).count
                if step < 1 || step > steps {
                    return [Problem(code: "finder-step", where: "finder",
                                    message: "\(skillId) has steps 1..\(steps), not \(step).")]
                }
            }
        } else if step != nil {
            return [Problem(code: "finder-step", where: "finder", message: "A step needs a skill.")]
        }
        return []
    }

    /// `hash_parts("finder", stage, skill or "-", step or "-", age tag or "-")`
    /// (DECISIONS_LOG 2026-09-12 "Finder seeding").
    public static func seed(stageId: String, skillId: String?, step: Int?, ageTag: String?) -> UInt64 {
        Canonical.hashParts(.string("finder"), .string(stageId), .string(skillId ?? nullPart),
                            step.map { Canonical.HashPart.int(Int64($0)) } ?? .string(nullPart),
                            .string(ageTag ?? nullPart))
    }

    /// The activities of every guide lesson block for `skillId` whose stepRange
    /// covers `step`, in guide order (lesson n, then block order), deduped (F3's
    /// first part). A block that pairs two skills lists both skills' activities;
    /// only those the skill itself lists count as paired with it.
    public static func guidePaired(_ curriculum: LoadedCurriculum, stageId: String, skillId: String,
                                   step: Int) -> [String] {
        let own = Set(stringItems(curriculum.skill(skillId)?["activityIds"]))
        let templates = dictItems(curriculum.stage(stageId)?["lessonTemplates"])
            .sorted { ($0["n"]?.intValue ?? 0) < ($1["n"]?.intValue ?? 0) }
        var found: [String] = []
        for template in templates {
            for block in dictItems(template["blocks"]) {
                guard stringItems(block["skillIds"]).contains(skillId) else { continue }
                let range = block["stepRange"]?.arrayValue?.compactMap(\.intValue) ?? []
                if range.count == 2, range[0] <= step, step <= range[1] {
                    found += stringItems(block["activityIds"]).filter { own.contains($0) }
                }
            }
        }
        return Activities.dedupe(found)
    }

    /// The finder's full ordered list for these inputs (F1–F4).
    public static func candidates(_ curriculum: LoadedCurriculum, stageId: String, pool: Pool,
                                  skillId: String? = nil, step: Int? = nil,
                                  ageTag: String? = nil) -> ([String], [Problem]) {
        let problems = checkInputs(curriculum, stageId: stageId, skillId: skillId, step: step)
        if !problems.isEmpty { return ([], problems) }
        let base: [String]
        if let skillId {
            base = Activities.dedupe(stringItems(curriculum.skill(skillId)?["activityIds"]))
        } else {
            base = Activities.library(curriculum, stageId)
        }
        let shown = Activities.filterIds(curriculum, base, pool: pool, ageTag: ageTag)
        let seeded = Activities.seededOrder(shown, seed: seed(stageId: stageId, skillId: skillId, step: step,
                                                              ageTag: ageTag))
        guard let step, let skillId else { return (seeded, []) }
        let shownSet = Set(shown)
        let paired = guidePaired(curriculum, stageId: stageId, skillId: skillId, step: step)
            .filter { shownSet.contains($0) }
        let pairedSet = Set(paired)
        return (paired + seeded.filter { !pairedSet.contains($0) }, [])
    }

    /// One page of the finder's list, before the inputs are attached (`finder.page`).
    public struct Slice: Equatable, Sendable {
        public var page: Int
        public var pageSize: Int
        public var total: Int
        public var activityIds: [String]
        public var wrapped: Bool
    }

    /// Page `pageNumber` (1-based) of three. The pages are fixed slices of the list;
    /// after the last (possibly short) page comes page 1 again, flagged `wrapped` (F1).
    public static func page(_ ordered: [String], pageNumber: Int, pageSize: Int = pageSize) -> Slice {
        let total = ordered.count
        if total == 0 || pageNumber < 1 {
            return Slice(page: max(pageNumber, 1), pageSize: pageSize, total: total, activityIds: [], wrapped: false)
        }
        let pageCount = (total + pageSize - 1) / pageSize
        let index = (pageNumber - 1) % pageCount
        let start = index * pageSize
        return Slice(page: pageNumber, pageSize: pageSize, total: total,
                     activityIds: Array(ordered[start..<min(start + pageSize, total)]),
                     wrapped: pageNumber - 1 >= pageCount)
    }

    /// One finder result: the inputs and page `pageNumber` of the ordered list.
    public static func find(_ curriculum: LoadedCurriculum, stageId: String, pool: Pool, skillId: String? = nil,
                            step: Int? = nil, ageTag: String? = nil,
                            pageNumber: Int = 1) -> (FinderPage?, [Problem]) {
        let (ordered, problems) = candidates(curriculum, stageId: stageId, pool: pool, skillId: skillId,
                                             step: step, ageTag: ageTag)
        if !problems.isEmpty { return (nil, problems) }
        let slice = page(ordered, pageNumber: pageNumber)
        return (FinderPage(stageId: stageId, skillId: skillId, step: step, ageTag: ageTag, page: slice.page,
                           pageSize: slice.pageSize, total: slice.total, activityIds: slice.activityIds,
                           wrapped: slice.wrapped), [])
    }

    /// What the finder shows for one activity (F5): name, description, required and
    /// optional equipment, ages, submerges, and the titles of the videos of
    /// `skillId` (or, without one, of every skill that lists the activity).
    public static func detail(_ curriculum: LoadedCurriculum, activityId: String,
                              skillId: String? = nil) -> ActivityDetail? {
        guard let activity = curriculum.activity(activityId) else { return nil }
        let skillIds = skillId.map { [$0] } ?? stringItems(activity["skillIds"])
        var titles: [String] = []
        for video in dictItems(curriculum.videos) {
            let videoSkills = stringItems(video["skillIds"])
            if skillIds.contains(where: { videoSkills.contains($0) }), let title = video["title"]?.stringValue {
                titles.append(title)
            }
        }
        let name = activity["name"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? activityId
        return ActivityDetail(
            id: activityId,
            name: name,
            description: activity["description"]?.stringValue ?? "",
            equipment: Activities.requirementPhrases(activity, curriculum.equipment),
            equipmentOptional: Activities.optionalNames(activity, curriculum.equipment),
            ages: stringItems(activity["ages"]),
            submerges: isTruthy(activity["submerges"]),
            videos: Activities.dedupe(titles))
    }

    /// The stage's pool-filtered library grouped by skill, Greeting first (F6). A
    /// skill with every activity hidden is an empty group.
    public static func browse(_ curriculum: LoadedCurriculum, stageId: String, pool: Pool,
                              ageTag: String? = nil) -> (BrowseResult?, [Problem]) {
        guard curriculum.stage(stageId) != nil else {
            return (nil, [Problem(code: "finder-stage", where: "browse",
                                  message: "Stage '\(stageId)' is not in the curriculum.")])
        }
        let groups = Activities.libraryGroups(curriculum, stageId).map { group in
            BrowseGroup(skillId: group.skillId, name: group.name,
                        activityIds: Activities.filterIds(curriculum, group.activityIds, pool: pool, ageTag: ageTag))
        }
        return (BrowseResult(stageId: stageId, ageTag: ageTag, groups: groups), [])
    }

    // MARK: - search (F7)

    /// Case- and diacritic-insensitive form (`finder.fold`): the Python normalises
    /// to NFKD, drops the combining marks and casefolds; Foundation's folding
    /// agrees for the library's names (ASCII, the odd accent).
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The stage's pool- and age-filtered library whose activity names contain
    /// `text`, grouped as browse (F6) with the groups that match nothing left out;
    /// an empty or blank text matches nothing (F7).
    public static func search(_ curriculum: LoadedCurriculum, stageId: String, pool: Pool, text: String,
                              ageTag: String? = nil) -> (SearchResult?, [Problem]) {
        guard curriculum.stage(stageId) != nil else {
            return (nil, [Problem(code: "finder-stage", where: "search",
                                  message: "Stage '\(stageId)' is not in the curriculum.")])
        }
        let needle = fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var groups: [BrowseGroup] = []
        if !needle.isEmpty {
            for group in Activities.libraryGroups(curriculum, stageId) {
                let shown = Activities.filterIds(curriculum, group.activityIds, pool: pool, ageTag: ageTag)
                let matching = shown.filter { activityId in
                    let name = curriculum.activity(activityId)?["name"]?.stringValue
                        .flatMap { $0.isEmpty ? nil : $0 } ?? activityId
                    return fold(name).contains(needle)
                }
                if !matching.isEmpty {
                    groups.append(BrowseGroup(skillId: group.skillId, name: group.name, activityIds: matching))
                }
            }
        }
        return (SearchResult(stageId: stageId, ageTag: ageTag, text: text, groups: groups), [])
    }
}
