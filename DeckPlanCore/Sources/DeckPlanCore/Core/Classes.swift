//
//  Classes.swift
//  DeckPlanCore
//
//  Classes and their lesson logs — a port of `tools/core/classes.py`
//  (docs/REDESIGN.md §2, §5; docs/TEST_CASES.md C1–C7). Every function is pure:
//  it returns a new `SwimClass` and never mutates its argument. Refusals are
//  `Problem` entries (never thrown), so the CLI, the tests and this port report
//  them the same way.
//

import Foundation

public enum Classes {

    public static let defaultLessons = 8

    static let weekdayLabels: [String: String] = [
        "mon": "Mon", "tue": "Tue", "wed": "Wed", "thu": "Thu", "fri": "Fri", "sat": "Sat", "sun": "Sun",
    ]

    // MARK: - create, list, delete (C1–C3)

    /// The recognized weekdays in week order (mon..sun), deduped.
    public static func orderedWeekdays(_ weekdays: [String]) -> [String] {
        let wanted = Set(weekdays)
        return Schedule.weekdayNames.filter { wanted.contains($0) }
    }

    /// "Stage 1 · Mon Wed" (C1).
    public static func defaultName(stageId: String, weekdays: [String]) -> String {
        let days = orderedWeekdays(weekdays).map { weekdayLabels[$0] ?? $0 }.joined(separator: " ")
        return days.isEmpty ? "Stage \(stageId)" : "Stage \(stageId) · \(days)"
    }

    /// The highest existing order + 1; 1 when there are no classes.
    public static func nextOrder(_ classes: [SwimClass]) -> Int {
        (classes.map(\.order).max() ?? 0) + 1
    }

    /// A class with REDESIGN §5's defaults filled in, or nil with the problems that
    /// stop it (an unloaded stage, an age group the stage has not, lessons < 1, no
    /// usable weekday, a bad date). `classId` defaults to a fresh lower-case UUID.
    public static func newClass(_ curriculum: LoadedCurriculum, stageId: String, weekdays: [String],
                                firstDate: String, classes: [SwimClass] = [], name: String? = nil,
                                ageGroup: String? = nil, lessons: Int = defaultLessons,
                                classId: String? = nil) -> (SwimClass?, [Problem]) {
        var problems: [Problem] = []
        guard let stage = curriculum.stage(stageId) else {
            return (nil, [Problem(code: "class-stage", where: "class",
                                  message: "Stage '\(stageId)' is not in the curriculum.")])
        }
        let stageAges = stringItems(stage["ageGroups"])
        let age = ageGroup ?? stageAges.first
        if age == nil || !stageAges.contains(age!) {
            problems.append(Problem(
                code: "class-age-group", where: "class",
                message: "Stage \(stageId) has no age group '\(age ?? "None")'; it has "
                    + "\(stageAges.isEmpty ? "none" : stageAges.joined(separator: ", "))."))
        }
        if lessons < 1 {
            problems.append(Problem(code: "class-lessons", where: "class",
                                    message: "A class needs at least one lesson, not \(lessons)."))
        }
        let days = orderedWeekdays(weekdays)
        if days.isEmpty {
            problems.append(Problem(code: "class-weekdays", where: "class",
                                    message: "A class needs at least one weekday (mon..sun) to meet on."))
        }
        do {
            _ = try Schedule.lessonDates(start: firstDate, weekdays: days.isEmpty ? ["mon"] : days, count: 1)
        } catch {
            problems.append(Problem(code: "class-first-date", where: "class",
                                    message: "'\(firstDate)' is not a date (YYYY-MM-DD)."))
        }
        if !problems.isEmpty { return (nil, problems) }
        let givenName = name.flatMap { $0.isEmpty ? nil : $0 }
        return (SwimClass(
            id: classId ?? UUID().uuidString.lowercased(),
            name: givenName ?? defaultName(stageId: stageId, weekdays: days),
            stageId: stageId,
            ageGroup: age!,
            lessons: lessons,
            order: nextOrder(classes),
            schedule: ClassSchedule(weekdays: days, firstDate: firstDate),
            log: [],
            draft: nil), [])
    }

    /// By order, then name, then id (C2).
    public static func sorted(_ classes: [SwimClass]) -> [SwimClass] {
        classes.sorted { a, b in
            if a.order != b.order { return a.order < b.order }
            if a.name != b.name { return Canonical.scalarsPrecede(a.name, b.name) }
            return Canonical.scalarsPrecede(a.id, b.id)
        }
    }

    /// Every class but the one; its log and draft go with it (C3).
    public static func delete(_ classes: [SwimClass], classId: String) -> [SwimClass] {
        classes.filter { $0.id != classId }
    }

    public static func find(_ classes: [SwimClass], classId: String) -> SwimClass? {
        classes.first { $0.id == classId }
    }

    // MARK: - dates and day numbering (C4, C6)

    /// The class's N dates; `[]` when its schedule cannot yield any.
    public static func lessonDates(_ swimClass: SwimClass) -> [String] {
        (try? Schedule.lessonDates(start: swimClass.schedule.firstDate, weekdays: swimClass.schedule.weekdays,
                                   count: swimClass.lessons)) ?? []
    }

    /// Day n's date, nil outside 1..N.
    public static func lessonDate(_ swimClass: SwimClass, _ n: Int) -> String? {
        let dates = lessonDates(swimClass)
        return n >= 1 && n <= dates.count ? dates[n - 1] : nil
    }

    public static func logEntry(_ swimClass: SwimClass, _ n: Int) -> LogEntry? {
        swimClass.log.first { $0.n == n }
    }

    /// The highest saved day, 0 when none (C6).
    public static func lastDayDone(_ swimClass: SwimClass) -> Int {
        swimClass.log.map(\.n).max() ?? 0
    }

    /// Last done + 1, or nil when every day is saved (the class is complete).
    public static func nextDay(_ swimClass: SwimClass) -> Int? {
        let following = lastDayDone(swimClass) + 1
        return following <= swimClass.lessons ? following : nil
    }

    public static func isComplete(_ swimClass: SwimClass) -> Bool {
        nextDay(swimClass) == nil
    }

    // MARK: - today by date (C7)
    //
    // DECISIONS_LOG 2026-09-12 "Today is the lesson dated today" and the owner's
    // answers. The Core takes the date as an argument and never reads the clock;
    // the app passes the device's calendar day as "YYYY-MM-DD".

    /// A lesson day named by class and n — `{classId, n}` from `today`, with its
    /// `date` from `nextLesson` and `missed` (the Python's dicts).
    public struct LessonRef: Hashable, Sendable {
        public var classId: String
        public var n: Int
        public var date: String?

        public init(classId: String, n: Int, date: String? = nil) {
            self.classId = classId
            self.n = n
            self.date = date
        }

        public var json: JSONValue {
            var fields: [String: JSONValue] = ["classId": .string(classId), "n": .int(Int64(n))]
            if let date { fields["date"] = .string(date) }
            return .object(fields)
        }
    }

    /// The n whose scheduled date (C4) is `isoDate`, else nil.
    public static func dayOn(_ swimClass: SwimClass, date isoDate: String) -> Int? {
        lessonDates(swimClass).firstIndex(of: isoDate).map { $0 + 1 }
    }

    /// Every class with a day on `isoDate`, saved or not, in class order (C2).
    public static func today(_ classes: [SwimClass], date isoDate: String) -> [LessonRef] {
        sorted(classes).compactMap { swimClass in
            dayOn(swimClass, date: isoDate).map { LessonRef(classId: swimClass.id, n: $0) }
        }
    }

    /// The nearest lesson on or after `isoDate` across the classes, ties by class
    /// order; nil when every class is past its last date.
    public static func nextLesson(_ classes: [SwimClass], date isoDate: String) -> LessonRef? {
        var best: (date: String, position: Int, lesson: LessonRef)?
        for (position, swimClass) in sorted(classes).enumerated() {
            let dates = lessonDates(swimClass)
            guard let index = dates.firstIndex(where: { !Canonical.scalarsPrecede($0, isoDate) }) else { continue }
            let date = dates[index]
            let earlier = best.map { Canonical.scalarsPrecede(date, $0.date) || (date == $0.date && position < $0.position) }
            if earlier ?? true {
                best = (date, position, LessonRef(classId: swimClass.id, n: index + 1, date: date))
            }
        }
        return best?.lesson
    }

    /// Every day dated before `isoDate` that has no log entry (a missed day),
    /// oldest first, ties by class order.
    public static func missed(_ classes: [SwimClass], date isoDate: String) -> [LessonRef] {
        var found: [(date: String, position: Int, index: Int, lesson: LessonRef)] = []
        for (position, swimClass) in sorted(classes).enumerated() {
            let saved = Set(swimClass.log.map(\.n))
            for (index, date) in lessonDates(swimClass).enumerated()
            where Canonical.scalarsPrecede(date, isoDate) && !saved.contains(index + 1) {
                found.append((date, position, index, LessonRef(classId: swimClass.id, n: index + 1, date: date)))
            }
        }
        return found.sorted { a, b in
            if a.date != b.date { return Canonical.scalarsPrecede(a.date, b.date) }
            if a.position != b.position { return a.position < b.position }
            return a.index < b.index
        }.map(\.lesson)
    }

    /// Every activity id in the class's saved days (docs/REDESIGN.md §2 "Done set");
    /// without day `n`'s own entry when given, so a saved day's shuffle and pick
    /// count as done only what another day holds (DECISIONS_LOG 2026-09-13, "A day
    /// saves itself").
    public static func doneSet(_ swimClass: SwimClass, except n: Int? = nil) -> Set<String> {
        var done: Set<String> = []
        for entry in swimClass.log where entry.n != n {
            for block in entry.blocks { done.formUnion(block.activityIds) }
        }
        return done
    }

    // MARK: - writes (return a new class)

    /// The class with `entry` in its log, replacing any entry with the same n; the
    /// log stays sorted by n.
    public static func withLogEntry(_ swimClass: SwimClass, _ entry: LogEntry) -> SwimClass {
        var updated = swimClass
        updated.log = (swimClass.log.filter { $0.n != entry.n } + [entry]).sorted { $0.n < $1.n }
        return updated
    }

    public static func withDraft(_ swimClass: SwimClass, _ draft: Draft?) -> SwimClass {
        var updated = swimClass
        updated.draft = draft
        return updated
    }

    /// The class's draft when it is for day n.
    public static func draftFor(_ swimClass: SwimClass, _ n: Int) -> Draft? {
        guard let draft = swimClass.draft, draft.n == n else { return nil }
        return draft
    }

    // MARK: - validation (for files read from disk)

    /// Problems of one class record beyond its JSON shape (which `SwimClass(json:)`
    /// enforces): empty ids, lessons < 1, an unusable schedule, log entries outside
    /// 1..N or doubled, blocks of an unknown kind; with a curriculum, its stage and
    /// age group too.
    public static func validate(_ swimClass: SwimClass, curriculum: LoadedCurriculum? = nil) -> [Problem] {
        var problems: [Problem] = []
        let whereLabel = "class \(swimClass.id)"
        func shape(_ message: String) {
            problems.append(Problem(code: "class-shape", where: whereLabel, message: message))
        }
        for (key, value) in [("id", swimClass.id), ("name", swimClass.name), ("stageId", swimClass.stageId),
                             ("ageGroup", swimClass.ageGroup)] where value.isEmpty {
            shape("`\(key)` must be a non-empty string.")
        }
        if swimClass.lessons < 1 { shape("`lessons` must be an integer of at least 1.") }
        let days = orderedWeekdays(swimClass.schedule.weekdays)
        if days.isEmpty {
            shape("`schedule` needs `weekdays` (mon..sun) and `firstDate`.")
        } else if (try? Schedule.lessonDates(start: swimClass.schedule.firstDate, weekdays: days, count: 1)) == nil {
            shape("`schedule.firstDate` is not a date (YYYY-MM-DD).")
        }
        var seen: Set<Int> = []
        for entry in swimClass.log {
            if entry.n < 1 || entry.n > swimClass.lessons {
                problems.append(Problem(code: "class-log", where: whereLabel,
                                        message: "A log entry's `n` (\(entry.n)) is not a day of the class."))
            } else if seen.contains(entry.n) {
                problems.append(Problem(code: "class-log", where: whereLabel,
                                        message: "Day \(entry.n) has two log entries."))
            }
            seen.insert(entry.n)
            for block in entry.blocks where !Ids.blockKinds.contains(block.kind) {
                problems.append(Problem(code: "class-log", where: whereLabel,
                                        message: "Day \(entry.n) has a block without a kind or activityIds."))
            }
        }
        if let curriculum {
            if let stage = curriculum.stage(swimClass.stageId) {
                if !stringItems(stage["ageGroups"]).contains(swimClass.ageGroup) {
                    problems.append(Problem(
                        code: "class-age-group", where: whereLabel,
                        message: "Stage \(swimClass.stageId) has no age group '\(swimClass.ageGroup)'."))
                }
            } else {
                problems.append(Problem(code: "class-stage", where: whereLabel,
                                        message: "Stage '\(swimClass.stageId)' is not in the curriculum."))
            }
        }
        return problems
    }
}
