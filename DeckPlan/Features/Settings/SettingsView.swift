//
//  SettingsView.swift
//  DeckPlan
//
//  Settings holds only choices (DECISIONS_LOG 2026-09-12, "The plan is the
//  product"): the class-day toggles (Welcome, Topic, Review before
//  Introduce), Pool, Backup, and one
//  "Curriculum 2026.09 · valid" row. The store sentence, the class orders, the
//  counts and the repository footer live on the Diagnostics screen at the
//  bottom. Local only: no account, no network.
//

import SwiftUI
import DeckPlanCore

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section(Display.SettingsWords.classDay) {
                Toggle(Display.SettingsWords.showWelcome, isOn: toggle(\.showWelcome))
                Toggle(Display.SettingsWords.showTopic, isOn: toggle(\.showTopic))
                Toggle(Display.SettingsWords.reviewFirst, isOn: toggle(\.reviewFirst))
            }

            Section {
                NavigationLink(value: SettingsRoute.pool) {
                    Label(Display.SettingsWords.pool, systemImage: "water.waves")
                }
                NavigationLink(value: SettingsRoute.backup) {
                    Label(Display.SettingsWords.backupAndRestore, systemImage: "arrow.up.doc")
                }
            }

            Section {
                Label(Display.SettingsWords.curriculumRow(model.curriculumStatus.version, shortStatus),
                      systemImage: statusSymbol)
                    .foregroundStyle(statusTint)
            }

            Section {
                NavigationLink(value: SettingsRoute.diagnostics) {
                    Label(Display.SettingsWords.diagnostics, systemImage: "stethoscope")
                }
            }
        }
        .navigationTitle(Display.SettingsWords.title)
    }

    /// A display toggle, written at once; it shows the new value only once the
    /// write succeeded.
    private func toggle(_ key: WritableKeyPath<Settings, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: key] },
                set: { value in
                    var settings = model.settings
                    settings[keyPath: key] = value
                    Task { await model.commit(settings: settings) }
                })
    }

    private var shortStatus: String {
        let status = model.curriculumStatus
        if !status.loaderAvailable || !status.validated || !status.bundleHasCurriculum {
            return Display.SettingsWords.notChecked
        }
        if !status.errors.isEmpty { return Display.SettingsWords.errors(status.errors.count) }
        if !status.warnings.isEmpty { return Display.SettingsWords.warnings(status.warnings.count) }
        return Display.SettingsWords.valid
    }

    private var statusSymbol: String {
        model.curriculumStatus.canPlan ? "checkmark.seal" : "exclamationmark.triangle"
    }

    private var statusTint: Color {
        let status = model.curriculumStatus
        if !status.canPlan { return .red }
        if !status.warnings.isEmpty { return .orange }
        return .primary
    }
}
