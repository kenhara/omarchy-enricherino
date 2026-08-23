#!/usr/bin/env python3
"""Yellow Pixels — individual contact lookup (LeadMagic + ZoomInfo GTM).

CLI for Omarchy bar-widget. Reads keys from env:
  LEADMAGIC_API_KEY
  ZOOMINFO_BEARER_TOKEN

User-Agent version is read from manifest.json.
Not for blast outbound. Unofficial client.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

LEADMAGIC_BASE = "https://api.leadmagic.io"
ZOOMINFO_ENRICH = "https://api.zoominfo.com/gtm/data/v1/contacts/enrich"
PLUGIN_ID = "harris.yellow-pixels"


def read_manifest_version() -> str:
    try:
        manifest = Path(__file__).resolve().parent.parent / "manifest.json"
        data = json.loads(manifest.read_text(encoding="utf-8"))
        ver = str(data.get("version") or "").strip()
        if ver:
            return ver
    except Exception:
        pass
    return "0.2.3"


VERSION = read_manifest_version()
USER_AGENT = f"YellowPixels/{VERSION} (Omarchy unofficial; {PLUGIN_ID})"

# Prefer /v1/people/…; fall back to root paths on 404 (legacy OpenAPI).
LM_PATHS = {
    "b2b_profile": ["/v1/people/b2b-profile", "/b2b-profile"],
    "b2b_profile_email": [
        "/v1/people/b2b-profile-email",
        "/v1/people/b2b-social-email",
        "/b2b-profile-email",
        "/b2b-social-email",
    ],
    "profile_search": ["/v1/people/profile-search", "/profile-search"],
    "email_finder": ["/v1/people/email-finder", "/email-finder"],
    "mobile_finder": ["/v1/people/mobile-finder", "/mobile-finder"],
    "personal_email": [
        "/v1/people/personal-email-finder",
        "/personal-email-finder",
    ],
}

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
        "provider": None,
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


def http_json(
    method: str,
    url: str,
    headers: dict[str, str],
    body: dict[str, Any] | None = None,
    timeout: float = 45.0,
) -> tuple[int, Any, str]:
    data = None
    hdrs = dict(headers)
    hdrs.setdefault("User-Agent", USER_AGENT)
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            code = getattr(resp, "status", 200) or 200
            try:
                return code, json.loads(raw) if raw else {}, raw
            except json.JSONDecodeError:
                return code, {"_raw": raw}, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace") if e.fp else ""
        try:
            parsed = json.loads(raw) if raw else {"error": str(e.reason)}
        except json.JSONDecodeError:
            parsed = {"_raw": raw or str(e.reason)}
        return int(e.code), parsed, raw
    except Exception as e:
        return 0, {"error": str(e)}, str(e)


def lm_post(
    paths: list[str],
    api_key: str,
    body: dict[str, Any],
    out: dict[str, Any],
) -> tuple[int, Any]:
    headers = {
        "X-API-Key": api_key,
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    last_code, last_payload = 0, {}
    for path in paths:
        url = LEADMAGIC_BASE + path
        code, payload, _raw = http_json("POST", url, headers, body)
        last_code, last_payload = code, payload
        if code == 404:
            out.setdefault("raw_notes", []).append(f"leadmagic 404 at {path}; trying next")
            continue
        out.setdefault("raw_notes", []).append(f"leadmagic {path} → HTTP {code}")
        return code, payload
    return last_code, last_payload


def lm_credits_note(payload: Any, out: dict[str, Any], label: str) -> None:
    if not isinstance(payload, dict):
        return
    for key in (
        "credits_consumed",
        "creditsConsumed",
        "credit_cost",
        "credits",
        "remaining_credits",
        "credits_remaining",
    ):
        if key in payload and payload[key] is not None:
            out.setdefault("credits", {})[f"leadmagic:{label}:{key}"] = payload[key]


def lm_error_message(code: int, payload: Any) -> str:
    if code == 401 or code == 403:
        return "LeadMagic API key rejected"
    if code == 402:
        return "LeadMagic credits exhausted or payment required"
    if isinstance(payload, dict):
        for k in ("message", "error", "detail", "msg"):
            v = payload.get(k)
            if isinstance(v, str) and v.strip():
                return f"LeadMagic HTTP {code}: {v.strip()}"
            if isinstance(v, dict) and v.get("message"):
                return f"LeadMagic HTTP {code}: {v['message']}"
    if code == 0:
        return f"LeadMagic network error: {payload}"
    return f"LeadMagic HTTP {code}"


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
    out["result"][field] = value if not isinstance(value, str) else str(value).strip()
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


def apply_leadmagic_payload(out: dict[str, Any], payload: Any, label: str) -> None:
    if not isinstance(payload, dict):
        return
    lm_credits_note(payload, out, label)
    # Nested data wrappers
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    if isinstance(payload.get("person"), dict):
        data = payload["person"]

    first = pick(data.get("first_name"), data.get("firstName"), data.get("firstname"))
    last = pick(data.get("last_name"), data.get("lastName"), data.get("lastname"))
    full = pick(
        data.get("full_name"),
        data.get("fullName"),
        data.get("name"),
        (" ".join(x for x in (first, last) if x) or None),
    )
    merge_field(out, "name", full, "leadmagic")
    merge_field(
        out,
        "title",
        pick(
            data.get("title"),
            data.get("job_title"),
            data.get("jobTitle"),
            data.get("headline"),
        ),
        "leadmagic",
    )
    company = data.get("company")
    if isinstance(company, dict):
        company = pick(company.get("name"), company.get("company_name"))
    merge_field(
        out,
        "company",
        pick(
            company,
            data.get("company_name"),
            data.get("companyName"),
            data.get("organization"),
        ),
        "leadmagic",
    )
    merge_field(
        out,
        "email",
        pick(
            data.get("email"),
            data.get("work_email"),
            data.get("workEmail"),
            data.get("business_email"),
            data.get("personal_email"),
            data.get("personalEmail"),
        ),
        "leadmagic",
    )
    merge_field(
        out,
        "phone",
        pick(
            data.get("mobile"),
            data.get("mobile_number"),
            data.get("mobilePhone"),
            data.get("phone"),
            data.get("phone_number"),
            data.get("direct_number"),
        ),
        "leadmagic",
    )
    li, tw, gen = extract_urls_from_obj(data)
    merge_field(out, "linkedin", li, "leadmagic")
    merge_field(out, "twitter", tw, "leadmagic")
    merge_field(out, "profile_url", pick(li, tw, gen, data.get("profile_url")), "leadmagic")


def leadmagic_lookup(mode: str, inputs: dict[str, Any], api_key: str, out: dict[str, Any]) -> None:
    out["provider"] = out.get("provider") or "leadmagic"
    if not api_key:
        out["errors"].append("LeadMagic API key missing — add leadmagicApiKey in widget settings")
        return

    if mode == "email":
        email = pick(inputs.get("email"), inputs.get("work_email"))
        if not email:
            out["errors"].append("email required")
            return
        body = {"work_email": email}
        code, payload = lm_post(LM_PATHS["b2b_profile"], api_key, body, out)
        if code and code < 400:
            apply_leadmagic_payload(out, payload, "b2b-profile")
        else:
            # Try personal_email key once
            code2, payload2 = lm_post(
                LM_PATHS["b2b_profile"], api_key, {"personal_email": email}, out
            )
            if code2 and code2 < 400:
                apply_leadmagic_payload(out, payload2, "b2b-profile-personal")
            else:
                out["errors"].append(lm_error_message(code or code2, payload or payload2))
        # Mobile if we have email
        if not is_blank(out["result"].get("email")) or email:
            mbody = {"work_email": pick(out["result"].get("email"), email)}
            mcode, mpayload = lm_post(LM_PATHS["mobile_finder"], api_key, mbody, out)
            if mcode and mcode < 400:
                apply_leadmagic_payload(out, mpayload, "mobile-finder")

    elif mode == "profile":
        purl = normalize_profile_url(pick(inputs.get("profile_url"), inputs.get("url")))
        if not purl:
            out["errors"].append("profile_url required")
            return
        # Profile search for identity fields
        code, payload = lm_post(
            LM_PATHS["profile_search"], api_key, {"profile_url": purl}, out
        )
        if code and code < 400:
            apply_leadmagic_payload(out, payload, "profile-search")
        else:
            out["warnings"].append(lm_error_message(code, payload))
        # Work email from profile
        code2, payload2 = lm_post(
            LM_PATHS["b2b_profile_email"], api_key, {"profile_url": purl}, out
        )
        if code2 and code2 < 400:
            apply_leadmagic_payload(out, payload2, "b2b-profile-email")
        else:
            out["warnings"].append(lm_error_message(code2, payload2))
        # Personal email fallback
        if is_blank(out["result"].get("email")):
            code3, payload3 = lm_post(
                LM_PATHS["personal_email"], api_key, {"profile_url": purl}, out
            )
            if code3 and code3 < 400:
                apply_leadmagic_payload(out, payload3, "personal-email-finder")
        # Mobile
        mbody: dict[str, Any] = {"profile_url": purl}
        if not is_blank(out["result"].get("email")):
            mbody["work_email"] = out["result"]["email"]
        mcode, mpayload = lm_post(LM_PATHS["mobile_finder"], api_key, mbody, out)
        if mcode and mcode < 400:
            apply_leadmagic_payload(out, mpayload, "mobile-finder")
        merge_field(out, "profile_url", purl, "leadmagic")
        if "linkedin.com" in purl.lower():
            merge_field(out, "linkedin", purl, "leadmagic")
        if "x.com/" in purl.lower() or "twitter.com" in purl.lower():
            merge_field(out, "twitter", purl, "leadmagic")

    elif mode == "name_company":
        full = pick(inputs.get("full_name"), inputs.get("name"))
        first = pick(inputs.get("first_name"), inputs.get("firstName"))
        last = pick(inputs.get("last_name"), inputs.get("lastName"))
        if not first and full:
            first, last = split_name(full)
        domain = pick(inputs.get("domain"), inputs.get("company_domain"))
        company = pick(inputs.get("company"), inputs.get("company_name"), inputs.get("companyName"))
        if not first or (not domain and not company):
            out["errors"].append("full name + domain (or company) required")
            return
        body: dict[str, Any] = {"first_name": first}
        if last:
            body["last_name"] = last
        if domain:
            body["domain"] = domain
        if company:
            body["company_name"] = company
        code, payload = lm_post(LM_PATHS["email_finder"], api_key, body, out)
        if code and code < 400:
            apply_leadmagic_payload(out, payload, "email-finder")
            if is_blank(out["result"].get("name")):
                merge_field(out, "name", " ".join(x for x in (first, last) if x), "leadmagic")
            if is_blank(out["result"].get("company")) and company:
                merge_field(out, "company", company, "leadmagic")
        else:
            out["errors"].append(lm_error_message(code, payload))
        if not is_blank(out["result"].get("email")):
            # Enrich profile from found email
            code2, payload2 = lm_post(
                LM_PATHS["b2b_profile"],
                api_key,
                {"work_email": out["result"]["email"]},
                out,
            )
            if code2 and code2 < 400:
                apply_leadmagic_payload(out, payload2, "b2b-profile")
            mcode, mpayload = lm_post(
                LM_PATHS["mobile_finder"],
                api_key,
                {"work_email": out["result"]["email"]},
                out,
            )
            if mcode and mcode < 400:
                apply_leadmagic_payload(out, mpayload, "mobile-finder")

    elif mode == "phone":
        phone = pick(inputs.get("phone"), inputs.get("mobile"))
        if not phone:
            out["errors"].append("phone required")
            return
        # LeadMagic has no clear phone→profile MVP endpoint; record attempt.
        # Do NOT echo the typed phone into result — that is not enrichment
        # (echoing would make ok:true and pin sources.phone so ZoomInfo cannot fill).
        out["warnings"].append(
            "LeadMagic has no dedicated phone→profile enrich in this MVP; "
            "try ZoomInfo or waterfall"
        )
        out["raw_notes"].append("leadmagic:phone-mode skipped (no endpoint)")
    else:
        out["errors"].append(f"unknown mode: {mode}")


def zi_error_message(code: int, payload: Any) -> str:
    if code in (401, 403):
        return "ZoomInfo token rejected"
    if isinstance(payload, dict):
        errs = payload.get("errors")
        if isinstance(errs, list) and errs:
            e0 = errs[0]
            if isinstance(e0, dict):
                return f"ZoomInfo HTTP {code}: {e0.get('detail') or e0.get('title') or e0}"
            return f"ZoomInfo HTTP {code}: {e0}"
        for k in ("message", "error", "detail"):
            if payload.get(k):
                return f"ZoomInfo HTTP {code}: {payload[k]}"
    if code == 0:
        return f"ZoomInfo network error: {payload}"
    return f"ZoomInfo HTTP {code}"


def apply_zoominfo_payload(out: dict[str, Any], payload: Any) -> None:
    if not isinstance(payload, dict):
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
        out["warnings"].append(f"ZoomInfo matchStatus={match}")


def zoominfo_attrs_for_mode(mode: str, inputs: dict[str, Any]) -> dict[str, Any] | None:
    if mode == "email":
        email = pick(inputs.get("email"), inputs.get("work_email"))
        if not email:
            return None
        return {"email": email, "emailAddress": email}
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


def zoominfo_lookup(mode: str, inputs: dict[str, Any], token: str, out: dict[str, Any]) -> None:
    out["provider"] = out.get("provider") or "zoominfo"
    if not token:
        out["errors"].append(
            "ZoomInfo / GTM.AI bearer token missing — add zoominfoBearerToken in widget settings"
        )
        return
    attrs = zoominfo_attrs_for_mode(mode, inputs)
    if not attrs:
        out["errors"].append(f"insufficient inputs for ZoomInfo mode={mode}")
        return
    body = {
        "data": [{"type": "ContactEnrich", "attributes": attrs}],
        "outputFields": [
            "firstName",
            "lastName",
            "jobTitle",
            "email",
            "phone",
            "mobilePhone",
            "companyName",
            "externalUrls",
        ],
    }
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.api+json",
        "Content-Type": "application/vnd.api+json",
    }
    code, payload, _raw = http_json("POST", ZOOMINFO_ENRICH, headers, body)
    out.setdefault("raw_notes", []).append(f"zoominfo enrich → HTTP {code}")
    if code in (401, 403):
        out["errors"].append("ZoomInfo token rejected")
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


def missing_fields(out: dict[str, Any]) -> list[str]:
    want = ["email", "phone", "linkedin", "name", "title", "company", "profile_url"]
    return [f for f in want if is_blank(out["result"].get(f))]


def has_any_result(out: dict[str, Any]) -> bool:
    return any(not is_blank(out["result"].get(f)) for f in RESULT_FIELDS)

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




def run(provider: str, mode: str, inputs: dict[str, Any]) -> dict[str, Any]:
    out = empty_result()
    out["provider"] = provider
    out["mode"] = mode
    lm_key = os.environ.get("LEADMAGIC_API_KEY", "").strip()
    zi_token = os.environ.get("ZOOMINFO_BEARER_TOKEN", "").strip()

    if provider == "leadmagic":
        leadmagic_lookup(mode, inputs, lm_key, out)
    elif provider == "zoominfo":
        zoominfo_lookup(mode, inputs, zi_token, out)
    elif provider == "waterfall":
        out["provider"] = "waterfall"
        # LeadMagic first
        if lm_key:
            leadmagic_lookup(mode, inputs, lm_key, out)
        else:
            out["warnings"].append(
                "LeadMagic API key missing — add leadmagicApiKey in widget settings"
            )
        # Clear hard errors that block ZoomInfo fill if they are key-missing only
        # Keep them but still try ZoomInfo for missing fields.
        need = missing_fields(out)
        if need:
            if zi_token:
                # Build inputs enriched with anything LeadMagic already found
                zi_inputs = dict(inputs)
                if not is_blank(out["result"].get("email")):
                    zi_inputs["email"] = out["result"]["email"]
                if not is_blank(out["result"].get("profile_url")):
                    zi_inputs.setdefault("profile_url", out["result"]["profile_url"])
                if not is_blank(out["result"].get("linkedin")):
                    zi_inputs.setdefault("profile_url", out["result"]["linkedin"])
                if not is_blank(out["result"].get("name")):
                    zi_inputs.setdefault("full_name", out["result"]["name"])
                if not is_blank(out["result"].get("company")):
                    zi_inputs.setdefault("company", out["result"]["company"])
                if not is_blank(out["result"].get("phone")):
                    zi_inputs.setdefault("phone", out["result"]["phone"])
                # Prefer same mode; if phone mode and LM skipped, still use phone.
                pre_errs = list(out["errors"])
                zoominfo_lookup(mode, zi_inputs, zi_token, out)
                # Drop duplicate key-missing noise if we actually filled via the other
                if has_any_result(out):
                    out["errors"] = [
                        e
                        for e in out["errors"]
                        if "missing" not in e.lower()
                        or "rejected" in e.lower()
                        or "HTTP" in e
                    ]
                # Restore unique prior errors that aren't mere key-missing if both missing
                for e in pre_errs:
                    if e not in out["errors"] and "rejected" in e.lower():
                        out["errors"].append(e)
            else:
                out["warnings"].append(
                    "ZoomInfo / GTM.AI bearer token missing — add zoominfoBearerToken in widget settings"
                )
        if not lm_key and not zi_token:
            out["errors"] = [
                "No API keys configured — add leadmagicApiKey and/or zoominfoBearerToken in widget settings"
            ]
    else:
        out["errors"].append(f"unknown provider: {provider}")

    # Waterfall phone honesty: only after ZoomInfo ran, if still no provider phone,
    # surface the typed number labeled "entered" (not "input") so it cannot pin/block
    # a later ZI fill and is not claimed as enrichment.
    if provider == "waterfall" and mode == "phone":
        typed = pick(inputs.get("phone"), inputs.get("mobile"))
        if typed and is_blank(out["result"].get("phone")):
            out["result"]["phone"] = str(typed).strip()
            out["sources"]["phone"] = "entered"
            out["warnings"].append(
                "phone shown is what you entered — not provider-enriched"
            )

    rejected = any("rejected" in e.lower() for e in out["errors"])
    # Honor rejected guard; do not override with a blank "has results → ok" pass.
    # "entered"/"input" fields alone do not count as successful enrich.
    out["ok"] = has_enriched_result(out) and not rejected
    return out


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="lookup.py",
        description="Yellow Pixels individual contact lookup (LeadMagic / ZoomInfo / waterfall)",
    )
    p.add_argument(
        "--provider",
        required=True,
        choices=["leadmagic", "zoominfo", "waterfall"],
        help="Which provider path to use",
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
                "provider": args.provider,
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
    out = run(args.provider, args.mode, inputs)
    emit(out, exit_code=0 if out.get("ok") else 1)


if __name__ == "__main__":
    main()
