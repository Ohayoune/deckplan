//
//  CurriculumService.swift
//  DeckPlan
//
//  The seam between the app and the Core's curriculum loader and validator
//  (docs/SPEC.md §6.1, docs/CURRICULUM_FORMAT.md §5).
//
//  The app never parses curriculum JSON itself: it asks a `CurriculumLoading`
//  for the bundle's `curriculum` directory and gets back what loaded plus every
//  problem the loader and the validator found. The protocol keeps `AppModel`
//  testable without a bundle, and keeps every call into `DeckPlanCore` in one
//  file (`CoreWiring.swift`).
//

import Foundation
import DeckPlanCore

// MARK: - Findings

/// One validation finding, mirroring the Python core's `Problem`
/// (`tools/core/curriculum.py`: code, severity, where, message).
///
/// `message` is a plain sentence; `location` is Python's `where` (the file or
/// the id the problem is about). The UI shows the sentence and keeps the code
/// as secondary text, so the owner can quote it (docs/SPEC.md §5.8).
struct CurriculumIssue: Identifiable, Hashable, Sendable {
    enum Severity: String, Sendable, Comparable {
        case error
        case warning

        /// Errors sort before warnings.
        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs == .error && rhs == .warning
        }
    }

    let code: String
    let severity: Severity
    let location: String
    let message: String

    var id: String { "\(severity.rawValue)|\(code)|\(location)|\(message)" }
}

/// What one load-and-validate pass produced.
///
/// Loading and validating are reported apart because they can be apart: a
/// curriculum that reads cleanly may still fail a check. Both must be true
/// before the app plans a lesson (docs/SPEC.md §6.1).
struct CurriculumLoadResult: Sendable {
    /// nil when the directory could not be read at all.
    var curriculum: LoadedCurriculum?
    /// Loader problems then validator problems, in the order they were found.
    var issues: [CurriculumIssue]
    /// False when the Core's loader is not in `DeckPlanCore` yet — the app is
    /// then in a known-incomplete state, not a valid one.
    var loaderAvailable: Bool
    /// False when the Core's validator has not run over `curriculum`, so an
    /// empty error list means "not checked", never "clean".
    var validated: Bool

}

extension CurriculumIssue {
    /// The Core's `Problem` as the app shows it. Same code, same severity,
    /// same sentence — the UI never rewords a finding.
    init(_ problem: Problem) {
        self.init(code: problem.code,
                  severity: problem.severity == .error ? .error : .warning,
                  location: problem.where,
                  message: problem.message)
    }
}

// MARK: - The seam

/// Loads and validates a curriculum directory. Pure with respect to the app:
/// it reads files and returns findings, and never touches the UI.
protocol CurriculumLoading: Sendable {
    /// - Parameters:
    ///   - directory: the bundle's `curriculum` directory (stages/, activities.json …).
    ///   - localPath: `local.json`, the owner's own additions (docs/SPEC.md §6.12).
    ///     The loader merges them after the YMCA entries, in catalog order.
    func loadAndValidate(directory: URL, localPath: URL?) -> CurriculumLoadResult
}
