# Yellow Pixels

Individual contact lookup for Omarchy — **yellow-pages joke, not a sequencer.**
Paste one email, LinkedIn/X URL, name+company, or phone; get a result card.
LeadMagic and/or ZoomInfo (GTM.AI) enrich. Built as a native Quattro `bar-widget`.

**ID:** `harris.yellow-pixels`  
**Author:** Harris Kenny  
**License:** MIT  
**Version:** 0.1.2

### 0.1.2
- UI polish + richer HTML preview: interactive mock with filled sample result
  card (Name/Title/Company/Email/Phone/LinkedIn/X + source tags), clickable
  provider chips & input tabs, demo toggle (result vs keys-missing), honest
  footer aligned with panel (phone = ZoomInfo-only · X best-effort · not for
  blast outbound · unofficial).

### 0.1.1
- Playbook refresh (Security Theater ops exemplar): `preview.png`, Remove /
  Security baseline / Controls, middle-click clears last result, cache last
  successful lookup to `~/.cache/yellow-pixels/last.json` (never API keys),
  honest capability copy (phone = ZoomInfo-only; X/Twitter best-effort),
  clearer **Keys** empty state.

### 0.1.0
- MVP — bar `● YP`, panel lookup, LeadMagic + ZoomInfo + waterfall, schema keys.

## Repository

**GitHub:** https://github.com/kenhara/omarchy-yellow-pixels  
Local folder: **`omarchy-yellow-pixels`**.

## Unofficial disclaimer

**Yellow Pixels is unofficial.** It is **not** affiliated with, endorsed by, or
sponsored by LeadMagic, ZoomInfo, GTM.AI, or any related entity. It is a thin
personal client that calls public/documented HTTP APIs with **your** keys.
Use only for lawful individual follow-up. **Not for blast outbound.**

## Install

### From GitHub

```sh
omarchy plugin add https://github.com/kenhara/omarchy-yellow-pixels.git --enable
omarchy bar move harris.yellow-pixels --section right
```

### Local copy (this tree)

The **git repo root is the plugin** (`manifest.json` at root). On an Omarchy
machine:

```sh
mkdir -p ~/.config/omarchy/plugins
cp -a . ~/.config/omarchy/plugins/harris.yellow-pixels

omarchy plugin validate ~/.config/omarchy/plugins/harris.yellow-pixels
omarchy-shell shell rescanPlugins

omarchy bar move harris.yellow-pixels --section right
```

Hot reload applies on save under `~/.config/omarchy/plugins/`.

### Symlink (dev)

```sh
mkdir -p ~/.config/omarchy/plugins
ln -sfn /path/to/omarchy-yellow-pixels ~/.config/omarchy/plugins/harris.yellow-pixels
omarchy-shell shell rescanPlugins
```

## Configure keys

Open **widget settings** for Yellow Pixels (Omarchy bar / plugin settings):

| Schema key | Label | Env passed to script |
|------------|-------|----------------------|
| `leadmagicApiKey` | LeadMagic API key | `LEADMAGIC_API_KEY` → header `X-API-Key` |
| `zoominfoBearerToken` | ZoomInfo / GTM.AI bearer token | `ZOOMINFO_BEARER_TOKEN` → `Authorization: Bearer …` |
| `providerMode` | `leadmagic` | `zoominfo` | `waterfall` (default) | CLI `--provider` |

**Do not commit real keys.** Defaults are empty strings. Keys are injected into
the lookup process env for that one call only — they are **never** written to
`~/.cache/yellow-pixels/`.

CLI smoke (optional):

```sh
export LEADMAGIC_API_KEY='…'
export ZOOMINFO_BEARER_TOKEN='…'
python3 scripts/lookup.py --provider waterfall --mode email --json '{"email":"a@b.com"}'
```

Without keys, the script returns structured error JSON asking you to add keys
in widget settings. The panel shows a **Keys** empty state until at least one
required key is present for the selected provider mode.

## Usage

- **Left-click** bar `● YP` to open/close the panel.
- **Middle-click** clears the last result (and cache) with toast **Cleared** —
  does **not** auto-fire paid APIs.
- Pick provider chip: **LeadMagic** / **ZoomInfo** / **Waterfall**.
- Pick input tab: **Email** | **Profile URL** | **Name + company** | **Phone**.
- Hit **Lookup**. Result card shows name, title, company, email, phone,
  LinkedIn / X, profile URL, and **which provider filled each field**.
- **Copy** per field or **Copy all**.
- Pointer cursor only on actionable controls.

### Controls

| Input | Action |
|-------|--------|
| Left-click bar | Toggle panel |
| Middle-click bar | Clear last result (+ cache); toast "Cleared" |
| Provider chips | Switch LeadMagic / ZoomInfo / Waterfall |
| Input tabs | Email · Profile URL · Name + company · Phone |
| Lookup | Run `scripts/lookup.py` (paid API call) |
| Copy / Copy all | Clipboard field or full card |
| Keys empty state | Shown when required key(s) missing — open widget settings |

### Honest capability notes

- **Phone → contact** is **ZoomInfo-only** in MVP (LeadMagic skips; waterfall
  still works when a ZoomInfo token is present).
- **X/Twitter profile URL** is **best-effort**; LinkedIn profile URLs hit more
  reliably on both providers.
- **Not for blast outbound** — one person at a time, lawful individual follow-up.

## Controls / flows that work

| Mode | LeadMagic | ZoomInfo | Waterfall |
|------|-----------|----------|-----------|
| Email | `POST /v1/people/b2b-profile` (+ mobile-finder) | Contact enrich `email` / `emailAddress` | LM then ZI for gaps |
| Profile URL (LinkedIn **or** X/Twitter) | profile-search + b2b-profile-email (+ personal-email + mobile) | enrich `externalURL` | LM then ZI |
| Name + company | email-finder (`first_name`/`last_name`/`domain`) then profile | enrich `fullName`+`companyName` | LM then ZI |
| Phone | honest skip (no clear LM phone→profile in MVP) | enrich `phone` | ZI fills when LM cannot |

Waterfall = LeadMagic first, then ZoomInfo only for still-missing fields
(email, phone, linkedin/profile, name, title, company).

## Remove

```sh
omarchy plugin remove harris.yellow-pixels
```

Optional cache cleanup:

```sh
rm -rf ~/.cache/yellow-pixels
```

## Network

- LeadMagic: `https://api.leadmagic.io` (paths under `/v1/people/…`, with
  root-path fallbacks if a route 404s).
- ZoomInfo GTM: `POST https://api.zoominfo.com/gtm/data/v1/contacts/enrich`
  with `Accept` / `Content-Type`: `application/vnd.api+json`.

Outbound HTTPS only when you click Lookup. Keys stay in widget settings /
process env for that one call — never written into the repo or the result cache.

Cache (last **successful** lookup only): `~/.cache/yellow-pixels/last.json`.

## Scripts

`scripts/lookup.py` — urllib only, no extra deps.

```sh
python3 scripts/lookup.py --help
python3 scripts/lookup.py --provider leadmagic|zoominfo|waterfall \
  --mode email|profile|name_company|phone --json '{…}'
```

## Layout

```
manifest.json          # harris.yellow-pixels @ 0.1.2
BarWidget.qml          # bar entry + Loader → Panel; middle-click clear
Panel.qml              # nested panel UI (Keys empty state + honest footer)
YellowStore.qml        # Process → lookup.py; result model + disk cache
qmldir
scripts/lookup.py
docs/preview/index.html
preview.svg
preview.png
DESIGN.md
REPO.md
LICENSE                # MIT
README.md
```

## Security baseline

- Keys live in widget settings only; injected as process env for a single
  `lookup.py` run. **Never** persisted to `~/.cache/yellow-pixels/` or the repo.
- Cache stores the last successful result card (and optional input snapshot) —
  no API keys / bearer tokens.
- Outbound HTTPS only on explicit Lookup. No auto-fire on panel open or
  middle-click.
- MIT at repo root. Unofficial — not affiliated with LeadMagic, ZoomInfo, or
  GTM.AI.

## Preview

Open `docs/preview/index.html` in a browser for an **interactive** HTML mock
(v0.1.2): clickable provider chips & input tabs, filled sample result card with
source tags, Copy buttons, and a demo toggle (result vs keys-missing). Not live
APIs. Marketplace card: `preview.png` (from `preview.svg`).

## License

MIT — see [LICENSE](LICENSE).
