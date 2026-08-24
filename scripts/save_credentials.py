#!/usr/bin/env python3
"""Write ZoomInfo credentials to ~/.config/enricherino/credentials.json (mode 0600).

Prefer one-shot JSON on stdin (so secrets are not long-lived in argv):
  {"zoominfoClientId":"…","zoominfoClientSecret":"…"}

If stdin is empty, fall back to ZOOMINFO_CLIENT_ID / ZOOMINFO_CLIENT_SECRET env.
Never prints secret values. Dir is created mode 0700.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

CRED_DIR = Path.home() / ".config" / "enricherino"
CRED_PATH = CRED_DIR / "credentials.json"


def load_from_stdin() -> dict | None:
    raw = sys.stdin.read()
    if not raw or not raw.strip():
        return None
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("stdin JSON must be an object")
    return data


def load_from_env() -> dict:
    return {
        "zoominfoClientId": os.environ.get("ZOOMINFO_CLIENT_ID", "").strip(),
        "zoominfoClientSecret": os.environ.get("ZOOMINFO_CLIENT_SECRET", "").strip(),
    }


def main() -> int:
    try:
        data = load_from_stdin()
        if data is None:
            data = load_from_env()
    except Exception as e:
        sys.stderr.write(f"save_credentials: invalid input: {e}\n")
        return 2

    client_id = str(
        data.get("zoominfoClientId")
        or data.get("client_id")
        or data.get("clientId")
        or ""
    ).strip()
    client_secret = str(
        data.get("zoominfoClientSecret")
        or data.get("client_secret")
        or data.get("clientSecret")
        or ""
    ).strip()

    payload = {
        "zoominfoClientId": client_id,
        "zoominfoClientSecret": client_secret,
    }

    try:
        CRED_DIR.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(CRED_DIR, 0o700)
        except Exception:
            pass
        # Write via temp + replace so we never leave a half-written world-readable file.
        tmp = CRED_PATH.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
        try:
            os.chmod(tmp, 0o600)
        except Exception:
            pass
        tmp.replace(CRED_PATH)
        try:
            os.chmod(CRED_PATH, 0o600)
        except Exception:
            pass
    except Exception as e:
        sys.stderr.write(f"save_credentials: write failed: {e}\n")
        return 1

    sys.stdout.write(
        json.dumps(
            {
                "ok": True,
                "path": str(CRED_PATH),
                "hasClientId": bool(client_id),
                "hasClientSecret": bool(client_secret),
            },
            ensure_ascii=False,
        )
        + "\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
