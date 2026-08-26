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

## 0.3.7 / HC-05 (marketplace #2222)

| ID | Severity | Fix |
|----|----------|-----|
| **HC-05** | HIGH | Stop FileView-reading `~/.cache/enricherino/last.json` and `~/.config/enricherino/credentials.json`. FileView `cacheFile` is writes-only (`preload: false`). Both reads go through one `scripts/load-cache.py` helper (`O_RDONLY|O_NOFOLLOW|O_NONBLOCK`, `fstat` S_ISREG, cap+1). `lookup.py` `read_text_capped` uses the same flags for credentials.json / zi_token.json (manifest stays a normal plugin-dir read). Symlink / FIFO / missing / not regular / oversize → exit 1, no body (cache: first-run; creds: `credentialsLoaded` + empty keys). Valid regular file → raw bytes, exit 0. Do not emit `{"cleared": true}` on success. |


## 0.3.8 security pass

| ID | Severity | Fix |
|----|----------|-----|
| **F1** | HIGH | Neutralize untrusted enrich strings at model entry (strip `<>`, collapse ASCII controls to spaces, cap 512–2000). `Text.PlainText` on fieldValue / titleCompanyLine / lastError / toastText / warnings. PRE-SHIP PlainText is OK. |
| **F2** | HIGH | `lookup.py` pins `https://api.zoominfo.com` and refuses 30x (no Authorization copy, token POST is not followed as GET). |
| **F3** | HIGH | Exclusive write (`O_EXCL` temp + fsync + `os.replace`) for credentials.json, zi_token.json, last.json. Dest dir 0700. FileView unused for cache writes. |
| **F4** | MED | After JSON parse: reject huge records; clamp display fields to 512/2000. |
| **F5** | MED | `Process.environment` PATH=`/usr/bin:/bin` plus existing PYTHONDONTWRITEBYTECODE / ZoomInfo env. `python3 -B` stays. |
| **F6** | MED | `load-cache.py --file` and `write-cache.py --file` realpath-jail under `~/.config/enricherino` or `~/.cache/enricherino`. lookup.py token/cred paths checked the same way. |
