//
//  DayPlan.swift
//  DeckPlanCore
//
//  Today's plan: a class's day k from the guide, its shuffle, edits and save —
//  a port of `tools/core/day_plan.py` (docs/REDESIGN.md §3; docs/TEST_CASES.md
//  C5, D1–D9). Pure functions over the curriculum, a `SwimClass` and a `Pool`;
//  every write returns a new class. Refusals are `Problem` entries.
//
//  Where a day's blocks come from (D8): the class's draft when it is for this
//  day (the working copy: edits, picks, shuffles); else the saved log entry;
//  else fresh from the guide (D1–D2). A saved day is edited, picked and
//  shuffled through the same draft and re-saved; its own entry is not "done"
//  for it. Every day dated on or before a given date saves itself, oldest
//  first (D11; DECISIONS_LOG 2026-09-13, "A day saves itself").
//

import Foundation

public enum DayPlans {

    /// An extra day (N > 8) borrows guide lesson 7's shape (C5).
    public static let extraDayGuideLesson = 7
    public static let shuffleExhausted = "no more new activities for this block"

    // MARK: - the guide lesson for a day (C5)

    /// (template, guide lesson number) for day `n` of an N = `lessons` class. An
    /// extra day gets guide lesson 7's block kinds and minutes with Review and
    /// Introduce ["any"], no guide activities and no topic (guide lesson nil).
    public static func templateForDay(_ curriculum: LoadedCurriculum, stageId: String, lessons: Int,
                                      n: Int) -> (template: JSONValue?, guideLesson: Int?) {
        let guideN: Int?
        do {
            guideN = try SessionPlan.guideLessonForDay(curriculum, stageId: stageId, lessons: lessons, day: n)
        } catch {
            return (nil, nil)
        }
        let templates = SessionPlan.templatesByN(curriculum, stageId)
        if let guideN { return (templates[guideN], guideN) }
        guard let source = templates[extraDayGuideLesson] else { return (nil, nil) }
        var blocks: [JSONValue] = []
        for block in dictItems(source["blocks"]) {
            let kind = block["kind"]?.stringValue
            var extra: [String: JSONValue] = [:]
            if let kindValue = block["kind"] { extra["kind"] = kindValue }
            if let minutes = block["minutes"] { extra["minutes"] = minutes }
            if kind == "review" || kind == "introduce" {
                extra["skillIds"] = .array([.string(Ids.anySkill)])
            } else if kind != "topic" {
                for key in ["skillIds", "stepRange"] {
                    if let value = block[key] { extra[key] = value }
                }
            }
            blocks.append(.object(extra))
        }
        var template: [String: JSONValue] = [
            "n": .int(Int64(n)), "blocks": .array(blocks), "stageId": .string(stageId),
        ]
        if let minutes = source["minutes"] { template["minutes"] = minutes }
        return (.object(template), nil)
    }

    /// Whether a template block's `skillIds` is exactly `["any"]`.
    public static func isAny(_ block: JSONValue) -> Bool {
        stringItems(block["skillIds"]) == [Ids.anySkill]
    }

    /// The stage's skills in library order, for an "any" block's pick (D3).
    public static func skillChoices(_ curriculum: LoadedCurriculum, stageId: String) -> [String] {
        curriculum.skillsOf(stageId).compactMap { $0["id"]?.stringValue }
    }

    // MARK: - candidates (D2)

    /// D2's full list for a block: the guide's own activities, then the activities
    /// of the block's skills in catalog order, deduped, then pool- and
    /// age-filtered. For an "any" block `skillIds` is the pick; without one the
    /// list is empty.
    public static func blockCandidates(_ curriculum: LoadedCurriculum, templateBlock: JSONValue, pool: Pool,
                                       ageTag: String?, skillIds: [String]? = nil) -> [String] {
        let chosen: [String]
        let guideIds: [String]
        if isAny(templateBlock) {
            chosen = (skillIds ?? []).filter { $0 != Ids.anySkill }
            if chosen.isEmpty { return [] }
            guideIds = []
        } else {
            chosen = stringItems(templateBlock["skillIds"])
            guideIds = stringItems(templateBlock["activityIds"])
        }
        let combined = Activities.dedupe(guideIds + Activities.skillActivityIds(curriculum, chosen))
        return Activities.dedupe(Activities.filterIds(curriculum, combined, pool: pool, ageTag: ageTag))
    }

    static func topic(_ curriculum: LoadedCurriculum, _ code: String) -> PlanTopic? {
        guard let topic = curriculum.topic(code) else { return nil }
        return PlanTopic(code: code,
                         name: topic["name"]?.stringValue ?? "",
                         summary: topic["summary"]?.stringValue ?? "")
    }

    static func planBlock(_ curriculum: LoadedCurriculum, templateBlock: JSONValue, stageId: String,
                          skillIds: [String], activityIds: [String], pool: Pool, ageTag: String?,
                          flagHidden: Bool) -> PlanBlock {
        var block = PlanBlock(kind: templateBlock["kind"]?.stringValue ?? "")
        block.minutes = templateBlock["minutes"].flatMap { $0.isNull ? nil : $0.intValue }
        block.stepRange = templateBlock["stepRange"].flatMap { value in
            value.isNull ? nil : value.arrayValue?.compactMap(\.intValue)
        }
        block.notes = templateBlock["notes"].flatMap { $0.isNull ? nil : stringItems($0) }
        block.topicCode = templateBlock["topicCode"]?.stringValue
        block.skillIds = skillIds
        if let code = block.topicCode, !code.isEmpty, let found = topic(curriculum, code) {
            block.topic = found
        }
        if isAny(templateBlock), skillIds == [Ids.anySkill] {
            block.skillChoices = skillChoices(curriculum, stageId: stageId)
        }
        block.activityIds = activityIds
        if flagHidden {
            let shown = Set(Activities.filterIds(curriculum, activityIds, pool: pool, ageTag: ageTag))
            let hidden = activityIds.filter { !shown.contains($0) }
            if !hidden.isEmpty { block.hidden = hidden }
        }
        return block
    }

    /// D10: the one activity a fresh block shows — the first candidate not in the
    /// class's done set, else the first candidate; nothing when there are none
    /// (DECISIONS_LOG 2026-09-12 "A block shows one activity, the app's pick").
    public static func shownActivities(_ candidates: [String], done: Set<String>) -> [String] {
        if let first = candidates.first(where: { !done.contains($0) }) { return [first] }
        return Array(candidates.prefix(1))
    }

    /// D1, D2, D10: the guide's blocks, each showing one of its candidates.
    public static func freshBlocks(_ curriculum: LoadedCurriculum, template: JSONValue, stageId: String,
                                   pool: Pool, ageTag: String?, done: Set<String>) -> [PlanBlock] {
        dictItems(template["blocks"]).map { templateBlock in
            let skillIds = stringItems(templateBlock["skillIds"])
            let candidates = blockCandidates(curriculum, templateBlock: templateBlock, pool: pool, ageTag: ageTag)
            return planBlock(curriculum, templateBlock: templateBlock, stageId: stageId, skillIds: skillIds,
                             activityIds: shownActivities(candidates, done: done), pool: pool, ageTag: ageTag,
                             flagHidden: false)
        }
    }

    // MARK: - the plan (D1, D8)

    static func checkDay(_ swimClass: SwimClass, _ n: Int) -> [Problem] {
        if n < 1 || n > swimClass.lessons {
            return [Problem(code: "day-range", where: "class \(swimClass.id)",
                            message: "Day \(n) is not one of this class's \(swimClass.lessons) lessons.")]
        }
        return []
    }

    /// The plan for day `n` (see the file comment for where its blocks come from).
    public static func planDay(_ curriculum: LoadedCurriculum, swimClass: SwimClass, pool: Pool,
                               n: Int) -> (DayPlan?, [Problem]) {
        let problems = checkDay(swimClass, n)
        if !problems.isEmpty { return (nil, problems) }
        let stageId = swimClass.stageId
        let (template, guideN) = templateForDay(curriculum, stageId: stageId, lessons: swimClass.lessons, n: n)
        guard let template else {
            return (nil, [Problem(code: "day-template", where: "class \(swimClass.id)",
                                  message: "Stage \(stageId) has no lesson template for day \(n).")])
        }
        let ageTag = Activities.ageTag(swimClass.ageGroup)
        let entry = Classes.logEntry(swimClass, n)
        let draft = Classes.draftFor(swimClass, n)
        let blocks: [PlanBlock]
        if draft != nil || entry != nil {
            var savedSkillIds: [String: [String]] = [:]
            var savedActivityIds: [String: [String]] = [:]
            if let draft {
                for block in draft.blocks {
                    savedSkillIds[block.kind] = block.skillIds
                    savedActivityIds[block.kind] = block.activityIds
                }
            } else if let entry {
                for block in entry.blocks { savedActivityIds[block.kind] = block.activityIds }
            }
            blocks = dictItems(template["blocks"]).map { templateBlock in
                let kind = templateBlock["kind"]?.stringValue ?? ""
                let skillIds = (draft != nil ? savedSkillIds[kind] : nil) ?? stringItems(templateBlock["skillIds"])
                return planBlock(curriculum, templateBlock: templateBlock, stageId: stageId, skillIds: skillIds,
                                 activityIds: savedActivityIds[kind] ?? [], pool: pool, ageTag: ageTag,
                                 flagHidden: true)
            }
        } else {
            blocks = freshBlocks(curriculum, template: template, stageId: stageId, pool: pool, ageTag: ageTag,
                                 done: Classes.doneSet(swimClass))
        }
        return (DayPlan(classId: swimClass.id, n: n, date: Classes.lessonDate(swimClass, n), guideLesson: guideN,
                        saved: entry != nil, draft: draft != nil, blocks: blocks), [])
    }

    /// The plan's canonical JSON (D9).
    public static func planJSON(_ plan: DayPlan) throws -> String {
        try Canonical.dumps(plan.json)
    }

    // MARK: - the draft (D6)

    static func draftFromPlan(_ plan: DayPlan) -> Draft {
        Draft(n: plan.n,
              blocks: plan.blocks.map { DraftBlock(kind: $0.kind, skillIds: $0.skillIds, activityIds: $0.activityIds) },
              shuffleCounts: [:])
    }

    /// The class with a draft for day `n` (created from the day's plan when there is
    /// none: another day's draft is dropped, D6) and that draft.
    public static func ensureDraft(_ curriculum: LoadedCurriculum, swimClass: SwimClass, pool: Pool,
                                   n: Int) -> (SwimClass, Draft?, [Problem]) {
        if let draft = Classes.draftFor(swimClass, n) { return (swimClass, draft, []) }
        let (plan, problems) = planDay(curriculum, swimClass: swimClass, pool: pool, n: n)
        guard let plan else { return (swimClass, nil, problems) }
        let draft = draftFromPlan(plan)
        return (Classes.withDraft(swimClass, draft), draft, [])
    }

    static func draftBlock(_ draft: Draft, _ kind: String) -> DraftBlock? {
        draft.blocks.first { $0.kind == kind }
    }

    static func replaceBlock(_ swimClass: SwimClass, draft: Draft, kind: String, newBlock: DraftBlock,
                             shuffleCount: Int? = nil) -> SwimClass {
        var updated = draft
        updated.blocks = draft.blocks.map { $0.kind == kind ? newBlock : $0 }
        if let shuffleCount { updated.shuffleCounts[kind] = shuffleCount }
        return Classes.withDraft(swimClass, updated)
    }

    static func templateBlock(_ curriculum: LoadedCurriculum, swimClass: SwimClass, n: Int,
                              kind: String) -> JSONValue? {
        let (template, _) = templateForDay(curriculum, stageId: swimClass.stageId, lessons: swimClass.lessons, n: n)
        return dictItems(template?["blocks"]).first { $0["kind"]?.stringValue == kind }
    }

    struct EditContext {
        var swimClass: SwimClass
        var draft: Draft
        var templateBlock: JSONValue
    }

    /// Common checks for shuffle and edits: a valid day, a block of that kind, a draft.
    static func editSetup(_ curriculum: LoadedCurriculum, swimClass: SwimClass, pool: Pool, n: Int,
                          kind: String) -> (EditContext?, [Problem]) {
        let problems = checkDay(swimClass, n)
        if !problems.isEmpty { return (nil, problems) }
        let whereLabel = "class \(swimClass.id) day \(n)"
        guard let templateBlock = templateBlock(curriculum, swimClass: swimClass, n: n, kind: kind),
              kind != "topic" else {
            return (nil, [Problem(code: "block-kind", where: whereLabel,
                                  message: "Day \(n) has no editable '\(kind)' block.")])
        }
        let (updated, draft, draftProblems) = ensureDraft(curriculum, swimClass: swimClass, pool: pool, n: n)
        guard let draft, draftProblems.isEmpty else { return (nil, draftProblems) }
        return (EditContext(swimClass: updated, draft: draft, templateBlock: templateBlock), [])
    }

    // MARK: - shuffle (D4, D5)

    /// D4: the next `slots` never-done candidates along their seeded order, read
    /// as a cycle from just after the last of `shown` in it (from the start when
    /// none is); the ones `shown` holds come only after every other, so repeated
    /// shuffles walk through every never-done candidate before one comes back
    /// (DECISIONS_LOG 2026-09-13; `tools/core/day_plan.py` `cycle_draw`).
    public static func cycleDraw(_ neverDone: [String], shown: [String], seed: UInt64, slots: Int) -> [String] {
        let order = Activities.seededOrder(neverDone, seed: seed)
        let anchor = shown.last(where: { order.contains($0) }).flatMap { order.firstIndex(of: $0) }
        let start = anchor.map { $0 + 1 } ?? 0
        let walk = Array(order[start...] + order[..<start])
        let held = Set(shown)
        return Array((walk.filter { !held.contains($0) } + walk.filter { held.contains($0) }).prefix(slots))
    }

    /// Replace the block's activities with as many never-done candidates, the next
    /// ones along a seeded cycle (seed = hash of class id, day, kind; `cycleDraw`).
    /// Never done: in no saved day but this one, so a saved day shuffles too
    /// (DECISIONS_LOG 2026-09-13, "A day saves itself"). Returns the class with the
    /// draft updated and the draw, with the message when fewer never-done
    /// candidates exist than the block shows, or none but those it shows; a block
    /// with nothing in it is refused with the class unchanged.
    public static func shuffle(_ curriculum: LoadedCurriculum, swimClass: SwimClass, pool: Pool, n: Int,
                               kind: String) -> (SwimClass, ShuffleResult?, [Problem]) {
        let whereLabel = "class \(swimClass.id) day \(n)"
        let (context, problems) = editSetup(curriculum, swimClass: swimClass, pool: pool, n: n, kind: kind)
        guard let context else { return (swimClass, nil, problems) }
        let block = draftBlock(context.draft, kind) ?? DraftBlock(kind: kind, skillIds: [], activityIds: [])
        let slots = block.activityIds.count
        if slots == 0 {
            let hint = isAny(context.templateBlock) ? "; pick a skill first" : ""
            return (context.swimClass, nil, [Problem(
                code: "shuffle-empty", where: whereLabel,
                message: "The \(kind) block has no activities to shuffle\(hint).")])
        }
        let ageTag = Activities.ageTag(swimClass.ageGroup)
        let candidates = blockCandidates(curriculum, templateBlock: context.templateBlock, pool: pool,
                                         ageTag: ageTag, skillIds: block.skillIds)
        let done = Classes.doneSet(swimClass, except: n)
        let neverDone = candidates.filter { !done.contains($0) }
        let count = (context.draft.shuffleCounts[kind] ?? 0) + 1
        let seed = Canonical.hashParts(.string(swimClass.id), .int(Int64(n)), .string(kind))
        let drawn = cycleDraw(neverDone, shown: block.activityIds, seed: seed, slots: slots)
        let exhausted = neverDone.count < slots || Set(drawn) == Set(block.activityIds)
        let result = ShuffleResult(kind: kind, activityIds: drawn, shuffleCount: count,
                                   message: exhausted ? shuffleExhausted : nil)
        var newBlock = block
        newBlock.activityIds = drawn
        return (replaceBlock(context.swimClass, draft: context.draft, kind: kind, newBlock: newBlock,
                             shuffleCount: count), result, [])
    }

    // MARK: - edits (D3, D6)

    /// Resolve an "any" block to one of the stage's skills; the block then shows one
    /// of that skill's activities, the first never done (D3, D10).
    public static func pickSkill(_ curriculum: LoadedCurriculum, swimClass: SwimClass, pool: Pool, n: Int,
                                 kind: String, skillId: String) -> (SwimClass, [Problem]) {
        let (context, problems) = editSetup(curriculum, swimClass: swimClass, pool: pool, n: n, kind: kind)
        guard let context else { return (swimClass, problems) }
        let whereLabel = "class \(swimClass.id) day \(n)"
        guard isAny(context.templateBlock) else {
            return (swimClass, [Problem(code: "pick-not-any", where: whereLabel,
                                        message: "The \(kind) block's skills are set by the guide.")])
        }
        guard skillChoices(curriculum, stageId: swimClass.stageId).contains(skillId) else {
            return (swimClass, [Problem(code: "pick-skill", where: whereLabel,
                                        message: "'\(skillId)' is not a Stage \(swimClass.stageId) skill.")])
        }
        let ageTag = Activities.ageTag(swimClass.ageGroup)
        let block = draftBlock(context.draft, kind) ?? DraftBlock(kind: kind, skillIds: [], activityIds: [])
        var newBlock = block
        newBlock.skillIds = [skillId]
        let candidates = blockCandidates(curriculum, templateBlock: context.templateBlock, pool: pool,
                                         ageTag: ageTag, skillIds: [skillId])
        newBlock.activityIds = shownActivities(candidates, done: Classes.doneSet(swimClass, except: n))
        return (replaceBlock(context.swimClass, draft: context.draft, kind: kind, newBlock: newBlock), [])
    }

    public static func removeActivity(_ curriculum: LoadedCurriculum, swimClass: SwimClass, pool: Pool, n: Int,
                                      kind: String, activityId: String) -> (SwimClass, [Problem]) {
        let (context, problems) = editSetup(curriculum, swimClass: swimClass, pool: pool, n: n, kind: kind)
        guard let context else { return (swimClass, problems) }
        let block = draftBlock(context.draft, kind) ?? DraftBlock(kind: kind, skillIds: [], activityIds: [])
        guard block.activityIds.contains(activityId) else {
            return (swimClass, [Problem(code: "edit-missing", where: "class \(swimClass.id) day \(n)",
                                        message: "'\(activityId)' is not in the \(kind) block.")])
        }
        var newBlock = block
        newBlock.activityIds = block.activityIds.filter { $0 != activityId }
        return (replaceBlock(context.swimClass, draft: context.draft, kind: kind, newBlock: newBlock), [])
    }

    public static func moveActivity(_ curriculum: LoadedCurriculum, swimClass: SwimClass, pool: Pool, n: Int,
                                    kind: String, from fromIndex: Int, to toIndex: Int) -> (SwimClass, [Problem]) {
        let (context, problems) = editSetup(curriculum, swimClass: swimClass, pool: pool, n: n, kind: kind)
        guard let context else { return (swimClass, problems) }
        let block = draftBlock(context.draft, kind) ?? DraftBlock(kind: kind, skillIds: [], activityIds: [])
        var items = block.activityIds
        guard items.indices.contains(fromIndex), items.indices.contains(toIndex) else {
            return (swimClass, [Problem(
                code: "edit-index", where: "class \(swimClass.id) day \(n)",
                message: "The \(kind) block has \(items.count) activities; positions \(fromIndex) -> \(toIndex) "
                    + "are out of range.")])
        }
        let moved = items.remove(at: fromIndex)
        items.insert(moved, at: toIndex)
        var newBlock = block
        newBlock.activityIds = items
        return (replaceBlock(context.swimClass, draft: context.draft, kind: kind, newBlock: newBlock), [])
    }

    /// Append an activity from the finder; it must be in the stage's library and not
    /// already in the block (D6).
    public static func addActivity(_ curriculum: LoadedCurriculum, swimClass: SwimClass, pool: Pool, n: Int,
                                   kind: String, activityId: String) -> (SwimClass, [Problem]) {
        let (context, problems) = editSetup(curriculum, swimClass: swimClass, pool: pool, n: n, kind: kind)
        guard let context else { return (swimClass, problems) }
        let whereLabel = "class \(swimClass.id) day \(n)"
        guard Activities.library(curriculum, swimClass.stageId).contains(activityId) else {
            return (swimClass, [Problem(code: "edit-library", where: whereLabel,
                                        message: "'\(activityId)' is not a Stage \(swimClass.stageId) activity.")])
        }
        let block = draftBlock(context.draft, kind) ?? DraftBlock(kind: kind, skillIds: [], activityIds: [])
        guard !block.activityIds.contains(activityId) else {
            return (swimClass, [Problem(code: "edit-duplicate", where: whereLabel,
                                        message: "'\(activityId)' is already in the \(kind) block.")])
        }
        var newBlock = block
        newBlock.activityIds = block.activityIds + [activityId]
        return (replaceBlock(context.swimClass, draft: context.draft, kind: kind, newBlock: newBlock), [])
    }

    // MARK: - save (D7)

    /// Write day `n`'s log entry `{n, date, blocks: [{kind, activityIds}]}` from the
    /// day's plan (draft, saved entry or fresh), dated by the schedule; clear the
    /// day's draft. Returns (class, entry, problems).
    public static func saveDay(_ curriculum: LoadedCurriculum, swimClass: SwimClass, pool: Pool,
                               n: Int) -> (SwimClass, LogEntry?, [Problem]) {
        let (plan, problems) = planDay(curriculum, swimClass: swimClass, pool: pool, n: n)
        guard let plan else { return (swimClass, nil, problems) }
        let entry = LogEntry(n: n, date: plan.date,
                             blocks: plan.blocks.map { LogBlock(kind: $0.kind, activityIds: $0.activityIds) })
        var updated = Classes.withLogEntry(swimClass, entry)
        if Classes.draftFor(updated, n) != nil {
            updated = Classes.withDraft(updated, nil)
        }
        return (updated, entry, [])
    }

    /// D11: save every day dated on or before `date` that has no log entry, oldest
    /// first, each as `saveDay` would (its draft when it has one, else its fresh
    /// plan with the days before it done), so the app needs no Save (DECISIONS_LOG
    /// 2026-09-13, "A day saves itself"; `tools/core/day_plan.py` `save_through`).
    /// Returns the class, the days saved, and the problems of a day the Core could
    /// not plan, which stays unsaved. The Core takes the date; it never reads the clock.
    public static func saveThrough(_ curriculum: LoadedCurriculum, swimClass: SwimClass, pool: Pool,
                                   date: String) -> (SwimClass, [Int], [Problem]) {
        var updated = swimClass
        var saved: [Int] = []
        var found: [Problem] = []
        for (index, lessonDate) in Classes.lessonDates(swimClass).enumerated() {
            let n = index + 1
            if Canonical.scalarsPrecede(date, lessonDate) || Classes.logEntry(updated, n) != nil { continue }
            let (next, entry, problems) = saveDay(curriculum, swimClass: updated, pool: pool, n: n)
            if entry == nil {
                found += problems
            } else {
                updated = next
                saved.append(n)
            }
        }
        return (updated, saved, found)
    }
}
