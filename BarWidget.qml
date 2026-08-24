import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Enricherino bar entry — Compliantish / Rocketlauncher pattern:
// BarWidget loads nested Panel.qml via Loader. kinds: ["bar-widget"] only.
BarWidget {
  id: root
  moduleName: "kenhara.enricherino"

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : "monospace"

  // Warm yellow accent for the joke yellow-pages vibe (falls back if theme lacks it)
  readonly property color ypAccent: Qt.rgba(1.0, 0.86, 0.28, 1.0)

  property string zoominfoClientId: {
    try {
      if (root.settings && root.settings.zoominfoClientId !== undefined)
        return String(root.settings.zoominfoClientId)
      if (typeof root.setting === "function")
        return String(root.setting("zoominfoClientId", ""))
    } catch (e) {}
    return ""
  }

  property string zoominfoClientSecret: {
    try {
      if (root.settings && root.settings.zoominfoClientSecret !== undefined)
        return String(root.settings.zoominfoClientSecret)
      if (typeof root.setting === "function")
        return String(root.setting("zoominfoClientSecret", ""))
    } catch (e) {}
    return ""
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) {
      panelLoader.item.toggle()
      return
    }
    var detail = root.panelLoadError && root.panelLoadError.length
      ? (" load error: " + root.panelLoadError)
      : (" Loader.status=" + panelLoader.status)
    console.warn(moduleName + " toggle ignored — panelLoader.item is null;" + detail)
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // Local name — middle-click clears last result (+ cache); do not auto-fire paid APIs.
  function clearLastResult() {
    yellowStore.clearResult()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("store" in target) target.store = yellowStore
  }

  function syncStoreSettings() {
    yellowStore.applySettings({
      zoominfoClientId: root.zoominfoClientId,
      zoominfoClientSecret: root.zoominfoClientSecret
    })
  }

  // Best-effort write-back into mutable settings (Compliantish mirrorSettingsEnable).
  // Keeps `omarchy bar set` / shell.json durable across reload.
  function mirrorSettingsKey(key, value) {
    if (!root.settings) return
    try {
      root.settings[key] = value
    } catch (e) {}
  }

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    syncStoreSettings()
  }
  onZoominfoClientIdChanged: syncStoreSettings()
  onZoominfoClientSecretChanged: syncStoreSettings()

  YellowStore {
    id: yellowStore
  }

  Component.onCompleted: {
    syncStoreSettings()
  }

  property string panelLoadError: ""

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.panelLoadError = ""
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
    onStatusChanged: {
      if (status === Loader.Error) {
        var err = ""
        try {
          if (sourceComponent)
            err = String(sourceComponent.errorString || "")
        } catch (e) {}
        root.panelLoadError = err.length ? err : "Panel.qml failed to load"
        console.warn(moduleName + " panel load failed: " + root.panelLoadError)
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // FA search (\uf002) — tintable; active while loading → Color.accent
    text: yellowStore.barLabel || "\uf002"
    active: yellowStore.loading
    activeColor: Color.accent
    fontSize: Style.font.caption
    horizontalMargin: 8.5
    tooltipText: {
      var tip = "Enricherino — look somebody up · middle: clear"
      if (yellowStore.loading)
        tip = "Enricherino — finding… · middle: clear"
      if (root.panelLoadError && root.panelLoadError.length) {
        var pe = root.panelLoadError
        if (pe.length > 120)
          pe = pe.substring(0, 117) + "…"
        tip += " · panel load error — " + pe
      }
      return tip
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.clearLastResult()
    }
  }
}
