//
//  Documents.swift
//  DeckPlanCore
//
//  Backup and restore as one document (docs/REDESIGN.md §6; docs/TEST_CASES.md
//  S2, carried from v1): the whole store — the pool profile, the classes with
//  their logs and drafts, settings — as one canonical JSON document. Nothing
//  leaves the device except through the share sheet by the owner's action (v1
//  D21); this is the document the share sheet carries.
//

import Foundation

extension Store {

    /// "deckplan-backup/2" — v2's three files; v1's "/1" carried swimmers,
    /// sessions and marks, which no longer exist.
    public static let backupFormat = "deckplan-backup/2"

    /// How ``importBackup(_:mode:)`` combines a backup with what the device
    /// already has.
    public enum ImportMode: Sendable, Equatable {
        /// Add only the class ids the store does not already have; an existing
        /// class keeps exactly what is on the device. The pool profile and
        /// settings are taken from the backup only when the device has none.
        case merge
        /// Every store file becomes exactly the backup's: classes not in the
        /// backup are removed, and the pool profile and settings are replaced
        /// (or removed, if the backup has none).
        case replaceAll
    }

    /// The whole store as one JSON document. The manifest inside is written
    /// fresh: a backup's `savedAt` is when the backup was made.
    public func exportBackup() throws -> Data {
        let manifest = StoreManifest(appVersion: appVersion, savedAt: Store.isoNow())
        let pool = try loadPool()
        let classes = try loadClasses()
        let settings = try loadSettings()

        var fields: [String: JSONValue] = [
            "format": .string(Store.backupFormat),
            "manifest": manifest.json,
            "classes": .array(classes.map(\.json)),
        ]
        if let pool { fields["pool"] = pool.json }
        if let settings { fields["settings"] = settings.json }

        do {
            return try Canonical.dumpsData(.object(fields))
        } catch {
            throw StoreError.writeFailed(file: "backup", reason: "could not encode the backup (\(error))")
        }
    }

    /// Restores from a document ``exportBackup()`` produced. Refuses — before
    /// writing anything at all — when the backup's `manifest.appVersion` is
    /// newer than the running app's.
    public func importBackup(_ data: Data, mode: ImportMode) throws {
        let backup = try parseBackup(data)

        if SemVer.isNewer(backup.manifest.appVersion, than: appVersion) {
            throw StoreError.newerAppVersion(backup: backup.manifest.appVersion, running: appVersion)
        }

        switch mode {
        case .replaceAll:
            try replaceAll(with: backup)
        case .merge:
            try merge(backup)
        }
    }

    // MARK: - replaceAll

    private func replaceAll(with backup: BackupDocument) throws {
        if let pool = backup.pool {
            try save(pool: pool)
        } else {
            try deleteFile(Store.poolFile)
        }
        try save(classes: backup.classes)
        if let settings = backup.settings {
            try save(settings: settings)
        } else {
            try deleteFile(Store.settingsFile)
        }
    }

    // MARK: - merge

    private func merge(_ backup: BackupDocument) throws {
        if try loadPool() == nil, let pool = backup.pool {
            try save(pool: pool)
        }
        let existingClasses = try loadClasses()
        let existingIds = Set(existingClasses.map(\.id))
        let newClasses = backup.classes.filter { !existingIds.contains($0.id) }
        if !newClasses.isEmpty {
            try save(classes: existingClasses + newClasses)
        }
        if try loadSettings() == nil, let settings = backup.settings {
            try save(settings: settings)
        }
    }

    // MARK: - Parsing the document

    private struct BackupDocument {
        var manifest: StoreManifest
        var pool: Pool?
        var classes: [SwimClass]
        var settings: Settings?
    }

    private func parseBackup(_ data: Data) throws -> BackupDocument {
        let parsed: JSONValue
        do {
            parsed = try JSONValue.parse(data)
        } catch {
            throw StoreError.invalidBackup(reason: "not valid JSON (\(error))")
        }
        guard case .object = parsed else {
            throw StoreError.invalidBackup(reason: "the top level is not a JSON object")
        }
        guard case .string(let format)? = parsed["format"], format == Store.backupFormat else {
            throw StoreError.invalidBackup(reason: "missing or unexpected \"format\" (not a DeckPlan backup)")
        }
        guard let manifestJSON = parsed["manifest"] else {
            throw StoreError.invalidBackup(reason: "missing its \"manifest\"")
        }
        do {
            return BackupDocument(
                manifest: try StoreManifest(json: manifestJSON),
                pool: try parsed["pool"].map { try Pool(json: $0) },
                classes: try (parsed["classes"]?.arrayValue ?? []).map { try SwimClass(json: $0) },
                settings: try parsed["settings"].map { try Settings(json: $0) })
        } catch let error as JSONModelError {
            throw StoreError.invalidBackup(reason: "\(error)")
        }
    }
}

/// A plain dot-separated version string, compared component by component as
/// integers (`"1.9.0"` < `"1.10.0"`). A component that is not a plain integer
/// counts as 0, so a malformed version is never mistaken for "newer".
enum SemVer {
    static func isNewer(_ candidate: String, than reference: String) -> Bool {
        let a = components(candidate)
        let b = components(reference)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}
