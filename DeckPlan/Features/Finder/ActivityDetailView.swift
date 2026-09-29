//
//  ActivityDetailView.swift
//  DeckPlan
//
//  One activity (docs/REDESIGN.md §4; DECISIONS_LOG 2026-09-12, "The plan is
//  the product"): the description first, then what to bring as one row (the
//  required items with the optional ones marked, props included), one line
//  for ages and submerging, the skill and stage, and the toolkit video the
//  skill appears in (a title, not a player). Reached from a day's block it
//  also shows the block's skills, steps and notes, and offers Add another
//  from the finder.
//

import SwiftUI
import DeckPlanCore

struct ActivityDetailView: View {
    let model: AppModel
    let activity: ActivityRef

    @State private var addTarget: DayBlockRef?

    var body: some View {
        Group {
            if let detail = model.activityDetail(activity.id, skillId: activity.skillId) {
                content(detail)
            } else {
                ContentUnavailableView(Display.Activity.unknown, systemImage: "questionmark.circle")
            }
        }
        .navigationTitle(model.activityName(activity.id))
        .navigationBarTitleDisplayMode(.inline)
        .finderSheet(model: model, target: $addTarget)
    }

    private func content(_ detail: ActivityDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(detail.description.isEmpty ? Display.Activity.noDescription : detail.description)
                    .foregroundStyle(detail.description.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    fact(Display.Activity.bring(detail.equipment, detail.equipmentOptional), symbol: "bag")
                    fact(Display.Activity.agesAndSubmerging(detail.ages, detail.submerges), symbol: "person.2")
                    if !place.isEmpty {
                        fact(place, symbol: "figure.pool.swim")
                    }
                    ForEach(detail.videos, id: \.self) { title in
                        fact(Display.Activity.inToolkitVideo(title), symbol: "film")
                    }
                }
                .cardStyle()

                if let block = activity.block, !block.isEmpty {
                    blockFacts(block)
                }

                if let day = activity.day {
                    Button {
                        addTarget = day
                    } label: {
                        Label(Display.Activity.addFromFinder(Display.block(day.kind)), systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    /// The skill and stage. Reached from a block, the block's own section
    /// names its skills, so this line names only the stage.
    private var place: String {
        let fromBlock = !(activity.block?.skillIds.isEmpty ?? true)
        let skill = fromBlock ? nil : activity.skillId.map(model.skillName)
        guard let stage = activity.stageId ?? activity.skillId.flatMap(model.stageId(ofSkill:)) else {
            return skill ?? ""
        }
        return Display.Activity.place(skill: skill, stage: model.stageTitle(stage))
    }

    private func fact(_ text: String, symbol: String) -> some View {
        Label {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
        }
    }

    /// The block this activity was reached from: its skills and step range,
    /// then the guide's notes.
    private func blockFacts(_ block: BlockFacts) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Display.block(block.kind))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if !block.skillIds.isEmpty {
                Text([block.skillIds.map(model.skillName).joined(separator: ", "),
                      Display.stepRange(block.stepRange)].compactMap { $0 }.joined(separator: " · "))
            }
            ForEach(block.notes, id: \.self) { note in
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
