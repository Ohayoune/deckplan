//
//  TodayView.swift
//  DeckPlan
//
//  Today is the lesson dated today (DECISIONS_LOG 2026-09-12): when a class
//  has a lesson on the device's calendar day the tab is that day's plan
//  itself, with a row of class chips when two lessons share the day —
//  tap to switch, hold one and slide it to reorder them (DECISIONS_LOG
//  2026-09-13) — otherwise one "Next: …" line opens the nearest lesson
//  ahead. No day is ever missed: every day through today saves itself
//  (DECISIONS_LOG 2026-09-13, "A day saves itself"). The Core takes the date
//  as an argument; this screen reads the clock (`Display.isoToday`) when it
//  appears and whenever the app becomes active.
//

import SwiftUI
import DeckPlanCore

struct TodayView: View {
    let model: AppModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var date = Display.isoToday()
    @State private var chosenClassId: String?
    @State private var creating = false
    /// The classes' chip order the owner last dragged to (session-only).
    @State private var classOrder: [String] = []

    var body: some View {
        let lessons = model.isReady ? model.todayLessons(on: date) : []
        Group {
            if let lesson = lessons.first(where: { $0.classId == chosenClassId }) ?? lessons.first {
                DayPlanView(model: model, classId: lesson.classId, n: lesson.n,
                            inToday: true, namesClass: lessons.count == 1) {
                    if lessons.count > 1 {
                        classPicker(lessons, selected: lesson.classId)
                    }
                }
                .id(lesson.classId)
            } else {
                noLessonToday
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { date = Display.isoToday() }
        }
        .sheet(isPresented: $creating) {
            ClassFormView(model: model, mode: .create)
        }
    }

    /// Two lessons share today: one chip per class, in the owner's last
    /// dragged order (class order the first time; DECISIONS_LOG 2026-09-13).
    /// A tap switches the plan at once, with no crossfade.
    private func classPicker(_ lessons: [Classes.LessonRef], selected: String) -> some View {
        ClassChipRow(classIds: orderedClassIds(lessons), selected: selected,
                     name: { model.swimClass($0)?.name ?? "" },
                     select: { chosenClassId = $0 },
                     reorder: { classOrder = $0 })
            .padding(.bottom, 12)
    }

    /// `lessons`' classIds in the order last dragged to, a class new to today
    /// appended at the end and one no longer sharing the day dropped.
    private func orderedClassIds(_ lessons: [Classes.LessonRef]) -> [String] {
        let ids = lessons.map(\.classId)
        let known = classOrder.filter(ids.contains)
        return known + ids.filter { !known.contains($0) }
    }

    /// No lesson today: the curriculum or store problem, then the empty state
    /// or the "Next: …" line.
    private var noLessonToday: some View {
        List {
            if !model.curriculumStatus.canPlan {
                Section {
                    CurriculumWarningRow(status: model.curriculumStatus)
                }
            } else if case .failed = model.storeStatus {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Display.General.storeCouldntOpen)
                            Text(Display.General.seeDiagnostics)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }

            if model.isReady {
                if model.classes.isEmpty {
                    emptyState(Display.Today.noClasses)
                } else if let next = model.nextLesson(on: date) {
                    Section {
                        NavigationLink(value: ClassDay(classId: next.classId, n: next.n)) {
                            Label(Display.Today.next(next.date, model.swimClass(next.classId)?.name ?? ""),
                                  systemImage: "calendar")
                        }
                    }
                } else {
                    emptyState(Display.Today.noLessonsAhead, description: Display.Today.noLessonsAheadHint)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Display.Today.title)
    }

    /// One sentence and the one action.
    private func emptyState(_ title: String, description: String? = nil) -> some View {
        Section {
            ContentUnavailableView {
                Label(title, systemImage: "figure.pool.swim")
            } description: {
                if let description {
                    Text(description)
                }
            } actions: {
                Button(Display.Today.createClass) { creating = true }
                    .buttonStyle(.borderedProminent)
            }
            .listRowBackground(Color.clear)
        }
    }
}

/// Today's class chips (DECISIONS_LOG 2026-09-13): tap one to open its class's
/// plan; swipe the row sideways when they don't all fit; hold one for a
/// moment, then slide it along the row to reorder. The
/// drag is this row's own gesture state, so the plan under it is not redrawn
/// while a chip moves, and the new order goes back to Today once, on release.
private struct ClassChipRow: View {
    let classIds: [String]
    let selected: String
    let name: (String) -> String
    let select: (String) -> Void
    let reorder: ([String]) -> Void

    private struct Hold: Equatable {
        var classId: String
        /// How far the finger has slid since the chip lifted.
        var x: CGFloat
    }

    private static let spacing: CGFloat = 8
    /// A hold let go after sliding less than this is a tap.
    private static let tapSlop: CGFloat = 4

    /// iOS 18 and later: the hold is a UIKit long press (`HoldAndSlide`),
    /// which leaves the row free to scroll until it lifts a chip. SwiftUI's
    /// long press sequenced before a drag took every touch on the row, with
    /// `.gesture` or `.simultaneousGesture`, so the row never scrolled.
    @State private var liftedHold: Hold?
    /// iOS 17: SwiftUI's hold-and-slide. Reset when the touch ends or is
    /// cancelled; the chips then settle with the same spring that moves them.
    @GestureState(resetTransaction: Transaction(animation: .snappy(duration: 0.25)))
    private var gestureHold: Hold? = nil
    @State private var widths: [String: CGFloat] = [:]

    private var hold: Hold? { liftedHold ?? gestureHold }

    var body: some View {
        let target = hold.map { targetIndex($0) }
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.spacing) {
                    ForEach(Array(classIds.enumerated()), id: \.element) { index, classId in
                        chip(classId, offset: offset(at: index, target: target))
                    }
                }
                .padding(2)
            }
            .scrollDisabled(hold != nil)
            // A switch rebuilds the day under Today's `.id`, this row with it,
            // so the new row opens on the chosen chip, not back at the first.
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
        }
        .sensoryFeedback(.selection, trigger: target)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Display.Today.classPicker)
    }

    private func chip(_ classId: String, offset: CGFloat) -> some View {
        let isSelected = classId == selected
        let isHeld = classId == hold?.classId
        let label = Text(name(classId))
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground),
                        in: Capsule())
            .contentShape(Capsule())
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { widths[classId] = $0 }
            .scaleEffect(isHeld ? 1.06 : 1)
            .shadow(color: .black.opacity(isHeld ? 0.18 : 0), radius: 6, y: 2)
            .offset(x: offset)
            // The held chip tracks the finger; the others glide aside.
            .animation(isHeld ? nil : .snappy(duration: 0.2), value: offset)
            .zIndex(isHeld ? 1 : 0)
        // The tap is its own gesture, not the hold's fallback: behind
        // `exclusively(before:)` a quick tap never fired, since a hold let go
        // early does not fail in time for it (DECISIONS_LOG 2026-09-13).
        return holdToMove(label, classId)
            .simultaneousGesture(TapGesture().onEnded { select(classId) })
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            .accessibilityAction { select(classId) }
    }

    /// Hold for a moment, then slide; letting go without sliding is a tap.
    @ViewBuilder
    private func holdToMove(_ label: some View, _ classId: String) -> some View {
        if #available(iOS 18.0, *) {
            label.gesture(HoldAndSlide(
                slide: { x in
                    var transaction = Transaction()
                    if liftedHold == nil { transaction.animation = .snappy(duration: 0.2) }
                    withTransaction(transaction) { liftedHold = Hold(classId: classId, x: x) }
                },
                release: { x in
                    if let x { letGo(classId, x: x) }
                    withAnimation(.snappy(duration: 0.25)) { liftedHold = nil }
                }))
        } else {
            label.gesture(holdAndSlide(classId))
        }
    }

    /// iOS 17's hold-and-slide, in SwiftUI gestures.
    private func holdAndSlide(_ classId: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($gestureHold) { value, state, transaction in
                guard case .second(true, let drag) = value else { return }
                if state == nil { transaction.animation = .snappy(duration: 0.2) }
                state = Hold(classId: classId, x: drag?.translation.width ?? 0)
            }
            .onEnded { value in
                guard case .second(true, let drag) = value else { return }
                letGo(classId, x: drag?.translation.width ?? 0)
            }
    }

    /// A hold let go after sliding less than `tapSlop` is a tap; else a drop.
    private func letGo(_ classId: String, x: CGFloat) {
        if abs(x) < Self.tapSlop {
            select(classId)
        } else {
            drop(classId, x: x)
        }
    }

    /// Each chip's middle along the row, from the measured widths.
    private var middles: [CGFloat] {
        var left: CGFloat = 0
        return classIds.map { classId in
            let width = widths[classId] ?? 0
            defer { left += width + Self.spacing }
            return left + width / 2
        }
    }

    /// Where the held chip would land: after every other chip whose middle
    /// its own middle has passed.
    private func targetIndex(_ hold: Hold) -> Int {
        guard let from = classIds.firstIndex(of: hold.classId) else { return 0 }
        let centers = middles
        let held = centers[from] + hold.x
        return centers.indices.filter { $0 != from && centers[$0] < held }.count
    }

    /// The held chip sits under the finger; the chips between its slot and
    /// its target step aside by its width.
    private func offset(at index: Int, target: Int?) -> CGFloat {
        guard let hold, let target, let from = classIds.firstIndex(of: hold.classId) else { return 0 }
        if index == from { return hold.x }
        let step = (widths[hold.classId] ?? 0) + Self.spacing
        if from < index, index <= target { return -step }
        if target <= index, index < from { return step }
        return 0
    }

    private func drop(_ classId: String, x: CGFloat) {
        guard let from = classIds.firstIndex(of: classId) else { return }
        let to = targetIndex(Hold(classId: classId, x: x))
        guard to != from else { return }
        var ids = classIds
        ids.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        withAnimation(.snappy(duration: 0.25)) { reorder(ids) }
    }
}

/// A chip's hold as a UIKit long press, which gives way to the row's
/// scrolling: a finger that moves before the 0.2 s hold is up scrolls the row,
/// and one that holds still lifts the chip, then tracks the slide while the
/// row stays put (the lifted press keeps the scroll view's pan from starting).
@available(iOS 18.0, *)
private struct HoldAndSlide: UIGestureRecognizerRepresentable {
    /// How far the finger has slid since the chip lifted.
    let slide: (CGFloat) -> Void
    /// On release, how far it slid; nil when the touch was cancelled.
    let release: (CGFloat?) -> Void

    final class Recognizer: UILongPressGestureRecognizer {
        var startX: CGFloat = 0
    }

    func makeUIGestureRecognizer(context: Context) -> Recognizer {
        let recognizer = Recognizer()
        recognizer.minimumPressDuration = 0.2
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: Recognizer, context: Context) {
        let x = recognizer.location(in: nil).x
        switch recognizer.state {
        case .began:
            recognizer.startX = x
            slide(0)
        case .changed:
            slide(x - recognizer.startX)
        case .ended:
            release(x - recognizer.startX)
        default:
            release(nil)
        }
    }
}

struct CurriculumWarningRow: View {
    let status: CurriculumStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(Display.General.planningOff)
                    .font(.headline)
                Text(status.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Display.General.seeDiagnostics)
                    .font(.footnote)
                    .foregroundStyle(.tint)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}
