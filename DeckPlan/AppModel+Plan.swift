//
//  AppModel+Plan.swift
//  DeckPlan
//
//  Today's plan (docs/REDESIGN.md §3): a class's day k from the guide lesson,
//  shuffle and edit, over `DeckPlanCore.DayPlans`. There is no Save: every day
//  through today saves itself and a change to a saved day is saved at once
//  (DECISIONS_LOG 2026-09-13, "A day saves itself"). Every mutation gives the
//  Core the current class and commits the class it returns, as it is kept
//  (`settled`); the Core's problems come back as one sentence for the screen.
//

import Foundation
import DeckPlanCore

/// What a plan mutation produced for the screen: the shuffle's message when it
/// had one, or the problem that refused it — as `Display`'s sentence, never
/// the Core's (DECISIONS_LOG 2026-09-12, "The plan is the product").
struct PlanOutcome: Equatable {
    var ok: Bool
    /// The Core's problem code, when it refused.
    var code: String? = nil
    /// The screen's sentence: a refusal, or "No more new activities for this block."
    var message: String?
}

extension AppModel {
    /// The plan for a class's day n, or nil when the Core refused (a day out of
    /// range, a stage that did not load).
    func plan(classId: String, n: Int) -> DayPlan? {
        guard let curriculum = planningCurriculum, let swimClass = swimClass(classId) else { return nil }
        return DayPlans.planDay(curriculum, swimClass: swimClass, pool: pool, n: n).0
    }

    /// The blocks a day's screen draws, in its order: all but Welcome and Topic
    /// while their Settings toggle is off; Review always, after Introduce unless
    /// Settings asks for the guide's order (DECISIONS_LOG 2026-09-13, "Review
    /// is back", "Introduce before Review"). Display only — the plan, the draft
    /// and the saved entry keep every block in the guide's order
    /// (DECISIONS_LOG 2026-09-12).
    func visibleBlocks(_ plan: DayPlan) -> [PlanBlock] {
        var blocks = plan.blocks.filter { block in
            switch block.kind {
            case "welcome": return settings.showWelcome
            case "topic": return settings.showTopic
            default: return true
            }
        }
        if !settings.reviewFirst,
           let review = blocks.firstIndex(where: { $0.kind == "review" }),
           let introduce = blocks.firstIndex(where: { $0.kind == "introduce" }),
           review < introduce {
            blocks.swapAt(review, introduce)
        }
        return blocks
    }

    /// The Core's problems for the same call, for the empty state.
    func planProblems(classId: String, n: Int) -> [Problem] {
        guard let curriculum = planningCurriculum, let swimClass = swimClass(classId) else { return [] }
        return DayPlans.planDay(curriculum, swimClass: swimClass, pool: pool, n: n).1
    }

    private func planContext(_ classId: String) -> (LoadedCurriculum, SwimClass)? {
        guard let curriculum = planningCurriculum, let swimClass = swimClass(classId) else { return nil }
        return (curriculum, swimClass)
    }

    /// Commits the class a change returned, as it is kept (`settled`): a
    /// change to a saved day is saved at once.
    private func finish(_ updated: SwimClass, _ problems: [Problem], message: String? = nil) async -> PlanOutcome {
        if let first = Problem.errors(problems).first {
            return PlanOutcome(ok: false, code: first.code, message: Display.problem(first))
        }
        let (kept, refusal) = settled(updated)
        if let first = Problem.errors(refusal).first {
            return PlanOutcome(ok: false, code: first.code, message: Display.problem(first))
        }
        let saved = await commit(class: kept)
        return PlanOutcome(ok: saved, code: saved ? nil : "store-write",
                           message: saved ? message : (saveError ?? Display.General.notSaved))
    }

    private var notReady: PlanOutcome {
        PlanOutcome(ok: false, code: "no-curriculum", message: Display.General.notReady)
    }

    /// Shuffle one block (REDESIGN §3.3): a seeded draw of activities no other
    /// saved day holds, on any day (DECISIONS_LOG 2026-09-13).
    func shuffle(classId: String, n: Int, kind: String) async -> PlanOutcome {
        guard let (curriculum, swimClass) = planContext(classId) else { return notReady }
        let (updated, result, problems) = DayPlans.shuffle(curriculum, swimClass: swimClass, pool: pool, n: n, kind: kind)
        let sentence = result?.message == DayPlans.shuffleExhausted ? Display.Plan.noMoreNew : result?.message
        return await finish(updated, problems, message: sentence)
    }

    /// Pick the skill of an `["any"]` block (REDESIGN §3.1).
    func pickSkill(classId: String, n: Int, kind: String, skillId: String) async -> PlanOutcome {
        guard let (curriculum, swimClass) = planContext(classId) else { return notReady }
        let (updated, problems) = DayPlans.pickSkill(curriculum, swimClass: swimClass, pool: pool, n: n,
                                                     kind: kind, skillId: skillId)
        return await finish(updated, problems)
    }

    func removeActivity(classId: String, n: Int, kind: String, activityId: String) async -> PlanOutcome {
        guard let (curriculum, swimClass) = planContext(classId) else { return notReady }
        let (updated, problems) = DayPlans.removeActivity(curriculum, swimClass: swimClass, pool: pool, n: n,
                                                          kind: kind, activityId: activityId)
        return await finish(updated, problems)
    }

    /// Move within a block: the item at `from` ends up at `to` (the Core's
    /// remove-then-insert).
    func moveActivity(classId: String, n: Int, kind: String, from: Int, to: Int) async -> PlanOutcome {
        guard let (curriculum, swimClass) = planContext(classId) else { return notReady }
        let (updated, problems) = DayPlans.moveActivity(curriculum, swimClass: swimClass, pool: pool, n: n,
                                                        kind: kind, from: from, to: to)
        return await finish(updated, problems)
    }

    /// Add one from the finder (REDESIGN §3.4).
    func addActivity(classId: String, n: Int, kind: String, activityId: String) async -> PlanOutcome {
        guard let (curriculum, swimClass) = planContext(classId) else { return notReady }
        let (updated, problems) = DayPlans.addActivity(curriculum, swimClass: swimClass, pool: pool, n: n,
                                                       kind: kind, activityId: activityId)
        return await finish(updated, problems)
    }

    // MARK: A day saves itself (DECISIONS_LOG 2026-09-13)

    /// The class as it is kept: a saved day the draft holds changes to is saved
    /// again (the Core's `saveDay`), then every day dated through `today()`
    /// that has no entry saves itself, oldest first (`saveThrough`, D11). A
    /// later day's changes stay in the draft until its date. The problems are
    /// the re-save's refusal; a day the Core cannot plan stays unsaved, and its
    /// screen says why.
    func settled(_ swimClass: SwimClass) -> (SwimClass, [Problem]) {
        guard let curriculum = planningCurriculum else { return (swimClass, []) }
        var kept = swimClass
        if let n = kept.draft?.n, Classes.logEntry(kept, n) != nil {
            let (resaved, entry, problems) = DayPlans.saveDay(curriculum, swimClass: kept, pool: pool, n: n)
            guard entry != nil else { return (swimClass, problems) }
            kept = resaved
        }
        return (DayPlans.saveThrough(curriculum, swimClass: kept, pool: pool, date: today()).0, [])
    }

    /// Every class as it is kept, written once when anything changed: run when
    /// the store is read, when the app comes back and when the date changes.
    /// False when the write failed (`saveError` says why).
    @discardableResult
    func saveDaysThroughToday() async -> Bool {
        guard isReady else { return true }
        let kept = classes.map { settled($0).0 }
        return kept == classes ? true : await commit(classes: kept)
    }
}
