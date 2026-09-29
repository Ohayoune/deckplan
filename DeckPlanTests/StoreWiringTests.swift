//
//  StoreWiringTests.swift
//  DeckPlanTests
//
//  The app's wiring of the Core over a real store (docs/TEST_CASES.md S1–S2,
//  and the unit half of the M cases): an `AppModel` over a temporary store
//  root and the Stage 1 sample curriculum (`examples/curriculum.stage1.sample.json`,
//  bundled into this test target) creates a class, plans, lets the days save
//  themselves (a fixed calendar day stands in for the clock), shuffles,
//  deletes, toggles the pool, and backs up and restores. Every write is
//  proven on disk, with complete file protection (D21).
//

import XCTest
import DeckPlanCore
@testable import DeckPlan

/// Loads the Stage 1 sample instead of the bundle's curriculum directory, so
/// these tests do not depend on the owner's private copy.
private struct SampleCurriculumLoading: CurriculumLoading {
    let sample: URL

    func loadAndValidate(directory: URL, localPath: URL?) -> CurriculumLoadResult {
        let (loaded, problems) = CurriculumValidator.check(sampleFile: sample)
        return CurriculumLoadResult(curriculum: loaded,
                                    issues: problems.map(CurriculumIssue.init),
                                    loaderAvailable: true,
                                    validated: true)
    }
}

/// The build for anyone but the owner: a bundled curriculum folder holding only
/// made-up samples (tools/dev/sync_resources.py --demo) loads through the app's
/// own loader, one stage per sample, so the app runs on made-up content.
final class DemoCurriculumLoadingTests: XCTestCase {

    func testAFolderHoldingOnlyTheSampleLoadsAsOneStage() throws {
        let files = FileManager.default
        let tests = Bundle(for: DemoCurriculumLoadingTests.self)
        let sample = try XCTUnwrap(tests.url(forResource: "curriculum.stage1.sample", withExtension: "json"),
                                   "the Stage 1 sample is not in the test bundle")
        let folder = files.temporaryDirectory.appendingPathComponent("deckplan-demo-\(UUID().uuidString)",
                                                                    isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        try files.copyItem(at: sample, to: folder.appendingPathComponent("sample.json"))

        let result = CoreCurriculumLoading().loadAndValidate(directory: folder, localPath: nil)
        XCTAssertEqual(["1"], result.curriculum?.loadedStageIds)
        XCTAssertEqual([], result.issues.filter { $0.severity == .error }.map(\.message))
        XCTAssertTrue(result.validated)
    }

    /// What `sync_resources.py --demo` bundles now: the three made-up samples,
    /// so the Finder's and the class form's stage pickers have stages to switch to.
    func testAFolderHoldingTheThreeSamplesLoadsAsThreeStages() throws {
        let files = FileManager.default
        let tests = Bundle(for: DemoCurriculumLoadingTests.self)
        let folder = files.temporaryDirectory.appendingPathComponent("deckplan-demo-\(UUID().uuidString)",
                                                                    isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        for stageId in ["1", "2", "4"] {
            let name = "curriculum.stage\(stageId).sample"
            let sample = try XCTUnwrap(tests.url(forResource: name, withExtension: "json"),
                                       "the Stage \(stageId) sample is not in the test bundle")
            try files.copyItem(at: sample, to: folder.appendingPathComponent("\(name).json"))
        }

        let result = CoreCurriculumLoading().loadAndValidate(directory: folder, localPath: nil)
        XCTAssertEqual(["1", "2", "4"], result.curriculum?.loadedStageIds)
        XCTAssertEqual([], result.issues.filter { $0.severity == .error }.map(\.message))
        XCTAssertTrue(result.validated)
    }
}

@MainActor
final class StoreWiringTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("deckplan-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A model over the sample curriculum and a fresh temporary store, on a
    /// fixed calendar day: 2026-09-13 is the Sunday before `stage1Form()`'s
    /// first lesson, so no day has saved itself yet.
    private func makeModel(today: String = "2026-09-13") async throws -> AppModel {
        let tests = Bundle(for: StoreWiringTests.self)
        let sample = try XCTUnwrap(tests.url(forResource: "curriculum.stage1.sample", withExtension: "json"),
                                   "the Stage 1 sample is not in the test bundle")
        // The app bundle's curriculum directory only gates the load; the loader
        // above reads the sample whatever the directory holds.
        let app = Bundle(for: AppModel.self)
        try XCTSkipUnless(app.url(forResource: "curriculum", withExtension: nil) != nil,
                          "This build carries no Resources/curriculum — run tools/dev/sync_resources.py and build again.")
        let model = AppModel(bundle: app, loader: SampleCurriculumLoading(sample: sample), storeRoot: root)
        model.today = { today }
        XCTAssertTrue(model.curriculumStatus.canPlan, model.curriculumStatus.headline)
        await model.openStore()
        XCTAssertTrue(model.isReady, model.storeStatus.sentence)
        return model
    }

    private func stage1Form() -> ClassForm {
        var form = ClassForm(stageId: "1", ageGroup: "preschool", firstDate: "2026-09-14")
        form.weekdays = ["mon", "wed"]
        return form
    }

    // MARK: M1 — create and plan; the day saves itself on its date

    func testCreateClassPlansDayOneAndTheDaySavesItselfOnItsDate() async throws {
        let model = try await makeModel()
        let problems = await model.createClass(stage1Form())
        XCTAssertEqual([], problems.map(\.message))
        let swimClass = try XCTUnwrap(model.classes.first)
        XCTAssertEqual("Stage 1 · Mon Wed", swimClass.name)
        XCTAssertEqual(8, swimClass.lessons)
        XCTAssertEqual(1, model.todayDay(swimClass))

        let plan = try XCTUnwrap(model.plan(classId: swimClass.id, n: 1))
        XCTAssertEqual(["welcome", "warmUp", "review", "introduce", "topic", "wrapUp"], plan.blocks.map(\.kind))
        XCTAssertFalse(plan.saved, "a day ahead is not saved")

        // Its date comes (DECISIONS_LOG 2026-09-13, "A day saves itself").
        model.today = { "2026-09-14" }
        let written = await model.saveDaysThroughToday()
        XCTAssertTrue(written)
        let saved = try XCTUnwrap(model.swimClass(swimClass.id))
        XCTAssertEqual(2, model.todayDay(saved))
        XCTAssertEqual("2026-09-14", saved.log.first?.date)
        XCTAssertEqual(plan.blocks.map(\.activityIds), saved.log.first?.blocks.map(\.activityIds),
                       "the day saves what it showed")

        // On disk, in the store's own shape (S1).
        let store = Store(root: root)
        let reread = try await store.loadClasses()
        XCTAssertEqual(1, reread.count)
        XCTAssertEqual(1, reread.first?.log.count)
    }

    // MARK: M2 — shuffle on any day; a saved day saves each change at once

    func testShuffleWorksOnEveryDayAndASavedDaySavesEachChangeAtOnce() async throws {
        let model = try await makeModel()
        _ = await model.createClass(stage1Form())
        let classId = try XCTUnwrap(model.classes.first?.id)
        let before = try XCTUnwrap(model.plan(classId: classId, n: 1))
        let warmUp = try XCTUnwrap(before.blocks.first { $0.kind == "warmUp" })
        XCTAssertFalse(warmUp.activityIds.isEmpty)

        let first = await model.shuffle(classId: classId, n: 1, kind: "warmUp")
        XCTAssertTrue(first.ok, first.message ?? "")
        let second = await model.shuffle(classId: classId, n: 1, kind: "warmUp")
        XCTAssertTrue(second.ok, second.message ?? "")
        let after = try XCTUnwrap(model.plan(classId: classId, n: 1))
        XCTAssertTrue(after.draft, "a day ahead keeps its changes in the draft")
        XCTAssertEqual(2, model.swimClass(classId)?.draft?.shuffleCounts["warmUp"])

        model.today = { "2026-09-14" }
        await model.saveDaysThroughToday()
        func loggedWarmUp() throws -> [String] {
            try XCTUnwrap(model.swimClass(classId)?.log.first?.blocks.first { $0.kind == "warmUp" }).activityIds
        }
        XCTAssertEqual(after.blocks.first { $0.kind == "warmUp" }?.activityIds, try loggedWarmUp(),
                       "the day saves its draft")
        XCTAssertNil(model.swimClass(classId)?.draft)

        let shown = try loggedWarmUp()
        let third = await model.shuffle(classId: classId, n: 1, kind: "warmUp")
        XCTAssertTrue(third.ok, third.message ?? "")
        XCTAssertNil(model.swimClass(classId)?.draft, "a saved day's change is saved at once")
        XCTAssertNotEqual(shown, try loggedWarmUp())
        let reread = try await Store(root: root).loadClasses()
        XCTAssertEqual(try loggedWarmUp(), reread.first?.log.first?.blocks.first { $0.kind == "warmUp" }?.activityIds)
    }

    // A first lesson already past: those days save themselves when the class
    // is created or its schedule moves; a change to one is saved at once.

    func testDaysAlreadyPastSaveThemselvesWhenTheClassIsCreatedOrMoved() async throws {
        let model = try await makeModel(today: "2026-09-17")
        _ = await model.createClass(stage1Form())  // Mon/Wed from 2026-09-14: Sep 14 and 16 are past
        let swimClass = try XCTUnwrap(model.classes.first)
        XCTAssertEqual([1, 2], swimClass.log.map(\.n))
        XCTAssertEqual(3, model.todayDay(swimClass))
        XCTAssertEqual(.done, model.dayStatus(swimClass, n: 2))

        let plan = try XCTUnwrap(model.plan(classId: swimClass.id, n: 1))
        let block = try XCTUnwrap(model.visibleBlocks(plan).first { !$0.activityIds.isEmpty })
        let removed = await model.removeActivity(classId: swimClass.id, n: 1, kind: block.kind,
                                                 activityId: block.activityIds[0])
        XCTAssertTrue(removed.ok, removed.message ?? "")
        let edited = try XCTUnwrap(model.swimClass(swimClass.id))
        XCTAssertNil(edited.draft)
        let logged = try XCTUnwrap(Classes.logEntry(edited, 1)?.blocks.first { $0.kind == block.kind })
        XCTAssertFalse(logged.activityIds.contains(block.activityIds[0]))

        var form = ClassForm(edited)
        form.firstDate = "2026-09-07"  // a week earlier: days 1–4 are Sep 7, 9, 14, 16
        let problems = await model.updateClass(swimClass.id, with: form)
        XCTAssertEqual([], problems.map(\.code))
        XCTAssertEqual([1, 2, 3, 4], model.swimClass(swimClass.id)?.log.map(\.n))
    }

    // MARK: M3 — the pool filter is one filter

    func testTurningEquipmentOffHidesItsActivitiesInPlanFinderAndBrowse() async throws {
        let model = try await makeModel()
        let curriculum = try XCTUnwrap(model.planningCurriculum)
        // An activity whose `equipment` is one requirement group of one *profile*
        // item (CURRICULUM_FORMAT §3: groups are lists of alternatives; P6: only a
        // profile item can hide — a prop is always on), from the sample.
        let profile = Set(Activities.profileItems(curriculum))
        XCTAssertEqual(5, profile.count)
        XCTAssertFalse(profile.contains("goggles"))
        func onlyItem(_ activity: JSONValue) -> String? {
            guard let groups = activity["equipment"]?.arrayValue, groups.count == 1,
                  let group = groups.first?.arrayValue, group.count == 1,
                  let item = group.first?.stringValue, profile.contains(item) else { return nil }
            return item
        }
        let single = try XCTUnwrap(curriculum.activities.first { onlyItem($0) != nil },
                                   "the sample has no single-profile-item activity")
        let activityId = try XCTUnwrap(single["id"]?.stringValue)
        let itemId = try XCTUnwrap(onlyItem(single))
        XCTAssertEqual(Set(profile), Set(model.pool.equipment.keys), "the profile carries one key per profile item")

        func visibleInBrowse() -> Bool {
            model.browse(stageId: "1", ageTag: nil)?.groups.contains { $0.activityIds.contains(activityId) } ?? false
        }
        XCTAssertTrue(visibleInBrowse(), "\(activityId) should show with everything on")

        var pool = model.pool
        pool.equipment[itemId] = false
        let turnedOff = await model.commit(pool: pool)
        XCTAssertTrue(turnedOff)
        XCTAssertFalse(visibleInBrowse(), "\(activityId) should hide with \(itemId) off")
        let store = Store(root: root)
        let saved = try await store.loadPool()
        XCTAssertEqual(false, saved?.equipment[itemId])

        pool.equipment[itemId] = true
        let turnedOn = await model.commit(pool: pool)
        XCTAssertTrue(turnedOn)
        XCTAssertTrue(visibleInBrowse())

        // A prop's key hides nothing and is dropped by the write (P6, M10).
        let straws = "submarine-peekaboo"  // [["straws"]]
        func strawsInBrowse() -> Bool {
            model.browse(stageId: "1", ageTag: nil)?.groups.contains { $0.activityIds.contains(straws) } ?? false
        }
        XCTAssertTrue(strawsInBrowse())
        pool.equipment["straws"] = false
        pool.equipment["goggles"] = false
        let propsOff = await model.commit(pool: pool)
        XCTAssertTrue(propsOff)
        XCTAssertTrue(strawsInBrowse())
        let written = try await store.loadPool()
        XCTAssertNil(written?.equipment["straws"])
        XCTAssertNil(written?.equipment["goggles"])
        XCTAssertNil(model.pool.equipment["goggles"])
    }

    // MARK: M8 — today by date, M9 — search and the remembered stage (the Core half)

    func testTodayAndNextTakeTheDateAndSearchFindsByName() async throws {
        let model = try await makeModel()
        _ = await model.createClass(stage1Form())  // Mon/Wed from 2026-09-14
        let classId = try XCTUnwrap(model.classes.first?.id)
        XCTAssertEqual([Classes.LessonRef(classId: classId, n: 1)], model.todayLessons(on: "2026-09-14"))
        XCTAssertEqual([], model.todayLessons(on: "2026-09-15"))
        XCTAssertEqual(Classes.LessonRef(classId: classId, n: 2, date: "2026-09-16"), model.nextLesson(on: "2026-09-15"))
        model.today = { "2026-09-15" }
        await model.saveDaysThroughToday()
        XCTAssertEqual([1], model.swimClass(classId)?.log.map(\.n), "a passed day is never missed: it saved itself")
        XCTAssertEqual([Classes.LessonRef(classId: classId, n: 1)], model.todayLessons(on: "2026-09-14"), "a saved day is still today's")
        XCTAssertNil(model.nextLesson(on: "2026-12-01"))

        let glide = try XCTUnwrap(model.search(stageId: "1", text: "GLIDE", ageTag: nil))
        XCTAssertEqual(["1.front-glide", "1.back-glide"], glide.groups.map { $0.skillId })
        XCTAssertEqual([], try XCTUnwrap(model.search(stageId: "1", text: "  ", ageTag: nil)).groups)

        XCTAssertEqual("1", model.initialFinderStage(on: "2026-09-14"))
        await model.rememberFinderStage("1")
        let onDisk = try await Store(root: root).loadSettings()
        XCTAssertEqual("1", onDisk?.finderStageId)
        XCTAssertEqual(false, onDisk?.showWelcome)
    }

    // MARK: M8 — the day list's marks; a class row says each fact once

    func testTheDayListMarksDoneEditedAndNextAndARowSaysEachFactOnce() async throws {
        let model = try await makeModel()
        _ = await model.createClass(stage1Form())  // Mon/Wed from 2026-09-14: days 1–3 are Sep 14, 16, 21
        let classId = try XCTUnwrap(model.classes.first?.id)
        var swimClass = try XCTUnwrap(model.swimClass(classId))
        XCTAssertEqual(.next, model.dayStatus(swimClass, n: 1))
        XCTAssertEqual(.later, model.dayStatus(swimClass, n: 2))

        model.today = { "2026-09-17" }
        await model.saveDaysThroughToday()
        swimClass = try XCTUnwrap(model.swimClass(classId))
        XCTAssertEqual(.done, model.dayStatus(swimClass, n: 1))
        XCTAssertEqual(.done, model.dayStatus(swimClass, n: 2), "a passed day is done on its own")
        XCTAssertEqual(.next, model.dayStatus(swimClass, n: 3))

        let plan = try XCTUnwrap(model.plan(classId: classId, n: 3))
        let block = try XCTUnwrap(plan.blocks.first { !$0.activityIds.isEmpty })
        let removed = await model.removeActivity(classId: classId, n: 3, kind: block.kind,
                                                 activityId: block.activityIds[0])
        XCTAssertTrue(removed.ok, removed.message ?? "")
        swimClass = try XCTUnwrap(model.swimClass(classId))
        XCTAssertEqual(.edited, model.dayStatus(swimClass, n: 3))

        XCTAssertTrue(model.usesDefaultName(swimClass))
        let summary = model.classSummary(swimClass).joined(separator: "\n")
        XCTAssertFalse(summary.contains("Stage 1"), summary)
        XCTAssertFalse(summary.contains(Display.weekdays(["mon", "wed"])), summary)
        XCTAssertTrue(summary.contains(Display.ageGroup("preschool")), summary)
        XCTAssertTrue(summary.contains(Display.doneOf(2, 8)), summary)

        var form = ClassForm(swimClass)
        form.name = "Tuesday tots"
        let problems = await model.updateClass(classId, with: form)
        XCTAssertEqual([], problems.map(\.code))
        let renamed = try XCTUnwrap(model.swimClass(classId))
        XCTAssertFalse(model.usesDefaultName(renamed))
        let named = model.classSummary(renamed).joined(separator: "\n")
        XCTAssertTrue(named.contains("Stage 1"), named)
        XCTAssertTrue(named.contains(Display.weekdays(["mon", "wed"])), named)
    }

    // MARK: M4 — finder pages

    func testFinderGivesThreeThenThreeOthersAndADetail() async throws {
        let model = try await makeModel()
        // Stage → skill → activities (DECISIONS_LOG 2026-09-12): the finder
        // opens on the stage's first skill, and never narrows by step.
        XCTAssertEqual("1.submerge", model.finderSkill(stageId: "1"))
        XCTAssertEqual("1.front-glide", model.finderSkill(stageId: "1", preferred: "1.front-glide"))
        XCTAssertEqual("1.submerge", model.finderSkill(stageId: "1", preferred: "2.not-in-stage-1"))

        let page1 = try XCTUnwrap(model.find(stageId: "1", skillId: "1.submerge", ageTag: nil, pageNumber: 1))
        XCTAssertEqual(3, page1.activityIds.count)
        XCTAssertNil(page1.step)
        let page2 = try XCTUnwrap(model.find(stageId: "1", skillId: "1.submerge", ageTag: nil, pageNumber: 2))
        XCTAssertEqual(3, page2.activityIds.count)
        XCTAssertTrue(Set(page1.activityIds).isDisjoint(with: page2.activityIds))
        // Same inputs, same page (determinism).
        XCTAssertEqual(page1, model.find(stageId: "1", skillId: "1.submerge", ageTag: nil, pageNumber: 1))

        let glide = try XCTUnwrap(model.find(stageId: "1", skillId: "1.front-glide", ageTag: nil, pageNumber: 1))
        XCTAssertEqual("1.front-glide", glide.skillId)
        let detail = try XCTUnwrap(model.activityDetail(glide.activityIds[0], skillId: "1.front-glide"))
        XCTAssertFalse(detail.name.isEmpty)
    }

    // MARK: Settings — Welcome, Topic and Review first are display toggles, off by default

    func testWelcomeIsHiddenByDefaultButStillSavedAndTheToggleIsWritten() async throws {
        let model = try await makeModel()
        XCTAssertFalse(model.settings.showWelcome)
        _ = await model.createClass(stage1Form())
        let classId = try XCTUnwrap(model.classes.first?.id)
        let plan = try XCTUnwrap(model.plan(classId: classId, n: 1))
        XCTAssertTrue(plan.blocks.contains { $0.kind == "welcome" }, "the plan keeps the Welcome block")
        XCTAssertEqual(["warmUp", "introduce", "review", "wrapUp"], model.visibleBlocks(plan).map(\.kind))

        // Saved with Welcome hidden, the log still holds the guide's Welcome.
        model.today = { "2026-09-14" }
        let saved = await model.saveDaysThroughToday()
        XCTAssertTrue(saved)
        let entry = try XCTUnwrap(model.swimClass(classId)?.log.first)
        XCTAssertTrue(entry.blocks.contains { $0.kind == "welcome" })

        var settings = model.settings
        settings.showWelcome = true
        let written = await model.commit(settings: settings)
        XCTAssertTrue(written)
        let after = try XCTUnwrap(model.plan(classId: classId, n: 1))
        XCTAssertEqual("welcome", model.visibleBlocks(after).first?.kind)
        let onDisk = try await Store(root: root).loadSettings()
        XCTAssertEqual(true, onDisk?.showWelcome)
        XCTAssertEqual(false, onDisk?.showTopic)
    }

    func testTopicIsHiddenByDefaultAndTheToggleIsWrittenAndReadBack() async throws {
        // A settings file written before the toggles existed reads as both off.
        try await Store(root: root).save(settings: Settings(extra: ["theme": "light"]))
        let model = try await makeModel()
        XCTAssertFalse(model.settings.showTopic)
        _ = await model.createClass(stage1Form())
        let classId = try XCTUnwrap(model.classes.first?.id)
        let plan = try XCTUnwrap(model.plan(classId: classId, n: 1))
        XCTAssertTrue(plan.blocks.contains { $0.kind == "topic" }, "the plan keeps the Topic block")
        XCTAssertFalse(model.visibleBlocks(plan).contains { $0.kind == "topic" })

        var settings = model.settings
        settings.showTopic = true
        let written = await model.commit(settings: settings)
        XCTAssertTrue(written)
        XCTAssertTrue(model.visibleBlocks(plan).contains { $0.kind == "topic" })
        XCTAssertFalse(model.visibleBlocks(plan).contains { $0.kind == "welcome" })

        // A fresh model over the same store reads the toggle back, other fields kept.
        let reopened = try await makeModel()
        XCTAssertTrue(reopened.settings.showTopic)
        XCTAssertEqual(["theme": "light"], reopened.settings.extra)
    }

    func testIntroduceDrawsBeforeReviewUntilTheToggleAsksForTheGuidesOrder() async throws {
        let model = try await makeModel()
        XCTAssertFalse(model.settings.reviewFirst)
        _ = await model.createClass(stage1Form())
        let classId = try XCTUnwrap(model.classes.first?.id)
        let plan = try XCTUnwrap(model.plan(classId: classId, n: 1))
        XCTAssertEqual(["welcome", "warmUp", "review", "introduce", "topic", "wrapUp"], plan.blocks.map(\.kind),
                       "the plan keeps the guide's order")
        XCTAssertEqual(["warmUp", "introduce", "review", "wrapUp"], model.visibleBlocks(plan).map(\.kind))

        var settings = model.settings
        settings.reviewFirst = true
        let written = await model.commit(settings: settings)
        XCTAssertTrue(written)
        XCTAssertEqual(["warmUp", "review", "introduce", "wrapUp"], model.visibleBlocks(plan).map(\.kind))
        let onDisk = try await Store(root: root).loadSettings()
        XCTAssertEqual(true, onDisk?.reviewFirst)
    }

    // MARK: M5 — delete

    func testDeletingAClassRemovesItsLogAndKeepsTheOthersOrder() async throws {
        let model = try await makeModel()
        _ = await model.createClass(stage1Form())
        var second = stage1Form()
        second.name = "Second"
        second.weekdays = ["tue"]
        _ = await model.createClass(second)
        XCTAssertEqual([1, 2], model.classes.map(\.order))
        let firstId = try XCTUnwrap(model.classes.first?.id)
        model.today = { "2026-09-14" }
        await model.saveDaysThroughToday()
        XCTAssertEqual(1, model.swimClass(firstId)?.log.count)

        let deleted = await model.deleteClass(firstId)
        XCTAssertTrue(deleted)
        XCTAssertEqual(["Second"], model.classes.map(\.name))
        XCTAssertEqual([2], model.classes.map(\.order))
        let reread = try await Store(root: root).loadClasses()
        XCTAssertEqual(["Second"], reread.map(\.name))
    }

    func testDeletingSelectedClassesRemovesThemAllAndKeepsTheRestsOrder() async throws {
        let model = try await makeModel()
        for (name, weekday) in [("First", "mon"), ("Second", "tue"), ("Third", "wed")] {
            var form = stage1Form()
            form.name = name
            form.weekdays = [weekday]
            _ = await model.createClass(form)
        }
        let ids = model.classes.map(\.id)
        XCTAssertEqual(3, ids.count)

        let deleted = await model.deleteClasses([ids[0], ids[2]])
        XCTAssertTrue(deleted)
        XCTAssertEqual(["Second"], model.classes.map(\.name))
        XCTAssertEqual([2], model.classes.map(\.order))
        let reread = try await Store(root: root).loadClasses()
        XCTAssertEqual(["Second"], reread.map(\.name))
    }

    // MARK: M6 — backup and restore

    func testBackupThenDeleteThenRestoreBringsTheClassAndItsLogBack() async throws {
        let model = try await makeModel()
        _ = await model.createClass(stage1Form())
        let classId = try XCTUnwrap(model.classes.first?.id)
        model.today = { "2026-09-14" }
        await model.saveDaysThroughToday()

        let exported = await model.exportBackupFile()
        let backup = try XCTUnwrap(exported)
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("DeckPlan-backup-"))
        let deleted = await model.deleteClass(classId)
        XCTAssertTrue(deleted)
        XCTAssertTrue(model.classes.isEmpty)

        let problem = await model.restoreBackup(from: backup, mode: .merge)
        XCTAssertNil(problem)
        let restored = try XCTUnwrap(model.swimClass(classId))
        XCTAssertEqual(1, restored.log.count)
        XCTAssertEqual(2, model.todayDay(restored))
    }

    // MARK: S2 — complete file protection (device only; `swift test` and the simulator skip it)

    func testStoreFilesCarryCompleteFileProtection() async throws {
        let model = try await makeModel()
        _ = await model.createClass(stage1Form())
        #if os(iOS) && !targetEnvironment(simulator)
        let classesFile = root.appendingPathComponent("classes.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: classesFile.path)
        // The attribute bridges as NSFileProtectionType or as its raw string; compare the name.
        XCTAssertTrue(String(describing: attributes[.protectionKey]).contains(FileProtectionType.complete.rawValue),
                      "classes.json protection is \(String(describing: attributes[.protectionKey]))")
        #else
        // The simulator writes the files but does not keep a protection class to read
        // back; the attribute is checked on a device.
        throw XCTSkip("File protection is a device-only attribute.")
        #endif
    }
}
