"""Check that every relative link and #anchor in the repo's Markdown resolves.

Run by prek over all *.md files. External (http, mailto) links are skipped.
Anchors follow GitHub's slug rules: lowercase, punctuation dropped, spaces to
hyphens.
"""

import re
import sys
from pathlib import Path

LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
HEADING = re.compile(r"^#{1,6}\s+(.*?)\s*#*\s*$", re.MULTILINE)
CODE = re.compile(r"```.*?```", re.DOTALL)


def slug(heading: str) -> str:
    """Return GitHub's anchor for a heading."""
    text = re.sub(r"[^\w\- ]", "", heading.strip().lower())
    return text.replace(" ", "-")


def anchors(path: Path) -> set[str]:
    """Return every heading anchor in a Markdown file."""
    text = CODE.sub("", path.read_text(encoding="utf-8"))
    return {slug(h) for h in HEADING.findall(text)}


def main() -> int:
    """Check every Markdown file under the repo; print and count failures."""
    root = Path(__file__).resolve().parent.parent
    failures = 0
    for page in sorted(root.rglob("*.md")):
        if any(part.startswith(".") for part in page.relative_to(root).parts):
            continue
        text = CODE.sub("", page.read_text(encoding="utf-8"))
        for target in LINK.findall(text):
            if re.match(r"[a-z]+:", target):
                continue
            file_part, _, anchor = target.partition("#")
            dest = (page.parent / file_part).resolve() if file_part else page
            if not dest.exists():
                print(f"{page.relative_to(root)}: missing {target}")
                failures += 1
            elif anchor and dest.suffix == ".md" and anchor not in anchors(dest):
                print(f"{page.relative_to(root)}: no anchor #{anchor} in {file_part or page.name}")
                failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
