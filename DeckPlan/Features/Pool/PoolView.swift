//
//  PoolView.swift
//  DeckPlan
//
//  The one pool profile (docs/REDESIGN.md §2, §3.2; DECISIONS_LOG 2026-09-12,
//  "The pool profile lists pool equipment, not props"): Depth, Diving, Tot
//  dock, then the five profile items in catalog order, nothing else. Props
//  (goggles, a balloon) are never here; they are always on for the filter and
//  named on the activity's page. Every change is written at once and applies
//  everywhere the same filter runs (plan, shuffle, finder, search, browse).
//

import SwiftUI
import DeckPlanCore

struct PoolView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(Display.PoolWords.shallow, isOn: depth("shallow"))
                Toggle(Display.PoolWords.medium, isOn: depth("medium"))
                Toggle(Display.PoolWords.deep, isOn: depth("deep"))
            } header: {
                Text(Display.PoolWords.depth)
            } footer: {
                Text(Display.PoolWords.depthFooter)
            }

            Section {
                Toggle(Display.PoolWords.diving, isOn: Binding(
                    get: { model.pool.diving },
                    set: { value in update { $0.diving = value } }))
                Toggle(Display.PoolWords.totDock, isOn: Binding(
                    get: { model.pool.totDock },
                    set: { value in update { $0.totDock = value } }))
            } footer: {
                Text(Display.PoolWords.divingFooter)
            }

            Section {
                ForEach(model.profileEquipment, id: \.id) { item in
                    Toggle(item.name.capitalizedFirst, isOn: Binding(
                        get: { model.pool.equipment[item.id] ?? false },
                        set: { value in update { $0.equipment[item.id] = value } }))
                }
            } header: {
                Text(Display.PoolWords.equipment)
            } footer: {
                Text(Display.PoolWords.equipmentFooter)
            }
        }
        .navigationTitle(Display.PoolWords.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func depth(_ zone: String) -> Binding<Bool> {
        Binding(get: { Activities.depthOn(model.pool, zone) },
                set: { value in update { $0.depths[zone] = value } })
    }

    private func update(_ change: @escaping (inout Pool) -> Void) {
        var pool = model.pool
        change(&pool)
        Task { await model.commit(pool: pool) }
    }
}
