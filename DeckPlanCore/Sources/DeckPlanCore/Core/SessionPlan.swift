//
//  SessionPlan.swift
//  DeckPlanCore
//
//  The N-lesson mapping: which guide lesson a class's day k follows when N ≠ 8
//  — a port of `tools/core/session_plan.py` (docs/REDESIGN.md §2 "Guide
//  lesson"; docs/TEST_CASES.md C5; v1 B12). Read from the stage's own lesson
//  templates, never a hard-coded table.
//

import Foundation

/// `guideLessonForDay` was asked for a day outside 1..lessons — the Python's `ValueError`.
public struct DayOutOfRange: Error, Equatable, Sendable, CustomStringConvertible {
    public let day: Int
    public let lessons: Int

    public var description: String {
        "day \(day) is not within 1..\(lessons)"
    }
}

public enum SessionPlan {

    /// Guide lesson number -> its template, from the stage's `lessonTemplates`.
    static func templatesByN(_ curriculum: LoadedCurriculum, _ stageId: String) -> [Int: JSONValue] {
        var byN: [Int: JSONValue] = [:]
        for template in dictItems(curriculum.stage(stageId)?["lessonTemplates"]) {
            if let n = template["n"]?.intValue { byN[n] = template }
        }
        return byN
    }

    static func blocksByKind(_ template: JSONValue?) -> [String: JSONValue] {
        var byKind: [String: JSONValue] = [:]
        for block in dictItems(template?["blocks"]) {
            if let kind = block["kind"]?.stringValue { byKind[kind] = block }
        }
        return byKind
    }

    /// The skills a guide lesson's Introduce block introduces; nil when the block is
    /// "any" (or missing), so the lesson introduces nothing in particular.
    static func introducedSkills(_ block: JSONValue?) -> [String]? {
        let skillIds = stringItems(block?["skillIds"])
        if skillIds.isEmpty || skillIds == [Ids.anySkill] { return nil }
        return skillIds.filter { $0 != Ids.anySkill }
    }

    /// Days 1..`lessons` -> their guide lesson (1–8), or nil for an extra day (C5).
    ///
    /// N >= 8: every guide lesson is kept; `n - 8` extra days are inserted just
    /// before the last. N < 8: guide lessons are dropped one at a time, latest
    /// first within each step, never guide lesson 8, each drop re-checked against
    /// the days still kept: (a) a guide lesson whose Introduce is only "any";
    /// (b) else one whose introduced skills are every one of them introduced by
    /// another still-kept lesson; (c) else the latest remaining guide lesson
    /// before the last.
    public static func guideLessonMapping(_ curriculum: LoadedCurriculum, stageId: String,
                                          lessons n: Int) -> [Int?] {
        if n >= 8 {
            return (1...7).map { Optional($0) } + Array(repeating: nil, count: n - 8) + [8]
        }
        let templates = templatesByN(curriculum, stageId)
        var introduced: [[String]?] = Array(repeating: nil, count: 8)
        for guideN in 1...7 {
            introduced[guideN] = introducedSkills(blocksByKind(templates[guideN])["introduce"])
        }
        var kept = Set(1...7)
        let target = max(0, n - 1)
        while kept.count > target {
            let anyOnly = kept.filter { introduced[$0] == nil }.sorted(by: >)
            if let first = anyOnly.first {
                kept.remove(first)
                continue
            }
            var dropped: Int?
            for guideN in kept.sorted(by: >) {
                guard let skills = introduced[guideN], !skills.isEmpty else { continue }
                let others = kept.filter { $0 != guideN }.map { introduced[$0] }
                let covered = skills.allSatisfy { skill in
                    others.contains { other in other.map { $0.contains(skill) } ?? false }
                }
                if covered {
                    dropped = guideN
                    break
                }
            }
            if let dropped {
                kept.remove(dropped)
                continue
            }
            kept.remove(kept.max()!)
        }
        return kept.sorted().map { Optional($0) } + [8]
    }

    /// Day `day` of an N = `lessons` class -> its guide lesson number, or nil for an
    /// extra day. Throws `DayOutOfRange` when `day` is outside 1..lessons.
    public static func guideLessonForDay(_ curriculum: LoadedCurriculum, stageId: String, lessons: Int,
                                         day: Int) throws -> Int? {
        guard day >= 1, day <= lessons else { throw DayOutOfRange(day: day, lessons: lessons) }
        return guideLessonMapping(curriculum, stageId: stageId, lessons: lessons)[day - 1]
    }
}
