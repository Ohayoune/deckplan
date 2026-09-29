//
//  Problem.swift
//  DeckPlanCore
//
//  One validation finding (docs/CURRICULUM_FORMAT.md §5). A port of the `Problem`
//  namedtuple and the `errors`/`warnings`/`can_plan` helpers in `tools/core/curriculum.py`.
//

import Foundation

/// How serious a `Problem` is. An `.error` curriculum must not be planned on
/// (`Problem.canPlan`); a `.warning` is printed but does not block planning —
/// most often a reference into a stage that is not yet loaded (docs/SPEC.md §6.1).
public enum Severity: String, Sendable, Equatable, Codable {
    case error
    case warning
}

/// One finding from loading or validating a curriculum: a missing file, a
/// malformed field, a dangling id… `message` is a plain sentence naming what
/// is wrong (the id, the file, the number) — the rule "report outcomes
/// faithfully" applies to these as much as to test results.
///
/// The field is named `where` (backticked: `where` is a Swift keyword) to keep
/// the same vocabulary as `tools/core/curriculum.py`'s `Problem(code, severity,
/// where, message)`, since this type is ported line for line and the Python
/// tests, docs and error codes all speak of a problem's "where".
public struct Problem: Sendable, Equatable, CustomStringConvertible {
    /// A short, stable tag naming which check found this (docs/CURRICULUM_FORMAT.md
    /// §5): "file-missing", "id-duplicate", "steps", "equipment-unknown"… Stable
    /// across releases; UI and tests key off it, never off `message`'s wording.
    public let code: String
    public let severity: Severity
    /// What the problem is about, for grouping and display: "stage 1", "video
    /// vimeo:172429568", "local.json / activity our-game".
    public let `where`: String
    /// A plain sentence a person can act on.
    public let message: String

    public init(code: String, severity: Severity = .error, where location: String, message: String) {
        self.code = code
        self.severity = severity
        self.where = location
        self.message = message
    }

    public var description: String {
        "\(severity.rawValue) [\(code)] \(self.where): \(message)"
    }
}

extension Problem {

    /// Only the errors — the ones that block planning.
    public static func errors(_ problems: [Problem]) -> [Problem] {
        problems.filter { $0.severity == .error }
    }

    /// Only the warnings.
    public static func warnings(_ problems: [Problem]) -> [Problem] {
        problems.filter { $0.severity == .warning }
    }

    /// The planner refuses to run on a curriculum with any error (docs/SPEC.md
    /// §6.1, docs/TEST_CASES.md A10).
    public static func canPlan(_ problems: [Problem]) -> Bool {
        errors(problems).isEmpty
    }
}
