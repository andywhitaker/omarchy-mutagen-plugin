import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string helperPath: pluginDir + "/mutagen_status.py"
  readonly property string homeDir: Quickshell.env("HOME") || ""

  property bool installed: false
  property bool daemonRunning: false
  property int _desiredDaemon: -1
  readonly property bool daemonActive: _desiredDaemon === -1 ? daemonRunning : (_desiredDaemon === 1)
  property string version: ""
  property bool refreshing: false
  readonly property bool busy: statusProcess.running || actionProcess.running

  property var syncs: []
  property var forwards: []
  property var projectGroups: []
  readonly property var summary: Model.summarize(installed, daemonActive, syncs, forwards, showSessionCount)
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 5, 2, 300)
  readonly property bool showSessionCount: boolSetting("showSessionCount", true)
  readonly property bool showForwards: boolSetting("showForwards", true)
  readonly property bool notifyOnIssues: boolSetting("notifyOnIssues", true)
  readonly property bool hideWhenEmpty: boolSetting("hideWhenEmpty", false)

  property string _statusOutput: ""
  property string _statusError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _syncsSig: "[]"
  property string _forwardsSig: "[]"
  property string _projectGroupsSig: "[]"
  property var _cycleMap: ({})
  property bool _hasPolledOnce: false
  property var _previousIssueKeys: ({})

  onPanelOpenChanged: {
    if (panelOpen) refresh()
  }

  onShowForwardsChanged: {
    refresh()
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (typeof value === "boolean") return value
    if (typeof value === "string") {
      var lowered = value.toLowerCase()
      if (lowered === "true" || lowered === "1") return true
      if (lowered === "false" || lowered === "0") return false
    }
    return fallback
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function showTransientStatus(message) {
    actionStatus = elideStatus(message)
    if (actionStatus !== "") actionStatusTimer.restart()
  }

  function expandLocalPath(path) {
    var p = String(path || "").trim()
    if (p === "") return ""
    if (homeDir !== "") {
      if (p === "~") return homeDir
      if (p.indexOf("~/") === 0) return homeDir + p.slice(1)
    }
    return p
  }

  function publishSyncs(nextSyncs) {
    var sig = JSON.stringify(nextSyncs)
    if (sig !== _syncsSig) {
      _syncsSig = sig
      syncs = nextSyncs
    }
    var nextGroups = Model.groupSyncs(nextSyncs)
    var gSig = JSON.stringify(nextGroups)
    if (gSig !== _projectGroupsSig) {
      _projectGroupsSig = gSig
      projectGroups = nextGroups
    }
  }

  function publishForwards(nextForwards) {
    var sig = JSON.stringify(nextForwards)
    if (sig !== _forwardsSig) {
      _forwardsSig = sig
      forwards = nextForwards
    }
  }

  function updateCycleMap(rawSyncs, nowMs) {
    var nextMap = {}
    var list = Array.isArray(rawSyncs) ? rawSyncs : []
    for (var i = 0; i < list.length; i++) {
      var raw = list[i] || {}
      var id = String(raw.identifier || raw.id || "")
      if (id === "") continue
      var cycles = Number(raw.successfulCycles || 0)
      if (!isFinite(cycles) || cycles < 0) cycles = 0
      var prev = _cycleMap[id]
      if (!prev) {
        nextMap[id] = { cycles: cycles, lastSyncMs: 0 }
      } else if (cycles > prev.cycles) {
        nextMap[id] = { cycles: cycles, lastSyncMs: nowMs }
      } else {
        nextMap[id] = { cycles: cycles, lastSyncMs: prev.lastSyncMs }
      }
    }
    _cycleMap = nextMap
  }

  function processIssueNotifications(nextSyncs, nextForwards, isRunning) {
    var nextIssues = {}
    if (isRunning) {
      for (var i = 0; i < nextSyncs.length; i++) {
        var s = nextSyncs[i]
        if (!s || !s.hasIssue) continue
        var sKey = "sync:" + s.id
        var sSig = String(s.issueSummary || s.statusLabel || "Sync issue")
        nextIssues[sKey] = sSig
        if (_hasPolledOnce && notifyOnIssues && _previousIssueKeys[sKey] !== sSig) {
          var urgency = (s.conflicts.length > 0 || s.rawStatus.indexOf("halted-") === 0) ? "critical" : "normal"
          Quickshell.execDetached([
            "notify-send", "-a", "Mutagen", "-u", urgency,
            "Mutagen: " + s.displayName,
            sSig
          ])
        }
      }
      for (var j = 0; j < nextForwards.length; j++) {
        var f = nextForwards[j]
        if (!f || f.health !== "issue") continue
        var fKey = "fwd:" + f.id
        var fSig = String(f.lastError || f.statusLabel || "Forward issue")
        nextIssues[fKey] = fSig
        if (_hasPolledOnce && notifyOnIssues && _previousIssueKeys[fKey] !== fSig) {
          Quickshell.execDetached([
            "notify-send", "-a", "Mutagen", "-u", "normal",
            "Mutagen Forward: " + f.displayName,
            fSig
          ])
        }
      }
    }
    _previousIssueKeys = nextIssues
    _hasPolledOnce = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      lastError = elideStatus(parsed.error || "Failed to parse Mutagen status")
      return
    }

    var nowMs = Date.now()
    installed = parsed.installed === true
    daemonRunning = parsed.daemonRunning === true
    if (_desiredDaemon !== -1 && daemonRunning === (_desiredDaemon === 1)) {
      _desiredDaemon = -1
    }
    if (parsed.version !== "") {
      version = parsed.version
    } else if (!installed) {
      version = ""
    }

    if (installed && daemonRunning) {
      updateCycleMap(parsed.syncs, nowMs)
      var nextSyncs = Model.normalizeSyncs(parsed.syncs, _cycleMap, nowMs, homeDir)
      var nextForwards = showForwards ? Model.normalizeForwards(parsed.forwards) : []
      publishSyncs(nextSyncs)
      publishForwards(nextForwards)
      processIssueNotifications(nextSyncs, nextForwards, true)
    } else {
      _cycleMap = {}
      publishSyncs([])
      publishForwards([])
      processIssueNotifications([], [], false)
    }

    lastError = parsed.error ? elideStatus(parsed.error) : ""
  }

  function refresh() {
    if (statusProcess.running || helperPath === "/mutagen_status.py") return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    var cmd = ["python3", helperPath]
    if (showForwards) cmd.push("--forwards")
    statusProcess.command = cmd
    statusProcess.running = true
    if (!pollWatchdog.running) pollWatchdog.start()
  }

  function runAction(command, label, desiredDaemon) {
    if (!installed || actionProcess.running) return
    if (desiredDaemon !== undefined && desiredDaemon !== null) {
      _desiredDaemon = desiredDaemon
    }
    _actionOutput = ""
    _actionError = ""
    actionStatus = label ? elideStatus(label) : ""
    actionProcess.command = command
    actionProcess.running = true
  }

  function startDaemon() {
    runAction(["mutagen", "daemon", "start"], "Starting Mutagen daemon…", 1)
  }

  function stopDaemon() {
    runAction(["mutagen", "daemon", "stop"], "Stopping Mutagen daemon…", 0)
  }

  function toggleDaemon() {
    if (!installed) return
    if (daemonActive) stopDaemon()
    else startDaemon()
  }

  function flushAll() {
    runAction(["mutagen", "sync", "flush", "--all", "--skip-wait"], "Flushing all sessions…")
  }

  function pauseAll() {
    runAction(["mutagen", "sync", "pause", "--all"], "Pausing all sessions…")
  }

  function resumeAll() {
    runAction(["mutagen", "sync", "resume", "--all"], "Resuming all sessions…")
  }

  function togglePauseAll() {
    var hasActive = false
    for (var i = 0; i < syncs.length; i++) {
      if (syncs[i] && !syncs[i].paused) {
        hasActive = true
        break
      }
    }
    if (hasActive) pauseAll()
    else resumeAll()
  }

  function flushSession(id) {
    var sid = String(id || "")
    if (sid === "") return
    runAction(["mutagen", "sync", "flush", "--skip-wait", sid], "Flushing session…")
  }

  function pauseSession(id) {
    var sid = String(id || "")
    if (sid === "") return
    runAction(["mutagen", "sync", "pause", sid], "Pausing session…")
  }

  function resumeSession(id) {
    var sid = String(id || "")
    if (sid === "") return
    runAction(["mutagen", "sync", "resume", sid], "Resuming session…")
  }

  function toggleSessionPause(session) {
    if (!session || !session.id) return
    if (session.paused) resumeSession(session.id)
    else pauseSession(session.id)
  }

  function resetSession(id) {
    var sid = String(id || "")
    if (sid === "") return
    runAction(["mutagen", "sync", "reset", sid], "Resetting session…")
  }

  function terminateSession(id) {
    var sid = String(id || "")
    if (sid === "") return
    runAction(["mutagen", "sync", "terminate", sid], "Terminating session…")
  }

  function flushProject(projectId) {
    var pid = String(projectId || "")
    if (pid === "") return
    runAction(["mutagen", "sync", "flush", "--skip-wait", "--label-selector", "io.mutagen.project=" + pid], "Flushing project…")
  }

  function pauseProject(projectId) {
    var pid = String(projectId || "")
    if (pid === "") return
    runAction(["mutagen", "sync", "pause", "--label-selector", "io.mutagen.project=" + pid], "Pausing project…")
  }

  function resumeProject(projectId) {
    var pid = String(projectId || "")
    if (pid === "") return
    runAction(["mutagen", "sync", "resume", "--label-selector", "io.mutagen.project=" + pid], "Resuming project…")
  }

  function pauseForward(id) {
    var fid = String(id || "")
    if (fid === "") return
    runAction(["mutagen", "forward", "pause", fid], "Pausing forward…")
  }

  function resumeForward(id) {
    var fid = String(id || "")
    if (fid === "") return
    runAction(["mutagen", "forward", "resume", fid], "Resuming forward…")
  }

  function toggleForwardPause(fwd) {
    if (!fwd || !fwd.id) return
    if (fwd.paused) resumeForward(fwd.id)
    else pauseForward(fwd.id)
  }

  function terminateForward(id) {
    var fid = String(id || "")
    if (fid === "") return
    runAction(["mutagen", "forward", "terminate", fid], "Terminating forward…")
  }

  function copyText(value, label) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
    showTransientStatus(label ? ("Copied " + label) : "Copied to clipboard")
  }

  function openLocalPath(path) {
    var target = expandLocalPath(path)
    if (target === "") return
    Util.execArgv(["xdg-open", target])
  }

  function openLocalTerminal(path) {
    var target = expandLocalPath(path)
    if (target === "") return
    Util.execArgv(["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + target])
  }

  function openRemoteSsh(sshEndpoint) {
    if (!sshEndpoint || !sshEndpoint.host) return
    var host = String(sshEndpoint.host || "").trim()
    if (host === "") return
    var user = String(sshEndpoint.user || "").trim()
    var port = Number(sshEndpoint.port || 0)
    var remotePath = String(sshEndpoint.path || "").trim()
    var target = (user !== "" ? (user + "@") : "") + host

    var argv = ["uwsm-app", "--", "xdg-terminal-exec", "--title=SSH " + target, "--", "ssh", "-t"]
    if (isFinite(port) && port > 0) {
      argv.push("-p")
      argv.push(String(Math.floor(port)))
    }
    argv.push(target)

    if (remotePath !== "") {
      var cdExpr = ""
      if (remotePath === "~") {
        cdExpr = "cd ~"
      } else if (remotePath.indexOf("~/") === 0) {
        cdExpr = "cd ~/" + Util.shellQuote(remotePath.slice(2))
      } else {
        cdExpr = "cd " + Util.shellQuote(remotePath)
      }
      argv.push(cdExpr + " && exec ${SHELL:-/bin/sh} -l")
    }

    Util.execArgv(argv)
  }

  Timer {
    id: refreshTimer
    interval: (root.panelOpen || (root.summary && root.summary.state === "syncing"))
      ? 1500
      : (root.refreshIntervalSec * 1000)
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      ticks += 1
      if (root.daemonRunning || ticks >= 10) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    id: delayedRefresh
    interval: 400
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: settleTimer
    property int ticks: 0
    interval: 1200
    repeat: true
    running: false
    onTriggered: {
      settleTimer.ticks += 1
      root.refresh()
      if (settleTimer.ticks >= 4) {
        settleTimer.ticks = 0
        settleTimer.running = false
        root._desiredDaemon = -1
      }
    }
  }

  Timer {
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (statusProcess.running) {
        statusProcess.running = false
        root.refreshing = false
        root.lastError = "Mutagen status check timed out"
      }
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2400
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      pollWatchdog.stop()
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) {
        root.applyStatus(stdout)
      } else {
        root.lastError = root.elideStatus(stderr || stdout || "Failed to read Mutagen status")
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || root._actionOutput || "")
      var stderr = String(actionStderr.text || root._actionError || "")
      if (exitCode !== 0) {
        root._desiredDaemon = -1
        root.lastError = root.elideStatus(stderr || stdout || "Mutagen command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      settleTimer.ticks = 0
      settleTimer.restart()
      delayedRefresh.restart()
    }
  }
}
