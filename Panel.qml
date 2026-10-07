import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

KeyboardPanel {
  id: panel

  property var host: null
  readonly property var svc: host ? host.svc : null
  readonly property var rows: svc ? Model.rows(svc.state, panel.showHidden, svc.reviews) : []
  readonly property color foreground: Color.popups.text
  readonly property var groupTitles: ({
    review: "TO REVIEW",
    mine: "MY MERGE REQUESTS"
  })
  readonly property var keyHints: [
    ["Enter", "open"],
    ["l", "details"],
    ["c", "review"],
    ["f", "fix"],
    ["x", "seen"],
    ["H", "hide"],
    ["a", "hidden"],
    ["r", "refresh"]
  ]
  readonly property var pipelineGlyphs: ({
    success: "\uf00c",
    danger: "\uf00d",
    warning: "\uf017",
    muted: "\uf05e"
  })

  property int cursor: 0
  // The cursor stays on its row when a refresh or a key changes the order of the rows.
  property string cursorKey: ""
  property bool cursorActive: false
  property bool showHidden: false
  property real now: Date.now()

  // The detail page shows one merge request. Leaving the page marks its row as seen.
  property string detailKey: ""
  property int detailCursor: 0
  property bool detailCursorActive: false
  readonly property var detail: svc && detailKey !== "" ? Model.detail(svc.state, detailKey, svc.reviews) : null

  contentWidth: fittedContentWidth(Style.space(480))
  contentHeight: cappedContentHeight(Style.space(520))
  focusTarget: keyCatcher

  onOpenChanged: {
    if (!open) {
      if (panel.detailKey !== "") panel.closeDetail()
      return
    }
    panel.showHidden = false
    panel.setCursor(0)
    panel.cursorActive = false
    panel.now = Date.now()
    rowList.positionViewAtBeginning()
    if (panel.svc) panel.svc.reloadLocal()
  }

  onRowsChanged: {
    var index = -1
    for (var i = 0; i < rows.length; i++) if (rows[i].key === panel.cursorKey) index = i
    if (index >= 0) panel.cursor = index
    else panel.setCursor(Math.max(0, Math.min(panel.cursor, rows.length - 1)))
    Qt.callLater(function() {
      if (panel.cursorActive) rowList.positionViewAtIndex(panel.cursor, ListView.Contain)
    })
  }

  // The merge request left the inbox, for example because it was merged.
  onDetailChanged: if (panel.detailKey !== "" && !panel.detail) panel.detailKey = ""

  function openDetail(index) {
    if (!panel.svc || index < 0 || index >= rows.length) return
    panel.detailKey = rows[index].key
    panel.detailCursor = 0
    panel.detailCursorActive = !!panel.detail && panel.detail.items.length > 0
  }

  function closeDetail() {
    var key = panel.detailKey
    panel.detailKey = ""
    if (panel.svc && key !== "") panel.svc.markSeen(key)
  }

  function setDetailCursor(index) {
    panel.detailCursor = index
    panel.detailCursorActive = true
  }

  function moveDetailCursor(delta) {
    var count = panel.detail ? panel.detail.items.length : 0
    if (count > 0) panel.setDetailCursor(Math.max(0, Math.min(count - 1, panel.detailCursor + delta)))
  }

  function openDetailItem(index) {
    if (!panel.detail || index < 0 || index >= panel.detail.items.length) return
    if (panel.svc.openUrl(panel.detail.items[index].url)) panel.close()
  }

  // The buttons of the detail page. Each button also has a key.
  function detailActions() {
    if (!panel.detail) return []
    var actions = [{ kind: "open", text: "Open", tooltip: "Open the merge request in the browser · o" }]
    if (panel.detail.diffUrl) actions.push({ kind: "diff", text: "Diff since you looked", tooltip: "The new commits as one diff · d" })
    if (panel.detail.row.group === "mine") actions.push({ kind: "fix", text: "Fix", tooltip: "Fix with Claude Code, then ask before the push · f" })
    actions.push({ kind: "review", text: "Review", tooltip: "Review with Claude Code and publish on GitLab · c" })
    return actions
  }

  function detailHints() {
    if (!panel.detail) return []
    var hints = [["h", "back"], ["Enter", "open item"], ["o", "open"]]
    if (panel.detail.diffUrl) hints.push(["d", "diff"])
    if (panel.detail.row.group === "mine") hints.push(["f", "fix"])
    return hints.concat([["c", "review"], ["x", "seen"]])
  }

  function detailAction(kind) {
    if (!panel.detail) return
    var key = panel.detailKey
    var done = kind === "open" ? panel.svc.openRow(key)
      : kind === "diff" ? panel.detail.diffUrl !== "" && panel.svc.openUrl(panel.detail.diffUrl)
      : kind === "fix" ? panel.detail.row.group === "mine" && panel.svc.startSession(key, "fix")
      : kind === "review" ? panel.svc.startSession(key, "review")
      : false
    if (done) panel.close()
  }

  function setCursor(index) {
    panel.cursor = index
    panel.cursorKey = index >= 0 && index < rows.length ? rows[index].key : ""
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    panel.cursorActive = true
    panel.setCursor(Math.max(0, Math.min(rows.length - 1, panel.cursor + delta)))
    rowList.positionViewAtIndex(panel.cursor, ListView.Contain)
  }

  function openRow(index) {
    if (!panel.svc || index < 0 || index >= rows.length) return
    if (panel.svc.openRow(rows[index].key)) panel.close()
  }

  function startSession(index, kind) {
    if (!panel.svc || index < 0 || index >= rows.length) return
    if (panel.svc.startSession(rows[index].key, kind)) panel.close()
  }

  // A fix session works on the source branch, so only a merge request of the user has one.
  function fixRow(index) {
    if (index >= 0 && index < rows.length && rows[index].group === "mine") panel.startSession(index, "fix")
  }

  // The buttons of the row under the cursor. Each button also has a key.
  function actionsFor(row) {
    var actions = []
    if (row.group === "mine") actions.push({ kind: "fix", text: "Fix", tooltip: "Fix with Claude Code, then ask before the push · f" })
    actions.push({ kind: "review", text: "Review", tooltip: "Review with Claude Code and publish on GitLab · c" })
    if (row.unseen) actions.push({ kind: "seen", text: "Seen", tooltip: "Mark as seen · x" })
    actions.push({ kind: "details", text: "", icon: "\uf054", tooltip: "Details · l" })
    return actions
  }

  function runAction(index, kind) {
    if (kind === "fix") panel.fixRow(index)
    else if (kind === "review") panel.startSession(index, "review")
    else if (kind === "seen") panel.markSeen(index)
    else if (kind === "details") panel.openDetail(index)
  }

  function toneColor(tone) {
    return panel.svc ? panel.svc.toneColor(tone) : panel.foreground
  }

  // The pills of a row: its open sessions, then its statuses.
  function pillsFor(row) {
    var pills = []
    var key = row.project + "!" + row.iid
    if (row.hidden) pills.push({ text: "hidden", tone: "muted" })
    if (panel.svc && panel.svc.sessions["review:" + key]) pills.push({ text: "reviewing", tone: "info" })
    if (panel.svc && panel.svc.sessions["fix:" + key]) pills.push({ text: "fixing", tone: "info" })
    return pills.concat(row.badges)
  }

  function groupCount(group) {
    var count = 0
    for (var i = 0; i < rows.length; i++) if (rows[i].group === group) count++
    return count
  }

  function markSeen(index) {
    if (panel.svc && index >= 0 && index < rows.length) panel.svc.markSeen(rows[index].key)
  }

  function toggleHidden(index) {
    if (panel.svc && index >= 0 && index < rows.length) panel.svc.setHidden(rows[index].key, !rows[index].hidden)
  }

  function markAllSeen() {
    if (panel.svc) panel.svc.markAllSeen()
  }

  function refresh() {
    if (panel.svc) panel.svc.refresh()
  }

  function emptyText() {
    if (!panel.svc || !panel.svc.state.initialized)
      return panel.svc && panel.svc.lastError !== "" ? "No saved rows" : "Reading GitLab…"
    return "Nothing waits for you"
  }

  function footerText() {
    if (!panel.svc) return "Starting…"
    if (panel.svc.refreshing) return "Refreshing…"
    if (panel.svc.lastError !== "") return panel.svc.lastError
    if (panel.svc.state.lastRefreshMs > 0) {
      var age = Model.relativeTime(panel.svc.state.lastRefreshMs, panel.now)
      return age === "now" ? "Updated just now" : "Updated " + age + " ago"
    }
    return "Waiting for the first refresh"
  }

  Item {
    anchors.fill: parent

    Timer {
      interval: 60000
      running: panel.open
      repeat: true
      onTriggered: panel.now = Date.now()
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (panel.detail) {
          if (dy !== 0) panel.moveDetailCursor(dy)
          else if (dx < 0) panel.closeDetail()
          else panel.openDetailItem(panel.detailCursor)
        } else if (dy !== 0) {
          panel.moveCursor(dy)
        } else if (dx > 0) {
          panel.openDetail(panel.cursor)
        }
      }
      onActivateRequested: panel.detail ? panel.openDetailItem(panel.detailCursor) : panel.openRow(panel.cursor)
      onDeleteRequested: panel.detail ? panel.svc.markSeen(panel.detailKey) : panel.markSeen(panel.cursor)
      onCloseRequested: panel.detail ? panel.closeDetail() : panel.close()
      onTabRequested: function(direction) {
        if (panel.host) panel.host.switchPanel(direction)
      }
      onTextKey: function(text) {
        if (panel.detail) {
          if (text === "o") panel.detailAction("open")
          else if (text === "d") panel.detailAction("diff")
          else if (text === "f") panel.detailAction("fix")
          else if (text === "c") panel.detailAction("review")
          else if (text === "r") panel.refresh()
          return
        }
        if (text === "o") panel.openRow(panel.cursor)
        else if (text === "c") panel.startSession(panel.cursor, "review")
        else if (text === "f") panel.fixRow(panel.cursor)
        else if (text === "r") panel.refresh()
        else if (text === "A") panel.markAllSeen()
        else if (text === "H") panel.toggleHidden(panel.cursor)
        else if (text === "a") panel.showHidden = !panel.showHidden
      }
    }

    Detail {
      anchors.fill: parent
      visible: !!panel.detail
      panel: panel
    }

    Item {
      id: listPage
      anchors.fill: parent
      visible: !panel.detail

      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(headerLabels.implicitHeight, markAllButton.implicitHeight)

        Column {
          id: headerLabels
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs

          Text {
            text: "MERGE REQUESTS"
            textFormat: Text.PlainText
            color: panel.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            font.letterSpacing: 1.1
          }

          Text {
            text: !panel.svc ? "Starting…"
              : panel.svc.unreadCount > 0 ? panel.svc.unreadCount + " new" : "Nothing new"
            textFormat: Text.PlainText
            color: panel.foreground
            opacity: 0.58
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Button {
          id: markAllButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: panel.svc && panel.svc.unreadCount > 0
          text: "Mark all seen"
          foreground: panel.foreground
          fontFamily: Style.font.family
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.spacing.lg
          verticalPadding: Style.spacing.sm
          onClicked: panel.markAllSeen()
        }
      }

      PanelSeparator {
        id: headerRule
        anchors.top: header.bottom
        anchors.topMargin: Style.spacing.xl
        foreground: panel.foreground
      }

      ListView {
        id: rowList
        anchors.top: headerRule.bottom
        anchors.bottom: footerRule.top
        anchors.topMargin: Style.spacing.sm
        anchors.bottomMargin: Style.spacing.sm
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: panel.rows
        currentIndex: panel.cursor
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Item {
          id: rowDelegate
          required property var modelData
          required property int index

          readonly property bool startsGroup: index === 0 || panel.rows[index - 1].group !== modelData.group

          width: rowList.width
          height: groupHeader.height + rowSurface.implicitHeight

          Item {
            id: groupHeader
            width: parent.width
            height: rowDelegate.startsGroup ? groupLabel.implicitHeight + Style.spacing.lg + Style.spacing.sm : 0
            visible: rowDelegate.startsGroup

            PanelSectionHeader {
              id: groupLabel
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.xl
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.spacing.sm
              text: panel.groupTitles[rowDelegate.modelData.group] + " · " + panel.groupCount(rowDelegate.modelData.group)
              foreground: panel.foreground
            }
          }

          CursorSurface {
            id: rowSurface
            anchors.top: groupHeader.bottom
            width: parent.width
            implicitHeight: rowContent.implicitHeight + Style.spacing.lg * 2
            hasCursor: panel.cursorActive && panel.cursor === rowDelegate.index
            foreground: panel.foreground
            opacity: rowDelegate.modelData.hidden ? 0.45 : 1

            Column {
              id: rowContent
              // The buttons of the row are above the mouse area that opens the row.
              z: 1
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.xl
              anchors.rightMargin: Style.spacing.xl
              spacing: Style.spacing.xs

              Item {
                width: parent.width
                height: Math.max(rowName.implicitHeight, rowTime.implicitHeight)

                Rectangle {
                  id: unseenDot
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  visible: rowDelegate.modelData.unseen
                  width: visible ? Style.space(6) : 0
                  height: Style.space(6)
                  radius: height / 2
                  color: Color.accent
                }

                Text {
                  id: rowTime
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.relativeTime(rowDelegate.modelData.timeMs, panel.now)
                  textFormat: Text.PlainText
                  color: panel.foreground
                  opacity: 0.52
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Text {
                  id: rowPipeline
                  anchors.right: rowTime.left
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  text: panel.pipelineGlyphs[rowDelegate.modelData.pipelineTone] || ""
                  textFormat: Text.PlainText
                  color: panel.toneColor(rowDelegate.modelData.pipelineTone)
                  opacity: rowDelegate.modelData.pipelineTone === "muted" ? 0.52 : 1
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  id: rowName
                  anchors.left: unseenDot.right
                  anchors.leftMargin: rowDelegate.modelData.unseen ? Style.spacing.sm : 0
                  anchors.right: rowPipeline.left
                  anchors.rightMargin: Style.spacing.lg
                  text: rowDelegate.modelData.name + " !" + rowDelegate.modelData.iid
                  textFormat: Text.PlainText
                  color: panel.foreground
                  opacity: rowDelegate.modelData.unseen ? 1 : 0.76
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: rowDelegate.modelData.unseen
                  elide: Text.ElideRight
                }
              }

              Item {
                width: parent.width
                height: Math.max(rowPills.implicitHeight, rowTitle.implicitHeight)
                clip: true

                Row {
                  id: rowPills
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.sm

                  Repeater {
                    model: panel.pillsFor(rowDelegate.modelData)

                    delegate: Rectangle {
                      id: pill
                      required property var modelData
                      readonly property color tint: panel.toneColor(modelData.tone)
                      readonly property bool muted: modelData.tone === "muted"

                      width: pillText.implicitWidth + Style.spacing.md * 2
                      height: pillText.implicitHeight + Style.spacing.xxs * 2
                      radius: Style.cornerRadius
                      color: Util.alpha(tint, muted ? 0.08 : 0.16)

                      Text {
                        id: pillText
                        anchors.centerIn: parent
                        text: pill.modelData.text
                        textFormat: Text.PlainText
                        color: pill.tint
                        opacity: pill.muted ? 0.62 : 1
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: rowDelegate.modelData.unseen
                      }
                    }
                  }
                }

                Row {
                  id: rowActions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  visible: panel.cursorActive && panel.cursor === rowDelegate.index
                  spacing: Style.spacing.sm

                  Repeater {
                    model: rowActions.visible ? panel.actionsFor(rowDelegate.modelData) : []

                    delegate: Button {
                      required property var modelData
                      height: rowPills.height
                      text: modelData.text
                      iconText: modelData.icon || ""
                      tooltipText: modelData.tooltip
                      bordered: true
                      background: Util.alpha(panel.foreground, 0.06)
                      foreground: panel.foreground
                      fontFamily: Style.font.family
                      fontSize: Style.font.caption
                      horizontalPadding: Style.spacing.md
                      verticalPadding: 0
                      onClicked: panel.runAction(rowDelegate.index, modelData.kind)
                    }
                  }
                }

                Text {
                  id: rowTitle
                  anchors.left: rowPills.right
                  anchors.leftMargin: Style.spacing.md
                  anchors.right: rowActions.visible ? rowActions.left : parent.right
                  anchors.rightMargin: rowActions.visible ? Style.spacing.md : 0
                  anchors.verticalCenter: parent.verticalCenter
                  text: rowDelegate.modelData.group === "mine" || rowDelegate.modelData.author === ""
                    ? rowDelegate.modelData.title
                    : rowDelegate.modelData.author + ": " + rowDelegate.modelData.title
                  textFormat: Text.PlainText
                  color: panel.foreground
                  opacity: 0.46
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton
              onEntered: {
                panel.cursorActive = true
                panel.setCursor(rowDelegate.index)
              }
              onClicked: panel.openRow(rowDelegate.index)
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: rowList.count === 0
          text: panel.emptyText()
          textFormat: Text.PlainText
          color: panel.foreground
          opacity: 0.56
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      PanelSeparator {
        id: footerRule
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.spacing.sm
        foreground: panel.foreground
      }

      Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: footerColumn.implicitHeight

        Column {
          id: footerColumn
          width: parent.width
          spacing: Style.spacing.sm

          Item {
            width: parent.width
            height: Math.max(footerStatus.implicitHeight, refreshButton.implicitHeight)

            Text {
              id: footerStatus
              anchors.left: parent.left
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: panel.footerText()
              textFormat: Text.PlainText
              color: panel.foreground
              opacity: 0.52
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            PanelActionButton {
              id: refreshButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              enabled: panel.svc && !panel.svc.refreshing
              iconText: ""
              tooltipText: "Refresh"
              foreground: panel.foreground
              fontFamily: Style.font.family
              fontSize: Style.font.bodySmall
              size: Style.space(20)
              onClicked: panel.refresh()
            }
          }

          KeyHints {
            width: parent.width
            foreground: panel.foreground
            hints: panel.keyHints
          }
        }
      }
    }
  }
}
