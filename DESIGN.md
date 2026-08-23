# Yellow Pixels — design notes

**Status:** 0.1.1 (playbook refresh)  
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
| Honest empty/error | **Keys** empty state; API credits/errors surfaced |
| Ship extras | `preview.png`, Remove / Security baseline / Controls |
| Cache last success | `~/.cache/yellow-pixels/last.json` (never keys) |
| Middle-click useful | Clear last result + toast "Cleared" |
| MIT + manifest at root | Marketplace layout |
| Unofficial disclaimer | LeadMagic / ZoomInfo / GTM.AI |

## Bar

`● YP` — left click toggles panel. Middle click clears last result / cache
(does **not** auto-lookup).

## Panel

Header **YELLOW PIXELS** + sub *individual lookup · not for blast outbound*.
Provider chips, **Keys** empty state when missing credentials, input tabs,
Lookup, result card with per-field source + copy. Footer states honest limits:
phone = ZoomInfo-only; X/Twitter URL best-effort; not for blast outbound.

## Providers

- **leadmagic** — `X-API-Key` → `https://api.leadmagic.io`
- **zoominfo** — Bearer → GTM enrich
- **waterfall** — LeadMagic first, ZoomInfo fills gaps

## Non-goals (MVP)

Scaled outbound, sequencing, CRM writeback, bulk CSV, storing results server-side.
