import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.thelost77.omasecretary"

  readonly property var svc: (bar && bar.shell && typeof bar.shell.serviceFor === "function")
    ? bar.shell.serviceFor(moduleName)
    : null
  readonly property int unread: svc ? svc.unreadCount : 0
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  // The count is red while an unseen row reports a failure, a conflict, or requested changes.
  readonly property color countColor: svc && svc.alarm ? svc.toneColor("danger") : Color.accent
  readonly property real iconVerticalOffset: 1

  property bool popoutSwitchClosing: false
  readonly property bool opened: panelLoader.item ? panelLoader.item.open === true : false
  readonly property real openPanelIndicatorWidth: horizontalContent.implicitWidth

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function ensurePanel() {
    if (!panelLoader.item) {
      panelLoader.setSource(Qt.resolvedUrl("Panel.qml"), {
        bar: root.bar,
        anchorItem: button,
        owner: root,
        host: root
      })
    }
    return panelLoader.item
  }

  function open() {
    var panel = ensurePanel()
    if (!panel) return
    root.popoutSwitchClosing = false
    panel.open = true
  }

  function close() {
    if (panelLoader.item) panelLoader.item.open = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function closeForPopoutSwitch() {
    root.popoutSwitchClosing = true
    root.close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root, direction)
    return false
  }

  Loader {
    id: panelLoader
    active: true
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical
      ? -1
      : (root.unread > 0
          ? horizontalContent.implicitWidth + Style.spacing.sm * 2
          : Style.bar.statusSlot)
    tooltipText: root.svc
      ? "OmaSecretary · " + (root.unread > 0 ? root.unread + " new" : "nothing new")
      : "OmaSecretary · starting"

    Row {
      id: horizontalContent
      anchors.centerIn: parent
      visible: !root.vertical
      spacing: Style.spacing.sm

      Item {
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas

        OpticalGlyph {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: root.iconVerticalOffset
          width: parent.width
          height: parent.height
          text: "\uf407"
          color: root.foreground
          opacity: root.unread > 0 ? 1 : 0.58
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.bar.iconFont
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.unread > 0
        text: root.unread > 99 ? "99+" : String(root.unread)
        textFormat: Text.PlainText
        color: root.countColor
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        renderType: Text.NativeRendering
      }
    }

    Column {
      anchors.centerIn: parent
      visible: root.vertical
      spacing: Style.spacing.xxs

      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas

        OpticalGlyph {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: root.iconVerticalOffset
          width: parent.width
          height: parent.height
          text: "\uf407"
          color: root.foreground
          opacity: root.unread > 0 ? 1 : 0.58
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.bar.iconFont
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.unread > 0
        text: root.unread > 9 ? "9+" : String(root.unread)
        textFormat: Text.PlainText
        color: root.countColor
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        renderType: Text.NativeRendering
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) {
        if (root.svc) root.svc.refresh()
      } else {
        root.toggle()
      }
    }
  }
}
