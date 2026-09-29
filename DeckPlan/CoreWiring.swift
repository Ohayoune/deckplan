//
//  CoreWiring.swift
//  DeckPlan
//
//  The one file that calls into `DeckPlanCore`. M4 was built by several
//  workers at once — the curriculum loader/validator and the `Store` actor
//  landed in the package separately from the app skeleton — so every call into
//  the Core goes through here and the app was built and proven against the
//  parts that existed at each point.
//
//  STATE (2026-09-12): `CurriculumLoader`, `CurriculumValidator` and `Store`
//  are wired. The curriculum is read and every CURRICULUM_FORMAT.md §5 check
//  runs at launch; Settings shows the result (docs/BUILD_PLAN.md M4).
//

import Foundation
import DeckPlanCore

/// Loads and validates through `DeckPlanCore` (docs/SPEC.md §6.1).
struct CoreCurriculumLoading: CurriculumLoading {
    func loadAndValidate(directory: URL, localPath: URL?) -> CurriculumLoadResult {
        // A build for anyone but the owner carries the made-up samples instead of the
        // curriculum files (tools/dev/sync_resources.py --demo). They load together,
        // one stage each, through the same validator.
        let files = FileManager.default
        let samples = ((try? files.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0 == "sample.json" || $0.hasSuffix(".sample.json") }
            .sorted()
            .map { directory.appendingPathComponent($0) }
        if !files.fileExists(atPath: directory.appendingPathComponent("version.json").path),
           !samples.isEmpty {
            let (demo, problems) = CurriculumValidator.check(sampleFiles: samples)
            return CurriculumLoadResult(curriculum: demo,
                                        issues: problems.map(CurriculumIssue.init),
                                        loaderAvailable: true,
                                        validated: true)
        }
        let loaded = CurriculumLoader.load(directory: directory, localPath: localPath)
        var issues = loaded.loadProblems.map(CurriculumIssue.init)

        issues += CurriculumValidator.validate(loaded).map(CurriculumIssue.init)

        return CurriculumLoadResult(curriculum: loaded,
                                    issues: issues,
                                    loaderAvailable: true,
                                    validated: true)
    }
}

extension AppModel {
    /// Opens the Core's `Store` over `root` (docs/SPEC.md §8). The directory
    /// itself is already created, with complete file protection, by the caller.
    ///
    /// Opening is a read: the manifest tells us whether this root has been
    /// written before and by which build. A store whose files are corrupt
    /// throws here rather than loading as empty (J1), and Settings shows it.
    static func attachStore(root: URL) async -> (Store, StoreStatus) {
        let store = Store(root: root)
        do {
            _ = try await store.loadManifest()
            return (store, .open(root: root))
        } catch {
            return (store, .failed("The store could not be read: \(error)"))
        }
    }
}
