//
//  JSONHelpers.swift
//  DeckPlanCore
//
//  Small duck-typing helpers over raw `JSONValue`, shared by the curriculum
//  loader and validator — a port of the module-level helpers at the top of
//  `tools/core/curriculum.py` (`is_int`, `is_number`, `is_str_list`, `dict_items`,
//  `text`, `_show`).
//
//  The curriculum is transcribed data whose shape faults are the validator's to
//  report, not the loader's or the type system's, so this whole subsystem reads
//  `JSONValue` trees rather than the strongly-typed `Curriculum`/`Stage`/… records
//  in `Models/CurriculumModels.swift` — see the doc comment on `LoadedCurriculum`
//  for why. These helpers are how the Python's tolerant `isinstance(...)` guards
//  read back once there is no dynamic typing to lean on.
//

import Foundation

/// Whether `value` is a JSON integer (`.int` or `.uint` — never `.bool`, which
/// `JSONValue` keeps apart from numbers unlike Python's `bool` subclassing `int`;
/// see `JSONValue`'s doc comment). `tools/core/curriculum.py`'s `is_int`.
func isInt(_ value: JSONValue?) -> Bool {
    switch value {
    case .int, .uint: return true
    default: return false
    }
}

/// Whether `value` is any JSON number. `tools/core/curriculum.py`'s `is_number`.
func isNumber(_ value: JSONValue?) -> Bool {
    switch value {
    case .int, .uint, .double: return true
    default: return false
    }
}

/// Whether `value` is a JSON array of only strings (`[]` counts).
/// `tools/core/curriculum.py`'s `is_str_list`.
func isStrList(_ value: JSONValue?) -> Bool {
    guard case .array(let items)? = value else { return false }
    return items.allSatisfy { if case .string = $0 { return true } else { return false } }
}

/// `value` as `[String]`, or nil when it is not a JSON array of only strings.
/// The typed companion to `isStrList`, for checks that need the strings, not
/// just the shape check.
func strList(_ value: JSONValue?) -> [String]? {
    guard case .array(let items)? = value else { return nil }
    var strings: [String] = []
    strings.reserveCapacity(items.count)
    for item in items {
        guard case .string(let text) = item else { return nil }
        strings.append(text)
    }
    return strings
}

/// The object entries of a JSON array, dropping anything that is not an object
/// — `tools/core/curriculum.py`'s `dict_items` (there, "not a list" also yields
/// `[]`; here that case is folded into the `JSONValue?` overload below).
func dictItems(_ items: [JSONValue]) -> [JSONValue] {
    items.filter { if case .object = $0 { return true } else { return false } }
}

/// The object entries of `value` when it is a JSON array, or `[]` when it is
/// not an array at all (including when it is absent). `tools/core/curriculum.py`'s
/// `dict_items`.
func dictItems(_ value: JSONValue?) -> [JSONValue] {
    guard case .array(let items)? = value else { return [] }
    return dictItems(items)
}

/// The object entries of a JSON array paired with their original index in that
/// array (before non-objects are dropped) — used where a later step needs to
/// know an entry's position in the *un-filtered* array, such as telling a
/// YMCA catalog entry from a local one by where it falls in the merged catalog
/// (`Checker.originOfActivity`, `Checker.originOfEquipment`).
func indexedDictItems(_ items: [JSONValue]) -> [(index: Int, value: JSONValue)] {
    items.enumerated().compactMap { index, value in
        if case .object = value { return (index, value) }
        return nil
    }
}

/// `value` when it is a string, or "" otherwise. `tools/core/curriculum.py`'s `text`.
func text(_ value: JSONValue?) -> String {
    if case .string(let string)? = value { return string }
    return ""
}

/// A short JSON-ish rendering of `value` for an error message, truncated with
/// an ellipsis past `limit` characters. Not required to match Python's `repr`
/// or `json.dumps` byte for byte (only the *codes* need to match Python's,
/// docs/BUILD_PLAN.md M4) — this exists so a message can name the bad value it
/// is complaining about. `tools/core/curriculum.py`'s `_show`.
func show(_ value: JSONValue?, limit: Int = 70) -> String {
    let rendered = describe(value ?? .null)
    guard rendered.count > limit else { return rendered }
    let truncated = rendered.prefix(max(0, limit - 1))
    return "\(truncated)\u{2026}"
}

/// `show` for a Swift array of strings — e.g. `show(sortedStageIds)` where
/// Python would `_show(sorted(stage_ids))`.
func show(_ strings: [String], limit: Int = 70) -> String {
    show(.array(strings.map { .string($0) }), limit: limit)
}

/// `show` for an array of optional JSON values (a raw field's `.map { $0["n"] }`,
/// with an absent key showing as `null`) — e.g. `show(numbers)` where Python
/// would `_show([step.get("n") for step in steps])`.
func show(_ values: [JSONValue?], limit: Int = 70) -> String {
    show(.array(values.map { $0 ?? .null }), limit: limit)
}

/// Whether `value` is a JSON string that is neither absent nor blank —
/// Python's recurring `not isinstance(x, str) or not x.strip()` shape check.
func isNonBlankString(_ value: JSONValue?) -> Bool {
    guard case .string(let s)? = value else { return false }
    return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// Whether `value` is present as a key *and* is not JSON null — Python's
/// `x is not None` after `x = d.get(key)`, where both an absent key and an
/// explicit `null` read back as `None`.
func isPresentNonNull(_ value: JSONValue?) -> Bool {
    value.map { !$0.isNull } ?? false
}

/// Python truthiness for a JSON value: `null`/absent, `false`, `0`, `""`, `[]`
/// and `{}` are falsy; everything else is truthy. Used only where the Python
/// reads as a bare `if value:` rather than a shape check.
func isTruthy(_ value: JSONValue?) -> Bool {
    switch value {
    case .none, .null: return false
    case .bool(let flag): return flag
    case .int(let n): return n != 0
    case .uint(let n): return n != 0
    case .double(let n): return n != 0
    case .string(let s): return !s.isEmpty
    case .array(let items): return !items.isEmpty
    case .object(let fields): return !fields.isEmpty
    }
}

/// An id-shaped field's display text: the string itself when it is one (the
/// overwhelmingly common, well-formed case), else a short JSON rendering of
/// whatever malformed value is actually there. Used for the many "where" labels
/// and messages built from a stage/skill/step id that the checks must still
/// name sensibly even when it turns out not to be a string at all.
func displayId(_ value: JSONValue?) -> String {
    value?.stringValue ?? show(value)
}

private func describe(_ value: JSONValue) -> String {
    switch value {
    case .null: return "null"
    case .bool(let flag): return flag ? "true" : "false"
    case .int(let n): return String(n)
    case .uint(let n): return String(n)
    case .double(let n): return String(n)
    case .string(let text): return "\"\(text)\""
    case .array(let items): return "[" + items.map(describe).joined(separator: ", ") + "]"
    case .object(let fields):
        let entries = fields.sorted { Array($0.key.unicodeScalars).lexicographicallyPrecedes(Array($1.key.unicodeScalars)) }
            .map { key, value in "\"\(key)\": \(describe(value))" }
        return "{" + entries.joined(separator: ", ") + "}"
    }
}
