import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Yellow Pixels bar entry — Security Theater / Space Jockey pattern:
// BarWidget loads nested Panel.qml via Loader. kinds: ["bar-widget"] only.
BarWidget {
  id: root
  moduleName: "harris.yellow-pixels"

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  // Warm yellow accent for the joke yellow-pages vibe (falls back if theme lacks it)
  readonly property color ypAccent: Qt.rgba(1.0, 0.86, 0.28, 1.0)

  property string leadmagicApiKey: {
    try {
      if (root.settings && root.settings.leadmagicApiKey !== undefined)
        return String(root.settings.leadmagicApiKey)
      if (typeof root.setting === "function")
        return String(root.setting("leadmagicApiKey", ""))
    } catch (e) {}
    return ""
  }

  property string zoominfoBearerToken: {
    try {
      if (root.settings && root.settings.zoominfoBearerToken !== undefined)
        return String(root.settings.zoominfoBearerToken)
      if (typeof root.setting === "function")
        return String(root.setting("zoominfoBearerToken", ""))
    } catch (e) {}
    return ""
  }

  property string providerMode: {
    try {
      var p = "waterfall"
      if (root.settings && root.settings.providerMode !== undefined)
        p = root.settings.providerMode
      else if (typeof root.setting === "function")
        p = root.setting("providerMode", "waterfall")
      return yellowStore.normalizeProvider(p)
    } catch (e) {}
    return "waterfall"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function handleSummonPayload(obj) {
    return yellowStore.handleSummonPayload(obj)
  }

  function open(payloadJson) {
    if (payloadJson !== undefined && payloadJson !== null && String(payloadJson).length)
      root.handleSummonPayload(payloadJson)
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function onBarMiddleClick() {
    // Useful middle-click: clear last result (+ cache) with toast — do not auto-fire paid APIs.
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
      leadmagicApiKey: root.leadmagicApiKey,
      zoominfoBearerToken: root.zoominfoBearerToken,
      providerMode: root.providerMode
    })
  }

  function mirrorProviderMode(mode) {
    if (!root.settings) return
    try {
      root.settings.providerMode = yellowStore.normalizeProvider(mode)
    } catch (e) {}
  }

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    syncStoreSettings()
  }
  onLeadmagicApiKeyChanged: syncStoreSettings()
  onZoominfoBearerTokenChanged: syncStoreSettings()
  onProviderModeChanged: syncStoreSettings()

  YellowStore {
    id: yellowStore
  }

  Component.onCompleted: {
    syncStoreSettings()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: yellowStore.barLabel || "● YP"
    horizontalMargin: 8.5
    tooltipText: {
      var tip = "Yellow Pixels — look somebody up · middle: clear"
      if (yellowStore.loading)
        tip = "Yellow Pixels — finding… · middle: clear"
      return tip
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.onBarMiddleClick()
    }
  }
}
