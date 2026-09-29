"""Add every Swift file under DeckPlan/ and DeckPlanTests/ to DeckPlan.xcodeproj.

    python3 tools/dev/xcode_sources.py [--check]

The project lists its sources explicitly (objectVersion 56, no synchronized folders,
because Resources/curriculum must stay one folder reference that the bundle copies
whole). A new .swift file is added as a PBXFileReference and a PBXBuildFile, put in
the group of its directory (groups created as needed) and in its target's Sources
phase. Files already listed are left alone; nothing is removed — delete a stale
reference by hand. --check exits 1 when a file is missing from the project and
writes nothing. Run after adding a file, before building.
"""
import argparse
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PBXPROJ = ROOT / "DeckPlan.xcodeproj" / "project.pbxproj"

# (directory, root group id, Sources phase id) per target.
TARGETS = [
    ("DeckPlan", "1A0000000000000000000005", "1A0000000000000000000040"),
    ("DeckPlanTests", "1A0000000000000000000009", "1A0000000000000000000043"),
]
SKIP_DIRS = {"Resources", "Assets.xcassets"}


def quoted(name):
    """A pbxproj string: bare when it is only [A-Za-z0-9_./], quoted otherwise ("+")."""
    return name if re.fullmatch(r"[A-Za-z0-9_./]+", name) else f'"{name}"'


def oid(prefix, key):
    """A stable 24-hex object id from a path."""
    return prefix + hashlib.sha1(key.encode()).hexdigest()[:22].upper()


def block(text, object_id):
    """(start, end) of the object block `<id> ... = { ... };` at two tabs of indent."""
    start = text.find(f"\n\t\t{object_id} ")
    if start < 0:
        raise KeyError(object_id)
    start += 1
    end = text.find("\n\t\t};", start)
    return start, end + len("\n\t\t};")


def children_of(text, group_id):
    start, end = block(text, group_id)
    body = text[start:end]
    match = re.search(r"children = \((.*?)\);", body, re.S)
    return re.findall(r"([0-9A-F]{24}) /\*", match.group(1))


def add_to_list(text, object_id, list_key, line):
    """Append `line` inside `list_key = ( ... );` of the object block."""
    start, end = block(text, object_id)
    body = text[start:end]
    marker = f"{list_key} = (\n"
    at = body.find(marker)
    if at < 0:
        raise ValueError(f"{object_id} has no {list_key}")
    close = body.find("\t\t\t);", at)
    body = body[:close] + line + body[close:]
    return text[:start] + body + text[end:]


def file_ref_path(text, ref_id):
    start, end = block(text, ref_id)
    match = re.search(r"path = ([^;]+);", text[start:end])
    return match.group(1).strip('"') if match else None


def is_group(text, object_id):
    start, end = block(text, object_id)
    return "isa = PBXGroup;" in text[start:end]


def insert_before(text, marker, chunk):
    at = text.find(marker)
    if at < 0:
        raise ValueError(marker)
    return text[:at] + chunk + text[at:]


def ensure_group(text, parent_id, dir_rel, name, changes):
    """The group for `name` under `parent_id`, created when absent."""
    for child in children_of(text, parent_id):
        if is_group(text, child) and file_ref_path(text, child) == name:
            return text, child
    group_id = oid("1D", dir_rel)
    chunk = (f"\t\t{group_id} /* {name} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n"
             f"\t\t\tpath = {quoted(name)};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    text = insert_before(text, "/* End PBXGroup section */", chunk)
    text = add_to_list(text, parent_id, "children", f"\t\t\t\t{group_id} /* {name} */,\n")
    changes.append(f"group {dir_rel}")
    return text, group_id


def ensure_file(text, group_id, phase_id, file_rel, name, changes):
    for child in children_of(text, group_id):
        if not is_group(text, child) and file_ref_path(text, child) == name:
            return text
    ref_id = oid("1F", file_rel)
    build_id = oid("1E", file_rel)
    text = insert_before(
        text, "/* End PBXFileReference section */",
        f"\t\t{ref_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        f"path = {quoted(name)}; sourceTree = \"<group>\"; }};\n")
    text = insert_before(
        text, "/* End PBXBuildFile section */",
        f"\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* {name} */; }};\n")
    text = add_to_list(text, group_id, "children", f"\t\t\t\t{ref_id} /* {name} */,\n")
    text = add_to_list(text, phase_id, "files", f"\t\t\t\t{build_id} /* {name} in Sources */,\n")
    changes.append(f"file {file_rel}")
    return text


def sync(text):
    changes = []
    for directory, root_group, phase in TARGETS:
        base = ROOT / directory
        for path in sorted(base.rglob("*.swift")):
            rel = path.relative_to(base)
            if any(part in SKIP_DIRS for part in rel.parts):
                continue
            group_id = root_group
            walked = directory
            for part in rel.parts[:-1]:
                walked = f"{walked}/{part}"
                text, group_id = ensure_group(text, group_id, walked, part, changes)
            text = ensure_file(text, group_id, phase, f"{directory}/{rel.as_posix()}", rel.name, changes)
    return text, changes


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="report missing files, write nothing")
    args = parser.parse_args()
    original = PBXPROJ.read_text()
    updated, changes = sync(original)
    if not changes:
        print("project.pbxproj lists every Swift file.")
        return 0
    for change in changes:
        print(("missing " if args.check else "added ") + change)
    if args.check:
        return 1
    PBXPROJ.write_text(updated)
    print(f"project.pbxproj: {len(changes)} addition(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
