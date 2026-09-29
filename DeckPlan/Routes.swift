//
//  Routes.swift
//  DeckPlan
//
//  Every value a NavigationStack can push, and the one modifier that
//  registers their destinations. Each tab's stack (and the finder sheet)
//  applies it once at its root.
//

import SwiftUI
import DeckPlanCore

/// A class's day k (a revisit from the class's days, a missed day, the next lesson).
struct ClassDay: Hashable {
    let classId: String
    let n: Int
}

/// The block of a class's day an activity was reached from: its page then
/// offers "Add another … from the finder" (DECISIONS_LOG 2026-09-12, "The
/// plan is the product").
struct DayBlockRef: Hashable, Identifiable {
    let classId: String
    let n: Int
    let kind: String

    var id: String { "\(classId)/\(n)/\(kind)" }
}

/// An activity's page, with the skill it was reached through (for the video
/// title, REDESIGN §4), its stage, and the day's block when reached from one.
struct ActivityRef: Hashable {
    let id: String
    let skillId: String?
    var stageId: String? = nil
    var block: BlockFacts? = nil
    var day: DayBlockRef? = nil
}

/// What a day's block says around its activities — skills, step range,
/// notes — shown on the activity's page, not on the day (DECISIONS_LOG
/// 2026-09-12, "A class day fits one screen").
struct BlockFacts: Hashable {
    let kind: String
    let skillIds: [String]
    let stepRange: [Int]?
    let notes: [String]

    init(_ block: PlanBlock) {
        kind = block.kind
        skillIds = block.skillIds
        stepRange = block.stepRange
        notes = block.notes ?? []
    }

    var isEmpty: Bool { skillIds.isEmpty && notes.isEmpty }
}

/// A class's own screen (edit, days, delete).
struct ClassRoute: Hashable {
    let classId: String
}

/// Browse of a stage's library, with the age tag when opened from a class.
struct BrowseRoute: Hashable {
    let stageId: String
    let ageTag: String?
}

enum SettingsRoute: Hashable {
    case pool
    case backup
    case diagnostics
}

/// What an alert says: a title that says what happened, and the sentence.
struct AlertText: Identifiable, Equatable {
    let title: String
    let message: String
    var id: String { title + "\n" + message }
}

extension View {
    func appDestinations(_ model: AppModel) -> some View {
        self
            .navigationDestination(for: ClassDay.self) { day in
                DayPlanView(model: model, classId: day.classId, n: day.n)
            }
            .navigationDestination(for: ActivityRef.self) { ref in
                ActivityDetailView(model: model, activity: ref)
            }
            .navigationDestination(for: ClassRoute.self) { route in
                ClassDetailView(model: model, classId: route.classId)
            }
            .navigationDestination(for: BrowseRoute.self) { route in
                BrowseView(model: model, stageId: route.stageId, ageTag: route.ageTag)
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .pool:
                    PoolView(model: model)
                case .backup:
                    BackupView(model: model)
                case .diagnostics:
                    DiagnosticsView(model: model)
                }
            }
    }

    /// One alert for the screens: the title says what happened.
    func alert(_ alert: Binding<AlertText?>) -> some View {
        self.alert(alert.wrappedValue?.title ?? "", isPresented: Binding(
            get: { alert.wrappedValue != nil },
            set: { if !$0 { alert.wrappedValue = nil } }
        ), presenting: alert.wrappedValue) { _ in
            Button(Display.General.ok) { alert.wrappedValue = nil }
        } message: { text in
            Text(text.message)
        }
    }

    /// The date under the title on iOS 26 and later; earlier systems show it
    /// in the header row instead (`Display.subtitleInHeader`).
    @ViewBuilder
    func dateSubtitle(_ text: String) -> some View {
        if #available(iOS 26.0, *) {
            self.navigationSubtitle(text)
        } else {
            self
        }
    }
}

extension Display {
    /// True when the navigation bar cannot show a subtitle, so the header
    /// row carries the date.
    static var subtitleInHeader: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }
}
