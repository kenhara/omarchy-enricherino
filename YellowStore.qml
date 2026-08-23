import QtQuick
import Quickshell
import Quickshell.Io

// Yellow Pixels — runs scripts/lookup.py via Process; parses JSON stdout.
// Individual follow-up only. Not a sequencer.
QtObject {
  id: store

  property string leadmagicApiKey: ""
  property string zoominfoBearerToken: ""
  property string providerMode: "waterfall"   // leadmagic | zoominfo | waterfall
  property bool panelOpen: false

  property string inputMode: "email"   // email | profile | name_company | phone
  property string emailInput: ""
  property string profileUrlInput: ""
  property string fullNameInput: ""
  property string domainInput: ""
  property string companyInput: ""
  property string phoneInput: ""

  property bool loading: false
  property string lastError: ""
  property string toastText: ""
  property var lastResult: null   // full JSON from lookup.py
  property string lookupBuf: ""
  property string lookedUpAt: ""

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
    var mode = String(store.providerMode || "waterfall")
    if (store.hasAnyKey) return ""
    if (mode === "leadmagic")
      return "Add LeadMagic API key in widget settings"
    if (mode === "zoominfo")
      return "Add ZoomInfo / GTM.AI bearer token in widget settings"
    return "Add API key in widget settings (LeadMagic and/or ZoomInfo)"
  }

  signal dataChanged()

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
    store.dataChanged()
  }

  function setProviderMode(mode) {
    store.providerMode = store.normalizeProvider(mode)
    store.dataChanged()
  }

  function setInputMode(mode) {
    store.inputMode = store.normalizeInputMode(mode)
    store.dataChanged()
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
      if (typeof Quickshell !== "undefined" && Quickshell.clipboard) {
        Quickshell.clipboard.text = t
        store.showToast("Copied")
        return true
      }
    } catch (e) {}
    copyProc.command = [
      "bash", "-lc",
      "printf '%s' \"$1\" | (command -v wl-copy >/dev/null && wl-copy || command -v xclip >/dev/null && xclip -selection clipboard || command -v xsel >/dev/null && xsel --clipboard --input || cat >/dev/null)",
      "yp-copy", t
    ]
    copyProc.running = true
    store.showToast("Copied")
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
      store.dataChanged()
      return
    }
    if (!store.hasAnyKey) {
      store.lastError = store.keysHint || "Add API key in widget settings"
      store.showToast(store.lastError)
      store.dataChanged()
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
    lookupProc.command = [
      "env",
      "LEADMAGIC_API_KEY=" + lm,
      "ZOOMINFO_BEARER_TOKEN=" + zi,
      "python3",
      store.lookupPath,
      "--provider", provider,
      "--mode", mode,
      "--json", jsonBlob
    ]
    lookupProc.running = true
    store.dataChanged()
  }

  function onLookupFinished(exitCode) {
    store.loading = false
    var raw = store.lookupBuf || ""
    store.lookupBuf = ""
    if (!raw.length) {
      store.lastError = "lookup produced no output (exit " + exitCode + ")"
      store.dataChanged()
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
      store.lastResult = obj
      store.lookedUpAt = new Date().toISOString()
      var errs = obj.errors || []
      if (errs && errs.length)
        store.lastError = String(errs[0])
      else
        store.lastError = ""
      if (obj.ok)
        store.showToast("Lookup done")
      else if (store.lastError)
        store.showToast(store.lastError)
      else
        store.showToast("No match")
      store.dataChanged()
    } catch (e) {
      store.lastError = "lookup JSON parse failed"
      store.dataChanged()
    }
  }

  function clearResult() {
    store.lastResult = null
    store.lastError = ""
    store.lookedUpAt = ""
    store.dataChanged()
  }

  function handleSummonPayload(obj) {
    if (obj === undefined || obj === null || obj === "")
      return false
    if (typeof obj === "string") {
      var raw = String(obj).trim()
      if (!raw.length) return false
      try { obj = JSON.parse(raw) } catch (e) { return false }
    }
    if (typeof obj !== "object") return false
    var acted = false
    if (obj.provider) {
      store.setProviderMode(obj.provider)
      acted = true
    }
    if (obj.mode) {
      store.setInputMode(obj.mode)
      acted = true
    }
    if (obj.email) { store.emailInput = String(obj.email); store.inputMode = "email"; acted = true }
    if (obj.profile_url || obj.url) {
      store.profileUrlInput = String(obj.profile_url || obj.url)
      store.inputMode = "profile"
      acted = true
    }
    if (obj.full_name || obj.name) {
      store.fullNameInput = String(obj.full_name || obj.name)
      store.inputMode = "name_company"
      acted = true
    }
    if (obj.domain) { store.domainInput = String(obj.domain); acted = true }
    if (obj.company) { store.companyInput = String(obj.company); acted = true }
    if (obj.phone) { store.phoneInput = String(obj.phone); store.inputMode = "phone"; acted = true }
    if (obj.lookup === true || obj.lookup === "true" || obj.lookup === 1) {
      Qt.callLater(function() { store.lookup() })
      acted = true
    }
    return acted
  }

  Timer {
    id: toastClear
    interval: 1800
    repeat: false
    onTriggered: store.toastText = ""
  }

  Process {
    id: copyProc
    running: false
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
