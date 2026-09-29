//
//  BackupView.swift
//  DeckPlan
//
//  Backup and restore as one document (docs/REDESIGN.md §6; M6). The backup
//  leaves the device only through the share sheet, by the owner's action
//  (D21). Restore reads a file the owner picks and either adds the classes
//  the device lacks or replaces everything. Every word is
//  `Display.BackupWords`'.
//

import SwiftUI
import UniformTypeIdentifiers
import DeckPlanCore

struct BackupView: View {
    let model: AppModel

    @State private var backupURL: URL?
    @State private var importing = false
    @State private var pendingRestore: URL?
    @State private var alert: AlertText?

    var body: some View {
        Form {
            Section {
                Button {
                    Task { backupURL = await model.exportBackupFile() }
                } label: {
                    Label(Display.BackupWords.prepare, systemImage: "doc.badge.plus")
                }
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label(Display.BackupWords.share(backupURL.lastPathComponent), systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text(Display.BackupWords.backup)
            } footer: {
                Text(Display.BackupWords.backupFooter)
            }

            Section {
                Button {
                    importing = true
                } label: {
                    Label(Display.BackupWords.restoreFromFile, systemImage: "arrow.down.doc")
                }
            } header: {
                Text(Display.BackupWords.restore)
            } footer: {
                Text(Display.BackupWords.restoreFooter)
            }
        }
        .navigationTitle(Display.BackupWords.title)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText]) { result in
            switch result {
            case .success(let url):
                pendingRestore = url
            case .failure:
                alert = AlertText(title: Display.BackupWords.couldntRestore, message: Display.BackupWords.fileUnreadable)
            }
        }
        .confirmationDialog(Display.BackupWords.restoreHow, isPresented: restoreShown, titleVisibility: .visible,
                            presenting: pendingRestore) { url in
            Button(Display.BackupWords.addMissing) { restore(url, mode: .merge) }
            Button(Display.BackupWords.replaceAll, role: .destructive) { restore(url, mode: .replaceAll) }
        } message: { url in
            Text(url.lastPathComponent)
        }
        .alert($alert)
    }

    private var restoreShown: Binding<Bool> {
        Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })
    }

    private func restore(_ url: URL, mode: Store.ImportMode) {
        Task {
            if let problem = await model.restoreBackup(from: url, mode: mode) {
                alert = AlertText(title: Display.BackupWords.couldntRestore, message: problem)
            } else {
                alert = AlertText(title: Display.BackupWords.restored,
                                  message: Display.BackupWords.restoredMessage(model.classes.count))
            }
        }
    }
}
