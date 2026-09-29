//
//  CurriculumBundleTests.swift
//  DeckPlanTests
//
//  M4's app-side smoke test (docs/BUILD_PLAN.md M4): the curriculum this build
//  carries loads and validates with no errors, so the app will plan lessons
//  (docs/SPEC.md §6.1).
//
//  Three honest skips, never a silent pass:
//   * `Resources/curriculum` absent — a build made without running
//     `tools/dev/sync_resources.py`, or a clone without the owner's private
//     transcription (D20).
//   * `DeckPlanCore` has no curriculum loader yet — M4's workers land in
//     separate commits; see `CoreWiring.swift`.
//   * the build carries the made-up samples (`sync_resources.py --demo`), for
//     the checks that hold only for the owner's curriculum;
//     `DemoCurriculumLoadingTests` covers that build.
//

import XCTest
@testable import DeckPlan

final class CurriculumBundleTests: XCTestCase {

    /// The app bundle under test is the host app, not the test bundle.
    private var appBundle: Bundle {
        Bundle(for: AppModel.self)
    }

    /// Skips when the curriculum could not have been read at all. Whether it
    /// was *validated* is checked per test, not skipped over.
    @MainActor
    private func makeLoadedModel() throws -> AppModel {
        let model = AppModel(bundle: appBundle)
        let status = model.curriculumStatus
        try XCTSkipUnless(
            status.bundleHasCurriculum,
            "This build carries no Resources/curriculum — run tools/dev/sync_resources.py and build again."
        )
        try XCTSkipUnless(
            status.loaderAvailable,
            "DeckPlanCore has no curriculum loader yet, so nothing was read (CoreWiring.swift)."
        )
        return model
    }

    /// Skips on a build carrying the made-up samples instead of the owner's
    /// curriculum — the same test `CoreCurriculumLoading` uses to load them.
    @MainActor
    private func skipOnTheDemoBuild(_ model: AppModel) throws {
        guard let directory = model.bundledCurriculumDirectory else { return }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        try XCTSkipIf(
            !files.contains("version.json")
                && files.contains { $0 == "sample.json" || $0.hasSuffix(".sample.json") },
            "This build carries the made-up samples (sync_resources.py --demo); DemoCurriculumLoadingTests covers it."
        )
    }

    // MARK: The bundle

    @MainActor
    func testBundleCarriesTheCurriculumDirectory() throws {
        let model = AppModel(bundle: appBundle)
        try XCTSkipUnless(
            model.bundledCurriculumDirectory != nil,
            "This build carries no Resources/curriculum — run tools/dev/sync_resources.py and build again."
        )
        try skipOnTheDemoBuild(model)
        let directory = try XCTUnwrap(model.bundledCurriculumDirectory)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        for expected in ["stages", "activities.json", "equipment.json",
                         "videos.json", "safety.json", "version.json", "local.json"] {
            XCTAssertTrue(files.contains(expected),
                          "The bundled curriculum is missing \(expected).")
        }
        let stages = try FileManager.default.contentsOfDirectory(
            atPath: directory.appendingPathComponent("stages").path)
        XCTAssertEqual(stages.filter { $0.hasSuffix(".json") }.count, 8,
                       "All eight stage files (A, B, 1–6) should be in the bundle.")
    }

    // MARK: Loading and validation

    /// The loader's own problems — unreadable files, a bad `version.json`, a
    /// stage that would not parse. Independent of the validator.
    @MainActor
    func testBundledCurriculumReadsWithNoLoadErrors() throws {
        let model = try makeLoadedModel()
        let status = model.curriculumStatus
        let loadErrors = status.errors.filter { $0.code != "validator-not-built" }
        let sentences = loadErrors.map { "\($0.code): \($0.message)" }.joined(separator: "\n")
        XCTAssertTrue(loadErrors.isEmpty,
                      "The bundled curriculum did not read cleanly:\n\(sentences)")
        XCTAssertNotNil(status.version, "version.json should give the curriculum a version.")
    }

    /// The whole point of §6.1: a validated, error-free curriculum plans.
    @MainActor
    func testBundledCurriculumValidatesWithNoErrors() throws {
        let model = try makeLoadedModel()
        let status = model.curriculumStatus
        try XCTSkipUnless(
            status.validated,
            "DeckPlanCore has no curriculum validator yet, so nothing was checked (CoreWiring.swift)."
        )
        let sentences = status.errors.map { "\($0.code): \($0.message)" }.joined(separator: "\n")
        XCTAssertTrue(status.errors.isEmpty,
                      "The bundled curriculum has validation errors:\n\(sentences)")
        XCTAssertTrue(status.canPlan, "With no errors the app should plan lessons (SPEC §6.1).")
    }

    /// An unchecked curriculum is never planned on, however clean it looks.
    @MainActor
    func testAnUnvalidatedCurriculumDoesNotPlan() throws {
        let model = try makeLoadedModel()
        let status = model.curriculumStatus
        if !status.validated {
            XCTAssertFalse(status.canPlan,
                           "Nothing has run the §5 checks, so the app must not plan.")
        }
    }

    @MainActor
    func testAllEightStagesAreLoaded() throws {
        let model = try makeLoadedModel()
        try skipOnTheDemoBuild(model)
        XCTAssertEqual(model.curriculumStatus.counts.loadedStageIds.sorted(),
                       CurriculumCounts.allStageIds.sorted(),
                       "M1 transcribed all eight stages; the bundle should carry them all.")
    }

    /// The counts Settings shows are real numbers off the loaded curriculum,
    /// not placeholders (docs/SPEC.md §5.8).
    @MainActor
    func testCountsAreReal() throws {
        let counts = try makeLoadedModel().curriculumStatus.counts
        XCTAssertGreaterThan(counts.skills, 0)
        XCTAssertGreaterThan(counts.steps, counts.skills)
        XCTAssertGreaterThan(counts.ymcaActivities, 0)
        XCTAssertGreaterThan(counts.equipmentItems, 0)
        XCTAssertGreaterThan(counts.safetyRules, 0)
    }


    // MARK: A build with no curriculum

    /// A clone without the owner's private transcription, or a build made
    /// without `tools/dev/sync_resources.py`, must say so and refuse to plan —
    /// never look valid (docs/SPEC.md §6.1, D20). The test bundle stands in for
    /// such a build: it carries no `curriculum` directory.
    @MainActor
    func testABuildWithNoCurriculumRefusesToPlanAndSaysWhy() {
        let model = AppModel(bundle: Bundle(for: CurriculumBundleTests.self))
        let status = model.curriculumStatus
        XCTAssertFalse(status.bundleHasCurriculum)
        XCTAssertFalse(status.canPlan, "With no curriculum the app must not plan lessons.")
        XCTAssertEqual(status.errors.count, 1)
        XCTAssertEqual(status.errors.first?.code, "bundle-curriculum-missing")
        XCTAssertTrue(status.headline.contains("sync_resources.py"),
                      "The headline should name the fix. Got: \(status.headline)")
    }
}
