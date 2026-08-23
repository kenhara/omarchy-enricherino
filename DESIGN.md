# Yellow Pixels — design notes

**Status:** MVP 0.1.0  
**Id:** `harris.yellow-pixels`  
**Paths:** `/workspace/omarchy-yellow-pixels/` · playbook peers: Security Theater, Space Jockey

## Why

Personal, joke-friendly **yellow pages** for one person at a time. Not a
sequencer, not blast outbound, not a CRM. Enrich a single follow-up contact
from email / LinkedIn-or-X URL / name+company / phone via LeadMagic and/or
ZoomInfo GTM.

## Shape (playbook)

| Lesson | Apply |
|--------|--------|
| `bar-widget` + nested `Panel.qml` | Same — no separate panel kind |
| Theme tokens (`Color` / `Style` / `bar.foreground`) | Warm yellow accent only for chips / CTA |
| Schema knobs early | API keys + `providerMode` |
| Honest empty/error | Keys missing banner; API credits/errors surfaced |
| MIT + manifest at root | Marketplace layout |
| Unofficial disclaimer | LeadMagic / ZoomInfo / GTM.AI |

## Bar

`● YP` — left click toggles panel. Middle click opens panel only (no auto lookup).

## Panel

Header **YELLOW PIXELS** + sub *individual lookup · not for blast outbound*.
Provider chips, input tabs, Lookup, result card with per-field source + copy.

## Providers

- **leadmagic** — `X-API-Key` → `https://api.leadmagic.io`
- **zoominfo** — Bearer → GTM enrich
- **waterfall** — LeadMagic first, ZoomInfo fills gaps

## Non-goals (MVP)

Scaled outbound, sequencing, CRM writeback, bulk CSV, storing results server-side.
