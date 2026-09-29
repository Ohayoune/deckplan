//
//  DayPlanView.swift
//  DeckPlan
//
//  A class's day k (docs/REDESIGN.md §3; DECISIONS_LOG 2026-09-12, "The plan
//  is the product"): the day and date in the navigation title and subtitle, a
//  header naming the class and stage once, then the blocks as a timeline —
//  name and minutes on one line, the block's activity as a card with the
//  first sentence of its description and Shuffle; the card opens the
//  activity, where Add from the finder lives, and Edit (toolbar) removes and
//  reorders. There is no Save: a day saves itself on its date, and every
//  change to a saved day is saved at once; a later day's changes wait in the
//  class's one draft (DECISIONS_LOG 2026-09-13, "A day saves itself").
//  Welcome and Topic are drawn only when Settings turns them on; Review
//  always, its card naming the day's review skills as the guide lists them
//  (DECISIONS_LOG 2026-09-13, "Review is back"), and after Introduce unless
//  Settings asks for the guide's order ("Introduce before Review"). On the
//  Today tab the title is "Today" and the header names the day.
//

import SwiftUI
import DeckPlanCore

struct DayPlanView<Top: View>: View {
    let model: AppModel
    let classId: String
    let n: Int
    /// On the Today tab: the title is "Today" and the header says "Day k of N".
    let inToday: Bool
    /// False when the class's name is already on screen (Today's class picker).
    let namesClass: Bool
    /// Today's class picker, above the header.
    let top: Top

    /// The sentence per block after a shuffle ("No more new activities for
    /// this block."), while the day is on screen.
    @State private var blockMessages: [String: String] = [:]
    @State private var addTarget: DayBlockRef?
    @State private var alert: AlertText?
    @State private var editing = false

    init(model: AppModel, classId: String, n: Int, inToday: Bool = false, namesClass: Bool = true,
         @ViewBuilder top: () -> Top) {
        self.model = model
        self.classId = classId
        self.n = n
        self.inToday = inToday
        self.namesClass = namesClass
        self.top = top()
    }

    private var swimClass: SwimClass? { model.swimClass(classId) }

    var body: some View {
        let plan = model.plan(classId: classId, n: n)
        Group {
            if let swimClass, let plan {
                content(swimClass, plan)
            } else {
                ContentUnavailableView {
                    Label(Display.Plan.noPlan(n), systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text(model.planProblems(classId: classId, n: n).map(Display.problem).joined(separator: "\n"))
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .dateSubtitle(Display.date(plan?.date))
        .alert($alert)
    }

    private var title: String {
        if inToday { return Display.Today.title }
        guard let swimClass else { return Display.day(n) }
        return Display.dayOf(n, swimClass.lessons)
    }

    private func content(_ swimClass: SwimClass, _ plan: DayPlan) -> some View {
        let blocks = model.visibleBlocks(plan)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                top
                header(swimClass, plan)
                    .padding(.bottom, 16)
                ForEach(Array(blocks.enumerated()), id: \.element.kind) { index, block in
                    blockView(block, stageId: swimClass.stageId, isLast: index == blocks.count - 1)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? Display.General.done : Display.General.edit) {
                    withAnimation { editing.toggle() }
                }
            }
        }
        .finderSheet(model: model, target: $addTarget)
    }

    /// The class and stage, each once: a default name already says the stage
    /// number, so the stage's name follows it; on Today the day too, and the
    /// date where the navigation bar has no subtitle.
    private func header(_ swimClass: SwimClass, _ plan: DayPlan) -> some View {
        let stage = model.usesDefaultName(swimClass)
            ? model.stageName(swimClass.stageId) : model.stageTitle(swimClass.stageId)
        let facts = [stage,
                     inToday ? Display.dayOf(plan.n, swimClass.lessons) : nil,
                     Display.subtitleInHeader ? Display.date(plan.date) : nil].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 2) {
            if namesClass {
                Text(swimClass.name)
                    .font(.title3.weight(.semibold))
            }
            Text(facts.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Blocks

    private func blockView(_ block: PlanBlock, stageId: String, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Display.blockHeader(block.kind, minutes: block.minutes))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    if isBare(block) && block.kind != "topic" {
                        Button {
                            addTarget = DayBlockRef(classId: classId, n: n, kind: block.kind)
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Display.Plan.addFromFinder)
                    }
                }
            if !isBare(block) {
                card(block, stageId: stageId)
            }
            if let message = blockMessages[block.kind] {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 22)
        .padding(.bottom, isLast ? 8 : 20)
        .background(alignment: .topLeading) {
            TimelineRail(isLast: isLast)
        }
    }

    /// A block the guide gives no minutes and that shows nothing: its line
    /// alone, with a small Add, so the day still fits one screen. A block the
    /// instructor emptied keeps its card.
    private func isBare(_ block: PlanBlock) -> Bool {
        block.activityIds.isEmpty && !block.awaitsPick && block.topic == nil && (block.minutes ?? 0) == 0
    }

    private func card(_ block: PlanBlock, stageId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let topic = block.topic {
                VStack(alignment: .leading, spacing: 4) {
                    Text(topic.name)
                        .font(.body.weight(.semibold))
                    Text(topic.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Review's skills are the point of the block, and one activity
            // names only one of them: the guide's list, in its order.
            if block.kind == "review" && !block.awaitsPick && !block.skillIds.isEmpty {
                Text(block.skillIds.map(model.skillName).joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
            }

            if block.awaitsPick {
                Menu {
                    ForEach(block.skillChoices ?? [], id: \.self) { skillId in
                        Button(model.skillName(skillId)) { pick(block, skillId) }
                    }
                } label: {
                    Label(Display.Plan.pickSkill, systemImage: "hand.point.up.left")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
            } else if block.activityIds.isEmpty && block.kind != "topic" {
                Text(Display.Plan.emptyBlock)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    addTarget = DayBlockRef(classId: classId, n: n, kind: block.kind)
                } label: {
                    Label(Display.Plan.addFromFinder, systemImage: "plus")
                        .frame(minHeight: 44)
                }
            }

            ForEach(Array(block.activityIds.enumerated()), id: \.element) { index, activityId in
                if index > 0 {
                    Divider()
                }
                activityRow(block, activityId: activityId, index: index, stageId: stageId)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// One activity: its name and first sentence open its page; Shuffle on the
    /// first, saved day or not; remove and move while editing.
    private func activityRow(_ block: PlanBlock, activityId: String, index: Int, stageId: String) -> some View {
        let name = model.activityName(activityId)
        let sentence = model.activityFirstSentence(activityId)
        let hidden = block.hidden?.contains(activityId) ?? false
        let canAdd = block.kind != "topic" && !block.awaitsPick
        let ref = ActivityRef(id: activityId, skillId: block.skillIds.first, stageId: stageId,
                              block: BlockFacts(block),
                              day: canAdd ? DayBlockRef(classId: classId, n: n, kind: block.kind) : nil)
        return HStack(spacing: 8) {
            if editing {
                Button {
                    remove(block, activityId)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Display.Plan.removeNamed(name))
            }

            NavigationLink(value: ref) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.body.weight(.semibold))
                        if !sentence.isEmpty {
                            Text(sentence)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if hidden {
                            Text(Display.Plan.hiddenNow)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if editing {
                if block.activityIds.count > 1 {
                    moveButton(block, from: index, to: index - 1, symbol: "arrow.up", label: Display.Plan.moveUp)
                    moveButton(block, from: index, to: index + 1, symbol: "arrow.down", label: Display.Plan.moveDown)
                }
            } else if index == 0 {
                Button {
                    shuffle(block)
                } label: {
                    Image(systemName: "shuffle")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Display.Plan.shuffleBlock(Display.block(block.kind)))
            }
        }
    }

    private func moveButton(_ block: PlanBlock, from: Int, to: Int, symbol: String, label: String) -> some View {
        Button {
            move(block, from: from, to: to)
        } label: {
            Image(systemName: symbol)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(to < 0 || to >= block.activityIds.count)
        .accessibilityLabel(label)
    }

    // MARK: Actions

    private func shuffle(_ block: PlanBlock) {
        Task {
            let outcome = await model.shuffle(classId: classId, n: n, kind: block.kind)
            if outcome.ok {
                blockMessages[block.kind] = outcome.message
            } else {
                alert = AlertText(title: Display.Plan.couldntShuffle, message: outcome.message ?? Display.General.notSaved)
            }
        }
    }

    private func pick(_ block: PlanBlock, _ skillId: String) {
        run(Display.Plan.couldntPick) {
            await model.pickSkill(classId: classId, n: n, kind: block.kind, skillId: skillId)
        }
    }

    private func remove(_ block: PlanBlock, _ activityId: String) {
        run(Display.Plan.couldntRemove) {
            await model.removeActivity(classId: classId, n: n, kind: block.kind, activityId: activityId)
        }
    }

    private func move(_ block: PlanBlock, from: Int, to: Int) {
        run(Display.Plan.couldntMove) {
            await model.moveActivity(classId: classId, n: n, kind: block.kind, from: from, to: to)
        }
    }

    private func run(_ failureTitle: String, _ action: @escaping @MainActor () async -> PlanOutcome) {
        Task {
            let outcome = await action()
            if !outcome.ok {
                alert = AlertText(title: failureTitle, message: outcome.message ?? Display.General.notSaved)
            }
        }
    }

}

extension DayPlanView where Top == EmptyView {
    /// A day reached from a class's days or the Next line.
    init(model: AppModel, classId: String, n: Int) {
        self.init(model: model, classId: classId, n: n, top: { EmptyView() })
    }
}

/// The timeline beside a day's blocks: a dot at the block's name and a line
/// down to the next block.
private struct TimelineRail: View {
    let isLast: Bool
    @ScaledMetric(relativeTo: .headline) private var dotTop: CGFloat = 6

    var body: some View {
        ZStack(alignment: .top) {
            if !isLast {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 2)
                    .padding(.top, dotTop + 5)
            }
            Circle()
                .fill(.tint)
                .frame(width: 10, height: 10)
                .padding(.top, dotTop)
        }
        .frame(width: 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}
