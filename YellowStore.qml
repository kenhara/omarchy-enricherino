import QtQuick
import Quickshell
import Quickshell.Io

// Yellow Pixels — runs scripts/lookup.py via Process; parses JSON stdout.
// Individual follow-up only. Not a sequencer.
// Caches last successful result to ~/.cache/yellow-pixels/last.json (never API keys).
QtObject {
  id: store

  property string leadmagicApiKey: ""
  property string zoominfoBearerToken: ""
  property string providerMode: "waterfall"   // leadmagic | zoominfo | waterfall

  property string inputMode: "email"   // email | profile | name_company | phone
  property string emailInput: ""
  property string profileUrlInput: ""
  property string fullNameInput: ""
  property string domainInput: ""
  property string companyInput: ""
  property string phoneInput: ""
  property string pasteInput: ""

  property bool loading: false
  property string lastError: ""
  property string toastText: ""
  property var lastResult: null   // full JSON from lookup.py (no keys)
  property string lookupBuf: ""
  property string lookedUpAt: ""

  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/yellow-pixels"
  readonly property string cachePath: cacheDir + "/last.json"
  readonly property string pluginDir: String(Qt.resolvedUrl("."))
    .replace(/^file:\/\//, "")
    .replace(/\/$/, "")
  readonly property string lookupPath: pluginDir + "/scripts/lookup.py"

  readonly property string barGlyph: "●"
  readonly property string barLabel: store.barGlyph + " YP"
  readonly property string lastUpdatedText: formatUpdated(store.lookedUpAt)

  readonly property bool hasLeadmagicKey: String(store.leadmagicApiKey || "").trim().length > 0
  readonly property bool hasZoominfoToken: String(store.zoominfoBearerToken || "").trim().length > 0
  readonly property bool hasAnyKey: {
    var mode = String(store.providerMode || "waterfall")
    if (mode === "leadmagic") return store.hasLeadmagicKey
    if (mode === "zoominfo") return store.hasZoominfoToken
    return store.hasLeadmagicKey || store.hasZoominfoToken
  }

  readonly property string keysHint: {
    if (store.hasAnyKey) return ""
    return "add keys in widget settings"
  }

  readonly property string detectedModeLabel: {
    var raw = String(store.pasteInput || "").trim()
    if (!raw.length) return ""
    var m = store.detectMode(raw)
    if (m === "email") return "looks like an email"
    if (m === "profile") return "looks like a profile URL"
    if (m === "phone") return "looks like a phone"
    if (m === "name_company") return "looks like name + company"
    return ""
  }

  function normalizeProvider(p) {
    var s = String(p || "waterfall").toLowerCase()
    if (s === "leadmagic" || s === "zoominfo" || s === "waterfall") return s
    return "waterfall"
  }

  function normalizeInputMode(m) {
    var s = String(m || "email").toLowerCase()
    if (s === "email" || s === "profile" || s === "name_company" || s === "phone") return s
    if (s === "name+company" || s === "namecompany" || s === "name") return "name_company"
    if (s === "url" || s === "linkedin" || s === "twitter" || s === "x") return "profile"
    return "email"
  }

  function applySettings(opts) {
    opts = opts || {}
    if (opts.leadmagicApiKey !== undefined)
      store.leadmagicApiKey = String(opts.leadmagicApiKey || "")
    if (opts.zoominfoBearerToken !== undefined)
      store.zoominfoBearerToken = String(opts.zoominfoBearerToken || "")
    if (opts.providerMode !== undefined)
      store.providerMode = store.normalizeProvider(opts.providerMode)
  }

  function setProviderMode(mode) {
    store.providerMode = store.normalizeProvider(mode)
  }

  function setInputMode(mode) {
    store.inputMode = store.normalizeInputMode(mode)
  }

  function detectMode(text) {
    var t = String(text || "").trim()
    if (!t.length) return ""
    var lower = t.toLowerCase()

    // Profile URL / social
    if (/https?:\/\//i.test(t)
        || lower.indexOf("linkedin.com") >= 0
        || lower.indexOf("twitter.com") >= 0
        || /(?:^|[\s/])x\.com\//i.test(t)
        || lower.indexOf("x.com/") >= 0)
      return "profile"

    // Phone: mostly digits / + ( ) -
    var stripped = t.replace(/[\s\-\(\)\+\.]/g, "")
    var digitCount = (t.match(/\d/g) || []).length
    var nonSpace = t.replace(/\s/g, "").length
    var hasLetters = /[A-Za-z]{2,}/.test(t)
    if (!hasLetters && nonSpace >= 7 && digitCount >= 7
        && digitCount / Math.max(1, nonSpace) >= 0.7)
      return "phone"
    if (!hasLetters && stripped.length >= 7 && /^\d+$/.test(stripped))
      return "phone"

    // Name + company patterns (before bare email — "Alex @ Acme" has @)
    if (/\s+at\s+/i.test(t) || /\s+@\s+/.test(t) || /,\s*[\w.-]+\.\w{2,}/.test(t))
      return "name_company"

    // Email: has @ and no http
    if (t.indexOf("@") >= 0 && !/https?:\/\//i.test(t))
      return "email"

    // "Name something.com" fallback
    if (/\S+\s+.+/.test(t) && /\.\w{2,}/.test(t))
      return "name_company"

    return "email"
  }

  function parseNameCompany(text) {
    var t = String(text || "").trim()
    var name = ""
    var rest = ""
    var m
    m = t.match(/^(.+?)\s+at\s+(.+)$/i)
    if (m) { name = m[1].trim(); rest = m[2].trim() }
    if (!name.length) {
      m = t.match(/^(.+?)\s+@\s+(.+)$/)
      if (m) { name = m[1].trim(); rest = m[2].trim() }
    }
    if (!name.length) {
      m = t.match(/^(.+?),\s*(.+)$/)
      if (m) { name = m[1].trim(); rest = m[2].trim() }
    }
    if (!name.length) {
      // "Name domain.com" — last token looks like domain
      m = t.match(/^(.+?)\s+([\w.-]+\.\w{2,})$/)
      if (m) { name = m[1].trim(); rest = m[2].trim() }
    }
    if (!name.length) {
      name = t
      rest = ""
    }
    var domain = ""
    var company = ""
    if (rest.length) {
      if (rest.indexOf(".") >= 0 && rest.indexOf(" ") < 0)
        domain = rest
      else
        company = rest
    }
    return { full_name: name, domain: domain, company: company }
  }

  function findFromPaste() {
    var text = String(store.pasteInput || "").trim()
    if (!text.length) {
      store.lastError = "Paste something to look up"
      store.showToast(store.lastError)
      return
    }
    var mode = store.detectMode(text)
    if (!mode) mode = "email"
    store.inputMode = store.normalizeInputMode(mode)

    // Clear sibling fields so buildInputs stays clean
    store.emailInput = ""
    store.profileUrlInput = ""
    store.fullNameInput = ""
    store.domainInput = ""
    store.companyInput = ""
    store.phoneInput = ""

    if (mode === "email") {
      store.emailInput = text
    } else if (mode === "profile") {
      store.profileUrlInput = text
    } else if (mode === "phone") {
      store.phoneInput = text
    } else if (mode === "name_company") {
      var parsed = store.parseNameCompany(text)
      store.fullNameInput = parsed.full_name || ""
      store.domainInput = parsed.domain || ""
      store.companyInput = parsed.company || ""
    }
    store.lookup()
  }

  function formatUpdated(iso) {
    if (!iso) return "never"
    var t = Date.parse(iso)
    if (!isFinite(t)) return String(iso)
    var sec = Math.max(0, Math.floor((Date.now() - t) / 1000))
    if (sec < 60) return "just now"
    if (sec < 3600) return Math.floor(sec / 60) + "m ago"
    if (sec < 86400) return Math.floor(sec / 3600) + "h ago"
    return Math.floor(sec / 86400) + "d ago"
  }

  function showToast(msg) {
    store.toastText = String(msg || "")
    toastClear.restart()
  }

  function copyText(text) {
    var t = String(text || "")
    if (!t.length) {
      store.showToast("Nothing to copy")
      return false
    }
    try {
      if (typeof Quickshell !== "undefined" && Quickshell.clipboardText !== undefined) {
        Quickshell.clipboardText = t
        store.showToast("Copied")
        return true
      }
    } catch (e) {}
    // Shell fallback: exactly one of wl-copy / xclip / xsel; bash -c (not -lc).
    // Toast only on copyProc success (onExited) — never claim Copied early.
    copyProc.command = [
      "bash", "-c",
      't="$1"; if command -v wl-copy >/dev/null 2>&1; then printf "%s" "$t" | wl-copy; elif command -v xclip >/dev/null 2>&1; then printf "%s" "$t" | xclip -selection clipboard; elif command -v xsel >/dev/null 2>&1; then printf "%s" "$t" | xsel --clipboard --input; else exit 127; fi',
      "yp-copy", t
    ]
    copyProc.running = true
    return true
  }

  function fieldValue(key) {
    var r = store.lastResult && store.lastResult.result ? store.lastResult.result : null
    if (!r) return ""
    var v = r[key]
    return v === undefined || v === null ? "" : String(v)
  }

  function fieldSource(key) {
    var s = store.lastResult && store.lastResult.sources ? store.lastResult.sources : null
    if (!s) return ""
    var v = s[key]
    return v === undefined || v === null ? "" : String(v)
  }

  function copyField(key) {
    return store.copyText(store.fieldValue(key))
  }

  function buildCopyAll() {
    var keys = ["name", "title", "company", "email", "phone", "linkedin", "twitter", "profile_url"]
    var lines = []
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i]
      var v = store.fieldValue(k)
      if (!v.length) continue
      var src = store.fieldSource(k)
      lines.push(k + ": " + v + (src ? "  [" + src + "]" : ""))
    }
    if (store.lastResult && store.lastResult.provider)
      lines.push("provider: " + store.lastResult.provider)
    return lines.join("\n")
  }

  function copyAll() {
    var t = store.buildCopyAll()
    if (!t.length) {
      store.showToast("No result yet")
      return false
    }
    return store.copyText(t)
  }

  function buildInputs() {
    var mode = store.inputMode
    var o = ({})
    if (mode === "email") {
      o.email = String(store.emailInput || "").trim()
    } else if (mode === "profile") {
      o.profile_url = String(store.profileUrlInput || "").trim()
    } else if (mode === "name_company") {
      o.full_name = String(store.fullNameInput || "").trim()
      o.domain = String(store.domainInput || "").trim()
      o.company = String(store.companyInput || "").trim()
    } else if (mode === "phone") {
      o.phone = String(store.phoneInput || "").trim()
    }
    return o
  }

  function validateInputs() {
    var mode = store.inputMode
    var o = store.buildInputs()
    if (mode === "email" && !o.email)
      return "Enter an email"
    if (mode === "profile" && !o.profile_url)
      return "Enter a LinkedIn or X/Twitter URL"
    if (mode === "name_company") {
      if (!o.full_name) return "Enter a full name"
      if (!o.domain && !o.company) return "Enter a domain or company name"
    }
    if (mode === "phone" && !o.phone)
      return "Enter a phone number"
    return ""
  }

  function lookup() {
    if (store.loading && lookupProc.running)
      return
    var verr = store.validateInputs()
    if (verr) {
      store.lastError = verr
      store.showToast(verr)
      return
    }
    if (!store.hasAnyKey) {
      store.lastError = store.keysHint || "Add API key in widget settings"
      store.showToast(store.lastError)
      return
    }
    store.loading = true
    store.lastError = ""
    store.lookupBuf = ""
    var provider = store.normalizeProvider(store.providerMode)
    var mode = store.normalizeInputMode(store.inputMode)
    var jsonBlob = JSON.stringify(store.buildInputs())
    var lm = String(store.leadmagicApiKey || "")
    var zi = String(store.zoominfoBearerToken || "")
    // Keys via Process.environment only — never in argv, never written to cache/disk.
    // clearEnvironment defaults false (inherit rest of env).
    lookupProc.command = [
      "python3",
      store.lookupPath,
      "--provider", provider,
      "--mode", mode,
      "--json", jsonBlob
    ]
    lookupProc.environment = ({
      "LEADMAGIC_API_KEY": lm,
      "ZOOMINFO_BEARER_TOKEN": zi
    })
    lookupProc.running = true
  }

  function stripSecrets(obj) {
    // Defensive: never persist anything that looks like a key/token.
    if (!obj || typeof obj !== "object") return obj
    var out = ({})
    var skip = {
      leadmagicApiKey: true,
      zoominfoBearerToken: true,
      apiKey: true,
      api_key: true,
      token: true,
      bearer: true,
      authorization: true
    }
    for (var k in obj) {
      if (!Object.prototype.hasOwnProperty.call(obj, k)) continue
      if (skip[k]) continue
      var v = obj[k]
      if (v && typeof v === "object" && !Array.isArray(v))
        out[k] = store.stripSecrets(v)
      else
        out[k] = v
    }
    return out
  }

  function buildCacheObject(resultObj, atIso) {
    return {
      version: 1,
      lookedUpAt: atIso || store.lookedUpAt || "",
      providerMode: store.normalizeProvider(store.providerMode),
      inputMode: store.normalizeInputMode(store.inputMode),
      // Snapshot of inputs used (no keys). Helps restore context; optional.
      inputs: store.buildInputs(),
      result: store.stripSecrets(resultObj || store.lastResult || ({}))
    }
  }

  function persistToDisk(obj) {
    var body = JSON.stringify(obj || store.buildCacheObject(), null, 2) + "\n"
    try {
      // FileView creates parent dirs (mkpath) on setText — no ensureCacheDir Process.
      cacheFile.setText(body)
    } catch (e) {}
  }

  function persistClear() {
    try {
      cacheFile.setText(JSON.stringify({ version: 1, cleared: true }, null, 2) + "\n")
    } catch (e) {}
  }

  function applyCachedPayload(obj, source) {
    if (!obj || typeof obj !== "object") return false
    if (obj.cleared === true) return false
    var res = obj.result
    if (!res || typeof res !== "object") return false
    // Accept either wrapped cache { result: <lookup json> } or raw lookup json
    if (res.result === undefined && res.ok === undefined && obj.ok !== undefined)
      res = obj
    store.lastResult = store.stripSecrets(res)
    store.lookedUpAt = obj.lookedUpAt || ""
    store.lastError = ""
    return true
  }

  function onLookupFinished(exitCode) {
    store.loading = false
    var raw = store.lookupBuf || ""
    store.lookupBuf = ""
    if (!raw.length) {
      store.lastError = "lookup produced no output (exit " + exitCode + ")"
      return
    }
    // Prefer last non-empty JSON line
    var lines = raw.split("\n")
    var blob = ""
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = String(lines[i] || "").trim()
      if (line.charAt(0) === "{") {
        blob = line
        break
      }
    }
    if (!blob.length)
      blob = raw.trim()
    try {
      var obj = JSON.parse(blob)
      store.lastResult = store.stripSecrets(obj)
      store.lookedUpAt = new Date().toISOString()
      var errs = obj.errors || []
      if (errs && errs.length)
        store.lastError = String(errs[0])
      else
        store.lastError = ""
      if (obj.ok) {
        store.showToast("Lookup done")
        // Cache successful results only — never API keys.
        store.persistToDisk(store.buildCacheObject(obj, store.lookedUpAt))
      } else if (store.lastError) {
        store.showToast(store.lastError)
      } else {
        store.showToast("No match")
      }
    } catch (e) {
      store.lastError = "lookup JSON parse failed"
    }
  }

  function clearResult() {
    store.lastResult = null
    store.lastError = ""
    store.lookedUpAt = ""
    store.persistClear()
    store.showToast("Cleared")
  }

  function loadDiskText(text) {
    try {
      var obj = JSON.parse(text || "{}")
      return store.applyCachedPayload(obj, "disk")
    } catch (e) {
      return false
    }
  }

  function bootstrap() {
    cacheFile.reload()
  }

  function onCacheLoaded(text) {
    if (text && text.length > 2)
      store.loadDiskText(text)
  }

  Component.onCompleted: {
    store.bootstrap()
  }

  Timer {
    id: toastClear
    interval: 1800
    repeat: false
    onTriggered: store.toastText = ""
  }

  FileView {
    id: cacheFile
    path: store.cachePath
    watchChanges: false
    printErrors: false
    onLoaded: store.onCacheLoaded(text())
    onLoadFailed: { /* first run — no cache yet */ }
  }

  Process {
    id: copyProc
    running: false
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0)
        store.showToast("Copied")
      else if (exitCode === 127)
        store.showToast("No clipboard tool")
      else
        store.showToast("Copy failed")
    }
  }

  Process {
    id: lookupProc
    running: false
    stdout: SplitParser {
      onRead: function(line) { store.lookupBuf += line + "\n" }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var s = String(line || "")
        if (s.length)
          store.lastError = s
      }
    }
    onExited: function(exitCode, exitStatus) {
      store.onLookupFinished(exitCode)
    }
  }
}
