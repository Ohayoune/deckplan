"""Copy the owner's curriculum into the app bundle folder.

    python3 tools/dev/sync_resources.py [--check] [--demo]

DeckPlan/Resources/curriculum/  <- curriculum/ (version.json, stages/*.json, activities.json,
                                   equipment.json, safety.json, videos.json, local.json)
       with --demo               <- examples/curriculum.stage*.sample.json (Stages 1, 2 and 4)

The destination is gitignored (**/Resources/curriculum/): the YMCA content goes into the
owner's build only (v1 SPEC D20). --check exits 1 when a destination is missing or stale,
writing nothing. --demo bundles the made-up samples instead, which is what a build for
anyone else carries: the app loads every `*.sample.json` together, one stage each, through
the same validator and runs on invented content. Run before building the app.
"""

import argparse
import filecmp
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CURRICULUM = ROOT / "curriculum"
APP = ROOT / "DeckPlan" / "Resources"
EXAMPLES = ROOT / "examples"
CURRICULUM_FILES = ("version.json", "activities.json", "equipment.json", "safety.json", "videos.json", "local.json")


def pairs(demo=False):
    """(source, destination) for every file to copy; a missing source is reported, not copied."""
    if demo:
        return [(path, APP / "curriculum" / path.name) for path in sorted(EXAMPLES.glob("curriculum.stage*.sample.json"))]
    out = []
    for name in CURRICULUM_FILES:
        out.append((CURRICULUM / name, APP / "curriculum" / name))
    stages = CURRICULUM / "stages"
    if stages.is_dir():
        for path in sorted(stages.glob("*.json")):
            out.append((path, APP / "curriculum" / "stages" / path.name))
    return out


def main(argv=None):
    parser = argparse.ArgumentParser(description="Copy curriculum/ into DeckPlan/Resources/.")
    parser.add_argument("--check", action="store_true", help="exit 1 if a destination is missing or stale; write nothing")
    parser.add_argument("--demo", action="store_true",
                        help="bundle the made-up sample instead of curriculum/ (the app then runs on invented content)")
    args = parser.parse_args(argv)
    if not args.check:
        # The two are mutually exclusive in the bundle: whichever was there before goes.
        if args.demo:
            shutil.rmtree(APP / "curriculum", ignore_errors=True)
        else:
            for path in [APP / "curriculum" / "sample.json", *(APP / "curriculum").glob("*.sample.json")]:
                path.unlink(missing_ok=True)
    missing, stale, copied = [], [], 0
    for source, destination in pairs(args.demo):
        if not source.is_file():
            missing.append(source.relative_to(ROOT))
            continue
        if destination.is_file() and filecmp.cmp(source, destination, shallow=False):
            continue
        if args.check:
            stale.append(destination.relative_to(ROOT))
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        copied += 1
    for path in missing:
        print("missing source: %s" % path, file=sys.stderr)
    if args.check:
        for path in stale:
            print("stale: %s" % path, file=sys.stderr)
        print("up to date" if not stale else "%d file(s) out of date: python3 tools/dev/sync_resources.py" % len(stale))
        return 1 if stale else 0
    print("copied %d file(s) into %s%s" % (copied, APP.relative_to(ROOT), " (the made-up samples)" if args.demo else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
