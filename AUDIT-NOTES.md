# Enricherino — audit notes (0.2.1)

Mapping of audit findings → fixes shipped in **0.2.1**.

## P0

| ID | Finding | Fix |
|----|---------|-----|
| 1 | `Style.font.size(N)` is not a real API (~33 call sites in Panel) | Replaced with named tokens: 10→`caption`, 11→`bodySmall`, 12→`body`, 13→`subtitle`, 14+/15/18→`title`. `Style.font.family` / `Style.space()` unchanged. BarWidget had none. |
| 2 | API keys on argv via `env KEY=… python3` | `lookupProc.command = ["python3", …]`; keys set on `lookupProc.environment` (`LEADMAGIC_API_KEY`, `ZOOMINFO_BEARER_TOKEN`). `clearEnvironment` left default false. `lookup.py` already reads `os.environ`. |
| 3 | Copy broken / clobber risk | `Quickshell.clipboardText = t` (not `Quickshell.clipboard.text`). Shell fallback is `bash -c` with if/elif so only one of wl-copy / xclip / xsel runs; no empty xclip after wl-copy. |
| 4 | LeadMagic phone echoed input as “success” | `leadmagic_lookup` phone mode: warning kept; **no** `merge_field(…, "input")`. Waterfall: after ZI, if still no phone, surface typed value with `sources.phone = "entered"` (not `input`, so ZI is not blocked). `ok` requires a real provider source. |
| 11 (w/ 3) | Toast “Copied” always | Toast “Copied” only after Quickshell success or `copyProc` exit 0; else “Copy failed”. |

## P1

| ID | Finding | Fix |
|----|---------|-----|
| 5 | `ensureCacheDir` Process + `Qt.callLater` | Removed. `persistToDisk` / `persistClear` call `cacheFile.setText` directly (FileView mkpath). |
| 6 | Unused `dataChanged` signal | Deleted signal + all emitters. |
| 7 | Unused `hasCachedResult`, `panelOpen`, `dataSource` | Removed (and BarWidget `panelOpen` sync). |
| 8 | `run()` `ok` contradicted rejected guard | Single rule: `ok = has_enriched_result(out) and not rejected`. Dropped the “any result → ok=True” override. |
| 9 | Popout-switch plumbing | Panel implements `popoutSwitchClosing` + `closeForPopoutSwitch()` → `close()`. BarWidget already forwards. |

## P2

| ID | Finding | Fix |
|----|---------|-----|
| 10 | README `providerMode` table row had 4 cells / 3 headers | One Label cell listing the three modes. |
| 12 | Preview detect labels | Already match Panel (“profile URL” / “name + company”); HTML mock banner bumped to 0.2.1. |
| 13 | Schema `providerMode` enum | **Kept as enum.** Documented: change in widget settings (shell may render enum chips). No primary-UI chips. |
| 14 | Where keys live | README Security / Configure: schema keys are **plaintext in shell settings**; env injection is per-lookup only. |

## Verify (local)

```sh
rg -n 'Style\.font\.size\(|dataChanged|ensureCacheDir' .
LEADMAGIC_API_KEY=fake python3 scripts/lookup.py --provider leadmagic --mode phone --json '{"phone":"+1 555"}'
# expect ok:false and result.phone null (not echoed)
bash -n scripts/lookup.py  # N/A for py; python3 -m py_compile scripts/lookup.py
```

## 0.3.6 (marketplace #2222)

| ID | Finding | Fix |
|----|---------|-----|
| 2222 | Unbounded `resp.read()` / `HTTPError.read()`, `lookupBuf` accumulation, wholesale FileView of cache/credentials | Cap HTTP (4 MiB), file (1 MiB), stdin (64 KiB), QML lookup/file buffers (1 MiB); clamp helper stderr to 2048; 60s lookup watchdog. Oversize/absent → existing fallbacks. |

