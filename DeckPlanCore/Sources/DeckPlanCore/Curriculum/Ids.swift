//
//  Ids.swift
//  DeckPlanCore
//
//  Ids and the slug rule (docs/CURRICULUM_FORMAT.md §3). A port of `tools/core/ids.py`.
//
//  Stage `A|B|1..6`; skill `<stage>.<skill-slug>`; step `<stage>.<skill-slug>.<n>`;
//  activity `<slug>` (a second description of the same name gets a suffix);
//  equipment `<slug>`; topic `<stage>.<n>`; video `vimeo:<id>`.
//
//  The slug rule: lower-case the name, "&" becomes "and", punctuation is dropped,
//  spaces become "-" (Jump and Return -> jump-and-return;
//  Kick, Glide & Breathe -> kick-glide-and-breathe; 3-2-1 Splash! -> 3-2-1-splash).
//

import Foundation

/// Ids, the slug rule, and the curriculum's small fixed vocabularies
/// (docs/CURRICULUM_FORMAT.md §3; `tools/core/ids.py`).
public enum Ids {

    /// Stage ids in curriculum order.
    public static let stageIds: [String] = ["A", "B", "1", "2", "3", "4", "5", "6"]

    /// Each stage id's position in `stageIds`, for sorting and "is this a stage id" checks.
    public static let stageIndex: [String: Int] =
        Dictionary(uniqueKeysWithValues: stageIds.enumerated().map { ($1, $0) })

    /// Activity age tags: preschool, school age, adult.
    public static let ageTags: [String] = ["P", "S", "A"]

    /// Stage age groups.
    public static let ageGroups: [String] = ["infantToddler", "preschool", "schoolAge", "teen", "adult"]

    /// Depth zones.
    public static let zones: [String] = ["shallow", "medium", "deep"]

    /// Lesson-template block kinds.
    public static let blockKinds: [String] = ["welcome", "warmUp", "review", "introduce", "topic", "wrapUp"]

    /// The skill id a Review or Introduce block uses to mean "any skill of the stage".
    public static let anySkill = "any"

    // MARK: - The slug rule

    /// The slug rule (docs/CURRICULUM_FORMAT.md §3): NFKD-normalize, drop combining
    /// marks, lower-case, "&" -> " and ", the Unicode dash variants -> space, keep
    /// only `[a-z0-9-]` (everything else punctuation is dropped, whitespace becomes
    /// "-"), collapse repeated "-" and trim it from both ends.
    ///
    /// Returns "" for a name with no letters or digits, or for a non-string input.
    public static func slug(_ name: String?) -> String {
        guard let name else { return "" }
        // NFKD, then strip every combining mark (unicodedata.combining(ch) != 0).
        let decomposed = name.decomposedStringWithCompatibilityMapping
        let strippedScalars = decomposed.unicodeScalars.filter {
            $0.properties.canonicalCombiningClass == .notReordered
        }
        var working = String(String.UnicodeScalarView(strippedScalars)).lowercased()
        working = working.replacingOccurrences(of: "&", with: " and ")
        for dash in dashes {
            working = working.replacingOccurrences(of: dash, with: " ")
        }

        var kept = String.UnicodeScalarView()
        let whitespace = CharacterSet.whitespacesAndNewlines
        for scalar in working.unicodeScalars {
            if ("a"...("z" as UnicodeScalar)).contains(scalar) || ("0"...("9" as UnicodeScalar)).contains(scalar)
                || scalar == "-" {
                kept.append(scalar)
            } else if whitespace.contains(scalar) {
                kept.append(" ")
            }
            // every other character is punctuation (or non-ASCII) and is dropped
        }
        let words = String(String.UnicodeScalarView(kept)).split(separator: " ", omittingEmptySubsequences: true)
        let joined = words.joined(separator: "-")
        return collapseDashes(joined).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Collapse two or more consecutive "-" into one (the equivalent of Python's
    /// `re.sub(r"-{2,}", "-", text)`).
    private static func collapseDashes(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.count)
        var previousWasDash = false
        for ch in text {
            if ch == "-" {
                if !previousWasDash { out.append(ch) }
                previousWasDash = true
            } else {
                out.append(ch)
                previousWasDash = false
            }
        }
        return out
    }

    /// The Unicode dash variants the slug rule and `normalizeText` treat specially
    /// (hyphen, non-breaking hyphen, figure dash, en dash, em dash, horizontal bar,
    /// minus sign) — `tools/core/ids.py`'s `_DASHES`.
    static let dashes: [String] = ["\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2015}", "\u{2212}"]

    /// Fancy quote and prime characters `normalizeText` folds to plain ASCII quotes
    /// — `tools/core/ids.py`'s `_QUOTES`.
    static let quotes: [(String, String)] = [
        ("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201A}", "'"), ("\u{201B}", "'"),
        ("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{201E}", "\""),
        ("\u{2032}", "'"), ("\u{2033}", "\""),
    ]

    // MARK: - Shape checks

    public static func isSlug(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        return parts.allSatisfy { part in part.allSatisfy(isLowerAlnum) }
    }

    private static func isLowerAlnum(_ ch: Character) -> Bool {
        guard ch.unicodeScalars.count == 1, let scalar = ch.unicodeScalars.first else { return false }
        return ("a"...("z" as UnicodeScalar)).contains(scalar) || ("0"...("9" as UnicodeScalar)).contains(scalar)
    }

    public static func isStageId(_ value: String?) -> Bool {
        guard let value else { return false }
        return stageIndex[value] != nil
    }

    public static func stageSortKey(_ stageId: String) -> Int {
        stageIndex[stageId] ?? stageIds.count
    }

    // MARK: - Building ids

    public static func skillId(_ stageId: String, _ skillSlug: String) -> String {
        "\(stageId).\(skillSlug)"
    }

    public static func stepId(_ stageId: String, _ skillSlug: String, _ n: Int) -> String {
        "\(stageId).\(skillSlug).\(n)"
    }

    public static func topicCode(_ stageId: String, _ n: Int) -> String {
        "\(stageId).\(n)"
    }

    public static func videoId(_ vimeoId: String) -> String {
        "vimeo:\(vimeoId)"
    }

    /// `<slug>`, or `<slug>-<suffix-slug>` when `suffix` names what differs
    /// between two same-named entries (docs/CURRICULUM_FORMAT.md §3, §5 step 3).
    public static func activityId(name: String?, suffix: String? = nil) -> String {
        let base = slug(name)
        guard let suffix, !suffix.isEmpty else { return base }
        return "\(base)-\(slug(suffix))"
    }

    // MARK: - Parsing ids

    /// "1.front-glide" -> ("1", "front-glide"); nil when malformed.
    public static func parseSkillId(_ value: String?) -> (stage: String, skillSlug: String)? {
        guard let value, let groups = firstMatch(skillIdPattern, value) else { return nil }
        return (groups[0], groups[1])
    }

    /// "1.front-glide.3" -> ("1", "front-glide", 3); nil when malformed.
    public static func parseStepId(_ value: String?) -> (stage: String, skillSlug: String, n: Int)? {
        guard let value, let groups = firstMatch(stepIdPattern, value), let n = Int(groups[2]) else { return nil }
        return (groups[0], groups[1], n)
    }

    /// "1.5" -> ("1", 5); nil when malformed.
    public static func parseTopicCode(_ value: String?) -> (stage: String, n: Int)? {
        guard let value, let groups = firstMatch(topicCodePattern, value), let n = Int(groups[1]) else { return nil }
        return (groups[0], n)
    }

    /// "vimeo:172429568" -> "172429568"; nil when malformed.
    public static func parseVideoId(_ value: String?) -> String? {
        guard let value, let groups = firstMatch(videoIdPattern, value) else { return nil }
        return groups[0]
    }

    /// The Vimeo id in a Vimeo url (`https://vimeo.com/<id>`, or
    /// `https://vimeo.com/album/<n>/video/<id>`, optionally with a private hash
    /// segment and a query or fragment), or nil when the url is not a Vimeo url.
    public static func vimeoId(fromURL url: String?) -> String? {
        guard let url, let groups = firstMatch(vimeoURLPattern, url) else { return nil }
        return groups[0]
    }

    /// "2.front-glide.1" -> "2 / Front glide / 1", the way the renderer prints a
    /// step whose stage isn't loaded (docs/SPEC.md §6.1): the slug in sentence
    /// case, no step name.
    public static func stepLabel(_ stepIdValue: String) -> String {
        guard let parsed = parseStepId(stepIdValue) else { return stepIdValue }
        let words = parsed.skillSlug.replacingOccurrences(of: "-", with: " ")
        let sentenceCase = words.isEmpty ? words : words.prefix(1).uppercased() + words.dropFirst()
        return "\(parsed.stage) / \(sentenceCase) / \(parsed.n)"
    }

    // MARK: - Text normalization

    /// Whitespace, quotes and dashes normalized; used to compare printed text.
    public static func normalizeText(_ value: String?) -> String {
        guard let value else { return "" }
        var working = value.precomposedStringWithCompatibilityMapping   // NFKC
        for (fancy, plain) in quotes { working = working.replacingOccurrences(of: fancy, with: plain) }
        for dash in dashes { working = working.replacingOccurrences(of: dash, with: "-") }
        let words = working.split(whereSeparator: { $0.isWhitespace })
        return words.joined(separator: " ")
    }

    /// The normalized description used by the assembler's dedupe.
    public static func descriptionKey(_ value: String?) -> String {
        normalizeText(value).folding(options: .caseInsensitive, locale: nil)
    }

    // MARK: - Regular expressions (NSRegularExpression: Foundation only, no third-party regex engine)

    private static let skillIdPattern = try! NSRegularExpression(
        pattern: "^([AB1-6])\\.([a-z0-9]+(?:-[a-z0-9]+)*)$")
    private static let stepIdPattern = try! NSRegularExpression(
        pattern: "^([AB1-6])\\.([a-z0-9]+(?:-[a-z0-9]+)*)\\.([1-9][0-9]*)$")
    private static let topicCodePattern = try! NSRegularExpression(
        pattern: "^([AB1-6])\\.([1-9][0-9]*)$")
    private static let videoIdPattern = try! NSRegularExpression(
        pattern: "^vimeo:([0-9]+)$")
    private static let vimeoURLPattern = try! NSRegularExpression(
        pattern: "^https://vimeo\\.com/(?:album/[0-9]+/video/)?([0-9]+)(?:/[0-9a-f]+)?(?:[?#].*)?$")

    /// The pattern's capture groups (index 1.., in order) when it matches `value`
    /// in full; nil when it does not match at all or matches only part of it.
    private static func firstMatch(_ regex: NSRegularExpression, _ value: String) -> [String]? {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let result = regex.firstMatch(in: value, range: range), result.range == range else { return nil }
        guard result.numberOfRanges > 1 else { return [] }
        return (1..<result.numberOfRanges).map { index in
            let groupRange = result.range(at: index)
            guard groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: value) else { return "" }
            return String(value[swiftRange])
        }
    }
}
