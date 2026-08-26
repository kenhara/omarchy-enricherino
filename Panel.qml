import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Nested details panel for Enricherino (loaded by BarWidget — not a separate kind).
// KeyboardPanel shell (Compliantish/Rocketlauncher).
// Header Keys lock + one paste field + FIND + contact card. No input tabs.
Panel {
  id: root
  moduleName: "kenhara.enricherino"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var store: null

  // Keys: locked hides fields. Default locked if creds exist, unlocked for setup.
  property bool keysUnlocked: true
  property bool keysLockInitialized: false

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : "monospace"
  readonly property color themeBackground: {
    try {
      if (typeof Color !== "undefined" && Color.popups && Color.popups.background)
        return Color.popups.background
      if (typeof Color !== "undefined" && Color.background)
        return Color.background
    } catch (e) {}
    return Qt.rgba(0.1, 0.1, 0.12, 1)
  }
  readonly property color surfaceColor: Qt.rgba(
    contentForeground.r, contentForeground.g, contentForeground.b, 0.06)
  readonly property color dimForeground: Qt.darker(contentForeground, 1.45)
  readonly property color ypYellow: Qt.rgba(1.0, 0.86, 0.28, 1.0)

  readonly property var liveStore: store
  readonly property bool credsReady: liveStore ? liveStore.credentialsLoaded : false

  // FA: lock \uf023 (saved), unlock \uf09c (editing), key \uf084 (needs setup)
  readonly property string keysGlyph: {
    if (!(liveStore && liveStore.hasAnyKey))
      return "\uf084"
    if (root.keysUnlocked)
      return "\uf09c"
    return "\uf023"
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }


  onOpenedChanged: {
    if (root.opened) {
      root.ensureKeysLockDefault()
      Qt.callLater(function () { if (pasteEdit) pasteEdit.forceActiveFocus() })
    }
  }

  onCredsReadyChanged: root.ensureKeysLockDefault()
  onStoreChanged: root.ensureKeysLockDefault()

  function contactRows() {
    return [
      { key: "email", label: "Email" },
      { key: "phone", label: "Phone" },
      { key: "linkedin", label: "LinkedIn" },
      { key: "twitter", label: "X" }
    ]
  }

  function hasAnyContactField() {
    if (!liveStore) return false
    var keys = ["name", "title", "company", "email", "phone", "linkedin", "twitter", "profile_url"]
    for (var i = 0; i < keys.length; i++) {
      if (liveStore.fieldValue(keys[i]).length) return true
    }
    return false
  }

  function titleCompanyLine() {
    if (!liveStore) return ""
    var title = liveStore.fieldValue("title")
    var company = liveStore.fieldValue("company")
    if (title && company) return title + " · " + company
    return title || company || ""
  }

  function ensureKeysLockDefault() {
    if (root.keysLockInitialized || !liveStore) return
    if (!liveStore.credentialsLoaded) return
    root.keysUnlocked = !liveStore.hasAnyKey
    root.keysLockInitialized = true
  }

  // Keys go to ~/.config/enricherino/credentials.json — never shell.json / bar settings.
  function persistKeys() {
    if (!liveStore) return
    liveStore.setKeys(
      liveStore.zoominfoClientId,
      liveStore.zoominfoClientSecret
    )
  }

  function onClientIdEdited(text) {
    if (!liveStore) return
    if (text === liveStore.zoominfoClientId) return
    liveStore.zoominfoClientId = text
  }

  function onClientSecretEdited(text) {
    if (!liveStore) return
    if (text === liveStore.zoominfoClientSecret) return
    liveStore.zoominfoClientSecret = text
  }

  function toggleKeysUnlocked() {
    if (root.keysUnlocked) {
      root.persistKeys()
      root.keysUnlocked = false
    } else {
      root.keysUnlocked = true
    }
  }

  function saveAndLock() {
    root.persistKeys()
    root.keysUnlocked = false
  }

  function clearKeysForm() {
    if (!liveStore) return
    liveStore.clearKeys()
    root.keysUnlocked = true
    // TextInput user edits can break the store binding — force empty for rotate path.
    if (clientIdEdit) clientIdEdit.text = ""
    if (clientSecretEdit) clientSecretEdit.text = ""
  }

  readonly property int panelBaseHeight: Style.space(root.keysUnlocked ? 960 : 680)

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(root.panelBaseHeight)
    popoutSwitching: root.popoutSwitching
    popoutSwitchClosing: root.popoutSwitchClosing

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: Style.space(16)
        contentWidth: width
        contentHeight: contentCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: contentCol
          width: flick.width
          spacing: Style.space(14)
          opacity: liveStore && liveStore.loading ? 0.72 : 1.0

          Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
          }

          // Header — person glyph + ENRICHERINO; Keys on their own row
          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              spacing: Style.space(8)
              Text {
                text: "\uf007"
                color: root.ypYellow
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: "ENRICHERINO"
                color: root.ypYellow
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                font.letterSpacing: 3.2
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              text: "look someone up"
              color: root.contentForeground
              opacity: 0.5
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              width: parent.width
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Item {
                width: Math.max(0, parent.width - keysCtl.width - parent.spacing)
                height: 1
              }

              Row {
                id: keysCtl
                spacing: Style.space(6)

                Text {
                  visible: liveStore && liveStore.hasAnyKey && !root.keysUnlocked
                  text: "Keys saved"
                  color: root.contentForeground
                  opacity: 0.45
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                  width: keysGlyphText.implicitWidth + Style.space(10)
                  height: keysGlyphText.implicitHeight + Style.space(8)

                  Text {
                    id: keysGlyphText
                    anchors.centerIn: parent
                    text: root.keysGlyph
                    color: {
                      if (keysGlyphMa.containsMouse) return root.ypYellow
                      if (!(liveStore && liveStore.hasAnyKey)) return root.ypYellow
                      if (root.keysUnlocked) return root.ypYellow
                      return root.contentForeground
                    }
                    opacity: keysGlyphMa.containsMouse ? 0.95 : 0.72
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: keysGlyphMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleKeysUnlocked()
                  }
                }
              }
            }
          }

          // Keys form — only while unlocked (not between paste and FIND)
          Column {
            width: parent.width
            visible: root.keysUnlocked
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "ZoomInfo GTM Studio → Custom Apps → Create → Client Credentials. Scopes: Data + GTM (at least). Enricherino mints Bearer tokens for you — never paste a Bearer."
              color: root.contentForeground
              opacity: 0.45
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "Unlock to rotate: paste new Client ID + Secret, Save. Clear wipes the saved file."
              color: root.contentForeground
              opacity: 0.45
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Column {
              width: parent.width
              spacing: Style.space(4)
              Text {
                text: "Client ID"
                color: root.contentForeground
                opacity: 0.55
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
              Rectangle {
                width: parent.width
                height: Style.space(32)
                radius: 6
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
                border.width: 1
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                TextInput {
                  id: clientIdEdit
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  echoMode: TextInput.Normal
                  selectByMouse: true
                  clip: true
                  text: liveStore ? liveStore.zoominfoClientId : ""
                  onTextChanged: root.onClientIdEdited(text)
                  Text {
                    anchors.fill: parent
                    visible: !clientIdEdit.text.length
                    text: "ZoomInfo Client ID"
                    color: root.contentForeground
                    opacity: 0.32
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    verticalAlignment: Text.AlignVCenter
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(4)
              Text {
                text: "Client Secret"
                color: root.contentForeground
                opacity: 0.55
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
              Rectangle {
                width: parent.width
                height: Style.space(32)
                radius: 6
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
                border.width: 1
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                TextInput {
                  id: clientSecretEdit
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  echoMode: TextInput.Password
                  selectByMouse: true
                  clip: true
                  text: liveStore ? liveStore.zoominfoClientSecret : ""
                  onTextChanged: root.onClientSecretEdited(text)
                  Text {
                    anchors.fill: parent
                    visible: !clientSecretEdit.text.length
                    text: "ZoomInfo Client Secret"
                    color: root.contentForeground
                    opacity: 0.32
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    verticalAlignment: Text.AlignVCenter
                  }
                }
              }
            }

            Row {
              spacing: Style.space(8)

              Rectangle {
                id: saveLockBtn
                width: saveLockRow.implicitWidth + Style.space(20)
                height: Style.space(32)
                radius: 6
                color: saveLockMa.containsMouse
                  ? Qt.rgba(root.ypYellow.r, root.ypYellow.g, root.ypYellow.b, 0.28)
                  : Qt.rgba(root.ypYellow.r, root.ypYellow.g, root.ypYellow.b, 0.16)
                border.width: 1
                border.color: Qt.rgba(root.ypYellow.r, root.ypYellow.g, root.ypYellow.b, 0.4)

                Row {
                  id: saveLockRow
                  anchors.centerIn: parent
                  spacing: Style.space(8)
                  Text {
                    text: "\uf023"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: "Save"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: saveLockMa
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.saveAndLock()
                }
              }

              Rectangle {
                id: clearKeysBtn
                width: clearKeysRow.implicitWidth + Style.space(20)
                height: Style.space(32)
                radius: 6
                color: clearKeysMa.containsMouse
                  ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.32)
                  : Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.16)
                border.width: 1
                border.color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.5)

                Row {
                  id: clearKeysRow
                  anchors.centerIn: parent
                  spacing: Style.space(8)
                  Text {
                    text: "\uf1f8"
                    color: Color.urgent
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: "Clear"
                    color: Color.urgent
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: clearKeysMa
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.clearKeysForm()
                }
              }
            }
          }

          // One paste field
          Column {
            width: parent.width
            spacing: Style.space(6)

            Rectangle {
              width: parent.width
              height: Math.max(Style.space(72), pasteEdit.implicitHeight + Style.space(20))
              radius: 10
              color: root.surfaceColor
              border.width: 1
              border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)

              TextEdit {
                id: pasteEdit
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(10)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                text: liveStore ? liveStore.pasteInput : ""
                onTextChanged: if (liveStore) liveStore.pasteInput = text
                Keys.onReturnPressed: function(event) {
                  if (event.modifiers & Qt.ShiftModifier) {
                    event.accepted = false
                    return
                  }
                  event.accepted = true
                  if (liveStore) liveStore.findFromPaste()
                }

                Text {
                  anchors.fill: parent
                  visible: !pasteEdit.text.length
                  text: "email, LinkedIn, X, phone, or Name at company.com"
                  color: root.contentForeground
                  opacity: 0.32
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                }
              }
            }

            // Tiny detected-mode hint
            Text {
              width: parent.width
              visible: liveStore && liveStore.detectedModeLabel && liveStore.detectedModeLabel.length
              text: liveStore ? liveStore.detectedModeLabel : ""
              color: root.contentForeground
              opacity: 0.4
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            // Empty-state hint when locked / no key yet
            Text {
              width: parent.width
              visible: liveStore && !liveStore.hasAnyKey && !root.keysUnlocked
              text: liveStore ? (liveStore.keysHint || "add ZoomInfo Client ID + Secret under Keys") : "add ZoomInfo Client ID + Secret under Keys"
              color: root.ypYellow
              opacity: 0.75
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // Huge yellow FIND — immediately under the paste field
          Rectangle {
            width: parent.width
            height: Style.space(48)
            radius: 10
            color: findMa.containsMouse
              ? Qt.lighter(root.ypYellow, 1.08)
              : root.ypYellow
            opacity: liveStore && liveStore.loading ? 0.7 : 1.0

            Text {
              anchors.centerIn: parent
              text: liveStore && liveStore.loading ? "FINDING…" : "FIND"
              color: Qt.rgba(0.08, 0.07, 0.04, 1)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              font.letterSpacing: 2.4
            }

            MouseArea {
              id: findMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              enabled: !(liveStore && liveStore.loading)
              onClicked: if (liveStore) liveStore.findFromPaste()
            }
          }

          // Toast / error
          Text {
            width: parent.width
            visible: liveStore && liveStore.lastError && liveStore.lastError.length
            text: liveStore ? liveStore.lastError : ""
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            visible: liveStore && liveStore.toastText && liveStore.toastText.length
            text: liveStore ? liveStore.toastText : ""
            textFormat: Text.PlainText
            color: root.ypYellow
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // Contact card
          Rectangle {
            width: parent.width
            visible: liveStore && liveStore.lastResult
            height: visible ? cardInner.implicitHeight + Style.space(24) : 0
            radius: 12
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(root.ypYellow.r, root.ypYellow.g, root.ypYellow.b, 0.22)

            Column {
              id: cardInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(14)
              spacing: Style.space(10)

              // Name big
              Text {
                width: parent.width
                visible: liveStore && liveStore.fieldValue("name").length
                text: liveStore ? liveStore.fieldValue("name") : ""
                textFormat: Text.PlainText
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                wrapMode: Text.WordWrap
              }

              // title · company
              Text {
                width: parent.width
                visible: root.titleCompanyLine().length > 0
                text: root.titleCompanyLine()
                textFormat: Text.PlainText
                color: root.contentForeground
                opacity: 0.55
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Rectangle {
                width: parent.width
                height: 1
                visible: root.hasAnyContactField()
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
              }

              // email / phone / LinkedIn / X rows
              Repeater {
                model: root.contactRows()
                delegate: Row {
                  required property var modelData
                  width: cardInner.width
                  spacing: Style.space(8)
                  visible: liveStore && liveStore.fieldValue(modelData.key).length > 0

                  Column {
                    width: parent.width - Style.space(56)
                    spacing: 2
                    Text {
                      text: modelData.label
                      color: root.contentForeground
                      opacity: 0.38
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      width: parent.width
                      text: liveStore ? liveStore.fieldValue(modelData.key) : ""
                      textFormat: Text.PlainText
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      wrapMode: Text.WrapAnywhere
                    }
                  }

                  Rectangle {
                    width: Style.space(48)
                    height: Style.space(26)
                    radius: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: copyRowMa.containsMouse
                      ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)
                      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                    Text {
                      anchors.centerIn: parent
                      text: "Copy"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      id: copyRowMa
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (liveStore) liveStore.copyField(modelData.key)
                    }
                  }
                }
              }

              // Empty honesty
              Text {
                width: parent.width
                visible: liveStore && liveStore.lastResult && !root.hasAnyContactField()
                text: "No contact fields returned. Try another paste."
                color: root.contentForeground
                opacity: 0.5
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              // One Copy card button
              Rectangle {
                width: parent.width
                height: Style.space(34)
                radius: 8
                visible: root.hasAnyContactField()
                color: copyCardMa.containsMouse
                  ? Qt.rgba(root.ypYellow.r, root.ypYellow.g, root.ypYellow.b, 0.28)
                  : Qt.rgba(root.ypYellow.r, root.ypYellow.g, root.ypYellow.b, 0.16)
                border.width: 1
                border.color: Qt.rgba(root.ypYellow.r, root.ypYellow.g, root.ypYellow.b, 0.4)

                Text {
                  anchors.centerIn: parent
                  text: "Copy card"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                MouseArea {
                  id: copyCardMa
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (liveStore) liveStore.copyAll()
                }
              }

              Text {
                width: parent.width
                visible: {
                  if (!liveStore || !liveStore.lastResult) return false
                  var w = liveStore.lastResult.warnings || []
                  return w && w.length
                }
                text: {
                  if (!liveStore || !liveStore.lastResult) return ""
                  return (liveStore.lastResult.warnings || []).join(" · ")
                }
                textFormat: Text.PlainText
                color: root.contentForeground
                opacity: 0.4
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          // Quiet footer
          Text {
            width: parent.width
            text: "Unofficial · GTM.AI / ZoomInfo"
            color: root.contentForeground
            opacity: 0.22
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            visible: root.keysUnlocked
            text: "Saved under ~/.config/enricherino/credentials.json (mode 0600). Not written to Omarchy bar settings."
            color: root.contentForeground
            opacity: 0.4
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
