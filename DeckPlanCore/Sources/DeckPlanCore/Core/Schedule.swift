//
//  Schedule.swift
//  DeckPlanCore
//
//  Lesson dates — the one pure date function v2 keeps from v1's
//  `tools/core/schedule.py` (`lesson_dates`; docs/REDESIGN.md §2 "Class",
//  docs/TEST_CASES.md C4 and the manifest's S* cases). Dates are ISO
//  "YYYY-MM-DD" strings in and out; the arithmetic is a proleptic Gregorian
//  day count, never `Calendar`, so a time zone can never move a lesson.
//

import Foundation

public enum ScheduleError: Error, Equatable, Sendable, CustomStringConvertible {
    /// `lessonDates` was given no recognized weekday (S8) — the Python's `ValueError`.
    case noWeekdays
    /// The start date is not "YYYY-MM-DD".
    case invalidDate(String)

    public var description: String {
        switch self {
        case .noWeekdays:
            return "lesson_dates needs at least one weekday (mon..sun) to meet on; none were given."
        case .invalidDate(let text):
            return "\(text.debugDescription) is not a date (YYYY-MM-DD)."
        }
    }
}

/// A calendar date with no time and no zone, as `datetime.date` reads
/// "YYYY-MM-DD": strictly four-digit year, two-digit month and day, in range.
public struct ISODate: Equatable, Comparable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), day >= 1, day <= ISODate.daysIn(month: month, year: year)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The date `dayNumber` days after 1970-01-01.
    public init(dayNumber: Int) {
        let z = dayNumber + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
        self.init(year: year, month: month, day: day)
    }

    static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Days since 1970-01-01 (negative before it).
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// Monday = 0 … Sunday = 6, as `date.weekday()`.
    public var weekdayIndex: Int {
        let z = dayNumber % 7
        return ((z < 0 ? z + 7 : z) + 3) % 7
    }

    public func adding(days: Int) -> ISODate {
        ISODate(dayNumber: dayNumber + days)
    }

    /// "YYYY-MM-DD".
    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: ISODate, rhs: ISODate) -> Bool {
        lhs.dayNumber < rhs.dayNumber
    }
}

public enum Schedule {

    /// `date.weekday()` order: Monday = 0.
    public static let weekdayNames: [String] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    /// The first `count` dates on or after `start` whose weekday is in `weekdays`
    /// and that are not in `skipDates` (`schedule.lesson_dates`; S1–S4, S8).
    ///
    /// Weekday names outside mon..sun are ignored; a set with nothing recognized
    /// throws `ScheduleError.noWeekdays`. `count` <= 0 gives `[]` before the start
    /// date is even looked at, as the Python does.
    public static func lessonDates(start: String?, weekdays: [String], count: Int,
                                   skipDates: Set<String> = []) throws -> [String] {
        let valid = Set(weekdays).intersection(weekdayNames)
        guard !valid.isEmpty else { throw ScheduleError.noWeekdays }
        if count <= 0 { return [] }
        guard let start, var current = ISODate(start) else {
            throw ScheduleError.invalidDate(start ?? "null")
        }
        var found: [String] = []
        while found.count < count {
            let iso = current.iso
            if valid.contains(weekdayNames[current.weekdayIndex]), !skipDates.contains(iso) {
                found.append(iso)
            }
            current = current.adding(days: 1)
        }
        return found
    }
}
