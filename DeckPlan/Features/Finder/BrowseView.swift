//
//  BrowseView.swift
//  DeckPlan
//
//  Browse (docs/REDESIGN.md §4): a stage's whole pool-filtered library,
//  grouped by skill, Greeting first.
//

import SwiftUI
import DeckPlanCore

struct BrowseView: View {
    let model: AppModel
    let stageId: String
    let ageTag: String?

    var body: some View {
        List {
            if let result = model.browse(stageId: stageId, ageTag: ageTag) {
                ForEach(Array(result.groups.enumerated()), id: \.offset) { _, group in
                    Section(group.name) {
                        if group.activityIds.isEmpty {
                            Text(Display.Finder.nothingPasses)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(group.activityIds, id: \.self) { activityId in
                            NavigationLink(value: ActivityRef(id: activityId, skillId: group.skillId, stageId: stageId)) {
                                Text(model.activityName(activityId))
                            }
                        }
                    }
                }
            } else {
                Text(Display.General.notReady)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(model.stageTitle(stageId))
        .navigationBarTitleDisplayMode(.inline)
    }
}
