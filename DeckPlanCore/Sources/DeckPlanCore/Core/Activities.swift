//
//  Activities.swift
//  DeckPlanCore
//
//  The one pool filter, the age filter and the library order — a port of
//  `tools/core/activities.py` (docs/REDESIGN.md §2, §3.2; docs/TEST_CASES.md
//  P1–P6). Every function is pure and works on the raw `JSONValue` shapes the
//  curriculum loader returns, plus the typed `Pool` the Store keeps.
//
//  The profile (P6; DECISIONS_LOG 2026-09-12 "The pool profile lists pool
//  equipment, not props" and the owner's answers): `equipment` has one key per
//  **profile item**, the five catalog items that are the only option of a required
//  group in the most activities of the loaded library (a `group` requirement
//  counting toward each of its `anyOf[]` members, ties by catalog order). Every
//  other catalog item is a **prop**: never in the profile, always on for the
//  filter. A missing profile key reads as off; a prop's key is ignored on read and
//  dropped by `normalizePool`. The profile is computed from the data, so these
//  functions take the curriculum, not just its catalog.
//
//  The filter (P2–P3, in this order): an activity is hidden when any group in its
//  `equipment[]` has no item on; when it has `depths` and none of them is on;
//  when it is `headfirst` and deep or diving is off. `equipmentOptional` never
//  hides. The age filter (P5) is separate: a class's `ageGroup` gives a tag P/S/A
//  (none for infantToddler); an activity whose `ages` lack the tag is hidden;
//  `ages: []` passes everywhere. `poolFilter` applies both and is the only
//  function the plan, shuffle, finder and browse go through (P4).
//

import Foundation

/// Why the pool (or the age tag) hides an activity (`activities.hidden_reason`).
public enum HiddenReason: Equatable, Sendable {
    /// The requirement groups with no item on.
    case equipment(missing: [[String]])
    /// The activity's zones, none of them on.
    case depth([String])
    /// A head-first entry with deep or diving off.
    case diving
    /// The activity's ages, the class's tag not among them.
    case age([String])
}

/// The strings of a JSON array, anything else dropped — the Python's
/// `[a for a in value or [] if isinstance(a, str)]`.
func stringItems(_ value: JSONValue?) -> [String] {
    guard case .array(let items)? = value else { return [] }
    return items.compactMap(\.stringValue)
}

public enum Activities {

    // MARK: - age (P5)

    /// preschool -> "P", schoolAge -> "S", teen/adult -> "A"; infantToddler (or
    /// an unrecognized value) -> nil, which passes every activity's age filter.
    public static let ageTagByGroup: [String: String] = [
        "preschool": "P", "schoolAge": "S", "teen": "A", "adult": "A",
    ]

    public static let ageWords: [String: String] = ["P": "preschool", "S": "school age", "A": "teen & adult"]

    public static func ageTag(_ ageGroup: String?) -> String? {
        guard let ageGroup else { return nil }
        return ageTagByGroup[ageGroup]
    }

    // MARK: - catalog

    /// Catalog id -> entry (`activities.catalog_index`: the last entry with an id wins).
    public static func catalogIndex(_ catalog: [JSONValue]) -> [String: JSONValue] {
        var index: [String: JSONValue] = [:]
        for entry in catalog {
            guard case .object = entry, let id = entry["id"]?.stringValue else { continue }
            index[id] = entry
        }
        return index
    }

    /// Every catalog *item* id in catalog order (groups left out).
    public static func catalogItems(_ catalog: [JSONValue]) -> [String] {
        catalog.compactMap { entry in
            guard case .object = entry, entry["kind"]?.stringValue == "item" else { return nil }
            return entry["id"]?.stringValue
        }
    }

    /// Catalog id -> its position among the distinct ids, in catalog order.
    public static func catalogOrder(_ catalog: [JSONValue]) -> [String: Int] {
        var order: [String: Int] = [:]
        for entry in catalog {
            guard case .object = entry, let id = entry["id"]?.stringValue, order[id] == nil else { continue }
            order[id] = order.count
        }
        return order
    }

    /// The catalog name, lower-cased ("life jacket"); the id when unknown.
    public static func equipmentName(_ catalog: [JSONValue], _ equipmentId: String) -> String {
        let name = catalogIndex(catalog)[equipmentId]?["name"]?.stringValue ?? equipmentId
        return name.lowercased()
    }

    /// `items` sorted by their place in `order`, unknown ids last, ties by id
    /// (the Python's `key=lambda a: (order.get(a, len(order)), a)`).
    static func byCatalogOrder(_ items: [String], order: [String: Int]) -> [String] {
        items.sorted { a, b in
            let pa = order[a] ?? order.count
            let pb = order[b] ?? order.count
            return pa != pb ? pa < pb : Canonical.scalarsPrecede(a, b)
        }
    }

    /// One phrase per requirement group, items in catalog order joined with "or":
    /// `[["life-jacket", "float-belt"]]` -> `["float belt or life jacket"]` (F5).
    public static func requirementPhrases(_ activity: JSONValue, _ catalog: [JSONValue]) -> [String] {
        let order = catalogOrder(catalog)
        var phrases: [String] = []
        for group in activity["equipment"]?.arrayValue ?? [] {
            let items = byCatalogOrder(stringItems(group), order: order)
            if !items.isEmpty {
                phrases.append(items.map { equipmentName(catalog, $0) }.joined(separator: " or "))
            }
        }
        return phrases
    }

    /// The optional equipment's display names, in catalog order (F5).
    public static func optionalNames(_ activity: JSONValue, _ catalog: [JSONValue]) -> [String] {
        let order = catalogOrder(catalog)
        return byCatalogOrder(stringItems(activity["equipmentOptional"]), order: order)
            .map { equipmentName(catalog, $0) }
    }

    // MARK: - profile items and props (P6)

    /// The number of profile items (the owner's answers, 2026-09-12).
    public static let profileSize = 5

    /// Catalog item id -> the number of activities in which it is the only option
    /// of a required group; a `group` entry as the only option counts toward each
    /// of its `anyOf[]` items. An activity counts an item once however many groups
    /// name it; ids that are not in the catalog do not count.
    public static func requirementCounts(_ activities: [JSONValue], catalog: [JSONValue]) -> [String: Int] {
        let index = catalogIndex(catalog)
        var counts: [String: Int] = [:]
        for activity in activities {
            guard case .object = activity else { continue }
            var counted: Set<String> = []
            for group in activity["equipment"]?.arrayValue ?? [] {
                let options = stringItems(group)
                guard options.count == 1, let entry = index[options[0]] else { continue }
                let kind = entry["kind"]?.stringValue
                if kind == "group" {
                    for item in stringItems(entry["anyOf"]) where index[item]?["kind"]?.stringValue == "item" {
                        counted.insert(item)
                    }
                } else if kind == "item" {
                    counted.insert(options[0])
                }
            }
            for item in counted { counts[item, default: 0] += 1 }
        }
        return counts
    }

    /// The profile's equipment (P6): the `profileSize` catalog items with the highest
    /// `requirementCounts` over the loaded library, ties by catalog order, listed in
    /// catalog order. Every other catalog item is a prop.
    public static func profileItems(_ curriculum: LoadedCurriculum) -> [String] {
        let items = catalogItems(curriculum.equipment)
        let counts = requirementCounts(curriculum.activities, catalog: curriculum.equipment)
        let ranked = Array(items.indices).sorted { a, b in
            let countA = counts[items[a]] ?? 0
            let countB = counts[items[b]] ?? 0
            return countA != countB ? countA > countB : a < b
        }
        let chosen = Set(ranked.prefix(profileSize))
        return items.enumerated().filter { chosen.contains($0.offset) }.map(\.element)
    }

    /// A catalog item that is not profile equipment (never in the profile, always
    /// on for the filter, named in the activity's detail).
    public static func isProp(_ curriculum: LoadedCurriculum, _ equipmentId: String,
                              profile: [String]? = nil) -> Bool {
        guard let entry = catalogIndex(curriculum.equipment)[equipmentId],
              entry["kind"]?.stringValue == "item" else { return false }
        return !(profile ?? profileItems(curriculum)).contains(equipmentId)
    }

    /// What the filter needs of a curriculum, computed once per call that filters
    /// many activities: the catalog index and the profile items.
    struct FilterContext {
        let index: [String: JSONValue]
        let profile: Set<String>

        init(_ curriculum: LoadedCurriculum) {
            index = catalogIndex(curriculum.equipment)
            profile = Set(profileItems(curriculum))
        }
    }

    // MARK: - pool profile (P1)

    /// A new profile: every depth, diving, the tot-dock and every profile item on.
    public static func defaultPool(_ curriculum: LoadedCurriculum) -> Pool {
        var depths: [String: Bool] = [:]
        for zone in Ids.zones { depths[zone] = true }
        var equipment: [String: Bool] = [:]
        for item in profileItems(curriculum) { equipment[item] = true }
        return Pool(depths: depths, diving: true, totDock: true, equipment: equipment)
    }

    /// The full profile shape from a possibly partial one: a missing key is off, a
    /// key that is not a profile item (a prop, a group, an unknown id) is dropped,
    /// values become booleans.
    public static func normalizePool(_ pool: JSONValue?, _ curriculum: LoadedCurriculum) -> Pool {
        let depthsValue = pool?["depths"]
        let equipmentValue = pool?["equipment"]
        var depths: [String: Bool] = [:]
        for zone in Ids.zones { depths[zone] = isTruthy(depthsValue?[zone]) }
        var equipment: [String: Bool] = [:]
        for item in profileItems(curriculum) { equipment[item] = isTruthy(equipmentValue?[item]) }
        return Pool(depths: depths, diving: isTruthy(pool?["diving"]), totDock: isTruthy(pool?["totDock"]),
                    equipment: equipment)
    }

    public static func normalizePool(_ pool: Pool, _ curriculum: LoadedCurriculum) -> Pool {
        normalizePool(pool.json, curriculum)
    }

    public static func depthOn(_ pool: Pool, _ zone: String) -> Bool {
        pool.depths[zone] ?? false
    }

    /// A profile item's toggle (a missing key is off); a prop is always on; a group
    /// is on when any of its `anyOf[]` items is; an unknown id is off.
    public static func isOn(_ pool: Pool, _ equipmentId: String, _ curriculum: LoadedCurriculum) -> Bool {
        isOn(pool, equipmentId, context: FilterContext(curriculum))
    }

    static func isOn(_ pool: Pool, _ equipmentId: String, context: FilterContext) -> Bool {
        guard let entry = context.index[equipmentId] else { return false }
        if entry["kind"]?.stringValue == "group" {
            return stringItems(entry["anyOf"]).contains { isOn(pool, $0, context: context) }
        }
        if !context.profile.contains(equipmentId) { return true }
        return pool.equipment[equipmentId] ?? false
    }

    /// One requirement group is satisfied when any of its ids is on. An empty group
    /// requires nothing.
    public static func groupSatisfied(_ pool: Pool, _ group: [String], _ curriculum: LoadedCurriculum) -> Bool {
        groupSatisfied(pool, group, context: FilterContext(curriculum))
    }

    static func groupSatisfied(_ pool: Pool, _ group: [String], context: FilterContext) -> Bool {
        group.isEmpty || group.contains { isOn(pool, $0, context: context) }
    }

    // MARK: - the filter (P2–P5)

    /// The first reason the pool (or the age tag) hides `activity`, or nil when it
    /// shows. A prop never hides (P6).
    public static func hiddenReason(_ activity: JSONValue, pool: Pool, curriculum: LoadedCurriculum,
                                    ageTag: String? = nil) -> HiddenReason? {
        hiddenReason(activity, pool: pool, context: FilterContext(curriculum), ageTag: ageTag)
    }

    static func hiddenReason(_ activity: JSONValue, pool: Pool, context: FilterContext,
                             ageTag: String?) -> HiddenReason? {
        var missing: [[String]] = []
        for group in activity["equipment"]?.arrayValue ?? [] {
            let ids = stringItems(group)
            if !groupSatisfied(pool, ids, context: context) { missing.append(ids) }
        }
        if !missing.isEmpty { return .equipment(missing: missing) }
        let depths = stringItems(activity["depths"])
        if !depths.isEmpty, !depths.contains(where: { depthOn(pool, $0) }) { return .depth(depths) }
        if isTruthy(activity["headfirst"]), !(depthOn(pool, "deep") && pool.diving) { return .diving }
        let ages = stringItems(activity["ages"])
        if !ages.isEmpty, let ageTag, !ages.contains(ageTag) { return .age(ages) }
        return nil
    }

    public static func passes(_ activity: JSONValue, pool: Pool, curriculum: LoadedCurriculum,
                              ageTag: String? = nil) -> Bool {
        hiddenReason(activity, pool: pool, curriculum: curriculum, ageTag: ageTag) == nil
    }

    /// The one filter (P4): the activities that show, in the order given.
    public static func poolFilter(_ activities: [JSONValue], pool: Pool, curriculum: LoadedCurriculum,
                                  ageTag: String? = nil) -> [JSONValue] {
        let context = FilterContext(curriculum)
        return activities.filter { hiddenReason($0, pool: pool, context: context, ageTag: ageTag) == nil }
    }

    /// `poolFilter` over ids resolved through the curriculum; an id that is not an
    /// activity is dropped. Order preserved, duplicates kept (callers dedupe).
    public static func filterIds(_ curriculum: LoadedCurriculum, _ activityIds: [String], pool: Pool,
                                 ageTag: String? = nil) -> [String] {
        let index = activityIndex(curriculum)
        let activities = activityIds.compactMap { index[$0] }
        return poolFilter(activities, pool: pool, curriculum: curriculum, ageTag: ageTag)
            .compactMap { $0["id"]?.stringValue }
    }

    // MARK: - library order

    /// Activity id -> entry; the first entry with an id wins, as `reindex` does.
    static func activityIndex(_ curriculum: LoadedCurriculum) -> [String: JSONValue] {
        var index: [String: JSONValue] = [:]
        for activity in curriculum.activities {
            guard case .object = activity, let id = activity["id"]?.stringValue, index[id] == nil else { continue }
            index[id] = activity
        }
        return index
    }

    /// Activity id -> its position in `activities.json` (the "catalog number").
    public static func catalogPosition(_ curriculum: LoadedCurriculum) -> [String: Int] {
        var position: [String: Int] = [:]
        for (index, activity) in curriculum.activities.enumerated() {
            guard case .object = activity, let id = activity["id"]?.stringValue else { continue }
            position[id] = index
        }
        return position
    }

    /// First occurrence wins, order kept.
    public static func dedupe(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for item in items where !seen.contains(item) {
            seen.insert(item)
            result.append(item)
        }
        return result
    }

    /// The activities of several skills, in catalog order, deduped (D2's second part).
    public static func skillActivityIds(_ curriculum: LoadedCurriculum, _ skillIds: [String]) -> [String] {
        let position = catalogPosition(curriculum)
        var collected: [String] = []
        for skillId in skillIds {
            if let skill = curriculum.skill(skillId) {
                collected += stringItems(skill["activityIds"])
            }
        }
        return dedupe(byCatalogOrder(collected, order: position))
    }

    /// The stage's library grouped: a Greeting group first (`greetingActivityIds`),
    /// then one group per skill in library order, each group's activities in catalog
    /// order (F6's grouping before the filter).
    public static func libraryGroups(_ curriculum: LoadedCurriculum, _ stageId: String) -> [BrowseGroup] {
        guard let stage = curriculum.stage(stageId) else { return [] }
        let position = catalogPosition(curriculum)
        func ordered(_ value: JSONValue?) -> [String] {
            dedupe(byCatalogOrder(stringItems(value), order: position))
        }
        var groups = [BrowseGroup(skillId: nil, name: "Greeting", activityIds: ordered(stage["greetingActivityIds"]))]
        for skill in curriculum.skillsOf(stageId) {
            let id = skill["id"]?.stringValue
            let name = skill["name"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? id ?? ""
            groups.append(BrowseGroup(skillId: id, name: name, activityIds: ordered(skill["activityIds"])))
        }
        return groups
    }

    /// Every activity id of a stage: Greeting first, then skill by skill, deduped.
    public static func library(_ curriculum: LoadedCurriculum, _ stageId: String) -> [String] {
        dedupe(libraryGroups(curriculum, stageId).flatMap(\.activityIds))
    }

    // MARK: - seeded order (D4, F1)

    /// `ids` sorted by `(hashParts(seed, id), id)` — the seeded draw the shuffle and
    /// the finder share (docs/CANONICAL_JSON.md; `canonical.hash_parts`).
    public static func seededOrder(_ ids: [String], seed: UInt64) -> [String] {
        let keyed = ids.map { ($0, Canonical.hashParts(.uint(seed), .string($0))) }
        return keyed
            .sorted { a, b in a.1 != b.1 ? a.1 < b.1 : Canonical.scalarsPrecede(a.0, b.0) }
            .map(\.0)
    }
}
