//
//  Store.swift
//  DeckPlanCore
//
//  The on-device store — docs/REDESIGN.md §6: `pool.json` (one profile),
//  `classes.json` (the classes with their logs and drafts) and `settings.json`,
//  in v1's file format `{"format": "<name>/1", "items": [...]}`, with v1's
//  mechanics kept (docs/TEST_CASES.md S1, S2): atomic writes, complete file
//  protection on iOS (v1 D21), corrupt-file detection with a readable error,
//  backup and restore as one document (Documents.swift).
//
//  Every store file is one JSON document, UTF-8, written through
//  `Canonical.dumpsData`: a canonical, key-sorted, whitespace-free file is
//  deterministic and diffable, and — since V1 — it is also exactly what the
//  Python CLI writes, so a class file made on the Mac is what the app keeps
//  (DECISIONS_LOG 2026-09-12 "Store documents from the CLI").
//
//  Reading is strict: a file that parses to something other than a JSON
//  object, that is missing its "format" key, whose "format" does not match, or
//  that lacks "items", is a torn or foreign file and is reported as
//  `StoreError.corrupt(file:reason:)` — never silently loaded as empty. A file
//  that is simply *absent* is the one case that means "nothing saved yet".
//
//  Every write goes to a temporary file in the file's own directory first,
//  with the platform's file-protection attributes set at creation time, and
//  only then replaces the destination — so a crash or a failed write never
//  leaves a torn file where a good one used to be.
//

import Foundation

// MARK: - Errors

/// What went wrong loading or writing a store file (docs/TEST_CASES.md S2).
public enum StoreError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A file that exists but is not valid store content: invalid JSON (a
    /// truncated write), not a JSON object, missing or mismatched "format",
    /// or missing "items" — never confused with a merely *absent* file, which
    /// loads as empty.
    case corrupt(file: String, reason: String)
    /// A write did not complete. Nothing at `file` was changed: the failure
    /// happened before the atomic replace.
    case writeFailed(file: String, reason: String)
    /// A backup's `manifest.appVersion` is newer than the running app's.
    /// Checked, and thrown, before `importBackup` writes anything.
    case newerAppVersion(backup: String, running: String)
    /// The data given to `importBackup` is not a DeckPlan backup document.
    case invalidBackup(reason: String)

    public var description: String {
        switch self {
        case .corrupt(let file, let reason):
            return "\(file) is corrupt: \(reason)"
        case .writeFailed(let file, let reason):
            return "could not write \(file): \(reason)"
        case .newerAppVersion(let backup, let running):
            return "this backup is from app version \(backup), which is newer than the "
                + "running \(running); update the app before restoring it"
        case .invalidBackup(let reason):
            return "not a DeckPlan backup: \(reason)"
        }
    }
}

// MARK: - The store's own bookkeeping file

/// `manifest.json`: the running app's version and when the store was last
/// saved to, rewritten after every successful save, so a backup can be checked
/// against the running app's version before `importBackup` writes anything.
public struct StoreManifest: JSONModel {
    public var format: String
    public var appVersion: String
    /// ISO-8601, when this manifest was written.
    public var savedAt: String
    public var extra: [String: JSONValue]

    public init(format: String = Store.manifestFormat, appVersion: String, savedAt: String,
                extra: [String: JSONValue] = [:]) {
        self.format = format
        self.appVersion = appVersion
        self.savedAt = savedAt
        self.extra = extra
    }

    public init(json: JSONValue) throws {
        var reader = try JSONReader(json, type: "StoreManifest")
        format = try reader.string("format")
        appVersion = try reader.string("appVersion")
        savedAt = try reader.string("savedAt")
        extra = reader.extra
    }

    public var json: JSONValue {
        var out = JSONBuilder(extra: extra)
        out.set("format", format)
        out.set("appVersion", appVersion)
        out.set("savedAt", savedAt)
        return out.json
    }
}

// MARK: - The store

/// The on-device store: the pool profile, the classes and settings
/// (docs/REDESIGN.md §6), as one actor over a root directory — the app's
/// Documents directory at runtime, a temporary directory in tests.
///
/// An actor because the app reads and writes it from more than one place; every
/// call serializes through the actor, so two saves never interleave. It holds
/// no cached copy of anything — every load reads the file fresh and every save
/// writes it fully — so the value a caller still holds after a failed save is
/// exactly what the untouched file still says.
public actor Store {

    // MARK: File names and formats

    static let poolFile = "pool.json"
    static let poolFormat = "pool/1"
    static let classesFile = "classes.json"
    static let classesFormat = "classes/1"
    static let settingsFile = "settings.json"
    static let settingsFormat = "settings/1"
    static let manifestFile = "manifest.json"
    public static let manifestFormat = "deckplan-store/1"

    /// The running version before the app target supplies its own
    /// `CFBundleShortVersionString`.
    public static let defaultAppVersion = "1.0.0"

    /// The store's root directory. Never written to except through this actor.
    public nonisolated let root: URL
    /// This running app's version, written into `manifest.json` on every save
    /// and compared against a backup's on `importBackup`.
    public nonisolated let appVersion: String

    public init(root: URL, appVersion: String = Store.defaultAppVersion) {
        self.root = root
        self.appVersion = appVersion
    }

    // MARK: - Pool (one profile; `{"format": "pool/1", "items": [profile]}`)

    /// The pool profile, or `nil` when none has been saved yet.
    public func loadPool() throws -> Pool? {
        try loadItems(Store.poolFile, format: Store.poolFormat, as: Pool.self).first
    }

    public func save(pool: Pool) throws {
        try saveItems([pool], to: Store.poolFile, format: Store.poolFormat)
    }

    // MARK: - Classes

    /// Every class, or `[]` when `classes.json` has never been saved.
    public func loadClasses() throws -> [SwimClass] {
        try loadItems(Store.classesFile, format: Store.classesFormat, as: SwimClass.self)
    }

    public func save(classes: [SwimClass]) throws {
        try saveItems(classes, to: Store.classesFile, format: Store.classesFormat)
    }

    // MARK: - Settings (`{"format": "settings/1", "items": [settings]}`)

    public func loadSettings() throws -> Settings? {
        try loadItems(Store.settingsFile, format: Store.settingsFormat, as: Settings.self).first
    }

    public func save(settings: Settings) throws {
        try saveItems([settings], to: Store.settingsFile, format: Store.settingsFormat)
    }

    // MARK: - Manifest

    /// `manifest.json`, or `nil` before the first save.
    public func loadManifest() throws -> StoreManifest? {
        guard let data = try readFileIfExists(
            at: root.appendingPathComponent(Store.manifestFile), file: Store.manifestFile
        ) else { return nil }
        let parsed: JSONValue
        do {
            parsed = try JSONValue.parse(data)
        } catch {
            throw StoreError.corrupt(file: Store.manifestFile, reason: "not valid JSON (\(error))")
        }
        do {
            return try StoreManifest(json: parsed)
        } catch {
            throw StoreError.corrupt(file: Store.manifestFile, reason: "\(error)")
        }
    }

    // MARK: - File protection (v1 D21; docs/TEST_CASES.md S2)

    /// The attributes a new store file is created with: complete file
    /// protection on iOS; nothing on macOS, where the attribute has no meaning.
    static func protectionAttributes() -> [FileAttributeKey: Any] {
        #if os(iOS)
        return [.protectionKey: FileProtectionType.complete]
        #else
        return [:]
        #endif
    }

    // MARK: - Reading a file

    private func readFileIfExists(at url: URL, file: String) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw StoreError.corrupt(file: file, reason: "could not be read (\(error.localizedDescription))")
        }
    }

    /// Parses `relativePath` and checks its envelope (`{"format": ..., ...}`),
    /// or returns `nil` when the file is simply absent. Every load funnels
    /// through here, which is what makes "torn or foreign, not empty" one rule.
    private func readEnvelope(relativePath: String, expectedFormat: String) throws -> JSONValue? {
        let url = root.appendingPathComponent(relativePath)
        guard let data = try readFileIfExists(at: url, file: relativePath) else { return nil }
        guard !data.isEmpty else {
            throw StoreError.corrupt(file: relativePath, reason: "the file is empty")
        }
        let parsed: JSONValue
        do {
            parsed = try JSONValue.parse(data)
        } catch {
            throw StoreError.corrupt(file: relativePath, reason: "not valid JSON (\(error))")
        }
        guard case .object = parsed else {
            throw StoreError.corrupt(file: relativePath, reason: "the top level is not a JSON object")
        }
        guard case .string(let format)? = parsed["format"] else {
            throw StoreError.corrupt(file: relativePath, reason: "missing its \"format\" field")
        }
        guard format == expectedFormat else {
            throw StoreError.corrupt(
                file: relativePath,
                reason: "unexpected format \(format.debugDescription) (expected \(expectedFormat.debugDescription))")
        }
        return parsed
    }

    private func loadItems<T: JSONModel>(_ relativePath: String, format: String, as type: T.Type) throws -> [T] {
        guard let envelope = try readEnvelope(relativePath: relativePath, expectedFormat: format) else {
            return []
        }
        guard case .array(let items)? = envelope["items"] else {
            throw StoreError.corrupt(file: relativePath, reason: "missing its \"items\" array")
        }
        do {
            return try items.map { try T(json: $0) }
        } catch {
            throw StoreError.corrupt(file: relativePath, reason: "one of its \"items\" is invalid (\(error))")
        }
    }

    // MARK: - Writing a file

    private func encode(_ value: JSONValue, file: String) throws -> Data {
        do {
            return try Canonical.dumpsData(value)
        } catch {
            throw StoreError.writeFailed(file: file, reason: "could not encode it as JSON (\(error))")
        }
    }

    private func saveItems<T: JSONModel>(_ items: [T], to relativePath: String, format: String) throws {
        try writeEnvelope(
            .object(["format": .string(format), "items": .array(items.map(\.json))]),
            to: relativePath)
    }

    /// Encodes, writes atomically, and refreshes `manifest.json` — every
    /// public save funnels through here.
    private func writeEnvelope(_ envelope: JSONValue, to relativePath: String) throws {
        try writeAtomically(try encode(envelope, file: relativePath), to: relativePath)
        try writeManifestNow()
    }

    private func writeManifestNow() throws {
        let manifest = StoreManifest(appVersion: appVersion, savedAt: Store.isoNow())
        try writeAtomically(try encode(manifest.json, file: Store.manifestFile), to: Store.manifestFile)
    }

    /// Removes a file outright (`importBackup(mode: .replaceAll)` dropping a
    /// singleton the backup does not have). A no-op when it is already absent.
    func deleteFile(_ relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw StoreError.writeFailed(file: relativePath, reason: error.localizedDescription)
            }
        }
        try writeManifestNow()
    }

    /// Writes `data` to `relativePath` by creating a temporary file *in the
    /// same directory* with the platform's file-protection attributes already
    /// on it, then replacing the destination (or, the first time, moving the
    /// temporary file into place) — the atomic write (S2).
    ///
    /// `.usingNewMetadataOnly` makes the replace keep the *new* file's
    /// attributes (the protection class just set on the temporary file).
    private func writeAtomically(_ data: Data, to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw StoreError.writeFailed(
                file: relativePath, reason: "could not create its directory (\(error.localizedDescription))")
        }
        let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: tempURL.path, contents: data, attributes: Store.protectionAttributes()
        ) else {
            throw StoreError.writeFailed(
                file: relativePath, reason: "could not create a temporary file to write it into")
        }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL, options: [.usingNewMetadataOnly])
            } else {
                try FileManager.default.moveItem(at: tempURL, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw StoreError.writeFailed(file: relativePath, reason: error.localizedDescription)
        }
    }

    static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}
