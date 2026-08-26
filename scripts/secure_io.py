#!/usr/bin/env python3
"""Shared exclusive-write + path-jail helpers for Enricherino.

Dest dir is created mode 0700. Writes use a unique temp in that dir:
  os.open(O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0o600) → write → fsync → close → os.replace
Never follows a dest symlink (replace swaps the name). Never opens dest for write.
"""
from __future__ import annotations

import os
import secrets
from pathlib import Path


DEFAULT_FILE_MODE = 0o600
DEFAULT_DIR_MODE = 0o700


def jail_roots(home: Path | None = None) -> list[Path]:
    home_path = Path(home) if home is not None else Path.home()
    home_res = home_path.resolve()
    return [
        (home_res / ".config" / "enricherino").resolve(),
        (home_res / ".cache" / "enricherino").resolve(),
    ]


def is_path_jailed(path: str | os.PathLike[str], roots: list[Path] | None = None) -> bool:
    """True when realpath(path) is inside ~/.config/enricherino or ~/.cache/enricherino."""
    if not path:
        return False
    allowed = roots if roots is not None else jail_roots()
    try:
        resolved = Path(path).resolve()
    except Exception:
        return False
    for root in allowed:
        try:
            root_res = root if root.is_absolute() else root.resolve()
            resolved.relative_to(root_res)
            return True
        except Exception:
            continue
    return False


def ensure_dir_mode(path: str | os.PathLike[str], mode: int = DEFAULT_DIR_MODE) -> None:
    p = Path(path)
    p.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(os.fspath(p), mode)
    except Exception:
        pass


def write_exclusive(
    dest: str | os.PathLike[str],
    data: bytes | str,
    *,
    mode: int = DEFAULT_FILE_MODE,
) -> None:
    """Write data via exclusive temp + os.replace. Dest dir mkdir 0700."""
    dest_path = Path(dest)
    dest_dir = dest_path.parent
    ensure_dir_mode(dest_dir)
    payload = data if isinstance(data, (bytes, bytearray)) else str(data).encode("utf-8")

    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    flags |= getattr(os, "O_NOFOLLOW", 0)
    flags |= getattr(os, "O_NONBLOCK", 0)

    tmp_path: Path | None = None
    fd = -1
    last_err: Exception | None = None
    for _ in range(16):
        candidate = dest_dir / f".{dest_path.name}.{secrets.token_hex(8)}.tmp"
        try:
            fd = os.open(os.fspath(candidate), flags, mode)
            tmp_path = candidate
            break
        except FileExistsError as e:
            last_err = e
            continue
        except OSError as e:
            last_err = e
            continue
    if fd < 0 or tmp_path is None:
        raise OSError(f"exclusive temp create failed: {last_err}")

    try:
        view = memoryview(payload)
        while len(view):
            n = os.write(fd, view)
            if n <= 0:
                raise OSError("short write")
            view = view[n:]
        os.fsync(fd)
    except Exception:
        try:
            os.close(fd)
        except Exception:
            pass
        fd = -1
        try:
            os.unlink(os.fspath(tmp_path))
        except Exception:
            pass
        raise
    os.close(fd)
    os.replace(os.fspath(tmp_path), os.fspath(dest_path))
    try:
        os.chmod(os.fspath(dest_path), mode)
    except Exception:
        pass
