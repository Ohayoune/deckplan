//
//  JSONModel.swift
//  DeckPlanCore
//
//  How every docs/SPEC.md §7 type moves between typed Swift values and
//  `JSONValue` — the two halves, `init(json:)` and `json`, plus the reader and
//  builder the models are written with.
//

import Foundation

// MARK: - The protocol

/// A docs/SPEC.md §7 record that can be read from and written back to JSON.
///
/// `init(json:)` and `json` are the round trip the Core works in: models never go
/// through `JSONSerialization` or `JSONEncoder` on the canonical path, because the
/// plan JSON and `inputsHash` have to come out of `Canonical.dumps` byte for byte
/// (docs/CANONICAL_JSON.md). `Codable` conformance is provided here in terms of the
/// same two members, so a model encoded by a `JSONEncoder` (a defaults file, a
/// SwiftUI preview) says exactly what `json` says.
public protocol JSONModel: Codable, Sendable, Equatable {
    /// Read the record out of `json`. Throws `JSONModelError` when a required
    /// field is missing or has the wrong type.
    init(json: JSONValue) throws

    /// The record as JSON, ready for `Canonical.dumps`.
    var json: JSONValue { get }
}

extension JSONModel {

    public init(from decoder: any Decoder) throws {
        try self.init(json: try JSONValue(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        try json.encode(to: encoder)
    }

    /// Read the record out of JSON text — for tests and for files read by the Store.
    public init(jsonData: Data) throws {
        try self.init(json: try JSONValue.parse(jsonData))
    }

    /// The record's canonical JSON text (docs/CANONICAL_JSON.md).
    public func canonicalJSON() throws -> String {
        try Canonical.dumps(json)
    }
}

// MARK: - Errors

/// What went wrong turning JSON into a docs/SPEC.md §7 record.
public enum JSONModelError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The value given for a record was not a JSON object.
    case notAnObject(type: String, found: String)
    /// A field the record cannot do without is missing or null.
    case missingField(type: String, field: String)
    /// A field is present but holds the wrong kind of value.
    case wrongType(type: String, field: String, expected: String, found: String)

    public var description: String {
        switch self {
        case .notAnObject(let type, let found):
            return "a \(type) must be a JSON object, not \(found)"
        case .missingField(let type, let field):
            return "\(type) is missing its \(field)"
        case .wrongType(let type, let field, let expected, let found):
            return "\(type)'s \(field) must be \(expected), not \(found)"
        }
    }
}

/// A JSON value named for an error message: "a string", "an array", "null".
func describeJSON(_ value: JSONValue) -> String {
    switch value {
    case .null: return "null"
    case .bool: return "a boolean"
    case .int, .uint: return "an integer"
    case .double: return "a number"
    case .string: return "a string"
    case .array: return "an array"
    case .object: return "an object"
    }
}

// MARK: - Reading

/// Reads one docs/SPEC.md §7 record's fields out of a JSON object, and keeps the
/// ones the record does not name.
///
/// Two rules make `init(json:)` -> `json` lossless, which is what lets the Store
/// save a record it loaded without quietly dropping anything:
///
/// - a key the record does not know is kept in ``extra`` and written back out;
/// - a key whose value is `null` is *also* kept in ``extra``, so a field that
///   arrived explicitly null leaves as explicitly null, while a field that was
///   absent stays absent. JSON tells those apart and so does the canonical hash,
///   so a record written back hashes as it was read (docs/CANONICAL_JSON.md).
public struct JSONReader {
    /// The record's type name, for error messages.
    public let type: String
    /// Every field, as given.
    public let fields: [String: JSONValue]
    /// The fields no `read` call has claimed, plus every explicitly null one.
    public private(set) var extra: [String: JSONValue]

    public init(_ value: JSONValue, type: String) throws {
        guard case .object(let fields) = value else {
            throw JSONModelError.notAnObject(type: type, found: describeJSON(value))
        }
        self.type = type
        self.fields = fields
        self.extra = fields
    }

    /// The raw value of `key`, claiming it. A null value is claimed but left in
    /// ``extra`` so it is written back as null.
    public mutating func claim(_ key: String) -> JSONValue? {
        guard let value = fields[key] else { return nil }
        if case .null = value { return nil }
        extra.removeValue(forKey: key)
        return value
    }

    /// The raw value of `key` including an explicit null, claiming it outright.
    public mutating func claimIncludingNull(_ key: String) -> JSONValue? {
        guard let value = fields[key] else { return nil }
        extra.removeValue(forKey: key)
        return value
    }

    private func wrong(_ key: String, _ expected: String, _ value: JSONValue) -> JSONModelError {
        .wrongType(type: type, field: key, expected: expected, found: describeJSON(value))
    }

    private func missing(_ key: String) -> JSONModelError {
        .missingField(type: type, field: key)
    }

    // required

    public mutating func string(_ key: String) throws -> String {
        guard let value = claim(key) else { throw missing(key) }
        guard case .string(let text) = value else { throw wrong(key, "a string", value) }
        return text
    }

    public mutating func int(_ key: String) throws -> Int {
        guard let value = claim(key) else { throw missing(key) }
        guard let number = value.intValue else { throw wrong(key, "an integer", value) }
        return number
    }

    public mutating func uint64(_ key: String) throws -> UInt64 {
        guard let value = claim(key) else { throw missing(key) }
        guard let number = value.uint64Value else {
            throw wrong(key, "a non-negative integer", value)
        }
        return number
    }

    public mutating func double(_ key: String) throws -> Double {
        guard let value = claim(key) else { throw missing(key) }
        guard let number = value.doubleValue else { throw wrong(key, "a number", value) }
        return number
    }

    public mutating func bool(_ key: String) throws -> Bool {
        guard let value = claim(key) else { throw missing(key) }
        guard case .bool(let flag) = value else { throw wrong(key, "a boolean", value) }
        return flag
    }

    public mutating func strings(_ key: String) throws -> [String] {
        guard let value = try optionalStrings(key) else { throw missing(key) }
        return value
    }

    public mutating func models<T: JSONModel>(_ key: String) throws -> [T] {
        let value: [T]? = try optionalModels(key)
        guard let value else { throw missing(key) }
        return value
    }

    public mutating func model<T: JSONModel>(_ key: String) throws -> T {
        let value: T? = try optionalModel(key)
        guard let value else { throw missing(key) }
        return value
    }

    // optional — nil when the key is absent or null

    public mutating func optionalString(_ key: String) throws -> String? {
        guard let value = claim(key) else { return nil }
        guard case .string(let text) = value else { throw wrong(key, "a string", value) }
        return text
    }

    public mutating func optionalInt(_ key: String) throws -> Int? {
        guard let value = claim(key) else { return nil }
        guard let number = value.intValue else { throw wrong(key, "an integer", value) }
        return number
    }

    public mutating func optionalUInt64(_ key: String) throws -> UInt64? {
        guard let value = claim(key) else { return nil }
        guard let number = value.uint64Value else {
            throw wrong(key, "a non-negative integer", value)
        }
        return number
    }

    public mutating func optionalDouble(_ key: String) throws -> Double? {
        guard let value = claim(key) else { return nil }
        guard let number = value.doubleValue else { throw wrong(key, "a number", value) }
        return number
    }

    public mutating func optionalBool(_ key: String) throws -> Bool? {
        guard let value = claim(key) else { return nil }
        guard case .bool(let flag) = value else { throw wrong(key, "a boolean", value) }
        return flag
    }

    // nullable — the key is claimed even when it is null, because the record
    // writes it back as a key either way (a Mark's `lessonId`, a Plan's
    // `sourceGuideLesson`).

    public mutating func nullableString(_ key: String) throws -> String? {
        guard let value = claimIncludingNull(key) else { return nil }
        if case .null = value { return nil }
        guard case .string(let text) = value else { throw wrong(key, "a string", value) }
        return text
    }

    public mutating func nullableInt(_ key: String) throws -> Int? {
        guard let value = claimIncludingNull(key) else { return nil }
        if case .null = value { return nil }
        guard let number = value.intValue else { throw wrong(key, "an integer", value) }
        return number
    }

    public mutating func optionalStrings(_ key: String) throws -> [String]? {
        guard let value = claim(key) else { return nil }
        guard case .array(let items) = value else { throw wrong(key, "an array", value) }
        return try items.map { item in
            guard case .string(let text) = item else {
                throw wrong(key, "an array of strings", item)
            }
            return text
        }
    }

    public mutating func optionalInts(_ key: String) throws -> [Int]? {
        guard let value = claim(key) else { return nil }
        guard case .array(let items) = value else { throw wrong(key, "an array", value) }
        return try items.map { item in
            guard let number = item.intValue else {
                throw wrong(key, "an array of integers", item)
            }
            return number
        }
    }

    /// Requirement groups: `[["rope", "rescue-tube"]]` (docs/SPEC.md §7, Activity).
    public mutating func optionalStringGroups(_ key: String) throws -> [[String]]? {
        guard let value = claim(key) else { return nil }
        guard case .array(let groups) = value else { throw wrong(key, "an array", value) }
        return try groups.map { group in
            guard case .array(let items) = group else {
                throw wrong(key, "an array of arrays of strings", group)
            }
            return try items.map { item in
                guard case .string(let text) = item else {
                    throw wrong(key, "an array of arrays of strings", item)
                }
                return text
            }
        }
    }

    public mutating func optionalModels<T: JSONModel>(_ key: String) throws -> [T]? {
        guard let value = claim(key) else { return nil }
        guard case .array(let items) = value else { throw wrong(key, "an array", value) }
        return try items.map { try T(json: $0) }
    }

    public mutating func optionalModel<T: JSONModel>(_ key: String) throws -> T? {
        guard let value = claim(key) else { return nil }
        return try T(json: value)
    }

    public mutating func optionalStringMap(_ key: String) throws -> [String: String]? {
        guard let value = claim(key) else { return nil }
        guard case .object(let entries) = value else { throw wrong(key, "an object", value) }
        return try entries.mapValues { entry in
            guard case .string(let text) = entry else {
                throw wrong(key, "an object of strings", entry)
            }
            return text
        }
    }

    public mutating func optionalBoolMap(_ key: String) throws -> [String: Bool]? {
        guard let value = claim(key) else { return nil }
        guard case .object(let entries) = value else { throw wrong(key, "an object", value) }
        return try entries.mapValues { entry in
            guard case .bool(let flag) = entry else {
                throw wrong(key, "an object of booleans", entry)
            }
            return flag
        }
    }

    public mutating func optionalStringsMap(_ key: String) throws -> [String: [String]]? {
        guard let value = claim(key) else { return nil }
        guard case .object(let entries) = value else { throw wrong(key, "an object", value) }
        return try entries.mapValues { entry in
            guard case .array(let items) = entry else {
                throw wrong(key, "an object of arrays of strings", entry)
            }
            return try items.map { item in
                guard case .string(let text) = item else {
                    throw wrong(key, "an object of arrays of strings", item)
                }
                return text
            }
        }
    }

    public mutating func optionalModelMap<T: JSONModel>(_ key: String) throws -> [String: T]? {
        guard let value = claim(key) else { return nil }
        guard case .object(let entries) = value else { throw wrong(key, "an object", value) }
        return try entries.mapValues { try T(json: $0) }
    }
}

// MARK: - Writing

/// Builds a record's JSON object: the fields the record knows, over the ones it
/// kept in ``JSONReader/extra``.
///
/// `set` writes a value and *omits the key* when it is nil, because the plan JSON's
/// optional keys are absent, never null (docs/PLANNER.md §2; `test_planner.py`'s
/// `test_D9_plan_has_exactly_the_SPEC_7_keys` asserts a welcome block has no
/// `topicCode` key at all). `setAllowingNull` writes `null` instead, for the two
/// fields the Python always writes as a key: a Mark's `lessonId` and a Plan's
/// `sourceGuideLesson`.
public struct JSONBuilder {
    private var fields: [String: JSONValue]

    /// Start from the fields the reader kept (unknown keys and explicit nulls).
    public init(extra: [String: JSONValue] = [:]) {
        fields = extra
    }

    public var json: JSONValue { .object(fields) }

    public mutating func set(_ key: String, _ value: JSONValue) {
        fields[key] = value
    }

    public mutating func set(_ key: String, _ value: String?) {
        if let value { fields[key] = .string(value) }
    }

    public mutating func set(_ key: String, _ value: Int?) {
        if let value { fields[key] = .int(Int64(value)) }
    }

    public mutating func set(_ key: String, _ value: UInt64?) {
        if let value { fields[key] = .uint(value) }
    }

    public mutating func set(_ key: String, _ value: Double?) {
        if let value { fields[key] = .double(value) }
    }

    public mutating func set(_ key: String, _ value: Bool?) {
        if let value { fields[key] = .bool(value) }
    }

    public mutating func set(_ key: String, _ value: [String]?) {
        if let value { fields[key] = .array(value.map { .string($0) }) }
    }

    public mutating func set(_ key: String, _ value: [Int]?) {
        if let value { fields[key] = .array(value.map { .int(Int64($0)) }) }
    }

    public mutating func set(_ key: String, _ value: [[String]]?) {
        if let value {
            fields[key] = .array(value.map { group in .array(group.map { .string($0) }) })
        }
    }

    public mutating func set(_ key: String, _ value: [String: String]?) {
        if let value { fields[key] = .object(value.mapValues { .string($0) }) }
    }

    public mutating func set(_ key: String, _ value: [String: Bool]?) {
        if let value { fields[key] = .object(value.mapValues { .bool($0) }) }
    }

    public mutating func set(_ key: String, _ value: [String: [String]]?) {
        if let value {
            fields[key] = .object(value.mapValues { items in .array(items.map { .string($0) }) })
        }
    }

    public mutating func set<T: JSONModel>(_ key: String, _ value: T?) {
        if let value { fields[key] = value.json }
    }

    public mutating func set<T: JSONModel>(_ key: String, _ value: [T]?) {
        if let value { fields[key] = .array(value.map(\.json)) }
    }

    public mutating func set<T: JSONModel>(_ key: String, _ value: [String: T]?) {
        if let value { fields[key] = .object(value.mapValues(\.json)) }
    }

    /// Write the key even when the value is nil, as `null`.
    public mutating func setAllowingNull(_ key: String, _ value: String?) {
        fields[key] = value.map { .string($0) } ?? .null
    }

    /// Write the key even when the value is nil, as `null`.
    public mutating func setAllowingNull(_ key: String, _ value: Int?) {
        fields[key] = value.map { .int(Int64($0)) } ?? .null
    }
}
