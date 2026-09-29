//
//  ClassFormView.swift
//  DeckPlan
//
//  Create or edit a class (docs/REDESIGN.md §2 Class, §5 defaults): stage,
//  age group, weekdays, first date, lessons, name. The Core checks the form
//  and names the class when the name is left empty. Cancel on the left, the
//  confirming action on the right; while Create is disabled the footer under
//  the weekday row says why, and a value with one choice is text, not a
//  picker (DECISIONS_LOG 2026-09-12, "The plan is the product").
//

import SwiftUI
import DeckPlanCore

enum ClassFormMode {
    case create
    case edit(classId: String)
}

struct ClassFormView: View {
    let model: AppModel
    let mode: ClassFormMode

    @Environment(\.dismiss) private var dismiss
    @State private var form: ClassForm
    @State private var problems: [Problem] = []
    @State private var busy = false

    init(model: AppModel, mode: ClassFormMode) {
        self.model = model
        self.mode = mode
        switch mode {
        case .create:
            let stageId = model.stageChoices.first?.id ?? "1"
            _form = State(initialValue: ClassForm(stageId: stageId,
                                                  ageGroup: model.ageGroups(of: stageId).first ?? "",
                                                  firstDate: Display.isoToday()))
        case .edit(let classId):
            if let swimClass = model.swimClass(classId) {
                _form = State(initialValue: ClassForm(swimClass))
            } else {
                _form = State(initialValue: ClassForm(stageId: "1", ageGroup: "", firstDate: Display.isoToday()))
            }
        }
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.stageChoices.count > 1 {
                        Picker(Display.ClassesWords.stage, selection: $form.stageId) {
                            ForEach(model.stageChoices, id: \.id) { stage in
                                Text(Display.Finder.stageTitle(stage.id, stage.name)).tag(stage.id)
                            }
                        }
                    } else {
                        LabeledContent(Display.ClassesWords.stage, value: model.stageTitle(form.stageId))
                    }
                    let groups = model.ageGroups(of: form.stageId)
                    if groups.count > 1 {
                        Picker(Display.ClassesWords.ageGroup, selection: $form.ageGroup) {
                            ForEach(groups, id: \.self) { group in
                                Text(Display.ageGroup(group)).tag(group)
                            }
                        }
                    } else {
                        LabeledContent(Display.ClassesWords.ageGroup, value: Display.ageGroup(form.ageGroup))
                    }
                }

                Section {
                    // Seven equal cells, so the row fits an iPhone form (DECISIONS_LOG
                    // 2026-09-12, the weekday row bug).
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(Schedule.weekdayNames, id: \.self) { day in
                            weekdayCell(day)
                        }
                    }
                    .padding(.vertical, 4)
                    DatePicker(Display.ClassesWords.firstLesson, selection: firstDate, displayedComponents: .date)
                    Stepper(Display.ClassesWords.lessonsStepper(form.lessons), value: $form.lessons, in: 1...20)
                } header: {
                    Text(Display.ClassesWords.schedule)
                } footer: {
                    if form.weekdays.isEmpty {
                        Text(Display.ClassesWords.pickAtLeastOneDay)
                    }
                }

                Section {
                    TextField(model.defaultClassName(form), text: $form.name)
                } header: {
                    Text(Display.ClassesWords.name)
                } footer: {
                    Text(Display.ClassesWords.leaveEmptyFor(model.defaultClassName(form)))
                }

                if !problems.isEmpty {
                    Section(isEdit ? Display.ClassesWords.couldntSave : Display.ClassesWords.couldntCreate) {
                        ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                            Text(Display.problem(problem))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(isEdit ? Display.ClassesWords.editClass : Display.ClassesWords.newClass)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Display.General.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? Display.ClassesWords.save : Display.ClassesWords.create) { submit() }
                        .disabled(busy || form.weekdays.isEmpty)
                }
            }
            .onChange(of: form.stageId) { _, stageId in
                let groups = model.ageGroups(of: stageId)
                if !groups.contains(form.ageGroup) {
                    form.ageGroup = groups.first ?? ""
                }
            }
        }
    }

    private func weekdayCell(_ day: String) -> some View {
        let on = form.weekdays.contains(day)
        let shape = RoundedRectangle(cornerRadius: 8)
        return Button {
            if on { form.weekdays.remove(day) } else { form.weekdays.insert(day) }
        } label: {
            Text(Display.weekdayLetters[day] ?? day)
                .fontWeight(on ? .semibold : .regular)
                .foregroundStyle(on ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? Color.accentColor : Color.clear, in: shape)
                .overlay(shape.stroke(on ? Color.accentColor : Color.secondary.opacity(0.4)))
                .contentShape(shape)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Display.weekdayFullNames[day] ?? day)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var firstDate: Binding<Date> {
        Binding(get: { Display.date(fromISO: form.firstDate) },
                set: { form.firstDate = Display.iso(from: $0) })
    }

    private func submit() {
        busy = true
        Task {
            let result: [Problem]
            switch mode {
            case .create:
                result = await model.createClass(form)
            case .edit(let classId):
                result = await model.updateClass(classId, with: form)
            }
            busy = false
            problems = result
            if result.isEmpty { dismiss() }
        }
    }
}
