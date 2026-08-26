#!/usr/bin/env python3
"""Enricherino — individual contact lookup via ZoomInfo GTM.

CLI for Omarchy bar-widget. Credentials (env wins over file):
  ZOOMINFO_CLIENT_ID / ZOOMINFO_CLIENT_SECRET
  or ~/.config/enricherino/credentials.json (mode 0600)

Mints a Bearer via client_credentials (cached under ~/.cache/enricherino/zi_token.json).
Never stores access_token in schema / shell.json. User-Agent version from manifest.json.
Not for blast outbound. Unofficial client.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import stat
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))
from secure_io import ensure_dir_mode, is_path_jailed, jail_roots, write_exclusive

ZOOMINFO_TOKEN = "https://api.zoominfo.com/gtm/oauth/v1/token"
ZOOMINFO_ENRICH = "https://api.zoominfo.com/gtm/data/v1/contacts/enrich"
PLUGIN_ID = "kenhara.enricherino"
TOKEN_CACHE_PATH = Path.home() / ".cache" / "enricherino" / "zi_token.json"
CREDENTIALS_PATH = Path.home() / ".config" / "enricherino" / "credentials.json"
TOKEN_SKEW_SEC = 60
MAX_HTTP_BYTES = 4 * 1024 * 1024   # 4 MiB
MAX_FILE_BYTES = 1 * 1024 * 1024   # 1 MiB
MAX_RECORD_CHARS = 256 * 1024
HUGE_FIELD_CHARS = 8192
DISPLAY_FIELD_CAP = 512
URL_FIELD_CAP = 2000
ERROR_ITEM_CAP = 512
MAX_ERROR_ITEMS = 16
ZOOMINFO_PINNED_SCHEME = "https"
ZOOMINFO_PINNED_HOST = "api.zoominfo.com"
_ASCII_CTRL_RE = re.compile(r"[\x00-\x1f\x7f]")


def read_text_capped(path: Path, limit: int = MAX_FILE_BYTES) -> str | None:
    """Bounded trust-path read: O_RDONLY|O_NOFOLLOW|O_NONBLOCK + S_ISREG.

    Used for credentials.json and zi_token.json. Manifest stays a normal read.
    """
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    fd = -1
    data = b""
    try:
        fd = os.open(os.fspath(path), flags)
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return None
        remaining = limit + 1
        while remaining > 0:
            chunk = os.read(fd, min(65536, remaining))
            if not chunk:
                break
            data += chunk
            remaining -= len(chunk)
    except Exception:
        return None
    finally:
        if fd >= 0:
            try:
                os.close(fd)
            except Exception:
                pass
    if len(data) > limit:
        return None
    try:
        return data.decode("utf-8", errors="replace")
    except Exception:
        return None


def read_manifest_version() -> str:
    try:
        # Plugin-dir manifest is not a user-writable trust path.
        manifest = Path(__file__).resolve().parent.parent / "manifest.json"
        raw = manifest.read_text(encoding="utf-8")
        data = json.loads(raw)
        ver = str(data.get("version") or "").strip()
        if ver:
            return ver
    except Exception:
        pass
    return "0.3.8"


VERSION = read_manifest_version()
USER_AGENT = f"Enricherino/{VERSION} (Omarchy unofficial; {PLUGIN_ID})"

FIELD_CAPS = {
    "name": DISPLAY_FIELD_CAP,
    "title": DISPLAY_FIELD_CAP,
    "company": DISPLAY_FIELD_CAP,
    "email": DISPLAY_FIELD_CAP,
    "phone": DISPLAY_FIELD_CAP,
    "linkedin": URL_FIELD_CAP,
    "twitter": URL_FIELD_CAP,
    "profile_url": URL_FIELD_CAP,
}


def sanitize_untrusted_text(value: Any, cap: int = DISPLAY_FIELD_CAP) -> str:
    """Neutralize untrusted enrich/API strings at model entry.

    Strip ``<`` ``>``; collapse ASCII controls to spaces; do not entity-escape.
    Cap length. Empty after cleanup stays empty.
    """
    if value is None:
        return ""
    s = str(value).replace("<", "").replace(">", "")
    s = _ASCII_CTRL_RE.sub(" ", s)
    if cap > 0 and len(s) > cap:
        s = s[:cap]
    return s


def payload_too_large(obj: Any, limit: int = MAX_RECORD_CHARS) -> bool:
    try:
        return len(json.dumps(obj, ensure_ascii=False)) > limit
    except Exception:
        return True


def is_pinned_zoominfo_url(url: str) -> bool:
    try:
        p = urlparse(url)
    except Exception:
        return False
    if (p.scheme or "").lower() != ZOOMINFO_PINNED_SCHEME:
        return False
    host = (p.hostname or "").lower()
    return host == ZOOMINFO_PINNED_HOST


def request_carries_secrets(headers: dict[str, str], body: bytes | None) -> bool:
    for k in headers:
        if str(k).lower() == "authorization":
            return True
    if body:
        low = body.lower()
        if b"client_secret" in low or b"client_id" in low:
            return True
    return False


def may_follow_redirect(headers: dict[str, str], body: bytes | None, newurl: str) -> bool:
    """Never follow when Authorization/client secrets are on the request.

    Token mint POST must not become a followed GET. Off-host Location is refused.
    Same-host 30x is also refused so secrets never copy across a hop.
    """
    if request_carries_secrets(headers, body):
        return False
    if not is_pinned_zoominfo_url(newurl):
        return False
    return False


class RefuseRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Do not emit a follow-up Request (Authorization is never copied)."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        raise urllib.error.HTTPError(
            getattr(req, "full_url", "") or "",
            int(code),
            "redirect refused",
            headers,
            fp,
        )


def build_api_opener() -> urllib.request.OpenerDirector:
    return urllib.request.build_opener(RefuseRedirectHandler)


def path_in_default_jail(path: Path) -> bool:
    return is_path_jailed(path, jail_roots())


RESULT_FIELDS = (
    "name",
    "title",
    "company",
    "email",
    "phone",
    "linkedin",
    "twitter",
    "profile_url",
)


def emit(obj: dict[str, Any], exit_code: int = 0) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()
    raise SystemExit(exit_code)


def empty_result() -> dict[str, Any]:
    return {
        "ok": False,
        "provider": "zoominfo",
        "mode": None,
        "result": {f: None for f in RESULT_FIELDS},
        "sources": {f: None for f in RESULT_FIELDS},
        "credits": {},
        "errors": [],
        "warnings": [],
        "raw_notes": [],
    }


def is_blank(v: Any) -> bool:
    return v is None or (isinstance(v, str) and not v.strip())


def pick(*vals: Any) -> Any:
    for v in vals:
        if not is_blank(v):
            if isinstance(v, str):
                return v.strip()
            return v
    return None


def normalize_profile_url(url: str | None) -> str | None:
    if is_blank(url):
        return None
    u = str(url).strip()
    if not re.match(r"^https?://", u, re.I):
        u = "https://" + u
    try:
        p = urlparse(u)
    except Exception:
        return u
    host = (p.netloc or "").lower().removeprefix("www.")
    path = p.path or ""
    if host in ("linkedin.com", "lnkd.in") or host.endswith(".linkedin.com"):
        return f"https://www.linkedin.com{path}".rstrip("/")
    if host in ("x.com", "twitter.com", "mobile.twitter.com"):
        return f"https://x.com{path}".rstrip("/")
    return u.rstrip("/")


def split_name(full: str | None) -> tuple[str | None, str | None]:
    if is_blank(full):
        return None, None
    parts = str(full).strip().split()
    if len(parts) == 1:
        return parts[0], None
    return parts[0], " ".join(parts[1:])


def _parse_http_body(raw: str, code: int) -> tuple[int, Any, str]:
    try:
        parsed: Any = json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        parsed = {"_raw": raw}
    if isinstance(parsed, (dict, list)) and payload_too_large(parsed):
        return 0, {"error": "record too large"}, "record too large"
    return code, parsed, raw


def http_request(
    method: str,
    url: str,
    headers: dict[str, str],
    body: bytes | None = None,
    timeout: float = 45.0,
) -> tuple[int, Any, str]:
    if not is_pinned_zoominfo_url(url):
        return 0, {"error": "url not pinned"}, "url not pinned"
    hdrs = dict(headers)
    hdrs.setdefault("User-Agent", USER_AGENT)
    # Refuse 30x whenever secrets are on the request (token body or Authorization).
    # Opener never follows; Authorization is never copied to Location.
    req = urllib.request.Request(url, data=body, headers=hdrs, method=method)
    opener = build_api_opener()
    try:
        with opener.open(req, timeout=timeout) as resp:
            raw_bytes = resp.read(MAX_HTTP_BYTES + 1)
            if len(raw_bytes) > MAX_HTTP_BYTES:
                return 0, {"error": "response too large"}, "response too large"
            raw = raw_bytes.decode("utf-8", errors="replace")
            code = int(getattr(resp, "status", 200) or 200)
            if 300 <= code < 400:
                return 0, {"error": "redirect refused"}, "redirect refused"
            return _parse_http_body(raw, code)
    except urllib.error.HTTPError as e:
        code = int(e.code)
        if 300 <= code < 400:
            return 0, {"error": "redirect refused"}, "redirect refused"
        raw_bytes = e.read(MAX_HTTP_BYTES + 1) if e.fp else b""
        if len(raw_bytes) > MAX_HTTP_BYTES:
            return code, {"error": "error response too large"}, "error response too large"
        raw = raw_bytes.decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else {"error": str(e.reason)}
        except json.JSONDecodeError:
            parsed = {"_raw": raw or str(e.reason)}
        if isinstance(parsed, (dict, list)) and payload_too_large(parsed):
            return 0, {"error": "record too large"}, "record too large"
        return code, parsed, raw
    except Exception as e:
        return 0, {"error": str(e)}, str(e)


def http_json(
    method: str,
    url: str,
    headers: dict[str, str],
    body: dict[str, Any] | None = None,
    timeout: float = 45.0,
) -> tuple[int, Any, str]:
    data = None
    hdrs = dict(headers)
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    return http_request(method, url, hdrs, data, timeout=timeout)


def http_form(
    url: str,
    headers: dict[str, str],
    form: dict[str, str],
    timeout: float = 45.0,
) -> tuple[int, Any, str]:
    data = urllib.parse.urlencode(form).encode("utf-8")
    hdrs = dict(headers)
    hdrs.setdefault("Content-Type", "application/x-www-form-urlencoded")
    return http_request("POST", url, hdrs, data, timeout=timeout)


def merge_field(
    out: dict[str, Any],
    field: str,
    value: Any,
    provider: str,
    only_if_missing: bool = True,
) -> None:
    if is_blank(value):
        return
    cur = out["result"].get(field)
    if only_if_missing and not is_blank(cur):
        return
    if field in ("linkedin", "twitter", "profile_url"):
        value = normalize_profile_url(str(value)) or value
    if isinstance(value, str):
        raw = value.strip()
        if len(raw) > HUGE_FIELD_CHARS:
            out.setdefault("_huge_record", True)
            return
        value = sanitize_untrusted_text(raw, FIELD_CAPS.get(field, DISPLAY_FIELD_CAP))
        if is_blank(value):
            return
    out["result"][field] = value
    out["sources"][field] = provider


def extract_urls_from_obj(obj: Any) -> tuple[str | None, str | None, str | None]:
    """Return (linkedin, twitter, generic_profile)."""
    linkedin = twitter = generic = None

    def consider(u: Any) -> None:
        nonlocal linkedin, twitter, generic
        if is_blank(u):
            return
        nu = normalize_profile_url(str(u))
        if not nu:
            return
        low = nu.lower()
        if "linkedin.com" in low or "lnkd.in" in low:
            if not linkedin:
                linkedin = nu
        elif "x.com/" in low or "twitter.com" in low:
            if not twitter:
                twitter = nu
        elif not generic:
            generic = nu

    if isinstance(obj, dict):
        for k in (
            "profile_url",
            "linkedin_url",
            "linkedin",
            "linkedinUrl",
            "twitter_url",
            "twitter",
            "x_url",
            "externalURL",
            "externalUrl",
        ):
            consider(obj.get(k))
        urls = obj.get("externalUrls") or obj.get("external_urls") or obj.get("urls")
        if isinstance(urls, list):
            for item in urls:
                if isinstance(item, str):
                    consider(item)
                elif isinstance(item, dict):
                    consider(item.get("url") or item.get("value") or item.get("externalURL"))
        elif isinstance(urls, dict):
            for v in urls.values():
                consider(v)
    elif isinstance(obj, str):
        consider(obj)
    return linkedin, twitter, generic


def zi_error_message(code: int, payload: Any) -> str:
    """Surface API errors[].detail fully for debug (not just the first title)."""
    if code in (401, 403):
        # Still attach detail when present — helps distinguish bad secret vs scope.
        detail = _zi_errors_detail(payload)
        if detail:
            return f"ZoomInfo credentials rejected: {detail}"
        return "ZoomInfo credentials rejected"
    if isinstance(payload, dict):
        detail = _zi_errors_detail(payload)
        if detail:
            return f"ZoomInfo HTTP {code}: {detail}"
        for k in ("message", "error", "detail", "error_description"):
            if payload.get(k):
                return f"ZoomInfo HTTP {code}: {payload[k]}"
        raw = payload.get("_raw")
        if isinstance(raw, str) and raw.strip():
            snippet = raw.strip().replace("\n", " ")
            if len(snippet) > 400:
                snippet = snippet[:397] + "…"
            return f"ZoomInfo HTTP {code}: {snippet}"
    if code == 0:
        return f"ZoomInfo network error: {payload}"
    return f"ZoomInfo HTTP {code}"


def _zi_errors_detail(payload: Any) -> str | None:
    if not isinstance(payload, dict):
        return None
    errs = payload.get("errors")
    if not isinstance(errs, list) or not errs:
        return None
    parts: list[str] = []
    for e in errs:
        if isinstance(e, dict):
            # Prefer detail; include title/code when detail alone is thin.
            detail = e.get("detail")
            title = e.get("title")
            code_s = e.get("code") or e.get("status")
            if detail is not None and str(detail).strip():
                bit = str(detail).strip()
                extras = []
                if title and str(title).strip() and str(title).strip() not in bit:
                    extras.append(str(title).strip())
                if code_s is not None and str(code_s).strip():
                    extras.append(f"code={code_s}")
                if extras:
                    bit = f"{bit} ({'; '.join(extras)})"
                parts.append(bit)
            elif title is not None and str(title).strip():
                parts.append(str(title).strip())
            else:
                try:
                    parts.append(json.dumps(e, ensure_ascii=False))
                except Exception:
                    parts.append(str(e))
        else:
            parts.append(str(e))
    return " | ".join(parts) if parts else None


def load_cached_token() -> str | None:
    try:
        if not path_in_default_jail(TOKEN_CACHE_PATH):
            return None
        if not TOKEN_CACHE_PATH.is_file():
            return None
        raw = read_text_capped(TOKEN_CACHE_PATH)
        if raw is None:
            return None
        data = json.loads(raw)
        token = str(data.get("access_token") or "").strip()
        expires_at = float(data.get("expires_at") or 0)
        if not token or expires_at <= time.time():
            return None
        return token
    except Exception:
        return None


def save_cached_token(access_token: str, expires_in: int | float) -> None:
    try:
        if not path_in_default_jail(TOKEN_CACHE_PATH):
            return
        ensure_dir_mode(TOKEN_CACHE_PATH.parent)
        expires_at = time.time() + max(0.0, float(expires_in) - TOKEN_SKEW_SEC)
        payload = {
            "access_token": access_token,
            "expires_at": expires_at,
            "cached_at": time.time(),
        }
        write_exclusive(
            TOKEN_CACHE_PATH,
            json.dumps(payload, ensure_ascii=False) + "\n",
        )
    except Exception:
        pass


def mint_zoominfo_token(
    client_id: str,
    client_secret: str,
    out: dict[str, Any],
) -> str | None:
    cached = load_cached_token()
    if cached:
        out.setdefault("raw_notes", []).append("zoominfo token cache hit")
        return cached

    headers = {
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
    }
    form = {
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
    }
    code, payload, _raw = http_form(ZOOMINFO_TOKEN, headers, form)
    out.setdefault("raw_notes", []).append(f"zoominfo token → HTTP {code}")
    if not code or code >= 400:
        out["errors"].append(zi_error_message(code, payload))
        return None
    if not isinstance(payload, dict):
        out["errors"].append("ZoomInfo token response invalid")
        return None
    token = str(payload.get("access_token") or "").strip()
    if not token:
        out["errors"].append("ZoomInfo token response missing access_token")
        return None
    expires_in = payload.get("expires_in", 3600)
    try:
        expires_in = int(expires_in)
    except (TypeError, ValueError):
        expires_in = 3600
    save_cached_token(token, expires_in)
    return token


def apply_zoominfo_payload(out: dict[str, Any], payload: Any) -> None:
    if not isinstance(payload, dict):
        return
    if payload_too_large(payload):
        out["errors"].append("enrich record too large — rejected")
        return
    meta = payload.get("meta")
    if isinstance(meta, dict):
        for k in ("creditsConsumed", "credits_consumed", "remainingCredits"):
            if k in meta:
                out.setdefault("credits", {})[f"zoominfo:{k}"] = meta[k]
    data = payload.get("data")
    items: list[Any] = []
    if isinstance(data, list):
        items = data
    elif isinstance(data, dict):
        items = [data]
    if not items:
        return
    item = items[0]
    if not isinstance(item, dict):
        return
    attrs = item.get("attributes") if isinstance(item.get("attributes"), dict) else item
    first = pick(attrs.get("firstName"), attrs.get("first_name"))
    last = pick(attrs.get("lastName"), attrs.get("last_name"))
    full = pick(
        attrs.get("fullName"),
        attrs.get("name"),
        (" ".join(x for x in (first, last) if x) or None),
    )
    merge_field(out, "name", full, "zoominfo")
    merge_field(
        out,
        "title",
        pick(attrs.get("jobTitle"), attrs.get("title"), attrs.get("job_title")),
        "zoominfo",
    )
    company = attrs.get("company")
    if isinstance(company, dict):
        company = pick(company.get("name"), company.get("companyName"))
    merge_field(
        out,
        "company",
        pick(company, attrs.get("companyName"), attrs.get("company_name")),
        "zoominfo",
    )
    merge_field(
        out,
        "email",
        pick(attrs.get("email"), attrs.get("emailAddress"), attrs.get("workEmail")),
        "zoominfo",
    )
    merge_field(
        out,
        "phone",
        pick(
            attrs.get("mobilePhone"),
            attrs.get("phone"),
            attrs.get("directPhone"),
            attrs.get("mobile"),
        ),
        "zoominfo",
    )
    li, tw, gen = extract_urls_from_obj(attrs)
    merge_field(out, "linkedin", li, "zoominfo")
    merge_field(out, "twitter", tw, "zoominfo")
    merge_field(out, "profile_url", pick(li, tw, gen), "zoominfo")
    match = None
    imeta = item.get("meta")
    if isinstance(imeta, dict):
        match = imeta.get("matchStatus")
    if match and str(match).upper() in ("NO_MATCH", "NONE"):
        out["warnings"].append(
            sanitize_untrusted_text(f"ZoomInfo matchStatus={match}", ERROR_ITEM_CAP)
        )


def zoominfo_attrs_for_mode(mode: str, inputs: dict[str, Any]) -> dict[str, Any] | None:
    if mode == "email":
        email = pick(inputs.get("email"), inputs.get("work_email"))
        if not email:
            return None
        return {"emailAddress": email}
    if mode == "profile":
        purl = normalize_profile_url(pick(inputs.get("profile_url"), inputs.get("url")))
        if not purl:
            return None
        return {"externalURL": purl}
    if mode == "name_company":
        full = pick(inputs.get("full_name"), inputs.get("name"))
        first = pick(inputs.get("first_name"), inputs.get("firstName"))
        last = pick(inputs.get("last_name"), inputs.get("lastName"))
        if not first and full:
            first, last = split_name(full)
        company = pick(
            inputs.get("company"),
            inputs.get("company_name"),
            inputs.get("companyName"),
        )
        domain = pick(inputs.get("domain"), inputs.get("company_domain"))
        attrs: dict[str, Any] = {}
        if full:
            attrs["fullName"] = full
        if first:
            attrs["firstName"] = first
        if last:
            attrs["lastName"] = last
        if company:
            attrs["companyName"] = company
        if domain and not company:
            attrs["companyName"] = domain
        if not attrs.get("fullName") and not attrs.get("firstName"):
            return None
        if not attrs.get("companyName"):
            return None
        return attrs
    if mode == "phone":
        phone = pick(inputs.get("phone"), inputs.get("mobile"))
        if not phone:
            return None
        return {"phone": phone}
    return None


def zoominfo_lookup(
    mode: str,
    inputs: dict[str, Any],
    client_id: str,
    client_secret: str,
    out: dict[str, Any],
) -> None:
    out["provider"] = "zoominfo"
    if not client_id or not client_secret:
        out["errors"].append(
            "ZoomInfo Client ID + Secret missing — add them under Keys "
            "(saved to ~/.config/enricherino/credentials.json)"
        )
        return
    token = mint_zoominfo_token(client_id, client_secret, out)
    if not token:
        return
    attrs = zoominfo_attrs_for_mode(mode, inputs)
    if not attrs:
        out["errors"].append(f"insufficient inputs for ZoomInfo mode={mode}")
        return
    # GTM Data API ContactEnrich shape (docs.zoominfo.com Enrich Contacts):
    # data is an object (not array); matchPersonInput + outputFields live under attributes.
    body = {
        "data": {
            "type": "ContactEnrich",
            "attributes": {
                "matchPersonInput": [attrs],
                "outputFields": [
                    "id",
                    "firstName",
                    "lastName",
                    "email",
                    "jobTitle",
                    "phone",
                    "mobilePhone",
                    "companyName",
                    "externalUrls",
                ],
            },
        }
    }
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.api+json",
        "Content-Type": "application/vnd.api+json",
    }
    code, payload, _raw = http_json("POST", ZOOMINFO_ENRICH, headers, body)
    out.setdefault("raw_notes", []).append(f"zoominfo enrich → HTTP {code}")
    if code in (401, 403):
        # Stale cache? Clear and retry once with a fresh mint.
        try:
            if TOKEN_CACHE_PATH.is_file():
                TOKEN_CACHE_PATH.unlink()
        except Exception:
            pass
        out.setdefault("raw_notes", []).append("zoominfo 401/403 — reminting token")
        token2 = mint_zoominfo_token(client_id, client_secret, out)
        if not token2:
            out["errors"].append("ZoomInfo credentials rejected")
            return
        headers["Authorization"] = f"Bearer {token2}"
        code, payload, _raw = http_json("POST", ZOOMINFO_ENRICH, headers, body)
        out.setdefault("raw_notes", []).append(f"zoominfo enrich retry → HTTP {code}")
        if code in (401, 403):
            out["errors"].append("ZoomInfo credentials rejected")
            return
    if not code or code >= 400:
        out["errors"].append(zi_error_message(code, payload))
        return
    apply_zoominfo_payload(out, payload)
    if mode == "profile":
        purl = normalize_profile_url(pick(inputs.get("profile_url"), inputs.get("url")))
        if purl:
            merge_field(out, "profile_url", purl, "input")
            if "linkedin.com" in purl.lower():
                merge_field(out, "linkedin", purl, "input")
            if "x.com/" in purl.lower() or "twitter.com" in purl.lower():
                merge_field(out, "twitter", purl, "input")


def has_enriched_result(out: dict[str, Any]) -> bool:
    """True when at least one field came from a real provider (not entered/input)."""
    sources = out.get("sources") or {}
    result = out.get("result") or {}
    for f in RESULT_FIELDS:
        if is_blank(result.get(f)):
            continue
        src = str(sources.get(f) or "")
        if src and src not in ("entered", "input"):
            return True
    return False


def load_file_credentials() -> tuple[str, str]:
    """Load Client ID/Secret from ~/.config/enricherino/credentials.json if present."""
    try:
        if not path_in_default_jail(CREDENTIALS_PATH):
            return "", ""
        if not CREDENTIALS_PATH.is_file():
            return "", ""
        raw = read_text_capped(CREDENTIALS_PATH)
        if raw is None:
            return "", ""
        data = json.loads(raw)
        if not isinstance(data, dict):
            return "", ""
        cid = str(
            data.get("zoominfoClientId")
            or data.get("client_id")
            or data.get("clientId")
            or ""
        ).strip()
        csec = str(
            data.get("zoominfoClientSecret")
            or data.get("client_secret")
            or data.get("clientSecret")
            or ""
        ).strip()
        return cid, csec
    except Exception:
        return "", ""


def resolve_credentials() -> tuple[str, str]:
    """Env wins (CLI smoke); otherwise credentials.json."""
    cid = os.environ.get("ZOOMINFO_CLIENT_ID", "").strip()
    csec = os.environ.get("ZOOMINFO_CLIENT_SECRET", "").strip()
    if cid and csec:
        return cid, csec
    file_cid, file_csec = load_file_credentials()
    return cid or file_cid, csec or file_csec


def _cap_string_list(items: Any, cap: int = ERROR_ITEM_CAP) -> list[str]:
    out: list[str] = []
    if not isinstance(items, list):
        return out
    for it in items[:MAX_ERROR_ITEMS]:
        s = sanitize_untrusted_text(it, cap)
        if s:
            out.append(s)
    return out


def sanitize_output(out: dict[str, Any]) -> dict[str, Any]:
    """Per-field / per-record caps after JSON parse. Huge record → reject."""
    if out.pop("_huge_record", False):
        out["result"] = {f: None for f in RESULT_FIELDS}
        out["sources"] = {f: None for f in RESULT_FIELDS}
        out.setdefault("errors", []).append("enrich record too large — rejected")
    result = out.get("result") or {}
    huge = False
    for f in RESULT_FIELDS:
        v = result.get(f)
        if is_blank(v):
            continue
        raw = str(v)
        if len(raw) > HUGE_FIELD_CHARS:
            huge = True
            break
        result[f] = sanitize_untrusted_text(raw, FIELD_CAPS.get(f, DISPLAY_FIELD_CAP))
    if huge:
        out["result"] = {f: None for f in RESULT_FIELDS}
        out["sources"] = {f: None for f in RESULT_FIELDS}
        out.setdefault("errors", []).append("enrich record too large — rejected")
    else:
        out["result"] = result
    out["errors"] = _cap_string_list(out.get("errors"))
    out["warnings"] = _cap_string_list(out.get("warnings"))
    out["raw_notes"] = _cap_string_list(out.get("raw_notes"))
    return out


def run(mode: str, inputs: dict[str, Any]) -> dict[str, Any]:
    out = empty_result()
    out["mode"] = mode
    client_id, client_secret = resolve_credentials()
    zoominfo_lookup(mode, inputs, client_id, client_secret, out)
    sanitize_output(out)
    rejected = any("rejected" in e.lower() for e in out["errors"])
    out["ok"] = has_enriched_result(out) and not rejected
    return out


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="lookup.py",
        description="Enricherino individual contact lookup (ZoomInfo GTM)",
    )
    p.add_argument(
        "--mode",
        required=True,
        choices=["email", "profile", "name_company", "phone"],
        help="Input mode",
    )
    p.add_argument(
        "--json",
        required=True,
        dest="json_blob",
        help="JSON object with mode inputs (email, profile_url, full_name, domain, company, phone, …)",
    )
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    try:
        inputs = json.loads(args.json_blob)
        if not isinstance(inputs, dict):
            raise ValueError("JSON must be an object")
    except Exception as e:
        emit(
            {
                "ok": False,
                "provider": "zoominfo",
                "mode": args.mode,
                "result": {f: None for f in RESULT_FIELDS},
                "sources": {f: None for f in RESULT_FIELDS},
                "credits": {},
                "errors": [f"invalid --json: {e}"],
                "warnings": [],
                "raw_notes": [],
            },
            exit_code=2,
        )
    out = run(args.mode, inputs)
    emit(out, exit_code=0 if out.get("ok") else 1)


if __name__ == "__main__":
    main()
