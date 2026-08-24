# Enricherino — design notes

**Status:** 0.3.2 (person bar glyph + lockable header Keys)  
**Id:** `kenhara.enricherino`  
**Peers:** Compliantish, Rocketlauncher, Encyclopedic, Scriptural

## Why

Personal, joke-friendly **yellow pages / pixel desk**. Look somebody up in
≤10 seconds. Not a sequencer, not blast outbound, not a CRM. Enrich a single
follow-up contact via ZoomInfo GTM.

## Shape (playbook)

| Lesson | Apply |
|--------|--------|
| `bar-widget` + nested `Panel.qml` | Same — no separate panel kind |
| Theme tokens (`Color` / `Style` / `bar.foreground`) | Yellow accent on title + FIND |
| Credentials file | `~/.config/enricherino/credentials.json` (0600); not shell.json |
| Honest empty/error | One-liner keys hint; toast on miss |
| Ship extras | `preview.png`, Remove / Security baseline / Controls |
| Cache last success | `~/.cache/enricherino/last.json` (never secrets) |
| Middle-click useful | Clear last result + toast "Cleared" |
| MIT + manifest at root | Marketplace layout |
| Unofficial disclaimer | ZoomInfo / GTM.AI |

## Bar

FA user/head `\uf007` — left click toggles panel. Tooltip: *Enricherino — look somebody up ·
middle: clear*. Middle click clears last result / cache (does **not** auto-lookup).
Right-click unused.

## Panel (0.3.2)

1. Big **ENRICHERINO** (letter-spacing) + compact Keys lock glyph (right of title) + *look somebody up*
2. Keys form only while unlocked (help + Client ID + Secret + Save/Lock) — not between paste and FIND
3. One multiline/paste field
4. Huge yellow **FIND** (immediately under paste)
5. Tiny detected-mode hint under the field
6. Contact card: name big, title · company, email/phone/LinkedIn/X + Copy, **Copy card**
7. Quiet footer: unofficial · ZoomInfo · not a sequencer; path note only while Keys unlocked

**Removed:** LeadMagic, waterfall / `providerMode`, Bearer paste field, provider chips, input mode tabs.

## Provider

- **zoominfo** — Client Credentials → mint Bearer → GTM `contacts/enrich`
- Token cache: `~/.cache/enricherino/zi_token.json` (expire ~60s early)
- Credentials: `~/.config/enricherino/credentials.json` (dir 0700, file 0600)

## Non-goals

Scaled outbound, sequencing, CRM writeback, bulk CSV, storing results server-side.
