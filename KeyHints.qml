import QtQuick
import qs.Commons

// Key hints as keycaps. They wrap to a second line when the panel is narrow.
Flow {
  id: root

  // Each hint is [key, label].
  property var hints: []
  property color foreground: Color.popups.text

  spacing: Style.spacing.md

  Repeater {
    model: root.hints

    delegate: Row {
      id: hint
      required property var modelData
      spacing: Style.spacing.xs

      Rectangle {
        width: keyText.implicitWidth + Style.spacing.sm * 2
        height: keyText.implicitHeight + Style.spacing.xxs * 2
        radius: Style.cornerRadius
        color: Util.alpha(root.foreground, 0.1)

        Text {
          id: keyText
          anchors.centerIn: parent
          text: hint.modelData[0]
          textFormat: Text.PlainText
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: hint.modelData[1]
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.68
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
