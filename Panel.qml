import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Nested details panel for Yellow Pixels (loaded by BarWidget — not a separate kind).
// 0.2.0 — one paste field, FIND, contact card. No provider chips / input tabs.
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

  implicitWidth: Style.space(400)
  implicitHeight: Math.min(Style.space(680), contentCol.implicitHeight + Style.space(36))

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
        spacing: Style.space(14)
        opacity: liveStore && liveStore.loading ? 0.72 : 1.0

        Behavior on opacity {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        // Header — big YELLOW PIXELS + one-line joke
        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "YELLOW PIXELS"
            color: root.ypYellow
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.size(18)
            font.bold: true
            font.letterSpacing: 3.2
          }

          Text {
            text: "look somebody up"
            color: root.contentForeground
            opacity: 0.5
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.size(12)
            width: parent.width
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
              font.pixelSize: Style.font.size(13)
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
                font.pixelSize: Style.font.size(13)
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
            font.pixelSize: Style.font.size(10)
          }

          // Compact keys one-liner (not a banner)
          Text {
            width: parent.width
            visible: liveStore && !liveStore.hasAnyKey
            text: liveStore ? (liveStore.keysHint || "add keys in widget settings") : "add keys in widget settings"
            color: root.ypYellow
            opacity: 0.75
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.size(10)
          }
        }

        // Huge yellow FIND
        Rectangle {
          width: parent.width
          height: Style.space(48)
          radius: 10
          color: root.ypYellow
          opacity: liveStore && liveStore.loading ? 0.7 : 1.0

          Text {
            anchors.centerIn: parent
            text: liveStore && liveStore.loading ? "FINDING…" : "FIND"
            color: Qt.rgba(0.08, 0.07, 0.04, 1)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.size(15)
            font.bold: true
            font.letterSpacing: 2.4
          }

          MouseArea {
            anchors.fill: parent
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
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(18)
              font.bold: true
              wrapMode: Text.WordWrap
            }

            // title · company
            Text {
              width: parent.width
              visible: root.titleCompanyLine().length > 0
              text: root.titleCompanyLine()
              color: root.contentForeground
              opacity: 0.55
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(12)
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
                    font.pixelSize: Style.font.size(10)
                  }
                  Text {
                    width: parent.width
                    text: liveStore ? liveStore.fieldValue(modelData.key) : ""
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.size(13)
                    wrapMode: Text.WrapAnywhere
                  }
                }

                Rectangle {
                  width: Style.space(48)
                  height: Style.space(26)
                  radius: 6
                  anchors.verticalCenter: parent.verticalCenter
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                  border.width: 1
                  border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
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

            // Empty honesty
            Text {
              width: parent.width
              visible: liveStore && liveStore.lastResult && !root.hasAnyContactField()
              text: "No contact fields returned. Try another paste."
              color: root.contentForeground
              opacity: 0.5
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(11)
              wrapMode: Text.WordWrap
            }

            // One Copy card button
            Rectangle {
              width: parent.width
              height: Style.space(34)
              radius: 8
              visible: root.hasAnyContactField()
              color: Qt.rgba(root.ypYellow.r, root.ypYellow.g, root.ypYellow.b, 0.16)
              border.width: 1
              border.color: Qt.rgba(root.ypYellow.r, root.ypYellow.g, root.ypYellow.b, 0.4)

              Text {
                anchors.centerIn: parent
                text: "Copy card"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.size(12)
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
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
              color: root.contentForeground
              opacity: 0.4
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.size(10)
              wrapMode: Text.WordWrap
            }
          }
        }

        // Quiet footer
        Text {
          width: parent.width
          text: "unofficial · waterfall under the hood · not a sequencer"
          color: root.contentForeground
          opacity: 0.22
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.size(10)
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
