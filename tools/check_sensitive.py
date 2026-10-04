"""Refuse commits that stage recordings, dumps, secrets or other sensitive files.

The repo is public (see CLAUDE.md), so anything with other people's data or
credentials must never be committed. Run by prek on every commit.
"""

import subprocess
import sys

BLOCKED = (
    ".wav",
    ".mp3",
    ".ogg",
    ".flac",
    ".m4a",  # voice recordings (proximity chat tests)
    ".mp4",
    ".mkv",
    ".mov",
    ".webm",  # screen recordings
    ".dmp",
    ".mdmp",
    ".log",  # crash dumps and logs can hold names and paths
    ".env",
    ".pem",
    ".key",
    ".pfx",
    ".p12",  # credentials
)


def main() -> int:
    """List staged files and fail on any with a blocked extension."""
    staged = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()
    bad = [name for name in staged if name.lower().endswith(BLOCKED)]
    for name in bad:
        print(f"refusing to commit sensitive file: {name}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
