import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: ""

  readonly property string moduleId: "io.github.thelost77.omasecretary"
  readonly property int refreshMinutes: 5
  readonly property int maxNotifications: 3

  property string stateDir: ""
  property string helperPath: ""
  property string reviewPath: ""
  property var state: Model.emptyState()
  property var reviews: ({})
  // The markers of the open tmux sessions, for example "review:group/app!5".
  property var sessions: ({})
  property var palette: ({})
  property bool ready: false
  property bool refreshing: false
  property string lastError: ""
  property string refreshReason: ""

  readonly property var visibleRows: Model.rows(state, false, reviews)
  readonly property int unreadCount: Model.unreadCount(visibleRows)
  readonly property bool alarm: Model.hasUnseenDanger(visibleRows)

  Component.onCompleted: bootstrapTimer.start()

  function pluginDir() {
    if (root.manifest && root.manifest.__sourceDir)
      return String(root.manifest.__sourceDir).replace(/\/$/, "")
    return (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/" + root.moduleId
  }

  function bootstrap() {
    var home = Quickshell.env("HOME") || ""
    var stateHome = Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
    root.stateDir = stateHome + "/omasecretary"
    root.helperPath = pluginDir() + "/bin/omasecretary-inbox"
    root.reviewPath = pluginDir() + "/bin/omasecretary-review"
    mkdirProc.command = ["bash", "-c", "umask 077; mkdir -p \"$1\"; chmod 700 \"$1\"", "_", root.stateDir]
    mkdirProc.running = true
  }

  function finishCacheLoad() {
    if (root.ready || root.stateDir === "") return
    root.ready = true
    Qt.callLater(root.refresh)
  }

  function refresh() {
    if (!root.ready || root.refreshing || root.helperPath === "") return
    root.refreshing = true
    root.refreshReason = ""
    refreshProc.running = true
  }

  // stdout and stderr of the helper can finish in either order.
  function refreshFailure() {
    return "Could not read GitLab" + (root.refreshReason !== "" ? ": " + root.refreshReason : "") + " · showing saved rows"
  }

  // The theme color of a tone. A theme without the color gives a color of the shell.
  function toneColor(tone) {
    if (tone === "danger") return root.palette.danger || Color.urgent
    if (tone === "warning") return root.palette.warning || Color.accent
    if (tone === "success") return root.palette.success || Color.accent
    if (tone === "info") return root.palette.info || Color.accent
    return Color.popups.text
  }

  function apply(next) {
    if (!root.ready) return
    root.state = next
    cacheFile.setText(Model.serialize(next))
    secureTimer.restart()
  }

  function markSeen(key) {
    root.apply(Model.markSeen(root.state, key))
  }

  function markAllSeen() {
    root.apply(Model.markAllSeen(root.state))
  }

  function setHidden(key, hide) {
    root.apply(Model.setHidden(root.state, key, hide))
  }

  // A click on a notification with a link opens the link.
  function notify(title, body, url) {
    var command = ["omarchy-notification-send", "--app-name", "OmaSecretary", title, body]
    if (url) command = command.concat(["--exec", "omarchy-launch-browser", url])
    Quickshell.execDetached(command)
  }

  // Tells the user about the rows that a refresh made unseen.
  function announce(fresh) {
    if (fresh.length > root.maxNotifications) {
      root.notify("OmaSecretary", fresh.length + " merge requests have news")
      return
    }
    for (var i = 0; i < fresh.length; i++)
      root.notify(fresh[i].name + " !" + fresh[i].iid, fresh[i].status + " · " + fresh[i].title, fresh[i].url)
  }

  // Reads again the data that other programs change: the review launcher, tmux, and the theme.
  function reloadLocal() {
    if (reviewsFile.path !== "") reviewsFile.reload()
    paletteFile.reload()
    sessionsProc.running = true
  }

  // kind is "review" or "fix".
  function startSession(key, kind) {
    var row = Model.rowByKey(root.state, key)
    if (!row || root.reviewPath === "") return false
    var command = [root.reviewPath, "open"]
    if (kind === "fix") command.push("--fix")
    Quickshell.execDetached(command.concat([row.project, String(row.iid)]))
    root.markSeen(key)
    return true
  }

  // Opens a link of GitLab, such as a note or a diff, in the browser.
  function openUrl(url) {
    if (!/^https:\/\/[^\s]+$/.test(String(url || ""))) return false
    Quickshell.execDetached(["omarchy-launch-browser", url])
    return true
  }

  function openRow(key) {
    var row = Model.rowByKey(root.state, key)
    if (!row) return false
    Quickshell.execDetached(["omarchy-launch-browser", row.url])
    root.markSeen(key)
    return true
  }

  Timer {
    id: bootstrapTimer
    interval: 0
    repeat: false
    onTriggered: root.bootstrap()
  }

  Process {
    id: mkdirProc
    running: false
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = "Could not create the state folder"
        return
      }
      cacheFile.path = root.stateDir + "/cache.json"
      cacheFile.reload()
      reviewsFile.path = root.stateDir + "/reviews.json"
      reviewsFile.reload()
    }
  }

  FileView {
    id: paletteFile
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: false
    printErrors: false

    onLoaded: root.palette = Model.parsePalette(text())
    onLoadFailed: root.palette = ({})
  }

  Process {
    id: sessionsProc
    running: false
    command: ["tmux", "list-sessions", "-F", "#{@omasecretary}"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.sessions = Model.parseSessions(text)
    }
  }

  // The review launcher writes this file.
  FileView {
    id: reviewsFile
    path: ""
    watchChanges: false
    printErrors: false

    onLoaded: root.reviews = Model.parseReviews(text())
    onLoadFailed: root.reviews = ({})
  }

  FileView {
    id: cacheFile
    path: ""
    watchChanges: false
    atomicWrites: true
    printErrors: false

    onLoaded: {
      if (root.stateDir === "") return
      root.state = Model.loadState(text())
      root.finishCacheLoad()
    }

    onLoadFailed: {
      if (root.stateDir === "") return
      root.state = Model.emptyState()
      root.finishCacheLoad()
    }
  }

  Process {
    id: refreshProc
    running: false
    // The shell does not have the GitLab token that a login profile exports.
    // A login shell gives the helper the same environment as a terminal.
    command: root.helperPath === "" ? [] : ["bash", "-lc", "exec \"$0\"", root.helperPath]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var inbox = Model.parseInbox(text)
        root.refreshing = false
        if (!inbox) {
          root.lastError = root.refreshFailure()
          return
        }

        root.lastError = ""
        var before = Model.rows(root.state, false, root.reviews)
        root.apply(Model.reconcile(root.state, inbox, Date.now()))
        root.announce(Model.freshRows(before, Model.rows(root.state, false, root.reviews)))
        root.reloadLocal()
        Quickshell.execDetached(["bash", "-lc", "exec \"$0\" prune", root.reviewPath])
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.trim().split("\n")
        root.refreshReason = lines[lines.length - 1].trim().slice(0, 160)
        if (!root.refreshing && root.lastError !== "") root.lastError = root.refreshFailure()
      }
    }
  }

  Timer {
    interval: root.refreshMinutes * 60 * 1000
    running: root.ready
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: secureTimer
    interval: 250
    repeat: false
    onTriggered: {
      secureProc.command = ["bash", "-c", "chmod 600 \"$1/cache.json\" 2>/dev/null || true", "_", root.stateDir]
      secureProc.running = true
    }
  }

  Process {
    id: secureProc
    running: false
  }
}
