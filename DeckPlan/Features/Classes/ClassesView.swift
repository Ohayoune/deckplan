//
//  ClassesView.swift
//  DeckPlan
//
//  Classes (docs/REDESIGN.md §5): the list sorted by order then name, create,
//  and delete with a confirmation that names the classes. Each class is a
//  card; hold one and the cards jiggle, as apps do on the Home Screen, with a
//  circle on each to select several and delete them together (DECISIONS_LOG
//  2026-09-13, "Hold a class"). A card names the stage once and the days once
//  (DECISIONS_LOG 2026-09-12, "The plan is the product").
//

import SwiftUI
import DeckPlanCore

struct ClassesView: View {
    let model: AppModel

    @State private var creating = false
    @State private var opened: ClassRoute?
    /// Select mode: on from a hold until Done or a delete.
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if model.isReady && model.classes.isEmpty {
                ContentUnavailableView {
                    Label(Display.ClassesWords.noClasses, systemImage: "person.3")
                } description: {
                    Text(Display.ClassesWords.createFirst)
                } actions: {
                    Button(Display.ClassesWords.createClass) { creating = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(model.classes.enumerated()), id: \.element.id) { index, swimClass in
                            card(swimClass)
                                .modifier(Jiggle(isOn: selecting, beat: Jiggle.beat(index)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Display.ClassesWords.title)
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) {
            if selecting { deleteBar }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: selecting) { _, isOn in isOn }
        .navigationDestination(item: $opened) { route in
            ClassDetailView(model: model, classId: route.classId)
        }
        .sheet(isPresented: $creating) {
            ClassFormView(model: model, mode: .create)
        }
        // A class deleted elsewhere leaves the selection; none left ends it.
        .onChange(of: model.classes.map(\.id)) { _, ids in
            selected.formIntersection(ids)
            if ids.isEmpty { selecting = false }
        }
        .onDisappear { endSelecting() }
    }

    /// A class's card: outside select mode a tap opens it and a hold starts
    /// select mode with it ticked; in select mode a tap ticks or unticks it.
    @ViewBuilder
    private func card(_ swimClass: SwimClass) -> some View {
        let isSelected = selected.contains(swimClass.id)
        if selecting {
            Button {
                toggle(swimClass.id)
            } label: {
                ClassCard(model: model, swimClass: swimClass, mark: isSelected ? .ticked : .unticked)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            let route = ClassRoute(classId: swimClass.id)
            ClassCard(model: model, swimClass: swimClass, mark: .opens)
                // The tap is its own gesture beside the hold, as on Today's
                // chips. The hold swaps this card for its select-mode one
                // while the finger is still down, so letting go opens nothing.
                .holdToSelect { begin(swimClass.id) }
                .simultaneousGesture(TapGesture().onEnded { opened = route })
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { opened = route }
                .accessibilityAction(named: Display.ClassesWords.select) { begin(swimClass.id) }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) {
                let all = selected.count == model.classes.count
                Button(all ? Display.ClassesWords.deselectAll : Display.ClassesWords.selectAll) {
                    selected = all ? [] : Set(model.classes.map(\.id))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(Display.General.done) { endSelecting() }
                    .fontWeight(.semibold)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creating = true
                } label: {
                    Label(Display.ClassesWords.newClass, systemImage: "plus")
                }
                .disabled(!model.isReady)
            }
        }
    }

    /// Select mode's one action, at the foot: off with nothing ticked.
    private var deleteBar: some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Text(Display.ClassesWords.deleteSelected(selected.count))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
        .disabled(selected.isEmpty)
        // On the button, so the confirmation comes from it (a popover from
        // iOS 26), not from the middle of the list.
        .confirmationDialog(deleteWords.title, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(deleteWords.button, role: .destructive) {
                let ids = selected
                Task {
                    if await model.deleteClasses(ids) { endSelecting() }
                }
            }
        } message: {
            Text(deleteWords.message)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// The confirmation's words: one class is named as on its page (M5);
    /// several are counted, then named, with their saved days together.
    private var deleteWords: (title: String, button: String, message: String) {
        let chosen = model.classes.filter { selected.contains($0.id) }
        let savedDays = chosen.reduce(0) { $0 + $1.log.count }
        if chosen.count == 1 {
            return (Display.ClassesWords.deleteTitle(chosen[0].name), Display.ClassesWords.deleteClass,
                    Display.ClassesWords.deleteMessage(savedDays))
        }
        return (Display.ClassesWords.deleteSeveralTitle(chosen.count),
                Display.ClassesWords.deleteSelected(chosen.count),
                Display.ClassesWords.deleteSeveralMessage(chosen.map(\.name), savedDays))
    }

    private func begin(_ classId: String) {
        withAnimation(.snappy(duration: 0.25)) {
            selected = [classId]
            selecting = true
        }
    }

    private func toggle(_ classId: String) {
        if selected.remove(classId) == nil { selected.insert(classId) }
    }

    private func endSelecting() {
        withAnimation(.snappy(duration: 0.25)) {
            selecting = false
            selected = []
        }
    }
}

/// A class's name and the facts under it, each said once (`classSummary`).
struct ClassRow: View {
    let model: AppModel
    let swimClass: SwimClass

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(swimClass.name)
                .font(.headline)
            ForEach(model.classSummary(swimClass), id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

/// A class as a card: its row and a chevron; in select mode a circle on its
/// top-left corner, where an app on the Home Screen shows its minus.
private struct ClassCard: View {
    enum Mark { case opens, ticked, unticked }

    let model: AppModel
    let swimClass: SwimClass
    let mark: Mark

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    var body: some View {
        HStack(spacing: 12) {
            ClassRow(model: model, swimClass: swimClass)
            Spacer(minLength: 0)
            if mark == .opens {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: shape)
        .overlay {
            if mark == .ticked {
                shape.strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .overlay(alignment: .topLeading) {
            if mark != .opens {
                TickCircle(isOn: mark == .ticked)
                    .offset(x: -8, y: -8)
            }
        }
    }
}

/// Select mode's circle: empty, or ticked in the accent colour.
private struct TickCircle: View {
    let isOn: Bool

    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(isOn ? Color.white : Color.secondary, Color.accentColor)
            .background(Circle().fill(Color(.systemBackground)).padding(2))
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

/// The Home Screen's jiggle: each card rocks a little, quickly, on its own
/// beat; still under Reduce Motion.
private struct Jiggle: ViewModifier {
    let isOn: Bool
    /// Where in the rock the card starts, as a fraction of one rock.
    let beat: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A third of a degree: a card is some six times an app icon's width, so
    /// its ends move about a point, as an icon's corners do.
    private static let degrees = 0.35
    private static let period: TimeInterval = 0.28

    /// Neighbours start about half a rock apart, no two alike in a run of six.
    static func beat(_ index: Int) -> Double { [0, 0.5, 0.2, 0.7, 0.35, 0.85][index % 6] }

    func body(content: Content) -> some View {
        let rocking = isOn && !reduceMotion
        TimelineView(.animation(minimumInterval: nil, paused: !rocking)) { timeline in
            let turns = timeline.date.timeIntervalSinceReferenceDate / Self.period + beat
            content.rotationEffect(.degrees(rocking ? Self.degrees * sin(turns * 2 * .pi) : 0))
        }
    }
}

/// How long a card is held before select mode starts.
private let holdSeconds: TimeInterval = 0.5

private extension View {
    /// Hold a card to start select mode. iOS 18 and later: a UIKit long
    /// press, which gives way to the list's scrolling, as on Today's chips;
    /// iOS 17: SwiftUI's.
    @ViewBuilder
    func holdToSelect(_ begin: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) {
            gesture(HoldToSelect(began: begin))
        } else {
            simultaneousGesture(LongPressGesture(minimumDuration: holdSeconds).onEnded { _ in begin() })
        }
    }
}

@available(iOS 18.0, *)
private struct HoldToSelect: UIGestureRecognizerRepresentable {
    let began: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = holdSeconds
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if recognizer.state == .began { began() }
    }
}

extension View {
    /// The delete confirmation every class screen uses (REDESIGN §5, M5): it
    /// names the class and says its log goes with it.
    func deleteClassDialog(model: AppModel, pending: Binding<SwimClass?>,
                           afterDelete: @escaping @MainActor () -> Void = {}) -> some View {
        confirmationDialog(
            Display.ClassesWords.deleteTitle(pending.wrappedValue?.name ?? ""),
            isPresented: Binding(get: { pending.wrappedValue != nil },
                                 set: { if !$0 { pending.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { swimClass in
            Button(Display.ClassesWords.deleteClass, role: .destructive) {
                Task {
                    if await model.deleteClass(swimClass.id) {
                        afterDelete()
                    }
                }
            }
        } message: { swimClass in
            Text(Display.ClassesWords.deleteMessage(swimClass.log.count))
        }
    }
}
