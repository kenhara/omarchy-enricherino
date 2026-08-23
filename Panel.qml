import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Nested details panel for Yellow Pixels (loaded by BarWidget — not a separate kind).
Panel {
  id: root
  moduleName: "harris.yellow-pixels"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var store: null

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
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

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function handleSummonPayload(obj) {
    if (!liveStore) return false
    var acted = liveStore.handleSummonPayload(obj)
    if (acted && !root.opened)
      root.open()
    return acted
  }

  function chipSelected(mode) {
    return liveStore && liveStore.providerMode === mode
  }

  function tabSelected(mode) {
    return liveStore && liveStore.inputMode === mode
  }

  function selectProvider(mode) {
    if (!liveStore) return
    liveStore.setProviderMode(mode)
    if (hostWidget && typeof hostWidget.mirrorProviderMode === "function")
      hostWidget.mirrorProviderMode(mode)
  }

  function resultRows() {
    return [
      { key: "name", label: "Name" },
      { key: "title", label: "Title" },
      { key: "company", label: "Company" },
      { key: "email", label: "Email" },
      { key: "phone", label: "Phone" },
      { key: "linkedin", label: "LinkedIn" },
      { key: "twitter", label: "X / Twitter" },
      { key: "profile_url", label: "Profile" }
    ]
  }

  implicitWidth: Style.space(420)
  implicitHeight: Math.min(Style.space(760), contentCol.implicitHeight + Style.space(36))

  Rectangle {
    anchors.fill: parent
    color: root.themeBackground
    radius: Style.space(12)

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
        spacing: Style.space(12)
        opacity: liveStore && liveStore.loading ? 0.72 : 1.0

        Behavior on opacity {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        // Header
        Column {
          width: parent.width
          spacing: Style.space(4)

          Row {
            spacing: Style.space(8)
            Text {
              text: "●"
              color: root.ypYellow
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(14)
            }
            Text {
              text: "YELLOW PIXELS"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(13)
              font.bold: true
              font.letterSpacing: 2.2
            }
          }

          Text {
            text: "individual lookup · not for blast outbound"
            color: root.contentForeground
            opacity: 0.45
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.size(11)
            width: parent.width
            wrapMode: Text.WordWrap
          }
        }

        // Provider chips
        Row {
          spacing: Style.space(6)
          Repeater {
            model: [
              { id: "leadmagic", label: "LeadMagic" },
              { id: "zoominfo", label: "ZoomInfo" },
              { id: "waterfall", label: "Waterfall" }
            ]
            delegate: Rectangle {
              required property var modelData
              width: chipLab.implicitWidth + Style.space(14)
              height: Style.space(26)
              radius: 6
              color: root.chipSelected(modelData.id)
                ? Qt.rgba(root.ypYellow.r, root.ypYellow.g, root.ypYellow.b, 0.22)
                : root.surfaceColor
              border.width: 1
              border.color: root.chipSelected(modelData.id)
                ? Qt.rgba(root.ypYellow.r, root.ypYellow.g, root.ypYellow.b, 0.55)
                : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

              Text {
                id: chipLab
                anchors.centerIn: parent
                text: modelData.label
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.size(11)
                font.bold: root.chipSelected(modelData.id)
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectProvider(modelData.id)
              }
            }
          }
        }

        // Keys missing banner
        Rectangle {
          width: parent.width
          visible: liveStore && !liveStore.hasAnyKey
          height: visible ? keysCol.implicitHeight + Style.space(16) : 0
          radius: 8
          color: Qt.rgba(1.0, 0.86, 0.28, 0.1)
          border.width: 1
          border.color: Qt.rgba(1.0, 0.86, 0.28, 0.35)

          Column {
            id: keysCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(10)
            spacing: Style.space(4)

            Text {
              text: "Add API key in widget settings"
              color: root.ypYellow
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(12)
              font.bold: true
              width: parent.width
              wrapMode: Text.WordWrap
            }
            Text {
              text: liveStore ? (liveStore.keysHint || "") : ""
              color: root.contentForeground
              opacity: 0.55
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(11)
              width: parent.width
              wrapMode: Text.WordWrap
            }
          }
        }

        // Input mode tabs
        Row {
          spacing: Style.space(4)
          Repeater {
            model: [
              { id: "email", label: "Email" },
              { id: "profile", label: "Profile URL" },
              { id: "name_company", label: "Name + company" },
              { id: "phone", label: "Phone" }
            ]
            delegate: Rectangle {
              required property var modelData
              width: tabLab.implicitWidth + Style.space(12)
              height: Style.space(24)
              radius: 5
              color: root.tabSelected(modelData.id)
                ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                : "transparent"
              border.width: root.tabSelected(modelData.id) ? 1 : 0
              border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)

              Text {
                id: tabLab
                anchors.centerIn: parent
                text: modelData.label
                color: root.contentForeground
                opacity: root.tabSelected(modelData.id) ? 1.0 : 0.55
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.size(11)
                font.bold: root.tabSelected(modelData.id)
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (liveStore) liveStore.setInputMode(modelData.id)
              }
            }
          }
        }

        // Input fields
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: liveStore !== null

          // Email
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: liveStore && liveStore.inputMode === "email"
            Text {
              text: "Work or personal email"
              color: root.contentForeground
              opacity: 0.45
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(10)
            }
            Rectangle {
              width: parent.width
              height: Style.space(32)
              radius: 6
              color: root.surfaceColor
              border.width: 1
              border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
              TextInput {
                id: emailField
                anchors.fill: parent
                anchors.margins: Style.space(8)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.size(12)
                clip: true
                selectByMouse: true
                text: liveStore ? liveStore.emailInput : ""
                onTextChanged: if (liveStore) liveStore.emailInput = text
                Keys.onReturnPressed: if (liveStore) liveStore.lookup()
              }
            }
          }

          // Profile URL
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: liveStore && liveStore.inputMode === "profile"
            Text {
              text: "LinkedIn or X/Twitter profile URL"
              color: root.contentForeground
              opacity: 0.45
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(10)
            }
            Rectangle {
              width: parent.width
              height: Style.space(32)
              radius: 6
              color: root.surfaceColor
              border.width: 1
              border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
              TextInput {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.size(12)
                clip: true
                selectByMouse: true
                text: liveStore ? liveStore.profileUrlInput : ""
                onTextChanged: if (liveStore) liveStore.profileUrlInput = text
                Keys.onReturnPressed: if (liveStore) liveStore.lookup()
              }
            }
          }

          // Name + company
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: liveStore && liveStore.inputMode === "name_company"
            Column {
              width: parent.width
              spacing: Style.space(4)
              Text {
                text: "Full name"
                color: root.contentForeground
                opacity: 0.45
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.size(10)
              }
              Rectangle {
                width: parent.width
                height: Style.space(32)
                radius: 6
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                TextInput {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.size(12)
                  clip: true
                  selectByMouse: true
                  text: liveStore ? liveStore.fullNameInput : ""
                  onTextChanged: if (liveStore) liveStore.fullNameInput = text
                }
              }
            }
            Column {
              width: parent.width
              spacing: Style.space(4)
              Text {
                text: "Domain (preferred) or company name"
                color: root.contentForeground
                opacity: 0.45
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.size(10)
              }
              Rectangle {
                width: parent.width
                height: Style.space(32)
                radius: 6
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                TextInput {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.size(12)
                  clip: true
                  selectByMouse: true
                  text: liveStore ? (liveStore.domainInput || liveStore.companyInput) : ""
                  onTextChanged: {
                    if (!liveStore) return
                    var t = text.trim()
                    if (t.indexOf(".") >= 0 && t.indexOf(" ") < 0) {
                      liveStore.domainInput = t
                      liveStore.companyInput = ""
                    } else {
                      liveStore.companyInput = t
                      liveStore.domainInput = ""
                    }
                  }
                  Keys.onReturnPressed: if (liveStore) liveStore.lookup()
                }
              }
            }
          }

          // Phone
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: liveStore && liveStore.inputMode === "phone"
            Text {
              text: "Phone number"
              color: root.contentForeground
              opacity: 0.45
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(10)
            }
            Rectangle {
              width: parent.width
              height: Style.space(32)
              radius: 6
              color: root.surfaceColor
              border.width: 1
              border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
              TextInput {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.size(12)
                clip: true
                selectByMouse: true
                text: liveStore ? liveStore.phoneInput : ""
                onTextChanged: if (liveStore) liveStore.phoneInput = text
                Keys.onReturnPressed: if (liveStore) liveStore.lookup()
              }
            }
          }
        }

        // Lookup button
        Rectangle {
          width: parent.width
          height: Style.space(34)
          radius: 8
          color: Qt.rgba(root.ypYellow.r, root.ypYellow.g, root.ypYellow.b, 0.28)
          border.width: 1
          border.color: Qt.rgba(root.ypYellow.r, root.ypYellow.g, root.ypYellow.b, 0.55)

          Text {
            anchors.centerIn: parent
            text: liveStore && liveStore.loading ? "Looking up…" : "Lookup"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.size(12)
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            enabled: !(liveStore && liveStore.loading)
            onClicked: if (liveStore) liveStore.lookup()
          }
        }

        // Error / status
        Text {
          width: parent.width
          visible: liveStore && liveStore.lastError && liveStore.lastError.length
          text: liveStore ? liveStore.lastError : ""
          color: Color.urgent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.size(11)
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: liveStore && liveStore.toastText && liveStore.toastText.length
          text: liveStore ? liveStore.toastText : ""
          color: root.ypYellow
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.size(11)
        }

        // Result card
        Rectangle {
          width: parent.width
          visible: liveStore && liveStore.lastResult
          height: visible ? resultInner.implicitHeight + Style.space(20) : 0
          radius: 10
          color: root.surfaceColor
          border.width: 1
          border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

          Column {
            id: resultInner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(8)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: "Result"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.size(12)
                font.bold: true
              }

              Text {
                text: {
                  if (!liveStore || !liveStore.lastResult) return ""
                  var p = liveStore.lastResult.provider || ""
                  var ok = liveStore.lastResult.ok ? "ok" : "empty"
                  return p + " · " + ok
                }
                color: root.contentForeground
                opacity: 0.45
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.size(11)
              }

              Item { width: Math.max(0, parent.width - 200); height: 1 }

              Rectangle {
                width: copyAllLab.implicitWidth + Style.space(12)
                height: Style.space(22)
                radius: 5
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                border.width: 1
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                Text {
                  id: copyAllLab
                  anchors.centerIn: parent
                  text: "Copy all"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.size(10)
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (liveStore) liveStore.copyAll()
                }
              }
            }

            Repeater {
              model: root.resultRows()
              delegate: Row {
                required property var modelData
                width: resultInner.width
                spacing: Style.space(6)
                visible: {
                  if (!liveStore) return false
                  var v = liveStore.fieldValue(modelData.key)
                  return v && v.length
                }

                Column {
                  width: parent.width - Style.space(52)
                  spacing: 2
                  Text {
                    text: modelData.label + (liveStore && liveStore.fieldSource(modelData.key)
                      ? " · " + liveStore.fieldSource(modelData.key) : "")
                    color: root.contentForeground
                    opacity: 0.4
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.size(10)
                  }
                  Text {
                    width: parent.width
                    text: liveStore ? liveStore.fieldValue(modelData.key) : ""
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.size(12)
                    wrapMode: Text.WrapAnywhere
                  }
                }

                Rectangle {
                  width: Style.space(40)
                  height: Style.space(22)
                  radius: 5
                  anchors.verticalCenter: parent.verticalCenter
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                  Text {
                    anchors.centerIn: parent
                    text: "Copy"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.size(10)
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (liveStore) liveStore.copyField(modelData.key)
                  }
                }
              }
            }

            // Empty result honesty
            Text {
              width: parent.width
              visible: {
                if (!liveStore || !liveStore.lastResult) return false
                var keys = ["name", "title", "company", "email", "phone", "linkedin", "twitter", "profile_url"]
                for (var i = 0; i < keys.length; i++) {
                  if (liveStore.fieldValue(keys[i]).length) return false
                }
                return true
              }
              text: "No contact fields returned. Try another provider or input."
              color: root.contentForeground
              opacity: 0.5
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(11)
              wrapMode: Text.WordWrap
            }

            // Credits / warnings
            Text {
              width: parent.width
              visible: {
                if (!liveStore || !liveStore.lastResult) return false
                var c = liveStore.lastResult.credits || {}
                return Object.keys(c).length > 0
              }
              text: {
                if (!liveStore || !liveStore.lastResult) return ""
                var c = liveStore.lastResult.credits || {}
                var parts = []
                for (var k in c) parts.push(k + "=" + c[k])
                return "Credits: " + parts.join(" · ")
              }
              color: root.contentForeground
              opacity: 0.4
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(10)
              wrapMode: Text.WordWrap
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
                return "Note: " + (liveStore.lastResult.warnings || []).join(" · ")
              }
              color: root.contentForeground
              opacity: 0.45
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(10)
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              visible: {
                if (!liveStore || !liveStore.lastResult) return false
                var e = liveStore.lastResult.errors || []
                return e && e.length
              }
              text: {
                if (!liveStore || !liveStore.lastResult) return ""
                return (liveStore.lastResult.errors || []).join(" · ")
              }
              color: Color.urgent
              opacity: 0.85
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(10)
              wrapMode: Text.WordWrap
            }
          }
        }

        Text {
          width: parent.width
          text: "Unofficial · LeadMagic / ZoomInfo / GTM.AI · individual follow-up only"
          color: root.contentForeground
          opacity: 0.28
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.size(10)
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
