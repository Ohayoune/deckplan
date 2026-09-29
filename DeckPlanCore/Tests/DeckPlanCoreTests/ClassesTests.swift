//
//  ClassesTests.swift
//  DeckPlanCoreTests
//
//  C1–C7: classes, their order, dates, day numbering and today by date (docs/TEST_CASES.md
//  group C) — the Swift half of `tests/test_classes.py` and
//  `tests/test_session_plan.py` — plus the manifest's S* schedule cases, carried
//  from v1, over `Schedule.lessonDates`.
//

import XCTest
@testable import DeckPlanCore

final class ClassesTests: XCTestCase {

    var curriculum: LoadedCurriculum!
    var swimClass: SwimClass!

    override func setUpWithError() throws {
        curriculum = Fixtures.sample()
        swimClass = try Fixtures.fixtureClass()
    }

    func minimal(id: String, order: Int, name: String) -> SwimClass {
        SwimClass(id: id, name: name, stageId: "1", ageGroup: "preschool", order: order,
                  schedule: ClassSchedule(weekdays: ["mon"], firstDate: "2026-09-14"))
    }

    func logOnly(_ days: [Int]) -> SwimClass {
        var copy = swimClass!
        copy.log = days.map { LogEntry(n: $0, date: "2026-01-01", blocks: []) }
        return copy
    }

    // MARK: - C1

    func test_C1_defaults() throws {
        let (created, problems) = Classes.newClass(curriculum, stageId: "1", weekdays: ["wed", "mon"],
                                                   firstDate: "2026-09-14", classId: "c1")
        XCTAssertEqual([], problems)
        let swimClass = try XCTUnwrap(created)
        XCTAssertEqual("Stage 1 · Mon Wed", swimClass.name)
        XCTAssertEqual(8, swimClass.lessons)
        XCTAssertEqual("preschool", swimClass.ageGroup)
        XCTAssertEqual(1, swimClass.order)
        XCTAssertEqual(ClassSchedule(weekdays: ["mon", "wed"], firstDate: "2026-09-14"), swimClass.schedule)
        XCTAssertEqual([], swimClass.log)
        XCTAssertNil(swimClass.draft)
        XCTAssertEqual("c1", swimClass.id)
        let (other, _) = Classes.newClass(
            curriculum, stageId: "1", weekdays: ["sat"], firstDate: "2026-09-19",
            classes: [minimal(id: "a", order: 1, name: "A"), minimal(id: "b", order: 4, name: "B")],
            name: "Saturdays", ageGroup: "schoolAge", lessons: 6)
        XCTAssertEqual(5, other?.order)
        XCTAssertEqual("Saturdays", other?.name)
        XCTAssertEqual("schoolAge", other?.ageGroup)
        XCTAssertEqual(6, other?.lessons)
        XCTAssertNotEqual(swimClass.id, other?.id)
        XCTAssertEqual(other?.id, other?.id.lowercased(), "a fresh id is a lower-case UUID, as Python writes it")
    }

    func test_C1_refusals() {
        let cases: [(code: String, stage: String, weekdays: [String], date: String, age: String?, lessons: Int)] = [
            ("class-stage", "9", ["mon"], "2026-09-14", nil, 8),
            ("class-age-group", "1", ["mon"], "2026-09-14", "infantToddler", 8),
            ("class-lessons", "1", ["mon"], "2026-09-14", nil, 0),
            ("class-weekdays", "1", ["someday"], "2026-09-14", nil, 8),
            ("class-first-date", "1", ["mon"], "14/09/2026", nil, 8),
        ]
        for item in cases {
            let (created, problems) = Classes.newClass(curriculum, stageId: item.stage, weekdays: item.weekdays,
                                                       firstDate: item.date, ageGroup: item.age,
                                                       lessons: item.lessons)
            XCTAssertNil(created, item.code)
            XCTAssertTrue(codes(problems).contains(item.code), "\(item.code): got \(codes(problems))")
        }
    }

    // MARK: - C2, C3

    func test_C2_list_order() {
        let classes = [minimal(id: "b", order: 2, name: "Beta"), minimal(id: "a", order: 1, name: "Zulu"),
                       minimal(id: "c", order: 2, name: "Alpha")]
        XCTAssertEqual(["a", "c", "b"], Classes.sorted(classes).map(\.id))
    }

    func test_C3_delete_removes_the_class_and_leaves_the_rest_untouched() throws {
        let keep = try Fixtures.fixtureClass()
        var gone = try Fixtures.fixtureClass()
        gone.id = "other"
        gone.log = [LogEntry(n: 1, date: "2026-01-01", blocks: [])]
        let result = Classes.delete([keep, gone], classId: "other")
        XCTAssertEqual([keep], result)
        XCTAssertNil(Classes.find(result, classId: "other"))
        XCTAssertEqual(try Fixtures.text("class.stage1.json"),
                       try Canonical.dumps(.object(["format": "classes/1", "items": .array(result.map(\.json))])) + "\n",
                       "nothing else in classes.json changes byte for byte")
    }

    // MARK: - C4, C6

    func test_C4_dates_follow_the_schedule() {
        let dates = Classes.lessonDates(swimClass)
        XCTAssertEqual(8, dates.count)
        XCTAssertEqual("2026-09-14", dates[0])
        XCTAssertEqual("2026-09-28", Classes.lessonDate(swimClass, 5))
        XCTAssertNil(Classes.lessonDate(swimClass, 9))
    }

    func test_C4_the_manifests_schedule_cases() throws {
        let cases = try Repo.json("examples/manifest.json")["cases"]?.arrayValue ?? []
        var checked = 0
        for item in cases where item["id"]?.stringValue?.hasPrefix("S") == true {
            let inputs = try XCTUnwrap(item["inputs"])
            let dates = try Schedule.lessonDates(
                start: inputs["startDate"]?.stringValue, weekdays: stringItems(inputs["weekdays"]),
                count: inputs["lessonCount"]?.intValue ?? 0, skipDates: Set(stringItems(inputs["skipDates"])))
            XCTAssertEqual(stringItems(item["expected"]?["dates"]), dates, item["id"]?.stringValue ?? "?")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 8, "the manifest carries v1's S* cases")
        XCTAssertThrowsError(try Schedule.lessonDates(start: "2026-09-14", weekdays: ["someday"], count: 8))
        XCTAssertThrowsError(try Schedule.lessonDates(start: "2026-9-14", weekdays: ["mon"], count: 1))
        XCTAssertEqual([], try Schedule.lessonDates(start: "not-a-date", weekdays: ["mon"], count: 0),
                       "count 0 returns nothing before the date is looked at, as the Python does")
        XCTAssertEqual(0, ISODate("2026-09-14")?.weekdayIndex, "2026-09-14 is a Monday")
        XCTAssertNil(ISODate("2026-02-29"))
        XCTAssertEqual("2024-02-29", ISODate("2024-02-28")?.adding(days: 1).iso)
    }

    func test_C6_next_day() {
        XCTAssertEqual(4, Classes.lastDayDone(swimClass))
        XCTAssertEqual(5, Classes.nextDay(swimClass))
        XCTAssertFalse(Classes.isComplete(swimClass))
        let empty = logOnly([])
        XCTAssertEqual(0, Classes.lastDayDone(empty))
        XCTAssertEqual(1, Classes.nextDay(empty))
        let gaps = logOnly([1, 2, 5])
        XCTAssertEqual(5, Classes.lastDayDone(gaps))
        XCTAssertEqual(6, Classes.nextDay(gaps))
        let full = logOnly(Array(1...8))
        XCTAssertNil(Classes.nextDay(full))
        XCTAssertTrue(Classes.isComplete(full))
    }

    func test_done_set_is_every_saved_activity() {
        let done = Classes.doneSet(swimClass)
        XCTAssertEqual(18, done.count)  // four days, one activity per block, snowflake-welcome twice (D10)
        XCTAssertTrue(done.contains("otter-bubbles"))
        XCTAssertTrue(done.contains("tugboat-treasure-hunt"))
        XCTAssertFalse(done.contains("sunflower-countdown"))
        XCTAssertEqual([], Classes.doneSet(logOnly([])))
    }

    // MARK: - C7

    func test_C7_day_on_today_next_and_missed_take_the_date_as_an_argument() throws {
        let ref = { (n: Int, date: String?) in Classes.LessonRef(classId: "c-stage1-mw", n: n, date: date) }
        XCTAssertEqual(5, Classes.dayOn(swimClass, date: "2026-09-28"))
        XCTAssertEqual(3, Classes.dayOn(swimClass, date: "2026-09-21"))  // saved days count too
        XCTAssertNil(Classes.dayOn(swimClass, date: "2026-09-29"))
        XCTAssertEqual([ref(5, nil)], Classes.today([swimClass], date: "2026-09-28"))
        XCTAssertEqual([], Classes.today([swimClass], date: "2026-09-29"))
        XCTAssertEqual(ref(6, "2026-09-30"), Classes.nextLesson([swimClass], date: "2026-09-29"))
        XCTAssertEqual(ref(5, "2026-09-28"), Classes.nextLesson([swimClass], date: "2026-09-28"))
        XCTAssertNil(Classes.nextLesson([swimClass], date: "2026-10-08"))
        XCTAssertEqual([], Classes.missed([swimClass], date: "2026-09-28"))
        XCTAssertEqual([ref(5, "2026-09-28")], Classes.missed([swimClass], date: "2026-09-29"))
        XCTAssertEqual([5, 6, 7, 8], Classes.missed([swimClass], date: "2026-10-08").map(\.n))
        // the manifest's facts, as JSON
        let cases = try XCTUnwrap(try Fixtures.manifestCase("C7.today")["expected"]?["cases"]?.arrayValue)
        XCTAssertEqual(4, cases.count)
        for testCase in cases {
            let date = try XCTUnwrap(testCase["date"]?.stringValue)
            XCTAssertEqual(testCase["today"], .array(Classes.today([swimClass], date: date).map(\.json)), date)
            XCTAssertEqual(testCase["next"], Classes.nextLesson([swimClass], date: date)?.json ?? .null, date)
            XCTAssertEqual(testCase["missed"], .array(Classes.missed([swimClass], date: date).map(\.json)), date)
        }
        // several classes: class order, then date order; a saved past day is not missed
        var tueThu = swimClass!
        tueThu.id = "c-tt"
        tueThu.name = "Stage 1 · Tue Thu"
        tueThu.order = 2
        tueThu.schedule = ClassSchedule(weekdays: ["tue", "thu"], firstDate: "2026-09-15")
        tueThu.log = []
        var first = swimClass!
        first.id = "c-first"
        first.name = "Earlier"
        first.order = 0
        first.log = []
        let classes = [tueThu, swimClass!, first]
        XCTAssertEqual([Classes.LessonRef(classId: "c-first", n: 5), ref(5, nil)], Classes.today(classes, date: "2026-09-28"))
        XCTAssertEqual(Classes.LessonRef(classId: "c-first", n: 5, date: "2026-09-28"), Classes.nextLesson(classes, date: "2026-09-27"))
        XCTAssertEqual(Classes.LessonRef(classId: "c-tt", n: 1, date: "2026-09-15"), Classes.nextLesson(classes, date: "2026-09-15"))
        let missed = Classes.missed(classes, date: "2026-09-17").map { "\($0.classId) \($0.n) \($0.date ?? "")" }
        XCTAssertEqual(["c-first 1 2026-09-14", "c-tt 1 2026-09-15", "c-first 2 2026-09-16"], missed)
        XCTAssertEqual([], Classes.missed([], date: "2026-09-17"))
        XCTAssertNil(Classes.nextLesson([], date: "2026-09-17"))
    }

    func test_log_writes_replace_by_n_and_keep_the_log_sorted() {
        let entry = LogEntry(n: 2, date: "2026-09-16", blocks: [LogBlock(kind: "welcome", activityIds: ["iceberg-wave"])])
        let updated = Classes.withLogEntry(swimClass, entry)
        XCTAssertEqual([1, 2, 3, 4], updated.log.map(\.n))
        XCTAssertEqual(entry, Classes.logEntry(updated, 2))
        XCTAssertEqual(4, swimClass.log.count)  // the original is untouched
        var later = Classes.withLogEntry(logOnly([]), LogEntry(n: 3, date: "x", blocks: []))
        later = Classes.withLogEntry(later, LogEntry(n: 1, date: "x", blocks: []))
        XCTAssertEqual([1, 3], later.log.map(\.n))
    }

    func test_validate_accepts_the_fixture_and_names_shape_problems() {
        XCTAssertEqual([], Classes.validate(swimClass, curriculum: curriculum))
        var broken = swimClass!
        broken.lessons = 0
        broken.schedule = ClassSchedule(weekdays: [], firstDate: "2026-09-14")
        broken.log.append(LogEntry(n: 1, date: "x", blocks: []))
        let found = codes(Classes.validate(broken))
        XCTAssertTrue(found.contains("class-shape"), "\(found)")
        XCTAssertTrue(found.contains("class-log"), "\(found)")
        var wrongAge = swimClass!
        wrongAge.ageGroup = "infantToddler"
        XCTAssertEqual(["class-age-group"], codes(Classes.validate(wrongAge, curriculum: curriculum)))
    }

    // MARK: - C5: the N-lesson mapping

    func test_C5_stage1_mappings() {
        let expected: [Int: [Int?]] = [
            8: [1, 2, 3, 4, 5, 6, 7, 8],
            7: [1, 2, 3, 4, 5, 7, 8],
            6: [1, 2, 3, 4, 7, 8],
            5: [1, 2, 4, 7, 8],
            4: [1, 2, 4, 8],
            10: [1, 2, 3, 4, 5, 6, 7, nil, nil, 8],
        ]
        for (n, mapping) in expected {
            XCTAssertEqual(mapping, SessionPlan.guideLessonMapping(curriculum, stageId: "1", lessons: n), "N = \(n)")
        }
    }

    func test_C5_guide_lesson_for_day() throws {
        XCTAssertEqual(7, try SessionPlan.guideLessonForDay(curriculum, stageId: "1", lessons: 6, day: 5))
        XCTAssertNil(try SessionPlan.guideLessonForDay(curriculum, stageId: "1", lessons: 10, day: 8))
        XCTAssertEqual(8, try SessionPlan.guideLessonForDay(curriculum, stageId: "1", lessons: 10, day: 10))
        for bad in [0, 9] {
            XCTAssertThrowsError(try SessionPlan.guideLessonForDay(curriculum, stageId: "1", lessons: 8, day: bad)) {
                XCTAssertEqual(DayOutOfRange(day: bad, lessons: 8), $0 as? DayOutOfRange)
            }
        }
    }
}
