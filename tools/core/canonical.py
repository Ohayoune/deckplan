"""Canonical hashing and JSON encoding (docs/CANONICAL_JSON.md).

`hash_parts` is the only hash the Core ever uses on plan-relevant data —
never a language's built-in `hash()`, which Python randomizes per process
(docs/CANONICAL_JSON.md; the "Determinism" rule). `dumps` is the Core's own
canonical JSON encoder: the plan JSON and every `inputsHash` are built
from it, so its escaping and number rules are pinned exactly here — not
inherited from `json.dumps`'s own defaults, which disagree on non-ASCII
escaping and float formatting — for a Swift port to match byte for byte.
"""

import hashlib
import json
import math

__all__ = ["hash_parts", "dumps", "sha256_hex", "loads"]


def hash_parts(*parts):
    """The seeded, deterministic hash (docs/CANONICAL_JSON.md).

    The first 8 bytes of SHA-256, read as an unsigned big-endian integer,
    over `parts` joined with "|" in UTF-8. Each part is either `str` (used
    as is) or `int` (its decimal string) — `bool` is rejected, since no
    documented part is a bool and `True`/`False` would otherwise silently
    hash as "True"/"False" rather than "1"/"0".

    `hash_parts("abc") == 13436514500253700074` (0xba7816bf8f01cfea);
    `hash_parts(12345, 0, "1.front-glide", "puffin-rocket-ride") == 7132184755009805105`
    (hashes "12345|0|1.front-glide|puffin-rocket-ride"); `hash_parts("L5") ==
    13095845880559124262` (D9's lesson seed, above the signed 64-bit max).
    A block without a skill uses its block kind ("welcome") as the skill part.
    """
    pieces = []
    for part in parts:
        if isinstance(part, str):
            pieces.append(part)
        elif isinstance(part, int) and not isinstance(part, bool):
            pieces.append(str(part))
        else:
            raise TypeError("hash_parts takes only str and int parts, got %r" % (part,))
    digest = hashlib.sha256("|".join(pieces).encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


# ---------------------------------------------------------------------------
# canonical JSON — a hand-written encoder (docs/CANONICAL_JSON.md), not a wrapper
# over `json.dumps`: its `ensure_ascii` default escapes non-ASCII and its
# float formatting doesn't match the integral-becomes-int rule below.

_ESCAPES = {
    '"': '\\"',
    "\\": "\\\\",
    "\b": "\\b",
    "\f": "\\f",
    "\n": "\\n",
    "\r": "\\r",
    "\t": "\\t",
}


def _dump_string(value):
    """A JSON string literal escaping only `"`, `\\` and U+0000-U+001F
    (short forms for `\\b \\f \\n \\r \\t`, else `\\u00xx` lower-case hex);
    "/" and non-ASCII characters are written through unescaped."""
    out = ['"']
    for ch in value:
        escape = _ESCAPES.get(ch)
        if escape is not None:
            out.append(escape)
        elif ch < " ":
            out.append("\\u%04x" % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def _dump_number(value):
    """`bool` is handled by the caller; an int is its decimal string; a
    float with an integral value is written as an integer (`7.0` -> `7`);
    any other float is written via `repr`, Python's shortest string that
    reads back to the same float (`5.75`, `0.1`, `1e-07`). NaN and the
    infinities have no JSON representation and raise `ValueError`."""
    if isinstance(value, int):
        return str(value)
    if math.isnan(value) or math.isinf(value):
        raise ValueError("dumps cannot encode a non-finite float: %r" % (value,))
    if value.is_integer():
        return str(int(value))
    return repr(value)


def _dump_value(value):
    if value is None:
        return "null"
    if isinstance(value, bool):  # before int: bool is an int subclass, never a number
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return _dump_number(value)
    if isinstance(value, str):
        return _dump_string(value)
    if isinstance(value, (list, tuple)):
        return "[" + ",".join(_dump_value(item) for item in value) + "]"
    if isinstance(value, dict):
        return _dump_object(value)
    raise TypeError("dumps cannot encode %r of type %s" % (value, type(value).__name__))


def _dump_object(value):
    for key in value:
        if not isinstance(key, str):
            raise TypeError("dumps object keys must be str, got %r" % (key,))
    # Python's `str` already compares by Unicode code point, so sorting the
    # keys with the plain `<` order sorts them by code point (docs/CANONICAL_JSON.md).
    items = sorted(value.items(), key=lambda pair: pair[0])
    return "{" + ",".join(_dump_string(key) + ":" + _dump_value(item) for key, item in items) + "}"


def dumps(value):
    """Canonical JSON of `value` (docs/CANONICAL_JSON.md): UTF-8, object keys
    sorted by Unicode code point, no insignificant whitespace, numbers and
    strings as `_dump_number`/`_dump_string` describe, lists in their given
    order. `dumps({"b": 1, "a": [7.0, 1.5, "é/x"]}) ==
    '{"a":[7,1.5,"é/x"],"b":1}'`.
    """
    return _dump_value(value)


def sha256_hex(text):
    """Lower-case hex SHA-256 of `text`, encoded UTF-8 (docs/CANONICAL_JSON.md).

    Used both directly (`localHash`) and over `dumps(...)` output to make
    `inputsHash` and the plan's content hashes.
    """
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def loads(text):
    """`json.loads`, kept here only for symmetry with `dumps` in callers and tests."""
    return json.loads(text)
