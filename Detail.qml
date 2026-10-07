import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The detail page of one merge request: its state and its activity, newest first.
// The panel owns the page state and the keys. This item only shows them.
Item {
  id: page

  property var panel: null
  readonly property var detail: panel ? panel.detail : null
  readonly property var row: detail ? detail.row : null
  readonly property color foreground: panel ? panel.foreground : Color.popups.text
  readonly property var kindGlyphs: ({
    reply: "",
    comment: "",
    own: "",
    commits: "",
    changed: "",
    approved: "",
    unapproved: "",
    "review-request": "",
    description: "",
    status: "",
    resolved: "",
    event: ""
  })
  readonly property var kindTones: ({
    reply: "warning",
    comment: "warning",
    own: "muted",
    commits: "info",
    changed: "info",
    approved: "success",
    unapproved: "danger",
    "review-request": "info",
    description: "muted",
    status: "muted",
    resolved: "success",
    event: "muted"
  })

  function who(author) {
    return page.detail && author === page.detail.me ? "you" : author
  }

  function reviewersText() {
    if (!page.detail || page.detail.reviewers.length === 0) return "no reviewers"
    var parts = []
    for (var i = 0; i < page.detail.reviewers.length; i++) {
      var reviewer = page.detail.reviewers[i]
      var state = reviewer.state && reviewer.state !== "unreviewed" ? " " + reviewer.state.replace(/_/g, " ") : ""
      parts.push(page.who(reviewer.username) + state)
    }
    return "reviewers: " + parts.join(" · ")
  }

  function sectionTitle(isNew) {
    if (isNew) return "NEW · " + page.detail.newCount
    var count = page.detail.items.length - page.detail.newCount
    return (page.detail.newCount > 0 ? "EARLIER · " : "ACTIVITY · ") + count
  }

  Column {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.xs

    Item {
      width: parent.width
      height: Math.max(backButton.implicitHeight, nameText.implicitHeight)

      PanelActionButton {
        id: backButton
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        iconText: ""
        tooltipText: "Back · h"
        foreground: page.foreground
        fontFamily: Style.font.family
        fontSize: Style.font.bodySmall
        size: Style.space(20)
        onClicked: page.panel.closeDetail()
      }

      Text {
        id: timeText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: page.row ? Model.relativeTime(page.row.timeMs, page.panel.now) : ""
        textFormat: Text.PlainText
        color: page.foreground
        opacity: 0.52
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Text {
        id: pipelineText
        anchors.right: timeText.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        text: page.row ? page.panel.pipelineGlyphs[page.row.pipelineTone] || "" : ""
        textFormat: Text.PlainText
        color: page.panel.toneColor(page.row ? page.row.pipelineTone : "")
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        id: nameText
        anchors.left: backButton.right
        anchors.leftMargin: Style.spacing.sm
        anchors.right: pipelineText.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        text: page.row ? page.row.name + " !" + page.row.iid : ""
        textFormat: Text.PlainText
        color: page.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
    }

    Text {
      width: parent.width
      text: page.row ? page.row.title : ""
      textFormat: Text.PlainText
      color: page.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: !page.detail ? ""
        : (page.row.author !== "" ? page.row.author + " · " : "") + page.detail.sourceBranch + " → " + page.detail.targetBranch
      textFormat: Text.PlainText
      color: page.foreground
      opacity: 0.52
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: page.reviewersText()
      textFormat: Text.PlainText
      color: page.foreground
      opacity: 0.52
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Flow {
      width: parent.width
      spacing: Style.spacing.sm

      Repeater {
        model: page.row ? page.panel.pillsFor(page.row) : []

        delegate: Rectangle {
          id: pill
          required property var modelData
          readonly property color tint: page.panel.toneColor(modelData.tone)

          width: pillText.implicitWidth + Style.spacing.md * 2
          height: pillText.implicitHeight + Style.spacing.xxs * 2
          radius: Style.cornerRadius
          color: Util.alpha(tint, modelData.tone === "muted" ? 0.08 : 0.16)

          Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.modelData.text
            textFormat: Text.PlainText
            color: pill.tint
            opacity: pill.modelData.tone === "muted" ? 0.62 : 1
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  PanelSeparator {
    id: headerRule
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.lg
    foreground: page.foreground
  }

  ListView {
    id: itemList
    anchors.top: headerRule.bottom
    anchors.bottom: footerRule.top
    anchors.topMargin: Style.spacing.sm
    anchors.bottomMargin: Style.spacing.sm
    anchors.left: parent.left
    anchors.right: parent.right
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: page.detail ? page.detail.items : []
    currentIndex: page.panel ? page.panel.detailCursor : 0
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    delegate: Item {
      id: itemDelegate
      required property var modelData
      required property int index

      readonly property bool startsSection: index === 0 || page.detail.items[index - 1].isNew !== modelData.isNew
      readonly property color tint: page.panel.toneColor(page.kindTones[modelData.kind] || "muted")

      width: itemList.width
      height: sectionHeader.height + itemSurface.implicitHeight

      Item {
        id: sectionHeader
        width: parent.width
        height: itemDelegate.startsSection ? sectionLabel.implicitHeight + Style.spacing.lg + Style.spacing.sm : 0
        visible: itemDelegate.startsSection

        PanelSectionHeader {
          id: sectionLabel
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.xl
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.spacing.sm
          text: page.sectionTitle(itemDelegate.modelData.isNew)
          foreground: page.foreground
        }
      }

      CursorSurface {
        id: itemSurface
        anchors.top: sectionHeader.bottom
        width: parent.width
        implicitHeight: itemContent.implicitHeight + Style.spacing.md * 2
        hasCursor: page.panel.detailCursorActive && page.panel.detailCursor === itemDelegate.index
        foreground: page.foreground
        opacity: itemDelegate.modelData.isNew ? 1 : 0.7

        Column {
          id: itemContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.spacing.xl
          anchors.rightMargin: Style.spacing.xl
          spacing: Style.spacing.xxs

          Item {
            width: parent.width
            height: Math.max(itemHeadline.implicitHeight, itemTime.implicitHeight)
            clip: true

            Text {
              id: itemGlyph
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              text: page.kindGlyphs[itemDelegate.modelData.kind] || page.kindGlyphs.event
              textFormat: Text.PlainText
              color: itemDelegate.tint
              opacity: page.kindTones[itemDelegate.modelData.kind] === "muted" ? 0.62 : 1
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              id: itemTime
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: Model.relativeTime(itemDelegate.modelData.atMs, page.panel.now)
              textFormat: Text.PlainText
              color: page.foreground
              opacity: 0.52
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Row {
              id: itemHeadline
              anchors.left: itemGlyph.right
              anchors.right: itemTime.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm
              clip: true

              Text {
                text: page.who(itemDelegate.modelData.author)
                textFormat: Text.PlainText
                color: page.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                text: itemDelegate.modelData.verb
                textFormat: Text.PlainText
                color: page.foreground
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                visible: itemDelegate.modelData.path !== ""
                text: itemDelegate.modelData.path.slice(itemDelegate.modelData.path.lastIndexOf("/") + 1)
                  + (itemDelegate.modelData.line > 0 ? ":" + itemDelegate.modelData.line : "")
                textFormat: Text.PlainText
                color: page.foreground
                opacity: 0.46
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          Text {
            visible: itemDelegate.modelData.body !== ""
            width: parent.width
            leftPadding: itemGlyph.width
            text: itemDelegate.modelData.body
            textFormat: Text.PlainText
            color: page.foreground
            opacity: 0.8
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }

          Repeater {
            model: itemDelegate.modelData.lines

            delegate: Text {
              required property var modelData
              width: itemContent.width
              leftPadding: itemGlyph.width
              text: modelData
              textFormat: Text.PlainText
              color: page.foreground
              opacity: 0.62
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton
          onEntered: page.panel.setDetailCursor(itemDelegate.index)
          onClicked: page.panel.openDetailItem(itemDelegate.index)
        }
      }
    }

    Text {
      anchors.centerIn: parent
      visible: itemList.count === 0
      text: "No comments or events yet"
      textFormat: Text.PlainText
      color: page.foreground
      opacity: 0.56
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  PanelSeparator {
    id: footerRule
    anchors.bottom: footer.top
    anchors.bottomMargin: Style.spacing.sm
    foreground: page.foreground
  }

  Column {
    id: footer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    spacing: Style.spacing.sm

    Flow {
      width: parent.width
      spacing: Style.spacing.sm

      Repeater {
        model: page.panel ? page.panel.detailActions() : []

        delegate: Button {
          required property var modelData
          text: modelData.text
          tooltipText: modelData.tooltip
          bordered: true
          background: Util.alpha(page.foreground, 0.06)
          foreground: page.foreground
          fontFamily: Style.font.family
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.md
          verticalPadding: Style.spacing.xxs
          onClicked: page.panel.detailAction(modelData.kind)
        }
      }
    }

    KeyHints {
      width: parent.width
      foreground: page.foreground
      hints: page.panel ? page.panel.detailHints() : []
    }
  }
}
