//
//  AppModel.swift
//  DeckPlan
//
//  The app's one observable model (docs/REDESIGN.md).
//
//  At launch it loads and validates the bundled curriculum (the `curriculum`
//  directory the build copies out of the repository, `local.json` included —
//  D20), opens the store under Documents (REDESIGN §6) and reads the pool
//  profile and the classes. Every screen reads from here; every change goes
//  through `commit(classes:)` / `commit(pool:)`, which write the store first
//  and only then update what the screens show, so a failed write is never
//  shown as a success.
//
//  The Core calls for each feature are in the `AppModel+*.swift` extensions.
//

import Foundation
import Observation
import DeckPlanCore

// MARK: - Curriculum status

/// The counts Settings → Curriculum status shows, read straight off the loaded
/// `Curriculum` so the screen never disagrees with what the planner sees.
struct CurriculumCounts: Equatable, Sendable {
    /// The stage ids in curriculum order (docs/CURRICULUM_FORMAT.md; Python's
    /// `ids.STAGE_IDS`).
    static let allStageIds = ["A", "B", "1", "2", "3", "4", "5", "6"]

    var loadedStageIds: [String] = []
    var skills = 0
    var steps = 0
    var topics = 0
    var lessonTemplates = 0
    var trackerRows = 0
    var ymcaActivities = 0
    var localActivities = 0
    var equipmentItems = 0
    var equipmentGroups = 0
    var localEquipment = 0
    var videos = 0
    var safetyRules = 0

    var notLoadedStageIds: [String] {
        Self.allStageIds.filter { !loadedStageIds.contains($0) }
    }

    init() {}

    /// Counts a loaded curriculum, matching `tools/core/curriculum.py`'s
    /// `summary()` field for field.
    ///
    /// Counted off the Core's JSON, not off typed models: this screen is the
    /// one the owner reads when the curriculum is *wrong*, so it must not
    /// itself fail to decode. A stage that is missing `skills` counts zero
    /// skills; it never stops the count.
    init(_ loaded: LoadedCurriculum) {
        loadedStageIds = loaded.stages.compactMap { $0["id"]?.stringValue }
        for stage in loaded.stages {
            let stageSkills = stage["skills"]?.arrayValue ?? []
            skills += stageSkills.count
            steps += stageSkills.reduce(0) { $0 + ($1["steps"]?.arrayValue?.count ?? 0) }
            topics += stage["topics"]?.arrayValue?.count ?? 0
            lessonTemplates += stage["lessonTemplates"]?.arrayValue?.count ?? 0
            trackerRows += stage["trackerRows"]?.arrayValue?.count ?? 0
        }
        localActivities = loaded.localActivityCount
        ymcaActivities = max(0, loaded.activities.count - loaded.localActivityCount)
        localEquipment = loaded.localEquipmentCount
        let ymcaEquipment = loaded.equipment.dropLast(loaded.localEquipmentCount)
        equipmentGroups = ymcaEquipment.filter { $0["kind"]?.stringValue == "group" }.count
        equipmentItems = ymcaEquipment.count - equipmentGroups
        videos = loaded.videos.count
        safetyRules = loaded.safety.count
    }
}

/// Everything Settings → Curriculum status needs.
struct CurriculumStatus: Equatable, Sendable {
    /// nil until the load has run.
    var version: String?
    var counts = CurriculumCounts()
    var issues: [CurriculumIssue] = []
    /// False when the bundle carries no `curriculum` directory (a build made
    /// without running `tools/dev/sync_resources.py`).
    var bundleHasCurriculum = false
    /// False while `DeckPlanCore` has no curriculum loader — the counts and the
    /// empty error list then mean nothing, and the screen says so.
    var loaderAvailable = false
    /// False until the Core's validator has run the checks of
    /// CURRICULUM_FORMAT.md §5 over what was loaded.
    var validated = false

    var errors: [CurriculumIssue] { issues.filter { $0.severity == .error } }
    var warnings: [CurriculumIssue] { issues.filter { $0.severity == .warning } }

    /// The app refuses to plan when the curriculum has errors, and equally when
    /// it has not been checked at all.
    var canPlan: Bool {
        loaderAvailable && validated && bundleHasCurriculum && errors.isEmpty
    }

    /// One sentence for the top of the screen.
    var headline: String {
        if !bundleHasCurriculum {
            return "No curriculum in this build. Run tools/dev/sync_resources.py and build again."
        }
        if !loaderAvailable {
            return "Not read — the Core's curriculum loader is not built yet."
        }
        if !validated {
            return "Read, but not checked — the Core's validator is not built yet."
        }
        if !errors.isEmpty {
            let n = errors.count
            return "\(n) error\(n == 1 ? "" : "s") — the app will not plan lessons until they are fixed."
        }
        if !warnings.isEmpty {
            let n = warnings.count
            return "Valid, with \(n) warning\(n == 1 ? "" : "s")."
        }
        return "Valid. Every check passed."
    }
}

// MARK: - Store status

/// Where the store is and whether it opened (REDESIGN §6).
enum StoreStatus: Equatable, Sendable {
    case opening
    /// The store's root directory under Documents.
    case open(root: URL)
    case failed(String)

    var sentence: String {
        switch self {
        case .opening:
            return "Opening…"
        case .open(let root):
            return "Open at \(root.lastPathComponent)/ in Documents."
        case .failed(let message):
            return message
        }
    }

    var isOpen: Bool {
        if case .open = self { return true }
        return false
    }
}

// MARK: - The model

@MainActor
@Observable
final class AppModel {
    /// The result of the launch-time load.
    private(set) var curriculumStatus = CurriculumStatus()
    /// The loaded curriculum. Set whenever the bundle read at all, so the
    /// status screen can count it; the features use it only through
    /// `planningCurriculum`, which also requires the validation to have passed.
    private(set) var loadedCurriculum: LoadedCurriculum?
    private(set) var storeStatus: StoreStatus = .opening

    /// The Core's store over Documents, once opened.
    private(set) var store: Store?

    /// Every class, in list order (REDESIGN §5: order, then name).
    private(set) var classes: [SwimClass] = []
    /// The one pool profile (REDESIGN §2), normalized against the catalog.
    private(set) var pool = Pool()
    /// The display toggles (DECISIONS_LOG 2026-09-12): Welcome and Topic are
    /// off until the owner turns them on.
    private(set) var settings = Settings()
    /// True once `pool.json`, `classes.json` and `settings.json` have been read
    /// after the store opened; the screens show a placeholder until then.
    private(set) var storeDataLoaded = false

    /// The last write that failed, as one sentence for an alert. Set by
    /// `commit(...)`; the root view shows and clears it.
    var saveError: String?

    /// The device's calendar day, "YYYY-MM-DD", for the days that save
    /// themselves (DECISIONS_LOG 2026-09-13); the Core never reads the clock.
    /// Tests set a fixed day.
    @ObservationIgnored var today: () -> String = { Display.isoToday() }

    private let bundle: Bundle
    private let loader: CurriculumLoading
    /// Where the store lives; nil means Documents/store (the app). Tests pass a
    /// temporary directory.
    private let storeRoot: URL?

    /// The one line to change when a different loader is wanted.
    static var defaultLoader: CurriculumLoading { CoreCurriculumLoading() }

    init(bundle: Bundle = .main,
         loader: CurriculumLoading = AppModel.defaultLoader,
         storeRoot: URL? = nil) {
        self.bundle = bundle
        self.loader = loader
        self.storeRoot = storeRoot
        loadCurriculum()
    }

    // MARK: Curriculum

    /// The bundle's read-only curriculum directory, or nil when this build was
    /// made without `tools/dev/sync_resources.py`.
    var bundledCurriculumDirectory: URL? {
        bundle.url(forResource: "curriculum", withExtension: nil)
    }

    /// The curriculum the features plan on: the loaded one, only when the
    /// validator passed it.
    var planningCurriculum: LoadedCurriculum? {
        guard curriculumStatus.canPlan else { return nil }
        return loadedCurriculum
    }

    /// True when a class can be created and a plan shown: the curriculum is
    /// valid and the store is open and read.
    var isReady: Bool {
        planningCurriculum != nil && storeStatus.isOpen && storeDataLoaded
    }

    func loadCurriculum() {
        var status = CurriculumStatus()

        guard let directory = bundledCurriculumDirectory else {
            status.bundleHasCurriculum = false
            status.loaderAvailable = false
            status.issues = [CurriculumIssue(
                code: "bundle-curriculum-missing",
                severity: .error,
                location: "Resources/curriculum",
                message: "This build carries no curriculum directory. Run tools/dev/sync_resources.py, then build again."
            )]
            curriculumStatus = status
            loadedCurriculum = nil
            return
        }

        status.bundleHasCurriculum = true
        let local = directory.appendingPathComponent("local.json")
        let localPath = FileManager.default.fileExists(atPath: local.path) ? local : nil
        let result = loader.loadAndValidate(directory: directory, localPath: localPath)
        status.loaderAvailable = result.loaderAvailable
        status.validated = result.validated
        status.issues = result.issues
        if let curriculum = result.curriculum {
            status.version = curriculum.version
            status.counts = CurriculumCounts(curriculum)
        }
        loadedCurriculum = result.curriculum
        curriculumStatus = status
    }

    // MARK: Store

    /// Opens the store (REDESIGN §6) and reads the pool and the classes. Called
    /// once, from the root view's `task`.
    func openStore() async {
        let root: URL
        if let storeRoot {
            root = storeRoot
        } else {
            let documents: URL
            do {
                documents = try FileManager.default.url(for: .documentDirectory,
                                                        in: .userDomainMask,
                                                        appropriateFor: nil,
                                                        create: true)
            } catch {
                storeStatus = .failed("Could not find the Documents directory: \(error.localizedDescription)")
                return
            }
            root = documents.appendingPathComponent("store", isDirectory: true)
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            // Nothing leaves the device (D21): complete file protection on the root.
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
        } catch {
            storeStatus = .failed("Could not open the store: \(error.localizedDescription)")
            return
        }
        let (store, status) = await Self.attachStore(root: root)
        self.store = store
        storeStatus = status
        guard status.isOpen else { return }
        await loadStoreData()
    }

    /// Reads `pool.json`, `classes.json` and `settings.json`. A pool that was
    /// never saved is the Core's default (everything on, DECISIONS_LOG
    /// 2026-09-12); a saved one is normalized against the curriculum's profile
    /// items (P6) so a prop's key is dropped and a new profile item gets a toggle.
    /// Settings never saved are both toggles off.
    func loadStoreData() async {
        guard let store else { return }
        do {
            let savedPool = try await store.loadPool()
            let savedClasses = try await store.loadClasses()
            settings = try await store.loadSettings() ?? Settings()
            let curriculum = loadedCurriculum ?? LoadedCurriculum()
            if let savedPool {
                pool = Activities.normalizePool(savedPool, curriculum)
            } else {
                pool = Activities.defaultPool(curriculum)
            }
            classes = Classes.sorted(savedClasses)
            storeDataLoaded = true
        } catch {
            storeStatus = .failed("The store could not be read: \(error)")
            return
        }
        // The days through today save themselves (DECISIONS_LOG 2026-09-13).
        await saveDaysThroughToday()
    }

    /// Writes the classes, then shows them. Returns false, with `saveError`
    /// set, when the write failed; the screens then still show the old state.
    @discardableResult
    func commit(classes newClasses: [SwimClass]) async -> Bool {
        guard let store else {
            saveError = "The store is not open, so the change was not saved."
            return false
        }
        let sorted = Classes.sorted(newClasses)
        do {
            try await store.save(classes: sorted)
        } catch {
            saveError = "The classes could not be saved: \(error)"
            return false
        }
        classes = sorted
        return true
    }

    /// Writes the pool profile, then shows it.
    @discardableResult
    func commit(pool newPool: Pool) async -> Bool {
        guard let store else {
            saveError = "The store is not open, so the change was not saved."
            return false
        }
        let normalized = Activities.normalizePool(newPool, loadedCurriculum ?? LoadedCurriculum())
        do {
            try await store.save(pool: normalized)
        } catch {
            saveError = "The pool profile could not be saved: \(error)"
            return false
        }
        pool = normalized
        return true
    }

    /// Writes the settings, then shows them.
    @discardableResult
    func commit(settings newSettings: Settings) async -> Bool {
        guard let store else {
            saveError = "The store is not open, so the change was not saved."
            return false
        }
        do {
            try await store.save(settings: newSettings)
        } catch {
            saveError = "The settings could not be saved: \(error)"
            return false
        }
        settings = newSettings
        return true
    }

    /// Replaces one class by id and commits.
    @discardableResult
    func commit(class updated: SwimClass) async -> Bool {
        var next = classes
        if let index = next.firstIndex(where: { $0.id == updated.id }) {
            next[index] = updated
        } else {
            next.append(updated)
        }
        return await commit(classes: next)
    }

    func swimClass(_ classId: String) -> SwimClass? {
        Classes.find(classes, classId: classId)
    }
}
