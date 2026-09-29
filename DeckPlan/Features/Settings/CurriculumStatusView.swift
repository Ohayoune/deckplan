//
//  CurriculumStatusView.swift
//  DeckPlan
//
//  Settings → Diagnostics (DECISIONS_LOG 2026-09-12, "The plan is the
//  product"): what used to sit on Settings and the class screen — the
//  curriculum's validation result and counts (docs/CURRICULUM_FORMAT.md §5,
//  errors first then warnings, each with its code so the owner can quote it
//  back), the store sentence, the classes with their `order`, the app version
//  and the repository footer.
//

import SwiftUI
import DeckPlanCore

struct DiagnosticsView: View {
    let model: AppModel

    private var status: CurriculumStatus { model.curriculumStatus }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: headlineSymbol)
                        .font(.title2)
                        .foregroundStyle(headlineTint)
                    Text(status.headline)
                        .font(.callout)
                }
                .padding(.vertical, 4)
                LabeledContent(Display.Diagnostics.version, value: status.version ?? "—")
                LabeledContent(Display.Diagnostics.plansLessons,
                               value: status.canPlan ? Display.Diagnostics.yes : Display.Diagnostics.no)
            } header: {
                Text(Display.Diagnostics.validation)
            }

            if !status.errors.isEmpty {
                Section(Display.Diagnostics.errors) {
                    ForEach(status.errors) { issue in
                        IssueRow(issue: issue)
                    }
                }
            }

            if !status.warnings.isEmpty {
                Section {
                    ForEach(status.warnings) { issue in
                        IssueRow(issue: issue)
                    }
                } header: {
                    Text(Display.Diagnostics.warnings)
                } footer: {
                    Text(Display.Diagnostics.warningsFooter)
                }
            }

            Section(Display.Diagnostics.loaded) {
                LabeledContent(Display.Diagnostics.stages, value: stagesValue)
                if !status.counts.notLoadedStageIds.isEmpty {
                    LabeledContent(Display.Diagnostics.notLoaded,
                                   value: status.counts.notLoadedStageIds.joined(separator: ", "))
                }
                LabeledContent(Display.Diagnostics.skills, value: "\(status.counts.skills)")
                LabeledContent(Display.Diagnostics.steps, value: "\(status.counts.steps)")
                LabeledContent(Display.Diagnostics.topics, value: "\(status.counts.topics)")
                LabeledContent(Display.Diagnostics.lessonTemplates, value: "\(status.counts.lessonTemplates)")
                LabeledContent(Display.Diagnostics.trackerRows, value: "\(status.counts.trackerRows)")
                LabeledContent(Display.Diagnostics.videos, value: "\(status.counts.videos)")
                LabeledContent(Display.Diagnostics.safetyRules, value: "\(status.counts.safetyRules)")
            }

            Section {
                LabeledContent(Display.Diagnostics.activities, value: "\(status.counts.ymcaActivities)")
                LabeledContent(Display.Diagnostics.equipmentItems, value: "\(status.counts.equipmentItems)")
                LabeledContent(Display.Diagnostics.equipmentGroups, value: "\(status.counts.equipmentGroups)")
                LabeledContent(Display.Diagnostics.profileItems,
                               value: model.profileEquipment.map(\.name).joined(separator: ", "))
            } header: {
                Text(Display.Diagnostics.catalog)
            }

            Section {
                LabeledContent(Display.Diagnostics.activities, value: "\(status.counts.localActivities)")
                LabeledContent(Display.Diagnostics.equipmentItems, value: "\(status.counts.localEquipment)")
            } header: {
                Text(Display.Diagnostics.localAdditions)
            } footer: {
                Text(Display.Diagnostics.localFooter)
            }

            Section(Display.Diagnostics.store) {
                Text(model.storeStatus.sentence)
                    .foregroundStyle(.secondary)
            }

            if !model.classes.isEmpty {
                Section(Display.Diagnostics.classes) {
                    ForEach(model.classes, id: \.id) { swimClass in
                        LabeledContent(swimClass.name, value: Display.Diagnostics.classOrder(swimClass.order))
                    }
                }
            }

            Section {
                LabeledContent(Display.Diagnostics.version_, value: appVersion)
                Text(Display.Diagnostics.about)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(Display.Diagnostics.app)
            }
        }
        .navigationTitle(Display.Diagnostics.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stagesValue: String {
        let loaded = status.counts.loadedStageIds
        guard !loaded.isEmpty else { return Display.Diagnostics.none }
        return "\(loaded.count) of \(CurriculumCounts.allStageIds.count) — \(loaded.joined(separator: ", "))"
    }

    private var headlineSymbol: String {
        if !status.loaderAvailable || !status.validated || !status.bundleHasCurriculum { return "questionmark.circle.fill" }
        if !status.errors.isEmpty { return "xmark.octagon.fill" }
        if !status.warnings.isEmpty { return "exclamationmark.triangle.fill" }
        return "checkmark.seal.fill"
    }

    private var headlineTint: Color {
        if !status.loaderAvailable || !status.validated || !status.bundleHasCurriculum { return .orange }
        if !status.errors.isEmpty { return .red }
        if !status.warnings.isEmpty { return .orange }
        return .green
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

/// One validation finding as a sentence, with its code and place underneath.
private struct IssueRow: View {
    let issue: CurriculumIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(issue.message)
                .font(.callout)
            Text("\(issue.code) · \(issue.location)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
