//
//  AppModel+Classes.swift
//  DeckPlan
//
//  Classes: list, create, edit, delete (docs/REDESIGN.md §5) over
//  `DeckPlanCore.Classes`. Every change is written before it is shown.
//

import Foundation
import DeckPlanCore

/// What a class form collects (REDESIGN §2 Class, minus id/order/log).
struct ClassForm: Equatable {
    var stageId: String
    var ageGroup: String
    /// Empty means the Core's default, "Stage <s> · <weekdays>".
    var name: String = ""
    var lessons: Int = Classes.defaultLessons
    var weekdays: Set<String> = []
    var firstDate: String

    init(stageId: String, ageGroup: String, firstDate: String) {
        self.stageId = stageId
        self.ageGroup = ageGroup
        self.firstDate = firstDate
    }

    /// The form prefilled from an existing class, for editing.
    init(_ swimClass: SwimClass) {
        stageId = swimClass.stageId
        ageGroup = swimClass.ageGroup
        name = swimClass.name
        lessons = swimClass.lessons
        weekdays = Set(swimClass.schedule.weekdays)
        firstDate = swimClass.schedule.firstDate
    }

    var orderedWeekdays: [String] { Classes.orderedWeekdays(Array(weekdays)) }
}

extension AppModel {
    /// The stages this curriculum loaded, in curriculum order, as (id, name).
    var stageChoices: [(id: String, name: String)] {
        guard let curriculum = planningCurriculum else { return [] }
        return curriculum.stages.compactMap { stage in
            guard let id = stage["id"]?.stringValue else { return nil }
            return (id, stage["name"]?.stringValue ?? "")
        }
    }

    /// The stage's age groups (REDESIGN §2: the class's age group is one of them).
    func ageGroups(of stageId: String) -> [String] {
        guard let stage = planningCurriculum?.stage(stageId) else { return [] }
        return stage["ageGroups"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    /// The name a class gets when the form's name is left empty.
    func defaultClassName(_ form: ClassForm) -> String {
        Classes.defaultName(stageId: form.stageId, weekdays: form.orderedWeekdays)
    }

    /// Creates a class from the form (REDESIGN §5 defaults) and commits.
    /// Returns the problems, empty on success.
    func createClass(_ form: ClassForm) async -> [Problem] {
        guard let curriculum = planningCurriculum else {
            return [Problem(code: "no-curriculum", where: "class", message: "The curriculum is not ready.")]
        }
        let (created, problems) = Classes.newClass(
            curriculum, stageId: form.stageId, weekdays: form.orderedWeekdays,
            firstDate: form.firstDate, classes: classes, name: form.name,
            ageGroup: form.ageGroup, lessons: form.lessons)
        guard let created else { return problems }
        // A first lesson today or earlier: those days save themselves at once.
        let saved = await commit(classes: classes + [settled(created).0])
        return saved ? [] : [Problem(code: "store-write", where: "class", message: saveError ?? "Not saved.")]
    }

    /// Applies the form to an existing class, keeping its id, order, log and
    /// draft, checks it with the Core and commits.
    func updateClass(_ classId: String, with form: ClassForm) async -> [Problem] {
        guard let curriculum = planningCurriculum else {
            return [Problem(code: "no-curriculum", where: "class", message: "The curriculum is not ready.")]
        }
        guard var updated = swimClass(classId) else {
            return [Problem(code: "class-missing", where: "class", message: "That class no longer exists.")]
        }
        updated.stageId = form.stageId
        updated.ageGroup = form.ageGroup
        updated.name = form.name.isEmpty ? defaultClassName(form) : form.name
        updated.lessons = form.lessons
        updated.schedule = ClassSchedule(weekdays: form.orderedWeekdays, firstDate: form.firstDate,
                                         extra: updated.schedule.extra)
        let problems = Problem.errors(Classes.validate(updated, curriculum: curriculum))
        guard problems.isEmpty else { return problems }
        let saved = await commit(class: settled(updated).0)
        return saved ? [] : [Problem(code: "store-write", where: "class", message: saveError ?? "Not saved.")]
    }

    /// Deletes the class and its lesson log (REDESIGN §5).
    @discardableResult
    func deleteClass(_ classId: String) async -> Bool {
        await deleteClasses([classId])
    }

    /// Deletes several classes and their logs in one write (the Classes
    /// list's select mode, DECISIONS_LOG 2026-09-13): all of them go, or,
    /// when the write fails, none.
    @discardableResult
    func deleteClasses(_ classIds: Set<String>) async -> Bool {
        await commit(classes: classIds.reduce(classes) { Classes.delete($0, classId: $1) })
    }

    /// The day a class's list marks next: the next day, or the last day done
    /// when the class is complete (DECISIONS_LOG 2026-09-12, C6).
    func todayDay(_ swimClass: SwimClass) -> Int {
        Classes.nextDay(swimClass) ?? Classes.lastDayDone(swimClass)
    }

    // MARK: Today by date (C7; DECISIONS_LOG 2026-09-12, "Today is the lesson dated today")

    /// The lessons dated `date`, in class order; the Core never reads the clock.
    func todayLessons(on date: String) -> [Classes.LessonRef] {
        Classes.today(classes, date: date)
    }

    /// The nearest lesson on or after `date`, across the classes.
    func nextLesson(on date: String) -> Classes.LessonRef? {
        Classes.nextLesson(classes, date: date)
    }

    /// True when the class carries the Core's default name, so a row does not
    /// repeat the stage and the days under it.
    func usesDefaultName(_ swimClass: SwimClass) -> Bool {
        swimClass.name == Classes.defaultName(stageId: swimClass.stageId, weekdays: swimClass.schedule.weekdays)
    }

    /// The date the schedule gives day n, or nil when the schedule cannot be
    /// computed.
    func lessonDate(_ swimClass: SwimClass, _ n: Int) -> String? {
        Classes.lessonDate(swimClass, n)
    }

    /// What the class's day list says about day n: a day in the log is Done
    /// (every day through today saves itself, DECISIONS_LOG 2026-09-13); a
    /// later day the draft holds changes to is Edited; then the next day.
    func dayStatus(_ swimClass: SwimClass, n: Int) -> DayStatus {
        if Classes.logEntry(swimClass, n) != nil { return .done }
        if swimClass.draft?.n == n { return .edited }
        if Classes.nextDay(swimClass) == n { return .next }
        return .later
    }

    /// The facts under a class's name, each said once (DECISIONS_LOG
    /// 2026-09-12, "The plan is the product"): a default name already says
    /// the stage number and the days, so the lines give the stage's name and
    /// the first date; a name of the owner's own gets the stage and the days.
    func classSummary(_ swimClass: SwimClass) -> [String] {
        let age = Display.ageGroup(swimClass.ageGroup)
        let done = Classes.lastDayDone(swimClass)
        let first = swimClass.schedule.firstDate
        if usesDefaultName(swimClass) {
            return [Display.ClassesWords.stageAndAge(stageName(swimClass.stageId), age),
                    Display.ClassesWords.fromDate(first, done, swimClass.lessons)]
        }
        return [Display.ClassesWords.stageAndAge(stageTitle(swimClass.stageId), age),
                Display.ClassesWords.weekdaysFromDate(swimClass.schedule.weekdays, first, done, swimClass.lessons)]
    }
}

/// A day's mark in a class's day list.
enum DayStatus: Equatable {
    /// In the log: every day through today is (DECISIONS_LOG 2026-09-13).
    case done
    /// A later day the class's draft holds changes to.
    case edited
    /// C6's next day: last done + 1.
    case next
    /// None of the above: a day still ahead.
    case later
}
