# Enricherino — design notes

**Status:** 0.2.4 (discoverability)  
**Id:** `harris.enricherino`  
**Peers:** Compliantish, Rocketlauncher, Encyclopedic, Scriptural

## Why

Personal, joke-friendly **yellow pages / pixel desk**. Look somebody up in
≤10 seconds. Not a sequencer, not blast outbound, not a CRM. Enrich a single
follow-up contact via LeadMagic and/or ZoomInfo GTM under the hood.

## Shape (playbook)

| Lesson | Apply |
|--------|--------|
| `bar-widget` + nested `Panel.qml` | Same — no separate panel kind |
| Theme tokens (`Color` / `Style` / `bar.foreground`) | Yellow accent on title + FIND |
| Schema knobs early | API keys + `providerMode` (advanced only) |
| Honest empty/error | One-liner keys hint; toast on miss |
| Ship extras | `preview.png`, Remove / Security baseline / Controls |
| Cache last success | `~/.cache/enricherino/last.json` (never keys) |
| Middle-click useful | Clear last result + toast "Cleared" |
| MIT + manifest at root | Marketplace layout |
| Unofficial disclaimer | LeadMagic / ZoomInfo / GTM.AI |

## Bar

`● YP` — left click toggles panel. Tooltip: *Enricherino — look somebody up ·
middle: clear*. Middle click clears last result / cache (does **not** auto-lookup).
Right-click unused.

## Panel (0.2.0+)

1. Big **YELLOW PIXELS** (letter-spacing) + *look somebody up*
2. One multiline/paste field
3. Huge yellow **FIND**
4. Tiny detected-mode hint under the field
5. Compact “add keys in widget settings” if no keys
6. Contact card: name big, title · company, email/phone/LinkedIn/X + Copy, **Copy card**
7. Quiet footer: unofficial · waterfall under the hood · not a sequencer

**Removed from primary UI:** provider chips, input mode tabs, per-mode fields.

## Providers (schema / under the hood)

- **leadmagic** — `X-API-Key` → `https://api.leadmagic.io`
- **zoominfo** — Bearer → GTM enrich
- **waterfall** — LeadMagic first, ZoomInfo fills gaps (default)

## Non-goals

Scaled outbound, sequencing, CRM writeback, bulk CSV, storing results server-side.
