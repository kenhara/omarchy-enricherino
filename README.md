# Yellow Pixels

Individual contact lookup for Omarchy — **yellow-pages joke, not a sequencer.**
Paste one email, LinkedIn/X URL, name+company, or phone; get a result card.
LeadMagic and/or ZoomInfo (GTM.AI) enrich. Built as a native Quattro `bar-widget`.

**ID:** `harris.yellow-pixels`  
**Author:** Harris Kenny  
**License:** MIT  
**Version:** 0.1.0

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

**Do not commit real keys.** Defaults are empty strings.

CLI smoke (optional):

```sh
export LEADMAGIC_API_KEY='…'
export ZOOMINFO_BEARER_TOKEN='…'
python3 scripts/lookup.py --provider waterfall --mode email --json '{"email":"a@b.com"}'
```

Without keys, the script returns structured error JSON asking you to add keys
in widget settings.

## Usage

- **Left-click** bar `● YP` to open/close the panel.
- **Middle-click** opens the panel (does not auto-fire paid APIs).
- Pick provider chip: **LeadMagic** / **ZoomInfo** / **Waterfall**.
- Pick input tab: **Email** | **Profile URL** | **Name + company** | **Phone**.
- Hit **Lookup**. Result card shows name, title, company, email, phone,
  LinkedIn / X, profile URL, and **which provider filled each field**.
- **Copy** per field or **Copy all**.

## Controls / flows that work

| Mode | LeadMagic | ZoomInfo | Waterfall |
|------|-----------|----------|-----------|
| Email | `POST /v1/people/b2b-profile` (+ mobile-finder) | Contact enrich `email` / `emailAddress` | LM then ZI for gaps |
| Profile URL (LinkedIn **or** X/Twitter) | profile-search + b2b-profile-email (+ personal-email + mobile) | enrich `externalURL` | LM then ZI |
| Name + company | email-finder (`first_name`/`last_name`/`domain`) then profile | enrich `fullName`+`companyName` | LM then ZI |
| Phone | honest skip (no clear LM phone→profile in MVP) | enrich `phone` | ZI fills when LM cannot |

Waterfall = LeadMagic first, then ZoomInfo only for still-missing fields
(email, phone, linkedin/profile, name, title, company).

## Network

- LeadMagic: `https://api.leadmagic.io` (paths under `/v1/people/…`, with
  root-path fallbacks if a route 404s).
- ZoomInfo GTM: `POST https://api.zoominfo.com/gtm/data/v1/contacts/enrich`
  with `Accept` / `Content-Type`: `application/vnd.api+json`.

Outbound HTTPS only when you click Lookup. Keys stay in widget settings /
process env for that one call — never written into the repo.

## Scripts

`scripts/lookup.py` — urllib only, no extra deps.

```sh
python3 scripts/lookup.py --help
python3 scripts/lookup.py --provider leadmagic|zoominfo|waterfall \
  --mode email|profile|name_company|phone --json '{…}'
```

## Layout

```
manifest.json          # harris.yellow-pixels @ 0.1.0
BarWidget.qml          # bar entry + Loader → Panel
Panel.qml              # nested panel UI
YellowStore.qml        # Process → lookup.py; result model
qmldir
scripts/lookup.py
docs/preview/index.html
preview.svg
DESIGN.md
LICENSE                # MIT
```

## Preview

Open `docs/preview/index.html` in a browser for a static mock of the panel.
