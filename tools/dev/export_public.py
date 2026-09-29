"""Copy the tracked tree, minus the owner's own notes, into a folder to publish.

    python3 tools/dev/export_public.py <folder> [--force]

Everything git tracks goes, except what was written for whoever builds the app (the agent
instruction files) and the owner's own record (docs/DECISIONS_LOG.md, BUILD_STATUS.md, IDEAS.md,
REDESIGN.md, DEVICE_CHECKLIST.md, docs/v1/, inputs/). Nothing gitignored is tracked, so the
curriculum, the reference PDFs and the app's bundled copy stay behind by themselves.

Before it writes anything it reads the files it is about to copy and refuses to export when
any of them carries toolkit text — a run of seven words shared with `reference/ymca-v6/text/`
(the same check as `tests/test_public.py`, which runs it over the whole tracked tree).
`--force` exports anyway and says what it found. With no `reference/` to compare against, the
check is skipped and says so.

Then, in the folder: `git init`, `git add -A`, one commit, and push it to the new repository.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = ROOT / "reference" / "ymca-v6" / "text"
RUN = 7
WORD = re.compile(r"[a-z0-9']+")

PRIVATE = ("CLAUDE.md", "AGENTS.md", "docs/DECISIONS_LOG.md", "docs/BUILD_STATUS.md", "docs/IDEAS.md",
           "docs/REDESIGN.md", "docs/DEVICE_CHECKLIST.md")
PRIVATE_DIRS = ("docs/v1/", "inputs/")
BINARY = (".png", ".jpg", ".jpeg", ".pdf", ".gif", ".icns", ".car", ".mp4", ".mov")
# Naming the source is not carrying its content: the version line every curriculum file
# holds, and the copyright notice itself, are meant to be there.
ALLOWED = ("ymca swim lessons v6 instructor toolkit yapp yslswim",
           "copyright 2016 by ymca of the usa all rights reserved",
           "copyright 2017 by ymca of the usa all rights reserved")


def is_attribution(run):
    """True for a run that is the copyright notice being quoted, not toolkit content."""
    return "copyright" in run and ("ymca" in run or "rights reserved" in run)


def is_private(path):
    return path in PRIVATE or any(path.startswith(d) for d in PRIVATE_DIRS)


def tracked(root=ROOT):
    out = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True).stdout
    return [line for line in out.split("\n") if line]


def runs(text):
    words = WORD.findall(text.lower())
    return {" ".join(words[i:i + RUN]) for i in range(len(words) - RUN + 1)}


def toolkit_runs(paths, root=ROOT, reference=REFERENCE):
    """{path: sorted runs} for every path that shares a seven-word run with the toolkit text.

    An empty result means nothing was found; `None` means there was nothing to compare
    against (no reference/, which is normal outside the owner's machine)."""
    reference = Path(reference)
    if not reference.is_dir():
        return None
    source = set()
    for folder, _, files in os.walk(reference):
        for name in files:
            source |= runs(Path(folder, name).read_text(encoding="utf-8", errors="ignore"))
    allowed = set()
    for sentence in ALLOWED:
        allowed |= runs(sentence)
    found = {}
    for path in paths:
        if path.endswith(BINARY):
            continue
        try:
            text = (Path(root) / path).read_text(encoding="utf-8")
        except (FileNotFoundError, IsADirectoryError, UnicodeDecodeError):
            continue
        hits = {run for run in (runs(text) & source) - allowed if not is_attribution(run)}
        if hits:
            found[path] = sorted(hits)
    return found


def main(argv=None):
    parser = argparse.ArgumentParser(description="Copy the tracked tree, minus the owner's notes, to a folder.")
    parser.add_argument("folder", help="where to write the copy (created; must be empty or new)")
    parser.add_argument("--force", action="store_true", help="export even when toolkit text is found")
    args = parser.parse_args(argv)

    files = [path for path in tracked() if not is_private(path)]
    found = toolkit_runs(files)
    if found is None:
        print("no reference/ymca-v6/text to compare against: the toolkit-text check was skipped")
    elif found:
        for path, hits in sorted(found.items()):
            print("toolkit text in %s: %s" % (path, hits[0]), file=sys.stderr)
        print("%d file(s) carry toolkit text." % len(found), file=sys.stderr)
        if not args.force:
            print("Nothing was written. Fix them, or re-run with --force.", file=sys.stderr)
            return 1

    folder = Path(args.folder).expanduser().resolve()
    if folder.exists() and any(folder.iterdir()):
        print("%s is not empty; give a new folder." % folder, file=sys.stderr)
        return 1
    for path in files:
        destination = folder / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / path, destination)
    left_out = len(tracked()) - len(files)
    print("%d file(s) -> %s (%d left behind: the owner's own notes)" % (len(files), folder, left_out))
    print("Then: cd %s && git init && git add -A && git commit" % folder)
    return 0


if __name__ == "__main__":
    sys.exit(main())
