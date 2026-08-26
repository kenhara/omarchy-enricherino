#!/usr/bin/env python3
"""Exclusive-write helper for Enricherino cache files (last.json).

Jails --file under ~/.cache/enricherino or ~/.config/enricherino.
Reads body from stdin (capped). Never prints file contents or secrets.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from secure_io import is_path_jailed, write_exclusive

MAX_STDIN_BYTES = 1 * 1024 * 1024


def main() -> int:
    p = argparse.ArgumentParser(description="Jailed exclusive cache write")
    p.add_argument("--file", required=True, help="destination path (must stay in jail)")
    args = p.parse_args()
    dest = str(args.file or "")
    if not dest or not is_path_jailed(dest):
        sys.stderr.write("write-cache: path not allowed\n")
        return 1

    raw = sys.stdin.buffer.read(MAX_STDIN_BYTES + 1)
    if len(raw) > MAX_STDIN_BYTES:
        sys.stderr.write("write-cache: stdin too large\n")
        return 1

    try:
        write_exclusive(Path(dest), raw)
    except Exception as e:
        sys.stderr.write(f"write-cache: write failed: {e}\n")
        return 1

    sys.stdout.write(json.dumps({"ok": True, "path": dest}, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
