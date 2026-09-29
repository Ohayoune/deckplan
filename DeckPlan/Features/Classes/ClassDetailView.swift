//
//  ClassDetailView.swift
//  DeckPlan
//
//  One class (docs/REDESIGN.md §5, §3.6): the facts under its name, each
//  said once; every day 1..N to revisit, marked Saved, Edited, Not saved (its
//  date passed without a save) or Next; Edit and Delete. The class's order is
//  on the Diagnostics screen (DECISIONS_LOG 2026-09-12, "The plan is the
//  product").
//

import SwiftUI
import DeckPlanCore

struct ClassDetailView: View {
    let model: AppModel
    let classId: String

    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var pendingDelete: SwimClass?

    private var swimClass: SwimClass? { model.swimClass(classId) }

    var body: some View {
        Group {
            if let swimClass {
                content(swimClass)
            } else {
                ContentUnavailableView(Display.ClassesWords.deleted, systemImage: "person.3")
            }
        }
        .navigationTitle(swimClass?.name ?? Display.ClassesWords.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ swimClass: SwimClass) -> some View {
        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.classSummary(swimClass).enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .foregroundStyle(index == 0 ? .primary : .secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(Display.ClassesWords.lessonDays) {
                ForEach(Array(1...max(1, swimClass.lessons)), id: \.self) { n in
                    NavigationLink(value: ClassDay(classId: swimClass.id, n: n)) {
                        DayRow(n: n, date: model.lessonDate(swimClass, n),
                               status: model.dayStatus(swimClass, n: n))
                    }
                }
            }

            Section {
                Button(Display.ClassesWords.deleteClass, role: .destructive) {
                    pendingDelete = swimClass
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(Display.General.edit) { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            ClassFormView(model: model, mode: .edit(classId: classId))
        }
        .deleteClassDialog(model: model, pending: $pendingDelete) {
            dismiss()
        }
    }
}

/// Day n, its date, and the day list's mark for it.
private struct DayRow: View {
    let n: Int
    let date: String?
    let status: DayStatus

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Display.day(n))
                Text(Display.date(date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            mark
                .font(.subheadline)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mark: some View {
        switch status {
        case .done:
            label(Display.ClassesWords.doneDay, symbol: "checkmark.circle.fill", tint: .green)
        case .edited:
            label(Display.ClassesWords.editedDay, symbol: "pencil.circle", tint: .orange)
        case .next:
            Text(Display.ClassesWords.nextDay)
                .foregroundStyle(.tint)
        case .later:
            EmptyView()
        }
    }

    private func label(_ text: String, symbol: String, tint: Color) -> some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
    }
}
