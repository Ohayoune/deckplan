"""Ids and the slug rule (CURRICULUM_FORMAT.md §3).

Stage `A|B|1..6`; skill `<stage>.<skill-slug>`; step `<stage>.<skill-slug>.<n>`;
activity `<slug>` (a second description of the same name gets a suffix);
equipment `<slug>`; topic `<stage>.<n>`; video `vimeo:<id>`.

The slug rule: lower-case the name, "&" becomes "and", punctuation is dropped,
spaces become "-" (Jump and Return -> jump-and-return;
Kick, Glide & Breathe -> kick-glide-and-breathe; 3-2-1 Splash! -> 3-2-1-splash).
"""

import re
import unicodedata

STAGE_IDS = ("A", "B", "1", "2", "3", "4", "5", "6")
STAGE_INDEX = {stage: index for index, stage in enumerate(STAGE_IDS)}

AGE_TAGS = ("P", "S", "A")
AGE_GROUPS = ("infantToddler", "preschool", "schoolAge", "teen", "adult")
ZONES = ("shallow", "medium", "deep")
BLOCK_KINDS = ("welcome", "warmUp", "review", "introduce", "topic", "wrapUp")
ANY_SKILL = "any"

_SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
_STEP_RE = re.compile(r"^([AB1-6])\.([a-z0-9]+(?:-[a-z0-9]+)*)\.([1-9][0-9]*)$")
_SKILL_RE = re.compile(r"^([AB1-6])\.([a-z0-9]+(?:-[a-z0-9]+)*)$")
_TOPIC_RE = re.compile(r"^([AB1-6])\.([1-9][0-9]*)$")
_VIDEO_RE = re.compile(r"^vimeo:([0-9]+)$")
# https://vimeo.com/<id>, https://vimeo.com/album/<n>/video/<id>, optionally with a
# private hash segment and a query or fragment.
_VIMEO_URL_RE = re.compile(
    r"^https://vimeo\.com/(?:album/[0-9]+/video/)?([0-9]+)(?:/[0-9a-f]+)?(?:[?#].*)?$")

_DASHES = "‐‑‒–—―−"
_QUOTES = {"‘": "'", "’": "'", "‚": "'", "‛": "'",
           "“": '"', "”": '"', "„": '"', "′": "'", "″": '"'}


def slug(name):
    """The slug rule. Returns "" for a name with no letters or digits."""
    if not isinstance(name, str):
        return ""
    text = unicodedata.normalize("NFKD", name)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = text.lower().replace("&", " and ")
    for dash in _DASHES:
        text = text.replace(dash, " ")
    kept = []
    for ch in text:
        if ("a" <= ch <= "z") or ("0" <= ch <= "9") or ch == "-":
            kept.append(ch)
        elif ch.isspace():
            kept.append(" ")
        # every other character is punctuation (or non-ASCII) and is dropped
    text = "-".join("".join(kept).split())
    text = re.sub(r"-{2,}", "-", text).strip("-")
    return text


def is_slug(value):
    return isinstance(value, str) and bool(_SLUG_RE.match(value))


def is_stage_id(value):
    return isinstance(value, str) and value in STAGE_INDEX


def stage_sort_key(stage_id):
    return STAGE_INDEX.get(stage_id, len(STAGE_IDS))


def skill_id(stage_id, skill_slug):
    return "%s.%s" % (stage_id, skill_slug)


def step_id(stage_id, skill_slug, n):
    return "%s.%s.%d" % (stage_id, skill_slug, n)


def topic_code(stage_id, n):
    return "%s.%d" % (stage_id, n)


def video_id(vimeo_id):
    return "vimeo:%s" % vimeo_id


def activity_id(name, suffix=None):
    base = slug(name)
    return base if not suffix else "%s-%s" % (base, slug(str(suffix)))


def parse_skill_id(value):
    """'1.front-glide' -> ('1', 'front-glide'); None when malformed."""
    if not isinstance(value, str):
        return None
    match = _SKILL_RE.match(value)
    return (match.group(1), match.group(2)) if match else None


def parse_step_id(value):
    """'1.front-glide.3' -> ('1', 'front-glide', 3); None when malformed."""
    if not isinstance(value, str):
        return None
    match = _STEP_RE.match(value)
    return (match.group(1), match.group(2), int(match.group(3))) if match else None


def parse_topic_code(value):
    """'1.5' -> ('1', 5); None when malformed."""
    if not isinstance(value, str):
        return None
    match = _TOPIC_RE.match(value)
    return (match.group(1), int(match.group(2))) if match else None


def parse_video_id(value):
    """'vimeo:172429568' -> '172429568'; None when malformed."""
    if not isinstance(value, str):
        return None
    match = _VIDEO_RE.match(value)
    return match.group(1) if match else None


def vimeo_id_from_url(url):
    """The Vimeo id in a Vimeo url, or None when the url is not a Vimeo url."""
    if not isinstance(url, str):
        return None
    match = _VIMEO_URL_RE.match(url)
    return match.group(1) if match else None


def step_label(step_id_value):
    """'2.front-glide.1' -> '2 / Front glide / 1', the way the renderer prints a step
    whose stage isn't loaded (SPEC §6.1): the slug in sentence case, no step name."""
    parsed = parse_step_id(step_id_value)
    if not parsed:
        return str(step_id_value)
    stage, skill_slug, n = parsed
    words = skill_slug.replace("-", " ")
    return "%s / %s / %d" % (stage, words[:1].upper() + words[1:], n)


def normalize_text(value):
    """Whitespace, quotes and dashes normalized; used to compare printed text."""
    if not isinstance(value, str):
        return ""
    text = unicodedata.normalize("NFKC", value)
    for fancy, plain in _QUOTES.items():
        text = text.replace(fancy, plain)
    for dash in _DASHES:
        text = text.replace(dash, "-")
    return " ".join(text.split())


def description_key(value):
    """The normalized description used by the assembler's dedupe."""
    return normalize_text(value).casefold()
