//
//  Display.swift
//  DeckPlan
//
//  Every word a screen shows (DECISIONS_LOG 2026-09-12, "The plan is the
//  product"): sentence case, REDESIGN §2's vocabulary, no id, no block kind
//  and no Core sentence reaches a screen unmapped. An alert's title says what
//  happened, never "Refused".
//

import Foundation
import DeckPlanCore

enum Display {
    // MARK: - Blocks, weekdays, ages, dates

    /// The six block kinds in guide order, with their labels.
    static let blockLabels: [String: String] = [
        "welcome": "Welcome", "warmUp": "Warm-up", "review": "Review",
        "introduce": "Introduce", "topic": "Topic", "wrapUp": "Wrap-up",
    ]

    static func block(_ kind: String) -> String {
        blockLabels[kind] ?? "Block"
    }

    /// "Warm-up · 3 min".
    static func blockHeader(_ kind: String, minutes: Int?) -> String {
        [block(kind), Display.minutes(minutes)].compactMap { $0 }.joined(separator: " · ")
    }

    static let weekdayLabels: [String: String] = [
        "mon": "Mon", "tue": "Tue", "wed": "Wed", "thu": "Thu", "fri": "Fri", "sat": "Sat", "sun": "Sun",
    ]

    static func weekday(_ id: String) -> String {
        weekdayLabels[id] ?? id
    }

    /// The class form's one-letter weekday cells (M T W T F S S).
    static let weekdayLetters: [String: String] = [
        "mon": "M", "tue": "T", "wed": "W", "thu": "T", "fri": "F", "sat": "S", "sun": "S",
    ]

    static let weekdayFullNames: [String: String] = [
        "mon": "Monday", "tue": "Tuesday", "wed": "Wednesday", "thu": "Thursday", "fri": "Friday",
        "sat": "Saturday", "sun": "Sunday",
    ]

    /// "Mon · Wed".
    static func weekdays(_ ids: [String]) -> String {
        ids.map(weekday).joined(separator: " · ")
    }

    static let ageGroupLabels: [String: String] = [
        "preschool": "Preschool", "schoolAge": "School age", "teen": "Teen", "adult": "Adult",
        "infantToddler": "Infant & toddler",
    ]

    static func ageGroup(_ id: String) -> String {
        ageGroupLabels[id] ?? id
    }

    /// The age words for an activity's `ages` (P/S/A).
    static func ages(_ tags: [String]) -> String {
        if tags.isEmpty { return "all ages" }
        return tags.map { Activities.ageWords[$0] ?? $0 }.joined(separator: ", ")
    }

    /// "Wed, Sep 16" from "2026-09-16"; the text itself when it is not a date.
    static func date(_ iso: String?) -> String {
        guard let iso, let parsed = ISODate(iso) else { return iso ?? "" }
        var components = DateComponents()
        components.year = parsed.year
        components.month = parsed.month
        components.day = parsed.day
        components.hour = 12
        guard let date = Calendar.current.date(from: components) else { return iso }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Today as "YYYY-MM-DD" in the current calendar — the one place the app
    /// reads the clock; the Core takes the date as an argument (C7).
    static func isoToday() -> String {
        iso(from: Date())
    }

    static func iso(from date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return ISODate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1).iso
    }

    static func date(fromISO iso: String) -> Date {
        guard let parsed = ISODate(iso) else { return Date() }
        var components = DateComponents()
        components.year = parsed.year
        components.month = parsed.month
        components.day = parsed.day
        components.hour = 12
        return Calendar.current.date(from: components) ?? Date()
    }

    /// "3 min".
    static func minutes(_ minutes: Int?) -> String? {
        guard let minutes else { return nil }
        return "\(minutes) min"
    }

    /// "steps 1–3" for a block's step range.
    static func stepRange(_ range: [Int]?) -> String? {
        guard let range, range.count == 2 else { return nil }
        if range[0] == range[1] { return "step \(range[0])" }
        return "steps \(range[0])–\(range[1])"
    }

    // MARK: - Days and counts

    /// "Day 5 of 8".
    static func dayOf(_ n: Int, _ lessons: Int) -> String { "Day \(n) of \(lessons)" }

    /// "Day 5".
    static func day(_ n: Int) -> String { "Day \(n)" }

    /// "4 of 8 done".
    static func doneOf(_ done: Int, _ lessons: Int) -> String { "\(done) of \(lessons) done" }

    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }

    /// The first sentence of a description, for a block's card.
    static func firstSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let end = trimmed.firstIndex(where: { ".!?".contains($0) }) else { return trimmed }
        return String(trimmed[...end])
    }

    // MARK: - The Core's sentences, mapped

    /// One sentence per problem code the screens can meet; the Core's own
    /// sentence for a code this list does not know.
    static func problem(_ problem: Problem) -> String {
        switch problem.code {
        case "shuffle-empty": return "There is nothing to shuffle here yet. Pick a skill first."
        case "block-kind": return "This block cannot be changed."
        case "day-range": return "This class has no such day."
        case "day-template": return "The curriculum has no lesson template for this day."
        case "pick-not-any": return "This block's skills are set by the guide."
        case "pick-skill": return "That skill is not in this stage."
        case "edit-missing": return "That activity is not in this block."
        case "edit-index": return "That move is out of range."
        case "edit-library": return "That activity is not in this stage's library."
        case "edit-duplicate": return "That activity is already in this block."
        case "class-stage": return "That stage is not in the curriculum."
        case "class-age-group": return "That age group is not one of the stage's."
        case "class-lessons": return "A class needs at least one lesson."
        case "class-weekdays": return "Pick at least one day."
        case "class-first-date": return "The first lesson needs a date."
        case "class-missing": return "That class no longer exists."
        case "no-curriculum": return General.notReady
        default: return problem.message
        }
    }

    // MARK: - Shared

    enum General {
        static let ok = "OK"
        static let cancel = "Cancel"
        static let done = "Done"
        static let edit = "Edit"
        static let notReady = "The curriculum is not ready."
        static let couldntSave = "Couldn't save"
        static let notSaved = "The change was not saved."
        static let planningOff = "Planning is off"
        static let seeDiagnostics = "Settings → Diagnostics"
        static let storeCouldntOpen = "The store could not be opened"
    }

    // MARK: - Today

    enum Today {
        static let title = "Today"
        static let classPicker = "Class"
        /// "Next: Wed, Sep 30 · Stage 1 · Mon Wed".
        static func next(_ date: String?, _ className: String) -> String {
            "Next: \(Display.date(date)) · \(className)"
        }
        static let noClasses = "No classes yet."
        static let createClass = "Create a class"
        static let noLessonsAhead = "No lessons ahead."
        static let noLessonsAheadHint = "Every class is past its last date. Create a class to plan again."
    }

    // MARK: - A day's plan

    enum Plan {
        static let shuffle = "Shuffle"
        static let pickSkill = "Pick a skill"
        static let addFromFinder = "Add from the finder"
        static let noMoreNew = "No more new activities for this block."
        static let hiddenNow = "The pool profile hides this now."
        static let emptyBlock = "Nothing in this block."
        static let moveUp = "Move up"
        static let moveDown = "Move down"
        static func removeNamed(_ name: String) -> String { "Remove \(name)" }
        /// The Shuffle button's spoken label: "Shuffle Warm-up".
        static func shuffleBlock(_ block: String) -> String { "Shuffle \(block)" }
        static func noPlan(_ n: Int) -> String { "No plan for \(day(n).lowercased())" }
        static let couldntShuffle = "Couldn't shuffle"
        static let couldntPick = "Couldn't pick that skill"
        static let couldntAdd = "Couldn't add the activity"
        static let couldntRemove = "Couldn't remove the activity"
        static let couldntMove = "Couldn't move the activity"
    }

    // MARK: - Finder

    enum Finder {
        static let title = "Finder"
        static func addTo(_ block: String) -> String { "Add to \(block)" }
        static let stage = "Stage"
        static let skill = "Skill"
        static let more = "More"
        static let add = "Add"
        static let added = "Added"
        static func addNamed(_ name: String) -> String { "Add \(name)" }
        static let searchPrompt = "Activity name"
        static let choosePrompt = "Pick a stage and a skill to see its activities."
        static let noneForSkill = "No activity of this skill passes the pool profile."
        static func nothingNamed(_ text: String) -> String { "Nothing named “\(text)” in this stage." }
        static let browse = "Browse the whole library"
        static let nothingPasses = "Nothing passes the pool profile."
        static func stageTitle(_ id: String, _ name: String) -> String {
            name.isEmpty ? "Stage \(id)" : "Stage \(id) · \(name)"
        }
    }

    // MARK: - An activity

    enum Activity {
        static let noDescription = "No description in the toolkit."
        /// "Bring: pool noodle · small toys or kickboard · goggles (optional)".
        static func bring(_ required: [String], _ optional: [String]) -> String {
            let items = required + optional.map { "\($0) (optional)" }
            return items.isEmpty ? "Nothing to bring." : "Bring: " + items.joined(separator: " · ")
        }
        /// "School age · submerges" / "All ages · no submerging".
        static func agesAndSubmerging(_ tags: [String], _ submerges: Bool) -> String {
            "\(ages(tags).capitalizedFirst) · \(submerges ? "submerges" : "no submerging")"
        }
        /// "Front Glide · Stage 1 · Getting Comfortable".
        static func place(skill: String?, stage: String) -> String {
            [skill, stage].compactMap { $0 }.joined(separator: " · ")
        }
        static func inToolkitVideo(_ title: String) -> String { "In the toolkit video “\(title)”" }
        static func addFromFinder(_ block: String) -> String { "Add another to \(block) from the finder" }
        static let unknown = "This activity is not in the curriculum."
    }

    // MARK: - Classes

    enum ClassesWords {
        static let title = "Classes"
        static let newClass = "New class"
        static let editClass = "Edit class"
        static let create = "Create"
        static let save = "Save"
        static let noClasses = "No classes yet."
        static let createFirst = "A class is one run of lessons at one stage."
        static let createClass = "Create a class"
        /// "Getting Comfortable · Preschool".
        static func stageAndAge(_ stage: String, _ ageGroup: String) -> String { "\(stage) · \(ageGroup)" }
        static let delete = "Delete"
        static let deleteClass = "Delete class"
        static func deleteTitle(_ name: String) -> String { "Delete \(name)?" }
        static func deleteMessage(_ savedDays: Int) -> String {
            "Its lesson log (\(count(savedDays, "saved day", "saved days"))) is deleted with it."
        }
        /// Select mode: hold a class (DECISIONS_LOG 2026-09-13).
        static let select = "Select"
        static let selectAll = "Select all"
        static let deselectAll = "Deselect all"
        /// "Delete 2 classes"; "Delete" with none selected.
        static func deleteSelected(_ n: Int) -> String {
            n == 0 ? delete : "Delete \(count(n, "class", "classes"))"
        }
        /// "Delete 2 classes?"
        static func deleteSeveralTitle(_ n: Int) -> String { "Delete \(count(n, "class", "classes"))?" }
        /// "First and Second. Their lesson logs (3 saved days) are deleted with them."
        static func deleteSeveralMessage(_ names: [String], _ savedDays: Int) -> String {
            "\(ListFormatter.localizedString(byJoining: names)). Their lesson logs "
                + "(\(count(savedDays, "saved day", "saved days"))) are deleted with them."
        }
        static let deleted = "This class was deleted."
        static let stage = "Stage"
        static let ageGroup = "Age group"
        static let schedule = "Schedule"
        static let days = "Days"
        static let firstLesson = "First lesson"
        static let lessons = "Lessons"
        static func lessonsStepper(_ n: Int) -> String { "Lessons: \(n)" }
        static let name = "Name"
        static func leaveEmptyFor(_ name: String) -> String { "Leave empty for “\(name)”." }
        static let pickAtLeastOneDay = "Pick at least one day."
        static let couldntCreate = "Couldn't create the class"
        static let couldntSave = "Couldn't save the class"
        static let lessonDays = "Lesson days"
        static let doneDay = "Done"
        static let editedDay = "Edited"
        static let nextDay = "Next"
        /// "From Mon, Sep 14 · 4 of 8 done".
        static func fromDate(_ date: String, _ done: Int, _ lessons: Int) -> String {
            "From \(Display.date(date)) · \(doneOf(done, lessons))"
        }
        /// "Mon · Wed from Mon, Sep 14 · 4 of 8 done".
        static func weekdaysFromDate(_ weekdays: [String], _ date: String, _ done: Int, _ lessons: Int) -> String {
            "\(Display.weekdays(weekdays)) from \(Display.date(date)) · \(doneOf(done, lessons))"
        }
    }

    // MARK: - Pool

    enum PoolWords {
        static let title = "Pool"
        static let depth = "Depth"
        static let shallow = "Shallow"
        static let medium = "Medium"
        static let deep = "Deep"
        static let depthFooter = "An activity that needs a depth that is off is hidden."
        static let diving = "Diving"
        static let totDock = "Tot dock"
        static let divingFooter = "Head-first entries are hidden when diving or deep water is off."
        static let equipment = "Equipment"
        static let equipmentFooter = "Off hides every activity that requires the item. Props such as goggles are always on; an activity's page says what to bring."
    }

    // MARK: - Settings

    enum SettingsWords {
        static let title = "Settings"
        static let classDay = "Class day"
        static let showWelcome = "Show the Welcome block"
        static let showTopic = "Show the Y value (topic) block"
        static let reviewFirst = "Review before Introduce"
        static let pool = "Pool"
        static let backup = "Backup"
        static let backupAndRestore = "Backup and restore"
        static let curriculum = "Curriculum"
        /// "Curriculum 2026.09 · valid".
        static func curriculumRow(_ version: String?, _ status: String) -> String {
            "Curriculum \(version ?? "—") · \(status)"
        }
        static let valid = "valid"
        static func errors(_ n: Int) -> String { count(n, "error", "errors") }
        static func warnings(_ n: Int) -> String { count(n, "warning", "warnings") }
        static let notChecked = "not checked"
        static let diagnostics = "Diagnostics"
    }

    enum Diagnostics {
        static let title = "Diagnostics"
        static let validation = "Validation"
        static let version = "Version"
        static let plansLessons = "Plans lessons"
        static let yes = "Yes"
        static let no = "No"
        static let errors = "Errors"
        static let warnings = "Warnings"
        static let warningsFooter = "A warning does not stop planning. A step in a stage this build did not load prints as \"2 / Front glide / 1\", without its name."
        static let loaded = "Loaded"
        static let stages = "Stages"
        static let notLoaded = "Not loaded"
        static let skills = "Skills"
        static let steps = "Steps"
        static let topics = "Topics"
        static let lessonTemplates = "Lesson templates"
        static let trackerRows = "Tracker rows"
        static let videos = "Videos"
        static let safetyRules = "Safety rules"
        static let catalog = "YMCA catalog"
        static let activities = "Activities"
        static let equipmentItems = "Equipment items"
        static let equipmentGroups = "Equipment groups"
        static let profileItems = "Profile equipment"
        static let localAdditions = "Your own additions"
        static let localFooter = "From curriculum/local.json in the repository. Edit it there; the build copies it in read-only."
        static let store = "Store"
        static let classes = "Classes"
        static func classOrder(_ order: Int) -> String { "Order \(order)" }
        static let app = "App"
        static let version_ = "DeckPlan"
        static let about = "A personal app for one YMCA swim instructor: sample plans and an activity finder over the YMCA V6 curriculum. Local only: no account, no server, nothing leaves this device except through the share sheet."
        static let none = "none"
    }

    enum BackupWords {
        static let title = "Backup and restore"
        static let backup = "Backup"
        static let prepare = "Prepare a backup"
        static func share(_ name: String) -> String { "Share \(name)" }
        static let backupFooter = "One file with the pool profile, every class and its lesson log. Nothing is sent anywhere until you share it."
        static let restore = "Restore"
        static let restoreFromFile = "Restore from a backup file…"
        static let restoreFooter = "Pick a DeckPlan backup file. You then choose whether to add only the classes this device lacks or to replace everything."
        static let restoreHow = "Restore how?"
        static let addMissing = "Add the classes this device lacks"
        static let replaceAll = "Replace everything with the backup"
        static let restored = "Restored"
        static let couldntRestore = "Couldn't restore"
        static let storeNotOpen = "The store is not open."
        static let couldntPrepare = "The backup could not be made."
        static let fileUnreadable = "The file could not be read."
        static let notABackup = "This file is not a DeckPlan backup, or it is damaged."
        static func newerBackup(_ version: String) -> String {
            "This backup was made by a newer DeckPlan (\(version)). Update the app, then restore it."
        }
        static let couldntWrite = "The backup could not be written on this device."
        static func restoredMessage(_ classes: Int) -> String {
            "\(count(classes, "class", "classes")) on this device now."
        }
    }
}

extension String {
    /// "life jacket" → "Life jacket".
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
