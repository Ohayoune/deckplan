"""Print the text of PDF pages, plain or column-preserving. Dev aid for M1 transcription.

The toolkit's progression pages have three columns (Prerequisite / Stage progression /
Advanced) that interleave in plain extraction; --layout keeps them side by side.

usage: python3 tools/dev/pdf_text.py FILE.pdf PAGES [--layout]
PAGES are 1-based: "8", "8-9", "5,8,12-13".
"""

import sys

from pypdf import PdfReader


def parse_pages(spec, count):
    pages = []
    for part in spec.split(","):
        first, _, last = part.partition("-")
        start, end = int(first), int(last or first)
        if not 1 <= start <= end <= count:
            raise ValueError(f"page range {part} outside 1-{count}")
        pages.extend(range(start, end + 1))
    return pages


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    reader = PdfReader(argv[1])
    mode = "layout" if "--layout" in argv[3:] else "plain"
    for n in parse_pages(argv[2], len(reader.pages)):
        print(f"===== PAGE {n} ({mode}) =====")
        print(reader.pages[n - 1].extract_text(extraction_mode=mode) or "")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
