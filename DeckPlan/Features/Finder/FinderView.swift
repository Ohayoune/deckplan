//
//  FinderView.swift
//  DeckPlan
//
//  The activity finder (docs/REDESIGN.md §4; DECISIONS_LOG 2026-09-12,
//  "Finder is stage → skill → activities" and "The plan is the product"): a
//  stage, one of its skills, and the skill's activities by name, three at a
//  time in a seeded order; "More" shows the next three. A search field finds
//  the stage's activities by name, grouped by skill (F7). The Finder tab's
//  stage picker opens on today's class's stage, else the one last chosen
//  (`Settings.finderStageId`), but activities stay hidden behind a prompt
//  until the owner has picked a stage (when there is more than one) and a
//  skill this time — no more auto-opening on a remembered or default skill
//  (DECISIONS_LOG 2026-09-13). Opened for a day's block (pick mode) the stage
//  is the class's, shown as text, and a skill is already implied by the
//  block, so activities show at once; the age group applies; Add puts an
//  activity in the block and keeps the sheet open. The pool profile always
//  applies.
//

import SwiftUI
import DeckPlanCore

enum FinderContext {
    /// The Finder tab: any stage, all ages.
    case standalone
    /// A sheet for one block of a class's day: the class's stage and age tag,
    /// the block's skill first, and Add on every row.
    case pick(DayBlockRef)
}

struct FinderView: View {
    let model: AppModel
    let context: FinderContext

    /// The stage and skill chosen on this screen; nil until the owner picks
    /// one, so the defaults follow the store once it has loaded.
    @State private var chosenStage: String?
    @State private var chosenSkill: String?
    @State private var pageNumber = 1
    @State private var searchText = ""
    @State private var alert: AlertText?

    private var target: DayBlockRef? {
        if case .pick(let ref) = context { return ref }
        return nil
    }

    private var targetClass: SwimClass? { target.flatMap { model.swimClass($0.classId) } }

    private var ageTag: String? { targetClass.flatMap { model.ageTag($0) } }

    private var stageId: String {
        if let targetClass { return targetClass.stageId }
        return chosenStage ?? model.initialFinderStage(on: Display.isoToday())
    }

    private var title: String {
        target.map { Display.Finder.addTo(Display.block($0.kind)) } ?? Display.Finder.title
    }

    /// True once there is enough to browse by: pick mode always has the
    /// class's stage and the block's skill; the Finder tab needs the owner to
    /// have chosen both this time (DECISIONS_LOG 2026-09-13) — a stage that is
    /// the curriculum's only one counts as chosen.
    private var readyToBrowse: Bool {
        target != nil || ((chosenStage != nil || model.stageChoices.count < 2) && chosenSkill != nil)
    }

    var body: some View {
        let block = target.flatMap { ref in
            model.plan(classId: ref.classId, n: ref.n)?.blocks.first { $0.kind == ref.kind }
        }
        let stage = stageId
        let skill = model.finderSkill(stageId: stage, preferred: chosenSkill ?? block?.skillIds.first)
        let added = Set(block?.activityIds ?? [])
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        List {
            if model.planningCurriculum == nil {
                Text(Display.General.notReady)
                    .foregroundStyle(.secondary)
            } else if query.isEmpty {
                Section {
                    stageRow(stage)
                    Picker(Display.Finder.skill, selection: Binding(get: { skill }, set: { choose(skill: $0) })) {
                        ForEach(model.skillChoices(of: stage), id: \.id) { choice in
                            Text(choice.name).tag(choice.id)
                        }
                    }
                }
                if readyToBrowse {
                    results(stage: stage, skill: skill, added: added)
                } else {
                    Section {
                        Text(Display.Finder.choosePrompt)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    NavigationLink(value: BrowseRoute(stageId: stage, ageTag: ageTag)) {
                        Label(Display.Finder.browse, systemImage: "books.vertical")
                    }
                }
            } else {
                Section {
                    stageRow(stage)
                }
                searchResults(stage: stage, text: query, added: added)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(target == nil ? .large : .inline)
        .searchable(text: $searchText, prompt: Display.Finder.searchPrompt)
        .alert($alert)
    }

    /// The stage: a picker on the Finder tab; text when it cannot change (a
    /// class's day, or one stage loaded).
    @ViewBuilder
    private func stageRow(_ stage: String) -> some View {
        if target != nil || model.stageChoices.count < 2 {
            LabeledContent(Display.Finder.stage, value: model.stageTitle(stage))
        } else {
            Picker(Display.Finder.stage, selection: Binding(get: { stage }, set: { choose(stage: $0) })) {
                ForEach(model.stageChoices, id: \.id) { choice in
                    Text(Display.Finder.stageTitle(choice.id, choice.name)).tag(choice.id)
                }
            }
        }
    }

    /// One page of the skill's seeded list, and More when there are others.
    @ViewBuilder
    private func results(stage: String, skill: String, added: Set<String>) -> some View {
        let page = skill.isEmpty ? nil
            : model.find(stageId: stage, skillId: skill, ageTag: ageTag, pageNumber: pageNumber)
        if let page {
            Section {
                if page.activityIds.isEmpty {
                    Text(Display.Finder.noneForSkill)
                        .foregroundStyle(.secondary)
                }
                ForEach(page.activityIds, id: \.self) { activityId in
                    row(activityId, skillId: skill, stageId: stage, added: added)
                }
                if page.total > page.pageSize {
                    Button(Display.Finder.more) { pageNumber = page.page + 1 }
                }
            }
        }
    }

    /// The stage's activities named like the text, grouped by skill (F7).
    @ViewBuilder
    private func searchResults(stage: String, text: String, added: Set<String>) -> some View {
        let groups = model.search(stageId: stage, text: text, ageTag: ageTag)?.groups ?? []
        if groups.isEmpty {
            Section {
                Text(Display.Finder.nothingNamed(text))
                    .foregroundStyle(.secondary)
            }
        }
        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            Section(group.name) {
                ForEach(group.activityIds, id: \.self) { activityId in
                    row(activityId, skillId: group.skillId, stageId: stage, added: added)
                }
            }
        }
    }

    /// An activity by name, opening its page; in pick mode with Add, or
    /// "Added" once the block holds it.
    @ViewBuilder
    private func row(_ activityId: String, skillId: String?, stageId: String, added: Set<String>) -> some View {
        let name = model.activityName(activityId)
        let link = NavigationLink(value: ActivityRef(id: activityId, skillId: skillId, stageId: stageId)) {
            Text(name)
        }
        if let target {
            HStack(spacing: 12) {
                link
                if added.contains(activityId) {
                    Label(Display.Finder.added, systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button(Display.Finder.add) { add(activityId, to: target) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(Display.Finder.addNamed(name))
                }
            }
        } else {
            link
        }
    }

    private func choose(stage: String) {
        chosenStage = stage
        chosenSkill = nil
        pageNumber = 1
        Task { await model.rememberFinderStage(stage) }
    }

    private func choose(skill: String) {
        chosenSkill = skill
        pageNumber = 1
    }

    private func add(_ activityId: String, to ref: DayBlockRef) {
        Task {
            let outcome = await model.addActivity(classId: ref.classId, n: ref.n, kind: ref.kind,
                                                  activityId: activityId)
            if !outcome.ok {
                alert = AlertText(title: Display.Plan.couldntAdd, message: outcome.message ?? Display.General.notSaved)
            }
        }
    }
}

extension View {
    /// The finder as a sheet for one block of a class's day: Add keeps it open
    /// for another add; Done closes it.
    func finderSheet(model: AppModel, target: Binding<DayBlockRef?>) -> some View {
        sheet(item: target) { ref in
            NavigationStack {
                FinderView(model: model, context: .pick(ref))
                    .appDestinations(model)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(Display.General.done) { target.wrappedValue = nil }
                        }
                    }
            }
        }
    }
}
