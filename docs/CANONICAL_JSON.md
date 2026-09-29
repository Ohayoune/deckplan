# Canonical JSON and the hash

Every plan, shuffle and finder result is a pure function of its inputs: the same inputs give the same JSON, byte for byte, on any machine and in either implementation. Two definitions hold that together. The reference implementation is `tools/core/canonical.py`; the Swift port is `DeckPlanCore/Sources/DeckPlanCore/JSON/Canonical.swift`; `tests/test_canonical.py` and `CanonicalTests.swift` hold both to the values below.

## The hash

`hash(parts)` is the first 8 bytes, read as an unsigned big-endian integer, of SHA-256 over the parts joined with `|` in UTF-8. A part is a string (used as is) or an integer (its decimal string); a boolean is rejected. It is never a language's built-in hash, which Python randomizes per process and Swift seeds per process.

The result is an unsigned 64-bit integer (Swift `UInt64`); it can be above the signed range, so it is written in JSON as its exact decimal integer, never through a floating-point value. Every seeded draw in the Core goes through it. A block without a skill uses its block kind (`welcome`) as the skill part.

| Parts | Hash |
|---|---|
| `"abc"` | `13436514500253700074` (`0xba7816bf8f01cfea`) |
| `12345, 0, "1.front-glide", "puffin-rocket-ride"` | `7132184755009805105` |
| `"L5"` | `13095845880559124262` (above the signed 64-bit maximum) |

## Canonical JSON

The plan output, every saved record and every input hash use one encoding:

- UTF-8, with no insignificant whitespace;
- object keys sorted by Unicode code point;
- arrays keep their order;
- a number with an integral value is written as an integer (`7`, not `7.0`); any other number in its shortest round-trip form (`5.75`); NaN and the infinities are an error, never written;
- strings escape only `"`, `\` and control characters (`\b \f \n \r \t`, others as `\u00xx` in lower-case hex), so `/` and non-ASCII characters stay unescaped.

For example, `dumps({"b": 1, "a": [7.0, 1.5, "é/x"]})` is `{"a":[7,1.5,"é/x"],"b":1}`.

`sha256_hex(text)` is the lower-case hex SHA-256 of `text` encoded as UTF-8. `localHash` is `sha256_hex` of `local.json`'s canonical JSON.
