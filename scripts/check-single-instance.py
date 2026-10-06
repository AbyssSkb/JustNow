#!/usr/bin/env python3
"""Check that a busy journal lock exits before any journal data is read or written."""
import fcntl
import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary = Path(sys.argv[1] if len(sys.argv) > 1 else ".build/debug/JustNow").resolve()
assert binary.is_file(), f"Build JustNow first: {binary}"

with tempfile.TemporaryDirectory(prefix="justnow-lock-check-") as home:
    directory = Path(home) / "Library/Application Support/JustNow"
    directory.mkdir(parents=True)
    journal = directory / "journal.json"
    sentinel = b"This deliberately invalid journal must never be loaded."
    journal.write_bytes(sentinel)
    with (directory / ".instance-lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        subprocess.run(
            [str(binary)],
            env={**os.environ, "CFFIXED_USER_HOME": home},
            check=True,
            timeout=5,
        )
    assert journal.read_bytes() == sentinel, "A blocked instance changed the journal"
    assert not (directory / "journal.previous.json").exists()

print("PASS: a blocked instance exits without touching the isolated journal")
