//
//  AppModel+Backup.swift
//  DeckPlan
//
//  Backup and restore as one document (docs/REDESIGN.md §6; S2). The export
//  is a file the owner hands to the share sheet — the only way anything
//  leaves the device (D21). Restore reads a file the owner picked. Every
//  sentence is `Display.BackupWords`', never the store's error text.
//

import Foundation
import DeckPlanCore

extension AppModel {
    /// Writes the whole store as one JSON document into a temporary file named
    /// for today, and returns it for the share sheet. nil, with `saveError`
    /// set, when the store could not be read.
    func exportBackupFile() async -> URL? {
        guard let store else {
            saveError = Display.BackupWords.storeNotOpen
            return nil
        }
        do {
            let data = try await store.exportBackup()
            let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current,
                                                    formatOptions: [.withFullDate])
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("backup", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("DeckPlan-backup-\(stamp).json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            saveError = Display.BackupWords.couldntPrepare
            return nil
        }
    }

    /// Restores from a backup file the owner picked, then re-reads the store.
    /// Returns the problem sentence, nil on success.
    func restoreBackup(from url: URL, mode: Store.ImportMode) async -> String? {
        guard let store else { return Display.BackupWords.storeNotOpen }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return Display.BackupWords.fileUnreadable
        }
        do {
            try await store.importBackup(data, mode: mode)
        } catch StoreError.newerAppVersion(let backup, _) {
            return Display.BackupWords.newerBackup(backup)
        } catch StoreError.writeFailed(_, _) {
            return Display.BackupWords.couldntWrite
        } catch {
            return Display.BackupWords.notABackup
        }
        await loadStoreData()
        return nil
    }
}
