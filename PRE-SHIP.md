# Yellow Pixels — pre-ship checklist (0.2.2)

Omarchy Quattro playbook greps + marketplace polish applied on top of **0.2.1**
audit fixes. YP-specific keep: **phone honesty** (LeadMagic never echoes typed
phone as enrich / `ok`) and waterfall **`entered`** labels for typed-only phone.

## Checklist

| # | Item | Status |
|---|------|--------|
| 1 | No `Style.font.size(` — named tokens only | OK (0.2.1) |
| 2 | Font: `bar.fontFamily` / `"monospace"` fallback | Fixed — dropped `Style.font.family` primary |
| 3 | `Quickshell.clipboardText = t` | OK (0.2.1) |
| 4 | Clipboard `bash -c` if/elif wl-copy→xclip→xsel; toast on success | OK; + “No clipboard tool” on exit 127 |
| 5 | Secrets via `Process.environment` (not `env KEY=` argv) | OK (0.2.1) |
| 6 | No `/workspace/` in public README/DESIGN | Fixed — DESIGN scrubbed |
| 7 | LICENSE second `Software` unquoted | Fixed |
| 8 | README hero `![Yellow Pixels](preview.png)`; Install+Remove; no WIP | Fixed hero |
| 9 | FileView `setText` cache (no mkdir + `Qt.callLater` race) | OK (0.2.1) |
| 10 | Dead `dataChanged` deleted | OK (0.2.1) |
| 11 | Honest copy toasts | OK + exit-127 toast |
| 12 | `Text.PlainText` | **N/A** — no remote HTML; contact fields are JSON strings |
| 13 | Hover on actionable; Flickable | Fixed hover on FIND / Copy / Copy card; Flickable already |
| 14 | Version sync manifest / README / DESIGN / preview / UA | **0.2.2**; UA from `manifest.json` |
| 15 | Integer schema `min`/`max`/`step` | **N/A** — string + enum only |
| 16 | No invented `handleSummonPayload` | Fixed — removed; middle-click → `clearLastResult` |
| 17 | Controls L/R/M; witty pitch ≤15 words; no curl\|sh | Fixed Controls + pitch; baseline clean |

## YP-specific kept

- LeadMagic phone mode: warning only — **no** input echo into `result.phone`.
- Waterfall: typed phone surfaces as `sources.phone = "entered"` only after ZI
  if still empty; `ok` requires a real provider source.
- API keys never written to `~/.cache/yellow-pixels/`.

## Changed in 0.2.2

- Dropped `handleSummonPayload` from `BarWidget.qml` / `Panel.qml` / `YellowStore.qml`
- LICENSE / DESIGN scrub / README hero + pitch + Controls L/R/M
- `"monospace"` font fallback; hover fills; paste `forceActiveFocus` on open
- `scripts/lookup.py` User-Agent from manifest
- Copy Process: exit 127 → “No clipboard tool”

## Verify (expect empty / honest)

```sh
rg -n 'Style\.font\.size\(|Quickshell\.clipboard[^T]|env .*API_KEY=|bash -lc|/workspace/|handleSummonPayload|curl\s*\|' .
LEADMAGIC_API_KEY=fake python3 scripts/lookup.py --provider leadmagic --mode phone --json '{"phone":"+1 555"}'
# expect ok:false and result.phone null (not echoed)
python3 -m py_compile scripts/lookup.py
```
