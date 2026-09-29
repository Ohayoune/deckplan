//
//  StoreTests.swift
//  DeckPlanCoreTests
//
//  docs/TEST_CASES.md S1 (the three v2 files round-trip through canonical JSON;
//  a class file from the Python fixture decodes and re-encodes byte-identical)
//  and S2 (carried from v1: atomic writes, complete file protection, corrupt-file
//  detection with a readable error, backup as one document and restore from it).
//

import Foundation
import XCTest
@testable import DeckPlanCore

final class StoreTests: XCTestCase {

    // MARK: - Temp directories

    private var createdDirectories: [URL] = []

    override func tearDown() {
        for url in createdDirectories {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }
        createdDirectories = []
        super.tearDown()
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        createdDirectories.append(url)
        return url
    }

    private func sampleSettings() -> Settings {
        Settings(extra: ["theme": "light"])
    }

    // MARK: - Settings: the display toggles (DECISIONS_LOG 2026-09-12, 2026-09-13)

    func test_settings_without_the_toggles_read_as_off_and_keep_other_fields() throws {
        let bare = try Settings(json: .object(["theme": .string("light")]))
        XCTAssertFalse(bare.showWelcome)
        XCTAssertFalse(bare.showTopic)
        XCTAssertFalse(bare.reviewFirst)
        XCTAssertEqual(["theme": .string("light")], bare.extra)
        // Written back as it was read until a toggle is set.
        XCTAssertEqual(.object(["theme": .string("light")]), bare.json)

        var on = bare
        on.showWelcome = true
        on.showTopic = true
        on.reviewFirst = true
        let reread = try Settings(json: on.json)
        XCTAssertEqual(on, reread)
        XCTAssertEqual(.bool(true), on.json["showWelcome"])
        XCTAssertEqual(.bool(true), on.json["showTopic"])
        XCTAssertEqual(.bool(true), on.json["reviewFirst"])
        XCTAssertEqual(.string("light"), on.json["theme"])
        XCTAssertThrowsError(try Settings(json: .object(["showWelcome": .string("yes")])))
    }

    // MARK: - S1: the three files

    func test_S1_every_file_round_trips_through_the_store() async throws {
        let root = try makeTempDirectory()
        let store = Store(root: root)
        let pool = try Fixtures.fixturePool()
        let swimClass = try Fixtures.fixtureClass()
        let settings = sampleSettings()

        try await store.save(pool: pool)
        try await store.save(classes: [swimClass])
        try await store.save(settings: settings)

        let reloadedPool = try await store.loadPool()
        let reloadedClasses = try await store.loadClasses()
        let reloadedSettings = try await store.loadSettings()
        XCTAssertEqual(pool, reloadedPool)
        XCTAssertEqual([swimClass], reloadedClasses)
        XCTAssertEqual(settings, reloadedSettings)

        // the file shapes docs/TEST_CASES.md S1 names, as canonical JSON
        for (file, format) in [("pool.json", "pool/1"), ("classes.json", "classes/1"), ("settings.json", "settings/1")] {
            let data = try Data(contentsOf: root.appendingPathComponent(file))
            let parsed = try JSONValue.parse(data)
            XCTAssertEqual(format, parsed["format"]?.stringValue, file)
            XCTAssertEqual(1, parsed["items"]?.arrayValue?.count, file)
            XCTAssertEqual(try Canonical.dumpsData(parsed), data, "\(file) is canonical JSON")
        }

        let manifest = try await store.loadManifest()
        XCTAssertEqual(Store.manifestFormat, manifest?.format)
        XCTAssertEqual(Store.defaultAppVersion, manifest?.appVersion)
        XCTAssertNotNil(manifest?.savedAt)
    }

    func test_S1_the_python_class_and_pool_files_load_and_save_byte_identical() async throws {
        let root = try makeTempDirectory()
        let store = Store(root: root)
        for (name, file) in [("class.stage1.json", "classes.json"), ("pool.shallow.json", "pool.json")] {
            try Repo.data("examples/\(name)").write(to: root.appendingPathComponent(file))
        }

        let classes = try await store.loadClasses()
        XCTAssertEqual(["c-stage1-mw"], classes.map(\.id))
        XCTAssertEqual(try Fixtures.fixtureClass(), classes[0])
        let pool = try await store.loadPool()
        XCTAssertEqual(try Fixtures.fixturePool(), pool)

        try await store.save(classes: classes)
        try await store.save(pool: try XCTUnwrap(pool))
        for (name, file) in [("class.stage1.json", "classes.json"), ("pool.shallow.json", "pool.json")] {
            // the Python writes the canonical document plus one trailing newline;
            // the Store writes the document alone
            let expected = Data(try Fixtures.text(name).dropLast().utf8)
            let written = try Data(contentsOf: root.appendingPathComponent(file))
            XCTAssertEqual(expected, written, "\(file) re-encodes the Python's bytes")
        }
    }

    func test_S1_a_missing_file_loads_as_empty_never_as_an_error() async throws {
        let store = Store(root: try makeTempDirectory())
        let pool = try await store.loadPool()
        let classes = try await store.loadClasses()
        let settings = try await store.loadSettings()
        let manifest = try await store.loadManifest()
        XCTAssertNil(pool)
        XCTAssertEqual([], classes)
        XCTAssertNil(settings)
        XCTAssertNil(manifest)
    }

    // MARK: - S2: corrupt files are reported, never loaded as empty

    func test_S2_a_torn_file_is_reported_as_corrupt_with_a_readable_error() async throws {
        let root = try makeTempDirectory()
        let store = Store(root: root)
        try await store.save(classes: [try Fixtures.fixtureClass()])

        // Simulate a crash mid-write: the file is valid up to the point it was
        // cut off, so a naive parse-failure-means-empty rule would lose the class.
        let url = root.appendingPathComponent("classes.json")
        let wholeFile = try Data(contentsOf: url)
        XCTAssertGreaterThan(wholeFile.count, 1)
        try wholeFile.dropLast().write(to: url)
        do {
            _ = try await store.loadClasses()
            XCTFail("a truncated classes.json must not load as an empty collection")
        } catch let error as StoreError {
            guard case .corrupt(let file, let reason) = error else { return XCTFail("expected .corrupt, got \(error)") }
            XCTAssertEqual("classes.json", file)
            XCTAssertTrue(reason.contains("not valid JSON"), reason)
            XCTAssertTrue(error.description.hasPrefix("classes.json is corrupt: "), error.description)
        }

        // A file that parses but is not this store's shape is just as foreign.
        try Data("{\"format\":\"classes/1\",\"notItems\":[]}".utf8).write(to: url)
        do {
            _ = try await store.loadClasses()
            XCTFail("a classes.json with no \"items\" must be reported, not treated as empty")
        } catch let error as StoreError {
            guard case .corrupt = error else { return XCTFail("expected .corrupt, got \(error)") }
        }
        try Data("{\"format\":\"swimmers/1\",\"items\":[]}".utf8).write(to: url)
        do {
            _ = try await store.loadClasses()
            XCTFail("a v1 file must be reported, not treated as empty")
        } catch let error as StoreError {
            guard case .corrupt(_, let reason) = error else { return XCTFail("expected .corrupt, got \(error)") }
            XCTAssertTrue(reason.contains("unexpected format"), reason)
        }

        // Every other file is untouched by classes.json being torn.
        let pool = try await store.loadPool()
        XCTAssertNil(pool)
    }

    // MARK: - S2: complete file protection on iOS, a no-op on macOS

    func test_S2_protection_attributes_select_by_platform() {
        let attributes = Store.protectionAttributes()
        #if os(iOS)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete,
                        "iOS store files must ask for complete file protection (v1 D21)")
        #else
        XCTAssertTrue(attributes.isEmpty, "file protection is an iOS-only concept; macOS contributes no attributes")
        #endif
    }

    func test_S2_store_files_are_written_with_complete_protection_on_iOS() async throws {
        let root = try makeTempDirectory()
        let store = Store(root: root)
        try await store.save(pool: try Fixtures.fixturePool())
        #if os(iOS)
        let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("pool.json").path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)
        #else
        throw XCTSkip("Complete file protection only applies on iOS (v1 D21); this run is on macOS. The write "
            + "path above still runs here, and test_S2_protection_attributes_select_by_platform asserts "
            + "Store.protectionAttributes()'s per-platform value.")
        #endif
    }

    // MARK: - S2: a failed write throws; prior content is unchanged

    func test_S2_a_failed_write_throws_and_leaves_prior_content_unchanged() async throws {
        let root = try makeTempDirectory()
        let store = Store(root: root)
        let originalPool = try Fixtures.fixturePool()
        let originalClasses = [try Fixtures.fixtureClass()]
        try await store.save(pool: originalPool)
        try await store.save(classes: originalClasses)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        let probe = root.appendingPathComponent(".permission-probe")
        if FileManager.default.createFile(atPath: probe.path, contents: Data("x".utf8)) {
            try? FileManager.default.removeItem(at: probe)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            throw XCTSkip("This environment does not enforce directory permissions (running as root?); "
                + "the failed-write case cannot be exercised here.")
        }

        let differentPool = Activities.defaultPool(LoadedCurriculum())
        do {
            try await store.save(pool: differentPool)
            XCTFail("a save into a read-only directory must throw")
        } catch let error as StoreError {
            guard case .writeFailed = error else { return XCTFail("expected .writeFailed, got \(error)") }
        }
        do {
            try await store.save(classes: [])
            XCTFail("a save into a read-only directory must throw")
        } catch let error as StoreError {
            guard case .writeFailed = error else { return XCTFail("expected .writeFailed, got \(error)") }
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        let reloadedPool = try await store.loadPool()
        let reloadedClasses = try await store.loadClasses()
        XCTAssertEqual(originalPool, reloadedPool, "a failed save must leave the file exactly as it was")
        XCTAssertEqual(originalClasses, reloadedClasses, "a failed save must leave the file exactly as it was")
    }

    // MARK: - S2: backup as one document, restore from it

    func test_S2_backup_export_then_replaceAll_import_round_trips_exactly() async throws {
        let source = Store(root: try makeTempDirectory())
        let pool = try Fixtures.fixturePool()
        let swimClass = try Fixtures.fixtureClass()
        let settings = sampleSettings()
        try await source.save(pool: pool)
        try await source.save(classes: [swimClass])
        try await source.save(settings: settings)

        let backupData = try await source.exportBackup()
        let backup = try JSONValue.parse(backupData)
        XCTAssertEqual(Store.backupFormat, backup["format"]?.stringValue)
        XCTAssertEqual(["classes", "format", "manifest", "pool", "settings"],
                       Canonical.sortedKeys(backup.objectValue ?? [:]))

        let destination = Store(root: try makeTempDirectory())
        var extra = swimClass
        extra.id = "extra-class"
        try await destination.save(classes: [extra])
        try await destination.importBackup(backupData, mode: .replaceAll)

        let reloadedPool = try await destination.loadPool()
        let reloadedClasses = try await destination.loadClasses()
        let reloadedSettings = try await destination.loadSettings()
        XCTAssertEqual(pool, reloadedPool)
        XCTAssertEqual([swimClass], reloadedClasses, "replaceAll drops a class the backup does not have")
        XCTAssertEqual(settings, reloadedSettings)
    }

    func test_S2_backup_merge_import_adds_only_missing_ids() async throws {
        let source = Store(root: try makeTempDirectory())
        let fixture = try Fixtures.fixtureClass()
        var fromA = fixture
        fromA.id = "a-only"
        var aVersion = fixture
        aVersion.id = "shared"
        aVersion.name = "A's Version"
        try await source.save(pool: try Fixtures.fixturePool())
        try await source.save(classes: [fromA, aVersion])
        try await source.save(settings: sampleSettings())
        let backupData = try await source.exportBackup()

        let destination = Store(root: try makeTempDirectory())
        var bVersion = fixture
        bVersion.id = "shared"
        bVersion.name = "B's Version"
        let devicePool = Activities.defaultPool(LoadedCurriculum())
        try await destination.save(pool: devicePool)
        try await destination.save(classes: [bVersion])
        try await destination.importBackup(backupData, mode: .merge)

        let classes = try await destination.loadClasses()
        XCTAssertEqual(["shared", "a-only"], classes.map(\.id))
        XCTAssertEqual("B's Version", classes[0].name, "an existing class keeps the device's version")
        let pool = try await destination.loadPool()
        XCTAssertEqual(devicePool, pool, "an existing pool profile is kept")
        let settings = try await destination.loadSettings()
        XCTAssertEqual(sampleSettings(), settings, "settings are taken only when the device has none")
    }

    func test_S2_importBackup_refuses_a_newer_app_version_and_writes_nothing() async throws {
        let source = Store(root: try makeTempDirectory(), appVersion: "2.0.0")
        try await source.save(classes: [try Fixtures.fixtureClass()])
        let backupData = try await source.exportBackup()

        let destination = Store(root: try makeTempDirectory(), appVersion: "1.9.5")
        do {
            try await destination.importBackup(backupData, mode: .replaceAll)
            XCTFail("a backup from a newer app must be refused")
        } catch let error as StoreError {
            XCTAssertEqual(StoreError.newerAppVersion(backup: "2.0.0", running: "1.9.5"), error)
        }
        let classes = try await destination.loadClasses()
        XCTAssertEqual([], classes, "nothing was written before the refusal")
        let manifest = try await destination.loadManifest()
        XCTAssertNil(manifest)

        do {
            try await destination.importBackup(Data("{\"format\":\"deckplan-backup/1\"}".utf8), mode: .merge)
            XCTFail("a v1 backup is not this store's document")
        } catch let error as StoreError {
            guard case .invalidBackup = error else { return XCTFail("expected .invalidBackup, got \(error)") }
        }
    }
}
